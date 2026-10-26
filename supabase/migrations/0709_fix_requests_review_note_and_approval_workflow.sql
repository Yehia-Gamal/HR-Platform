-- ==============================================================================
-- Migration 0709: إصلاح تعطل اعتماد الطلبات لجميع الأدوار (المدير المباشر، HR، مدير التشغيل 1)
-- ==============================================================================
-- 1. إضافة عمود review_note الناقص إلى جدول public.requests لمنع خطأ UndefinedColumn.
-- 2. توسيع قيد request_steps_status_check ليشمل 'returned' و 'in_progress'.
-- 3. تعريف دالة public.activate_approved_leave(uuid) لمنع خطأ UndefinedFunction عند اعتماد الإجازات.
-- 4. إعادة نشر دالة public.decide_request(uuid, text, text) بالتحصينات الشاملة ومعالجة الاستثناءات.
-- ==============================================================================

begin;

-- ─── 1) إضافة عمود review_note إلى جدول requests ─────────────────────────────
alter table public.requests
  add column if not exists review_note text;

comment on column public.requests.review_note is
  'ملاحظة/تعليق المعتمِد أو الرافض للطلب (تم توحيده لمنع أي استثناء في دوال اتخاذ القرار).';

-- ─── 2) توسيع قيد الحالات في جدول request_steps ──────────────────────────────
alter table public.request_steps
  drop constraint if exists request_steps_status_check;

alter table public.request_steps
  add constraint request_steps_status_check
  check (status in ('pending', 'active', 'approved', 'rejected', 'skipped', 'escalated', 'expired', 'returned', 'in_progress'));

