-- migration: 0386
-- description: إشعارات تقديم الطلب + تقييد صلاحية الموافقة بالزمن + إصلاح بگ 0380
--
-- التغييرات:
--   (1) تريغر: عند كل طلب جديد → إشعار فوري للمدير التنفيذي + HR (للإطلاع فقط)
--   (2) decide_request: صلاحية مقيَّدة بالزمن بدلاً من المتزامن الكلي (0366)
--       • المدير المباشر:    دائماً مخوَّل (منذ اللحظة الأولى)
--       • الأوبريشن:         مخوَّل فقط بعد تصعيد الخطوة 1 (بعد 2 ساعة بلا رد)
--       • HR:                مخوَّل فقط بعد تصعيد الخطوة 2 (بعد 6 ساعات إجمالاً)
--       • المدير التنفيذي + full-access: دائماً (استثنائي)
--   (3) إصلاح بگ 0380: حذف submit_my_request(text,date,date,...) المعطوب
--       + إصلاح _request_idempotency_key(integer,…) → uuid

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) تريغر: إشعار فوري للمدير التنفيذي + HR عند كل طلب جديد
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.tg_notify_awareness_on_request_submit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_body   text;
  v_emp_id uuid;
begin
  v_body := format('%s: %s',
    public.request_type_label(new.request_type),
    coalesce(new.title, ''));

  -- المدير التنفيذي (للإطلاع فقط، بدون صلاحية قرار في هذه المرحلة)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('executive-director', 'executive')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      'طلب جديد — للإطلاع',
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  -- HR (للمتابعة فقط، بدون صلاحية قرار إلا بعد 6 ساعات)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('hr-manager', 'hr-specialist')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      'طلب جديد — للمتابعة',
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_awareness_on_request_submit on public.requests;
create trigger trg_notify_awareness_on_request_submit
  after insert on public.requests
  for each row
  when (new.status = 'pending')
  execute function public.tg_notify_awareness_on_request_submit();

