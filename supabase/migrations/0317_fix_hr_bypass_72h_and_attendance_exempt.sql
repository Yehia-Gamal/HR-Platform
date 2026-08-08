-- =====================================================================
-- 0317: إصلاحات على سلسلة 0313-0316 (مسار آمن دون تعديل الملفات السابقة)
-- ---------------------------------------------------------------------
-- (1) decide_request: 0313 رفع تجاوز HR إلى 60 ساعة ثم عادت 0316 (إعادة
--     تعريف للدالة بنسخة «بعد انتهاء مهلة المدير مباشرة» 12 ساعة) — النسخة
--     الأخيرة تفوز، فعاد التجاوز عملياً إلى 12 ساعة. هنا نعيد التعريف
--     بدمج إشعار المعتمِد التالي (من 0316) مع رفع التجاوز إلى 72 ساعة
--     بعد انتهاء مهلة المدير (طوارئ فقط).
-- (2) notifications.category CHECK (0180): لا يسمح بالكثير من الفئات التي
--     يستخدمها 0316 (attendance, location, security, privacy, documents,
--     service, wellbeing, offboarding) — كل استدعاء notify منها سيفشل عند
--     الإدراج بخرق الـ CHECK. نوسّع الـ CHECK ليشملها.
-- (3) tg_request_approved_attendance_exempt (من 0314): فرع المأمورية كان
--     يقرأ جدول missions (start_date/end_date) بينما الجدول الحقيقي
--     (0006) عنده start_at/end_at، ولا شيء يُدرج في هذا الجدول أصلاً —
--     الفرع مكسور/ميت. نعيد التعريف ليقرأ التواريخ من payload الطلب
--     (startDate/endDate للمأمورية، permitDate للأذونات) — تطابق إرسال
--     تطبيقي الموبايل (mobile_requests_page / mobile_self_service_page).
-- (4) صلاحيات وحدة requests غير موجودة في الترحيلات إطلاقاً (فقط في seed):
--     صفر صفوف في public.permissions يحوي "requests." — بينما كل سلاسل
--     الموافقة (0012/0253/0313/0316 وهذا الملف) تفحص
--     can_access_employee(emp,'requests.approve') التي تعيد false دائماً
--     لغير full-access لأن الصلاحية غائبة. 0121/0138 يحاولان ربطها بصمت
--     (select id ... if not null). نضمن هنا إدراج الصلاحيات الأساسية
--     وربطها بالأدوار على غرار seed/0121 (on conflict do nothing آمن
--     لبيئة seed'd أيضاً).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (4) ضمان صلاحيات وحدة requests (تعمل في بيئة db-push بلا seed)
-- ---------------------------------------------------------------------

insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values
  ('requests.approve',        'requests', 'requests', 'approve', 'الموافقة على الطلبات', 'normal', false),
  ('requests.read',           'requests', 'requests', 'read',    'قراءة الطلبات',         'normal', false),
  ('requests.request.approve','requests', 'request',  'approve', 'اعتماد طلب',            'normal', false),
  ('requests.request.read',   'requests', 'request',  'read',    'عرض الطلبات',           'normal', false)
on conflict (code) do nothing;

-- ربط الصلاحيات بالأدوار (نفس نطاقات مصفوفة الصلاحيات في seed/0121)
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[];
begin
  -- hr-manager: organization
  v_codes := array[
    'requests.approve','requests.read',
    'requests.request.approve','requests.request.read'
  ];
  select id into v_role_id from public.roles where slug = 'hr-manager';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;

  -- hr-specialist: organization (قراءة فقط)
  v_codes := array['requests.read','requests.request.read'];
  select id into v_role_id from public.roles where slug = 'hr-specialist';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;

  -- direct-manager: direct_reports
  v_codes := array[
    'requests.approve','requests.read',
    'requests.request.approve','requests.request.read'
  ];
  select id into v_role_id from public.roles where slug = 'direct-manager';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'direct_reports')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;

  -- executive-secretary: organization
  v_codes := array[
    'requests.approve','requests.read',
    'requests.request.approve','requests.request.read'
  ];
  select id into v_role_id from public.roles where slug = 'executive-secretary';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- (2) توسيع notifications.category CHECK ليشمل الفئات المستخدمة في 0316