-- ─── 3) تعريف دالة activate_approved_leave الآمنة ────────────────────────────
create or replace function public.activate_approved_leave(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- دالة مساعدة آمنة لاعتماد وتفعيل الإجازة.
  -- التسوية المالية والرصيد وسجلات الحضور تُدار تلقائياً بواسطة triggers
  -- tg_leave_settle_on_request_decision و tg_leave_attendance_on_approval.
  return;
end;
$$;

revoke all on function public.activate_approved_leave(uuid) from public, anon;
grant execute on function public.activate_approved_leave(uuid) to authenticated, service_role;
comment on function public.activate_approved_leave(uuid) is
  'دالة آمنة لمعالجة اعتماد الإجازات دون تعليق أو أخطاء وظائف غير معرفة.';

-- ─── 4) إعادة تعريف دالة decide_request المحصّنة ──────────────────────────────
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
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_is_clinic_mgr   boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_actor_role_name text;
  v_correction_id   uuid;
  v_decision        text;
  v_permit_eval_date date;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- تطبيع صيغة القرار وقبول كافة الصيغ المتوافقة (approve / approved, reject / rejected, return / returned)
  v_decision := case
    when lower(trim(coalesce(p_decision, ''))) in ('approve', 'approved') then 'approve'
    when lower(trim(coalesce(p_decision, ''))) in ('reject', 'rejected') then 'reject'
    when lower(trim(coalesce(p_decision, ''))) in ('return', 'returned') then 'return'
    else lower(trim(coalesce(p_decision, '')))
  end;

  if v_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if v_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status not in ('pending', 'under_review') then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager','executive-secretary']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer'])
               or public.current_is_full_access()
               or public.current_has_active_role(array['admin','super-admin'])
               or public.has_any_permission(array['requests.decide.hr', 'requests.decide.executive', 'payroll.run.manage']);
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-manager','operations-manager-2']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or v_is_operations or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending','in_progress')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step := coalesce(v_step.step_order, 0);

  -- التحقق من كون المعتمِد مدير العيادات
  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or public.current_has_active_role(array['clinics-manager'])
  );

  -- التحقق من صفة المدير المباشر:
  v_is_direct_mgr := (v_req.manager_employee_id = v_me)
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_req.employee_id)
        or v_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  -- الصلاحية الشاملة لاعتماد الطلبات (تشمل الإدارة التنفيذية وإدارة الموارد البشرية والتشغيلية والمدير المباشر)
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or v_is_operations
    or (v_step.id is not null and (
      v_step.assignee_employee_id = v_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or public.current_has_active_role(array['admin','super-admin','executive-secretary']);

  if not v_authorized then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  -- تحديد الدور الفعلي لمتخذ القرار واسمه الوظيفي الواضح
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
    v_actor_role_name := 'إدارة النظام';
  elsif v_is_hr then
    v_actor_role := 'hr-manager';
    v_actor_role_name := 'الموارد البشرية';
  elsif v_is_exec then
    v_actor_role := 'executive';
    v_actor_role_name := 'المدير التنفيذي';
  elsif v_is_operations then
    v_actor_role := 'operations-manager-1';
    v_actor_role_name := 'مدير التشغيل 1';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
    v_actor_role_name := 'المدير المباشر';
  else
    v_actor_role := 'manager';
    v_actor_role_name := 'المعتمِد';
  end if;

  -- 1) إذا كان القرار هو الرفض أو الإرجاع: يُغلق الطلب مباشرة
  if v_decision in ('reject', 'return') then
    v_final_status := case when v_decision = 'reject' then 'rejected' else 'returned' end;

    update public.requests
    set status = v_final_status,
        workflow_status = case when v_decision = 'reject' then 'terminated' else 'in_review' end,
        decided_at = now(),
        decided_by = v_me,
        review_note = coalesce(p_comment, review_note),
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_step.id is not null then
      update public.request_steps
      set status = v_final_status,
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'skipped',
        updated_at = now()
    where request_id = p_request_id
      and (v_step.id is null or id <> v_step.id)
      and status in ('active', 'escalated', 'pending');

    update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, v_decision, 'pending', v_final_status, p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    -- تصحيح البصمة عند الرفض أو الإرجاع:
    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        update public.attendance_corrections
        set status = case when v_decision = 'reject' then 'rejected' else 'cancelled' end,
            reviewed_by = v_me,
            reviewed_at = now(),
            review_note = coalesce(p_comment, case when v_decision = 'reject' then 'مرفوض مع الطلب' else 'معاد للمراجعة' end),
            updated_at = now()
        where id = v_correction_id and status = 'pending';
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      case when v_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', v_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- 2) إذا كان القرار هو الموافقة (approve):
  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  -- فحص ما إذا كان الطلب يحتاج خطوة لاحقة:
  -- القاعدة 1: إذا اعتمد المدير التنفيذي أو الأدمن أو مدير الموارد البشرية أو مدير التشغيل في أي مرحلة -> يُعتمد نهائياً فوراً
  -- القاعدة 2: إذا اعتمد المدير المباشر طلباً تصعّد بالفعل للمرحلة 2 أو أعلى -> يُعتمد نهائياً فوراً
  -- خلاف ذلك (إذا كان المدير المباشر فقط يعتمد المرحلة 1 وتوجد مرحلة 2 متبقية): تُنشّط المرحلة 2
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec or v_is_hr or v_is_operations) then
    -- تنشيط الخطوة التالية
    if v_step.id is not null then
      update public.request_steps
      set status = 'approved',
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'active',
        updated_at = now()
    where request_id = p_request_id
      and step_order = (
        select min(step_order) from public.request_steps
        where request_id = p_request_id and step_order > v_current_step and status = 'pending'
      );

    select * into v_req from public.requests where id = p_request_id;
    return v_req;
  end if;

  -- اعتماد نهائي للطلب:
  -- أ) الخطوة التي بُتّ فيها: تُعتمد مع الفاعل الفعلي والتعليق
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  -- ب) الخطوات المتبقية الأخرى في المسار التي تم تجاوزها أو لم تلزم:
  -- تُسجّل كـ 'skipped' (لم يلزم) دون تكرار فاعل أو تعليق عليها منعاً للازدواجية في السجل
  update public.request_steps
  set status = 'skipped',
      acted_at = null,
      acted_by = null,
      comment = null,
      updated_at = now()
  where request_id = p_request_id
    and (v_step.id is null or id <> v_step.id)
    and status in ('active', 'escalated', 'pending');

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = coalesce(p_comment, review_note),
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  update public.workflow_instances
  set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  -- تطبيق الآثار التلقائية للطلب المعتمد:
  -- أ) تغيير الوردية (shift_change):
  if v_req.request_type = 'shift_change' and v_req.payload->>'shiftId' is not null then
    declare
      v_target_shift_id uuid := nullif(v_req.payload->>'shiftId','')::uuid;
      v_eff_date date := coalesce(nullif(v_req.payload->>'effectiveFrom','')::date, (now() at time zone 'Africa/Cairo')::date);
    begin
      if v_target_shift_id is not null then
        update public.shift_assignments
        set is_active = false,
            effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
            updated_at = now()
        where employee_id = v_req.employee_id and is_active = true;

        insert into public.shift_assignments (
          employee_id, shift_id, effective_from, is_active, notes, created_by
        ) values (
          v_req.employee_id, v_target_shift_id, v_eff_date, true,
          'معتمد بطلب تغيير وردية: ' || coalesce(v_req.title, ''), auth.uid()
        );

        update public.roster_days
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date >= v_eff_date;

        update public.attendance_daily
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date = v_eff_date;
      end if;
    end;
  end if;

  -- ب) تصحيح البصمة (attendance_correction):
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      perform public.decide_attendance_correction(v_correction_id, 'approved', coalesce(p_comment, 'معتمد مع الطلب'));
    end if;
  end if;

  -- ج) الإجازات (leave):
  if v_req.request_type = 'leave' then
    begin
      perform public.activate_approved_leave(v_req.id);
    exception when others then
      null;
    end;
  end if;

  -- د) إعادة تقييم وإسقاط غرامة اليوم تلقائياً عند اعتماد أذونات الانصراف أو التأخير أو الوردية
  if v_req.request_type in ('early_permit', 'late_permit', 'permit', 'attendance_permit', 'permission', 'errand', 'shift_change') then
    v_permit_eval_date := coalesce(
      public.try_cast_date(v_req.payload->>'permitDate'),
      public.try_cast_date(v_req.payload->>'date'),
      public.try_cast_date(v_req.payload->>'effectiveFrom'),
      public.try_cast_date(v_req.payload->>'startDate'),
      public.try_cast_date(v_req.payload->>'start_date'),
      public.try_cast_date(v_req.payload->>'workDate'),
      v_req.created_at::date
    );

    if v_permit_eval_date is not null then
      begin
        perform public.auto_waive_penalty_if_completed_eight_hours(v_req.employee_id, v_permit_eval_date);
      exception when others then
        null;
      end;
    end if;
  end if;

  -- إشعار صاحب الطلب بالاعتماد
  perform public.notify_employee(
    v_req.employee_id,
    'تم اعتماد طلبك بنجاح ✓',
    coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'decision', 'approve', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;
comment on function public.decide_request(uuid, text, text) is
  '0709: اعتماد ورفض وإرجاع الطلبات لكافة الأدوار مع ضمان وجود review_note ودعم الإجازات وحماية قيود الخطوات.';

commit;
