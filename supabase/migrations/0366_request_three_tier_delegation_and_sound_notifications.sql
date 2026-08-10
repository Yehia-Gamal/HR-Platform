-- ═══════════════════════════════════════════════════════════════════════════════
-- 0364: سير موافقات ثلاثي المراتب + صلاحية متزامنة + إشعارات صوتية
-- ═══════════════════════════════════════════════════════════════════════════════
-- المتطلبات:
--   (1) المسؤول الأول عن قبول/رفض أي طلب = المدير المباشر للموظف.
--   (2) إن لم يُرد المدير خلال ساعتين → يُفوّض القرار إلى الأوبريشن.
--   (3) إن لم يرد الأوبريشن خلال 4 ساعات إضافية → يُفوّض إلى HR.
--   (4) خلال كل هذه المدة يكون الإجراء متاحًا (متزامنًا) لكل من:
--       المدير المباشر + الأوبريشن + المدير التنفيذي + HR. أيّهم يقرر يُنهي الطلب.
--   (5) كل خطوة (إرسال/تصعيد/قرار) لها إشعار داخل التطبيق + إشعار دفع خارجي
--       مع صوت (priority=high بدل urgent لتفادي شاشة كاملة مزعجة، لكن بصوت).
--
-- الأثر:
--   • إعادة تعريف workflow_definitions/steps لـ leave/mission/convoy/generic
--     بثلاث خطوات: direct_manager(2h) → operator(4h) → hr-manager(48h).
--   • إعادة كتابة decide_request: صلاحية موسّعة متزامنة، وموافقة واحدة تُنهي الطلب.
--   • إعادة كتابة process_request_sla: تصعيد حقيقي ثلاثي عبر request_steps
--     مع إشعار كل مرتبة + مرجعية للطلبات القديمة بلا خطوات ثلاثية.
--   • cron job يُجدول كل 5 دقائق (أسرع من */10 القديم) لالتقاط مهلة الساعتين.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) تعريفات سير العمل ثلاثية المراتب
-- ─────────────────────────────────────────────────────────────────────────────
-- لا نحذف التعريفات القديمة (مرتبطة بـ workflow_instances)؛ بل نُحدّث تعريف
-- كل نوع افتراضي موجود ليعكس المسار الثلاثي، وننشئ تعريفًا جديدًا للأنواع
-- التي لا تملك واحدًا. ثم نستبدل خطوات التعريف بثلاث خطوات جديدة.
-- ملاحظة: request_steps.workflow_step_id مرتبط بـ on delete set null، فحذف
-- خطوط workflow_steps آمن ولا يكسر النسخ الجارية القديمة.

do $$
declare
  v_type text;
  v_def uuid;