-- ---------------------------------------------------------------------
alter table public.notifications
  drop constraint if exists notifications_category_check;

alter table public.notifications
  add constraint notifications_category_check
  check (category in (
    'general','decision','announcement','survey','request',
    'dispute','recognition','system','kpi','device',
    'attendance','location','security','privacy','documents',
    'service','wellbeing','offboarding'
  ));

-- ---------------------------------------------------------------------
-- (1) decide_request — تجاوز HR بعد 72 ساعة + إشعار المعتمِد التالي
-- ---------------------------------------------------------------------
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
  v_next public.request_steps;
  v_step_def public.workflow_steps;
  v_authorized boolean := false;
  v_bypass_hr boolean := false;
  v_notif_title text;
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

  select * into v_req
  from public.requests
  where id = p_request_id
  for update;

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
    and status in ('active','escalated')
  order by step_order
  limit 1
  for update;

  -- ── مسار احتياطي: طلبات بدون تعريف دورة عمل ──
  if not found then
    v_authorized :=
      public.current_is_full_access()
      or v_req.manager_employee_id = v_me
      or public.can_access_employee(v_req.employee_id, 'requests.approve');

    if not v_authorized then
      raise exception 'not authorized to decide this request' using errcode = '42501';
    end if;

    update public.requests
      set status = case p_decision
                     when 'approve' then 'approved'
                     when 'return'  then 'returned'
                     else 'rejected'
                   end,
          workflow_status = 'completed',
          decided_at = now(),
          decided_by = v_me,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;

    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_me, p_decision, 'pending', v_req.status, p_comment, auth.uid()
    );

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
      case when v_req.status = 'approved' then 'normal' else 'high' end,
      'request',
      v_req.id,
      jsonb_build_object('decision', p_decision, 'request_type', v_req.request_type)
    );

    return v_req;
  end if;

  if v_step.workflow_step_id is not null then
    select * into v_step_def
    from public.workflow_steps
    where id = v_step.workflow_step_id;
  end if;

  -- الصلاحية الأساسية
  v_authorized := public.current_is_full_access()
    or v_step.assignee_employee_id = v_me
    or (
      v_step.assignee_role_slug is not null
      and exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = auth.uid()
          and r.slug = v_step.assignee_role_slug
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
      and public.can_access_employee(
        v_req.employee_id,
        coalesce(v_step_def.approver_permission, 'requests.approve')
      )
    )
    or (
      v_step_def.approver_permission is not null
      and public.can_access_employee(v_req.employee_id, v_step_def.approver_permission)
    )
    or (
      v_req.manager_employee_id = v_me
      and v_step.step_order = 1
    );

  -- 0317: تجاوز HR بعد 72 ساعة من انتهاء مهلة المدير (طوارئ فقط).
  -- ملاحظة: HR يكون مخوّلاً أصلاً عبر approver_permission (requests.approve
  -- بنطاق organization)، لذا نفحص التجاوز بغضّ النظر عن v_authorized —
  -- الحارس السابق `if not v_authorized` كان يمنع التفعيل لأن v_authorized
  -- صحيح دائماً لـ HR.
  if v_step.step_order = 1
     and v_step.due_at < now() - interval '72 hours'
     and public.current_has_active_role(array['hr-manager', 'hr-specialist'])
     and public.can_access_employee(v_req.employee_id, 'requests.approve') then
    v_authorized := true;
    v_bypass_hr  := true;
  end if;

  if not v_authorized then
    raise exception 'not authorized for the active workflow step' using errcode = '42501';
  end if;

  -- تسجيل إجراء الخطوة الحالية
  update public.request_steps
  set status = case p_decision
                 when 'approve' then 'approved'
                 else 'rejected'
               end,
      acted_at = now(),
      acted_by = v_me,
      comment = case when v_bypass_hr then coalesce(p_comment, 'اعتماد تجاوزي — تجاوز مهلة المدير') else p_comment end,
      updated_at = now()
  where id = v_step.id;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    v_step.status,
    case p_decision
      when 'approve' then 'approved'
      when 'return'  then 'returned'
      else 'rejected'
    end,
    case when v_bypass_hr then coalesce(p_comment, 'اعتماد تجاوزي — تجاوز مهلة المدير') else p_comment end,
    auth.uid()
  );

  -- ── رفض أو إعادة → إنهاء كل الخطوات المعلقة وإغلاق الطلب ──
  if p_decision in ('reject', 'return') then
    update public.request_steps
      set status = 'skipped', updated_at = now()
    where request_id = p_request_id
      and status = 'pending';

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = case p_decision when 'return' then 'returned' else 'rejected' end,
          workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      case v_req.status
        when 'rejected' then 'تم رفض طلبك'
        else 'تم إعادة طلبك لتعديله'
      end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'high',
      'request',
      v_req.id,
      jsonb_build_object('decision', p_decision, 'request_type', v_req.request_type)
    );

    return v_req;
  end if;

  -- ── موافقة: الانتقال للخطوة التالية أو الإغلاق ──
  if not v_bypass_hr then
    select * into v_next
    from public.request_steps
    where request_id = p_request_id
      and status = 'pending'
      and step_order > v_step.step_order
    order by step_order
    limit 1
    for update;
  end if;

  if found and v_next.id is not null then
    update public.request_steps
      set status = 'active',
          due_at = now() + make_interval(hours => coalesce(v_next.sla_hours, 48)),
          updated_at = now()
    where id = v_next.id;

    update public.workflow_instances
      set current_step_order = v_next.step_order, updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set workflow_status = 'in_review',
          current_step_order = v_next.step_order,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;

    -- إشعار المعتمِد التالي في السلسلة (0316)
    if v_next.assignee_employee_id is not null and v_next.assignee_employee_id <> v_me then
      perform public.notify_employee(
        v_next.assignee_employee_id,
        'طلب بانتظار مراجعتك',
        format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
        'request', 'normal', 'request', p_request_id,
        jsonb_build_object('requestType', v_req.request_type, 'workflowStatus', 'in_review'));
    end if;
  else
    -- لا توجد خطوة تالية → إكمال الطلب
    if v_bypass_hr then
      -- تجاوز الخطوة الثانية: نسجّل إجراء تلقائي للخطوة الثانية
      select * into v_next
      from public.request_steps
      where request_id = p_request_id
        and status = 'pending'
        and step_order > v_step.step_order
      order by step_order
      limit 1
      for update;

      if found then
        update public.request_steps
          set status = 'approved',
              acted_at = now(),
              acted_by = v_me,
              comment = 'اعتماد تلقائي — تجاوز مهلة المدير',
              updated_at = now()
        where id = v_next.id;

        insert into public.request_actions(
          request_id, request_step_id, actor_employee_id, action,
          from_status, to_status, comment, created_by
        ) values (
          p_request_id, v_next.id, v_me, 'approve',
          'pending', 'approved',
          'اعتماد تلقائي — تجاوز مهلة المدير',
          auth.uid()
        );
      end if;
    end if;

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      'تمت الموافقة على طلبك',
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'normal',
      'request',
      v_req.id,
      jsonb_build_object(
        'decision', 'approve',
        'request_type', v_req.request_type,
        'bypassHr', v_bypass_hr
      )
    );
  end if;

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  'V25: قرار على الطلب (approve/reject/return) مع سير عمل متعدد الخطوات + إشعار المعتمِد التالي + تجاوز HR بعد 72 ساعة (طوارئ).';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- (2) تصحيح tg_request_approved_attendance_exempt (F3) — يقرأ من payload
-- ---------------------------------------------------------------------
create or replace function public.tg_request_approved_attendance_exempt()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_work_date date;
  v_start_date date;
  v_end_date date;
  v_day date;
  v_employee_id uuid;
  v_employee_name text;