comment on function public.tg_notify_awareness_on_request_submit() is
  '0386: إشعار فوري للمدير التنفيذي + HR عند كل طلب جديد — للإطلاع فقط بدون صلاحية قرار.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) decide_request — صلاحية مقيَّدة بالزمن (يحل محل 0366)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision   text,
  p_comment    text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_step_def        public.workflow_steps;
  v_authorized      boolean := false;
  v_is_manager      boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_executive    boolean;
  v_step1_escalated boolean;
  v_step2_escalated boolean;
  v_no_steps        boolean;
  v_final_status    text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;
  if v_req.employee_id = v_me then
    raise exception 'self-approval is not allowed' using errcode = '42501';
  end if;

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active', 'escalated', 'pending')
  order by step_order
  limit 1
  for update;

  if v_step.workflow_step_id is not null then
    select * into v_step_def from public.workflow_steps where id = v_step.workflow_step_id;
  end if;

  -- فحص تصعيد الخطوات (أساس التقييد الزمني)
  v_no_steps := not exists(
    select 1 from public.request_steps where request_id = p_request_id
  );
  v_step1_escalated := exists(
    select 1 from public.request_steps
    where request_id = p_request_id and step_order = 1 and status = 'escalated'
  );
  v_step2_escalated := exists(
    select 1 from public.request_steps
    where request_id = p_request_id and step_order = 2 and status = 'escalated'
  );

  -- أدوار الفاعل
  v_is_manager    := (v_req.manager_employee_id = v_me);
  v_is_operations := public.current_has_active_role(
    array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']);
  v_is_hr         := public.current_has_active_role(array['hr-manager','hr-specialist']);
  v_is_executive  := public.current_has_active_role(
    array['executive-director','executive','executive-secretary']);

  -- صلاحية مقيَّدة بالزمن:
  --   المدير المباشر: دائماً
  --   الأوبريشن:      فقط بعد تصعيد الخطوة 1 (مرور 2 ساعة بلا رد من المدير)
  --   HR:             فقط بعد تصعيد الخطوة 2 (مرور 4 ساعات أوبريشن = 6 ساعات إجمالاً)
  --   fallback لطلبات قديمة بلا خطوات: تقييد زمني مباشر من created_at
  v_authorized :=
    public.current_is_full_access()
    or v_is_executive
    or v_is_manager
    or (v_step.assignee_employee_id = v_me)
    -- أوبريشن: بعد تصعيد الخطوة 1
    or (v_is_operations
        and (v_step1_escalated
             or (v_no_steps and v_req.created_at < now() - interval '2 hours'))
        and public.can_access_employee(v_req.employee_id, 'requests.approve'))
    -- HR: بعد تصعيد الخطوة 2
    or (v_is_hr
        and (v_step2_escalated
             or (v_no_steps and v_req.created_at < now() - interval '6 hours'))
        and public.can_access_employee(v_req.employee_id, 'requests.approve'));

  if not v_authorized then
    raise exception 'not_authorized — الطلب لا يزال في مهلة المدير المباشر' using errcode = '42501';
  end if;

  v_final_status := case p_decision
    when 'approve' then 'approved'
    when 'return'  then 'returned'
    else 'rejected'
  end;

  -- سجّل الخطوة الحالية
  if v_step.id is not null then
    update public.request_steps
      set status     = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at   = now(),
          acted_by   = v_me,
          comment    = coalesce(p_comment, comment),
          updated_at = now()
    where id = v_step.id;
  end if;

  -- موافقة واحدة تُغلق جميع الخطوات المعلقة (لا مرحلتان)
  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending', 'active', 'escalated')
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid);

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status          = v_final_status,
        workflow_status = 'completed',
        decided_at      = now(),
        decided_by      = v_me,
        updated_at      = now()
  where id = p_request_id
  returning * into v_req;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف بالنتيجة (صوتي — priority=high)
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request', 'high', 'request', v_req.id,
    jsonb_build_object(
      'decision',     p_decision,
      'request_type', v_req.request_type,
      'actorRole',
        case
          when v_is_manager    then 'direct_manager'
          when v_is_operations then 'operations'
          when v_is_executive  then 'executive'
          when v_is_hr         then 'hr'
          else 'authorized'
        end,
      'deepLink', '/requests/' || v_req.id
    )
  );

  return v_req;
end;
$$;

comment on function public.decide_request(uuid, text, text) is
  '0386: موافقة مقيَّدة بالزمن — مدير(دائم) → أوبريشن(بعد 2h) → HR(بعد 6h). نقرة واحدة تُنهي الطلب.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) إصلاح بگ 0380: حذف submit_my_request(text,date,date,...) المعطوب
--     + إصلاح نوع _request_idempotency_key (integer → uuid)
-- ─────────────────────────────────────────────────────────────────────────────
-- حذف الدالة المعطوبة (كانت تستدعي submit_request بمعاملات غير موجودة)
drop function if exists public.submit_my_request(text, date, date, jsonb, uuid);

-- حذف الإصدار المعطوب واستبداله بالنوع الصحيح
drop function if exists public._request_idempotency_key(integer, text, date, date);

create or replace function public._request_idempotency_key(
  p_employee_id  uuid,
  p_request_type text,
  p_start_date   date,
  p_end_date     date
) returns uuid
language sql
immutable
security definer
set search_path = public
as $$
  select (
    left(h,8)||'-'||substr(h,9,4)||'-'||substr(h,13,4)||'-'||substr(h,17,4)||'-'||right(h,12)
  )::uuid
  from (
    select md5(format('%s|%s|%s|%s',
      p_employee_id, p_request_type, p_start_date, p_end_date)) as h
  ) as _;
$$;
revoke all on function public._request_idempotency_key(uuid, text, date, date) from anon, authenticated;

comment on function public._request_idempotency_key(uuid,text,date,date) is
  '0386: مفتاح idempotency md5 — نوع employee_id مصحَّح إلى uuid (كان integer في 0380).';

notify pgrst, 'reload schema';

commit;