begin
  foreach v_type in array array['leave','mission','convoy','generic'] loop
    -- ابحث عن تعريف افتراضي موجود لهذا النوع، أو أنشئ واحدًا.
    select id into v_def
    from public.workflow_definitions
    where request_type = v_type and is_default = true and is_active = true
    order by version desc limit 1;

    if v_def is null then
      insert into public.workflow_definitions (
        code, name_ar, description, request_type, version, is_active, is_default,
        auto_escalate, default_due_hours, config
      ) values (
        'three-tier-' || v_type,
        case v_type
          when 'leave' then 'اعتماد الطلبات — مدير مباشر ثم أوبريشن ثم HR'
          when 'mission' then 'اعتماد المأموريات — مدير ثم أوبريشن ثم HR'
          when 'convoy' then 'اعتماد القوافل — مدير ثم أوبريشن ثم HR'
          else 'اعتماد الطلبات العامة — مدير ثم أوبريشن ثم HR'
        end,
        'سير ثلاثي: مدير مباشر (مهلة ساعتان) → أوبريشن (مهلة 4 ساعات) → HR. الإجراء متاح متزامنًا لكل الأدوار طوال الوقت.',
        v_type, 1, true, true, true, 48,
        jsonb_build_object(
          'tierHours', jsonb_build_object('manager', 2, 'operations', 4, 'hr', 48),
          'concurrentActors', jsonb_build_array('direct_manager','operations','executive','hr')
        )
      )
      returning id into v_def;
    else
      -- حدّث بيانات التعريف الموجود ليعكس المسار الثلاثي.
      update public.workflow_definitions
        set name_ar = case v_type
                       when 'leave' then 'اعتماد الطلبات — مدير مباشر ثم أوبريشن ثم HR'
                       when 'mission' then 'اعتماد المأموريات — مدير ثم أوبريشن ثم HR'
                       when 'convoy' then 'اعتماد القوافل — مدير ثم أوبريشن ثم HR'
                       else 'اعتماد الطلبات العامة — مدير ثم أوبريشن ثم HR'
                      end,
            description = 'سير ثلاثي: مدير مباشر (مهلة ساعتان) → أوبريشن (مهلة 4 ساعات) → HR. الإجراء متاح متزامنًا لكل الأدوار طوال الوقت.',
            config = jsonb_build_object(
              'tierHours', jsonb_build_object('manager', 2, 'operations', 4, 'hr', 48),
              'concurrentActors', jsonb_build_array('direct_manager','operations','executive','hr')
            ),
            updated_at = now()
      where id = v_def;
    end if;

    -- احذف الخطوات القديمة (request_steps.workflow_step_id → null آمنًا).
    delete from public.workflow_steps where definition_id = v_def;

    -- الخطوة 1: المدير المباشر — مهلة ساعتان، تصعيد بعد ساعتين.
    insert into public.workflow_steps (
      definition_id, step_order, name_ar, step_type, approver_type,
      approver_role_slug, sla_hours, escalate_after_hours,
      approver_permission, is_optional, allow_delegate, is_active
    ) values (
      v_def, 1, 'المدير المباشر', 'approval', 'direct_manager',
      null, 2, 2, 'requests.approve', false, true, true
    );

    -- الخطوة 2: الأوبريشن — مهلة 4 ساعات، تصعيد بعد 4 ساعات.
    insert into public.workflow_steps (
      definition_id, step_order, name_ar, step_type, approver_type,
      approver_role_slug, sla_hours, escalate_after_hours,
      approver_permission, is_optional, allow_delegate, is_active
    ) values (
      v_def, 2, 'الأوبريشن', 'approval', 'operator',
      'operations-officer', 4, 4, 'requests.approve', true, true, true
    );

    -- الخطوة 3: الموارد البشرية — مهلة 48 ساعة، لا تصعيد أبعد.
    insert into public.workflow_steps (
      definition_id, step_order, name_ar, step_type, approver_type,
      approver_role_slug, sla_hours, escalate_after_hours,
      approver_permission, is_optional, allow_delegate, is_active
    ) values (
      v_def, 3, 'الموارد البشرية', 'approval', 'role',
      'hr-manager', 48, null, 'requests.approve', true, true, true
    );
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) decide_request — صلاحية متزامنة موسّعة + موافقة واحدة تُنهي الطلب
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.requests;
  v_step public.request_steps;
  v_step_def public.workflow_steps;
  v_authorized boolean := false;
  v_is_direct_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_executive boolean := false;
  v_final_status text;
  v_notif_priority text := 'high';
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return' and nullif(trim(coalesce(p_comment, '')), '') is null then
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

  -- ── تحديد أدوار الفاعل (متزامنة) ──
  v_is_direct_manager := (v_req.manager_employee_id = v_me);
  v_is_operations := public.current_has_active_role(
    array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']);
  v_is_hr := public.current_has_active_role(array['hr-manager','hr-specialist']);
  v_is_executive := public.current_has_active_role(
    array['executive-director','executive','executive-secretary']);

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by step_order
  limit 1
  for update;

  if v_step.workflow_step_id is not null then
    select * into v_step_def from public.workflow_steps where id = v_step.workflow_step_id;
  end if;

  -- ── الصلاحية المتزامنة: أيٌّ من الأدوار الأربعة + full-access + مخوّل الخطوة ──
  v_authorized :=
    public.current_is_full_access()
    or v_is_direct_manager
    or (v_is_operations and public.can_access_employee(v_req.employee_id, 'requests.approve'))
    or (v_is_hr and public.can_access_employee(v_req.employee_id, 'requests.approve'))
    or (v_is_executive and public.can_access_employee(v_req.employee_id, 'requests.approve'))
    or (v_step.assignee_employee_id = v_me)
    or (
      v_step_def.approver_permission is not null
      and public.can_access_employee(v_req.employee_id, v_step_def.approver_permission)
    );

  if not v_authorized then
    raise exception 'not authorized for this request — الإجراء متاح للمدير المباشر/الأوبريشن/المدير التنفيذي/HR' using errcode = '42501';
  end if;

  v_final_status := case p_decision
                      when 'approve' then 'approved'
                      when 'return' then 'returned'
                      else 'rejected'
                    end;

  -- سجل إجراء الخطوة الحالية (إن وُجدت)
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(),
          acted_by = v_me,
          comment = coalesce(p_comment, comment),
          updated_at = now()
    where id = v_step.id;
  end if;

  -- أغلق باقي الخطوات المعلقة (الموافقة المتزامنة تُنهي الطلب)
  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending','active','escalated')
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid);

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status = v_final_status,
        workflow_status = 'completed',
        decided_at = now(),
        decided_by = v_me,
        updated_at = now()
  where id = p_request_id
  returning * into v_req;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف (داخل التطبيق + دفع بصوت) — priority=high لضمان صوت دون شاشة كاملة.
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request',
    v_notif_priority,
    'request',
    v_req.id,
    jsonb_build_object(
      'decision', p_decision,
      'request_type', v_req.request_type,
      'actorRole',
        case
          when v_is_direct_manager then 'direct_manager'
          when v_is_operations then 'operations'
          when v_is_executive then 'executive'
          when v_is_hr then 'hr'
          else 'authorized'
        end,
      'deepLink', '/requests/' || v_req.id
    )
  );

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  '0364: قرار متزامن على الطلب — أيٌّ من {المدير المباشر، الأوبريشن، المدير التنفيذي، HR} يمكنه إنهاء الطلب، مع إشعار صوتي للموظف.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) process_request_sla — تصعيد ثلاثي حقيقي عبر request_steps
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.process_request_sla(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
  v_row record;
  v_ops_emp uuid;
  v_hr_emp uuid;
  v_exec_emp uuid;
  v_next_step public.request_steps;
begin
  -- إيجاد أول موظف نشط لكل دور كمُصعَّد إليه (للإسناد + الإشعار).
  v_ops_emp := public.first_active_employee_for_role('operations-officer');
  v_hr_emp  := public.first_active_employee_for_role('hr-manager');
  v_exec_emp:= public.first_active_employee_for_role('executive-director');

  for v_row in
    select rs.id as step_id, rs.request_id, rs.step_order, rs.status,
           rs.escalation_deadline, rs.due_at, r.employee_id,
           r.manager_employee_id, r.title, r.request_type
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active','escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(p_limit, 2000))
    for update of rs skip locked
  loop
    -- إن كانت الخطوة الحالية هي الأخيرة (HR) فلا تصعيد أبعد — فقط تذكير صوتي.
    if v_row.step_order >= 3 then
      perform public.notify_employee(
        v_row.employee_id,  -- لا: نُشعر HR فعليًا
        'طلب بانتظار قرار HR',
        coalesce(v_row.title, '') || ' — تجاوز مهلة الأوبريشن ويحتاج قرار HR الآن.',
        'request', 'high', 'request', v_row.request_id,
        jsonb_build_object('escalation','hr','deepLink','/requests/' || v_row.request_id));
      if v_hr_emp is not null then
        perform public.notify_employee(
          v_hr_emp, 'طلب يحتاج قرارك الآن (HR)',
          coalesce(v_row.title, ''),
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object('escalation','hr_reminder','deepLink','/requests/' || v_row.request_id));
      end if;
      continue;
    end if;

    -- ابحث عن الخطوة التالية (المُصعَّد إليه).
    select * into v_next_step
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    -- قفّ الخطوة الحالية لحالة escalated.
    update public.request_steps
      set status = 'escalated', escalated_at = now(), updated_at = now()
    where id = v_row.step_id;

    if v_next_step.id is not null then
      -- فعّل الخطوة التالية مع إسناد المُصعَّد إليه.
      declare v_target uuid; v_role text;
      begin
        if v_row.step_order = 1 then
          v_target := v_ops_emp; v_role := 'operations-officer';
        else
          v_target := v_hr_emp; v_role := 'hr-manager';
        end if;
        update public.request_steps
          set status = 'active',
              assignee_employee_id = coalesce(v_target, assignee_employee_id),
              assignee_role_slug = coalesce(v_role, assignee_role_slug),
              due_at = now() + make_interval(hours => coalesce(v_next_step.sla_hours, 48)),
              escalation_deadline = case when v_next_step.escalation_after_hours is not null
                                          then now() + make_interval(hours => v_next_step.escalation_after_hours)
                                        else null end,
              updated_at = now()
        where id = v_next_step.id;

        update public.requests
          set workflow_status = case when v_row.step_order = 1 then 'awaiting_operator' else 'escalated' end,
              escalated_at = coalesce(escalated_at, now()),
              updated_at = now()
        where id = v_row.request_id;

        insert into public.request_actions(
          request_id, actor_employee_id, action, from_status, to_status, comment, metadata)
        values(
          v_row.request_id, null, 'escalate', 'pending', 'pending',
          case when v_row.step_order = 1 then 'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)'
               else 'تصعيد تلقائي — تجاوز مهلة الأوبريشن (4 ساعات)' end,
          jsonb_build_object('tier', v_row.step_order + 1, 'targetRole', v_role));
      end;
    else
      -- لا توجد خطوة تالية (طلب قديم بلا خطوات ثلاثية): استخدم fallback.
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            updated_at = now()
        where id = v_row.request_id;
    end if;

    -- إشعارات صوتية لكل المرتب المعنية: المُصعَّد إليه + المدير التنفيذي + HR
    -- (الإجراء متاح للجميع متزامنًا).
    declare
      v_tier_label text := case when v_row.step_order = 1 then 'الأوبريشن' else 'HR' end;
      v_target_emp uuid := case when v_row.step_order = 1 then v_ops_emp else v_hr_emp end;
    begin
      if v_target_emp is not null then
        perform public.notify_employee(
          v_target_emp,
          'طلب محوّل إليك الآن (' || v_tier_label || ')',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object('escalation', v_tier_label, 'deepLink', '/requests/' || v_row.request_id));
      end if;
      if v_exec_emp is not null then
        perform public.notify_employee(
          v_exec_emp, 'تصعيد طلب يحتاج متابعتك',
          coalesce(v_row.title, ''),
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object('escalation','executive_notify','deepLink','/requests/' || v_row.request_id));
      end if;
    end;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;
comment on function public.process_request_sla(integer) is
  '0364: تصعيد ثلاثي — مدير(2h)→أوبريشن(4h)→HR، مع إشعارات صوتية لكل مرتبة وإجراء متاح متزامنًا.';
revoke all on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- (4) إعادة جدولة cron أسرع (كل 5 دقائق) لالتقاط مهلة الساعتين بدقة
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job where jobname = 'hr_request_sla') then
    perform cron.alter_job(jobname => 'hr_request_sla', schedule => '*/5 * * * *');
  else
    perform cron.schedule('hr_request_sla', '*/5 * * * *',
      $j$ select net.http_post(
        url := (select value from public.system_settings where key = 'edge_base_url') || '/functions/v1/process-request-sla',
        headers := jsonb_build_object('content-type','application/json','x-cron-secret',(select value from public.system_settings where key = 'cron_secret')),
        body := '{}'::jsonb) $j$);
  end if;
exception when others then
  -- لا نفشل الـ migration كله بسبب جدولة cron؛ تستمر الدوال بدونها.
  raise notice 'cron schedule skipped: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