begin
  -- فقط عند الموافقة على الطلب
  if new.status <> 'approved' or (old.status = new.status) then
    return new;
  end if;

  v_employee_id := new.employee_id;

  -- تجاهل الإجازات — لها تريجر خاص (tg_leave_attendance_on_approval)
  if new.request_type = 'leave' then
    return new;
  end if;

  -- اسم الموظف للإشعار
  select full_name_ar into v_employee_name from public.employees where id = v_employee_id;

  -- ─── المأمورية/القافلة: قراءة التواريخ من payload الطلب ──────────────
  if new.request_type in ('mission', 'convoy') then
    v_start_date := (new.payload->>'startDate')::date;
    v_end_date   := coalesce((new.payload->>'endDate')::date, v_start_date);
    if v_start_date is null then return new; end if;

    v_day := v_start_date;
    while v_day <= v_end_date loop
      insert into public.attendance_daily (employee_id, work_date, status)
      values (v_employee_id, v_day, 'present')
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('on_leave', 'holiday', 'weekend');

      -- سجل استثناء: مأمورية معتمدة
      insert into public.attendance_exceptions (
        employee_id, attendance_daily_id, work_date, kind, description, status, created_by
      )
      select v_employee_id, ad.id, v_day, 'manual_adjustment',
             'مأمورية معتمدة — إعفاء من التأخير/الغياب',
             'approved', auth.uid()
      from public.attendance_daily ad
      where ad.employee_id = v_employee_id and ad.work_date = v_day
      on conflict do nothing;

      v_day := v_day + 1;
    end loop;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد مأمورية',
      format('من %s إلى %s', v_start_date, v_end_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type,
                         'startDate', v_start_date, 'endDate', v_end_date)
    );
    return new;
  end if;

  -- ─── إذن تأخير/انصراف: قراءة permitDate من payload ──────────────────
  if new.request_type in ('late_permit', 'early_permit') then
    v_work_date := (new.payload->>'permitDate')::date;
    if v_work_date is null then
      v_work_date := (new.payload->>'date')::date;
    end if;
    if v_work_date is null then return new; end if;

    if new.request_type = 'late_permit' then
      insert into public.attendance_daily (employee_id, work_date, status, late_minutes)
      values (v_employee_id, v_work_date, 'present', 0)
      on conflict on constraint attendance_daily_uq do update
        set late_minutes = 0,
            status = case when public.attendance_daily.status in ('on_leave','holiday','weekend')
                         then public.attendance_daily.status else 'present' end,
            updated_at = now()
        where public.attendance_daily.is_finalized = false;

      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'late',
              'إذن تأخير معتمد — إعفاء من دقائق التأخير',
              0, 'approved', auth.uid())
      on conflict do nothing;
    else
      -- إذن انصراف مبكر: سجل استثناء
      insert into public.attendance_exceptions (
        employee_id, work_date, kind, description, minutes_adjustment, status, created_by
      )
      values (v_employee_id, v_work_date, 'early_leave',
              'إذن انصراف مبكر معتمد',
              0, 'approved', auth.uid())
      on conflict do nothing;
    end if;

    perform public.log_audit_event(
      'request.attendance_exempted', 'workflow', 'info',
      'attendance_daily', v_employee_id,
      'إعفاء حضور بعد اعتماد طلب',
      format('النوع: %s، التاريخ: %s', new.request_type, v_work_date),
      jsonb_build_object('requestId', new.id, 'requestType', new.request_type, 'workDate', v_work_date)
    );
    return new;
  end if;

  -- أنواع أخرى (convoy عولج أعلاه، attendance_correction) — لا نعالجها
  return new;
end;
$$;

comment on function public.tg_request_approved_attendance_exempt() is
  'يُعفي الموظف من التأخير/الغياب عند اعتماد مأمورية (من payload startDate/endDate) أو إذن تأخير/انصراف مبكر (permitDate).';

drop trigger if exists trg_request_approved_attendance_exempt on public.requests;
create trigger trg_request_approved_attendance_exempt
  after update of status on public.requests
  for each row execute function public.tg_request_approved_attendance_exempt();

notify pgrst, 'reload schema';

commit;
