-- ============================================================================
-- Migration: 0731_auto_cancel_penalties_on_permit_and_excuse_approval.sql
-- Description:
--   تحديث دالة decide_request لإلغاء الغرامة الفورية وتصفير دقائق التأخير
--   ورفع تعليق الحساب فوراً بمجرد اعتماد عذر التأخير (late_excuse) أو إذن العمل
-- ============================================================================

create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null::text
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
  v_is_direct_mgr   boolean := false;
  v_is_operations   boolean := false;
  v_is_hr           boolean := false;
  v_is_exec         boolean := false;
  v_is_clinic_mgr   boolean := false;
  v_actor_role      text;
  v_actor_role_name text;
  v_correction_id   uuid;
  v_decision        text;
  v_eff_date        date;
  v_chk_start       date;
  v_chk_end         date;
  v_cancelled_pens  int := 0;
begin
  if v_me is null and auth.role() <> 'service_role' then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_decision := case
    when lower(trim(coalesce(p_decision, ''))) in ('approve', 'approved') then 'approve'
    when lower(trim(coalesce(p_decision, ''))) in ('reject', 'rejected') then 'reject'
    when lower(trim(coalesce(p_decision, ''))) in ('return', 'returned') then 'return'
    else lower(trim(coalesce(p_decision, '')))
  end;

  if v_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if v_decision = 'return' and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;

  if v_req.status not in ('pending', 'under_review', 'escalated') then
    raise exception 'request_not_actionable: request status is %', v_req.status using errcode = '22023';
  end if;

  -- فحص تداخل الإجازات عند الاعتماد
  if v_decision = 'approve' and v_req.request_type = 'leave' then
    v_chk_start := nullif(coalesce(v_req.payload->>'startDate', v_req.payload->>'start_date'), '')::date;
    v_chk_end   := nullif(coalesce(v_req.payload->>'endDate', v_req.payload->>'end_date'), '')::date;
    if v_chk_start is not null and v_chk_end is not null then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_req.employee_id
          and r.id <> v_req.id
          and r.request_type = 'leave'
          and r.status = 'approved'
          and nullif(coalesce(r.payload->>'startDate', r.payload->>'start_date'), '')::date <= v_chk_end
          and nullif(coalesce(r.payload->>'endDate', r.payload->>'end_date'), '')::date >= v_chk_start
      ) then
        raise exception 'لا يمكن اعتماد الطلب: يوجد بالفعل إجازة أخرى معتمدة للموظف تغطي نفس الفترة' using errcode = '22023';
      end if;

      -- إلغاء أي أذونات معتمدة أو معلقة في هذا اليوم
      update public.requests
      set status = 'cancelled',
          review_note = 'تم إلغاء الإذن تلقائياً لاعتماد إجازة كاملة للموظف في نفس اليوم',
          updated_at = now()
      where employee_id = v_req.employee_id
        and request_type in ('late_permit', 'early_permit', 'attendance_permit')
        and status in ('pending', 'approved')
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date >= v_chk_start
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date <= v_chk_end;
    end if;
  end if;

  -- فحص الأدوار والصلاحيات
  v_is_exec := public.is_employee_executive(v_me);
  v_is_hr := public.current_has_active_role(array['admin','super-admin','executive','executive-director','hr-manager']);
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-officer']);
  v_is_direct_mgr := (
    v_req.manager_employee_id = v_me
    or public.is_manager_of(v_me, v_req.employee_id)
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
  );

  v_is_clinic_mgr := (
    v_me in (
      '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
      'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
    )
    and public.is_clinic_team_member(v_req.employee_id)
  );

  if auth.role() = 'service_role' or v_is_clinic_mgr or v_is_exec or v_is_hr or v_is_operations or v_is_direct_mgr then
    v_authorized := true;
  end if;

  select s.* into v_step
  from public.request_steps s
  where s.request_id = p_request_id and s.status in ('active','escalated')
  order by (s.status = 'active') desc, s.step_order limit 1;

  if not v_authorized and v_step.id is not null and v_step.assignee_employee_id = v_me then
    v_authorized := true;
  end if;

  if not v_authorized then
    raise exception 'not_authorized_for_step' using errcode = '42501';
  end if;

  v_actor_role := case
    when v_is_exec then 'executive'
    when v_is_clinic_mgr then 'clinic_manager'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_operations then 'operations_manager'
    when v_is_hr then 'hr_manager'
    else 'approver'
  end;

  v_actor_role_name := case
    when v_is_exec then 'المدير التنفيذي'
    when v_is_clinic_mgr then 'مدير العيادات'
    when v_is_direct_mgr then 'المدير المباشر'
    when v_is_operations then 'مدير العمليات'
    when v_is_hr then 'إدارة الموارد البشرية'
    else 'المعتمد'
  end;

  -- ─── قرار الإرجاع للتعديل ───
  if v_decision = 'return' then
    if v_step.id is not null then
      update public.request_steps
      set status = 'returned', acted_at = now(), acted_by = v_me, comment = p_comment, updated_at = now()
      where id = v_step.id;
    end if;

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, 'return', v_req.status, 'returned', p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = 'returned',
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      'طلبك بحاجة لتعديل',
      coalesce(v_req.title, '') || ' — تم إرجاعه بواسطة ' || v_actor_role_name || ': ' || coalesce(p_comment, ''),
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', 'returned', 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- ─── قرار الرفض ───
  if v_decision = 'reject' then
    if v_step.id is not null then
      update public.request_steps
      set status = 'rejected', acted_at = now(), acted_by = v_me, comment = p_comment, updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'skipped', updated_at = now()
    where request_id = p_request_id and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and status in ('active', 'pending', 'escalated');

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, 'reject', v_req.status, 'rejected', p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = 'rejected',
        workflow_status = 'terminated',
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        begin
          perform public.decide_attendance_correction(v_correction_id, 'rejected', coalesce(p_comment, 'مرفوض'));
        exception when others then
          update public.attendance_corrections
          set status = 'rejected', reviewed_by = v_me, reviewed_at = now(), review_note = p_comment, updated_at = now()
          where id = v_correction_id;
        end;
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      'تم رفض طلبك',
      coalesce(v_req.title, '') || ' — تم الرفض بواسطة ' || v_actor_role_name || case when p_comment is not null then ': ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', 'rejected', 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- ─── قرار الاعتماد (approve) ───
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
  set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and status in ('active', 'pending', 'escalated');

  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = p_comment,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- تنفيذ الآثار الجانبية التلقائية للاعتماد:
  -- أ) إعفاء وإلغاء الغرامات فوراً لطلبات الفاندي الترفيهي، المأموريات، الإجازات، والقوافل
  if v_req.request_type in (
    'fundraising', 'fandy', 'fundi',
    'mission', 'external_mission', 'administrative_mission',
    'convoy', 'field_convoy',
    'leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave',
    'remote_work', 'compensation'
  ) or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy', 'convoy', 'mission') then
    v_chk_start := coalesce(
      public.try_cast_date(v_req.payload->>'startDate'),
      public.try_cast_date(v_req.payload->>'start_date'),
      v_req.created_at::date
    );
    v_chk_end := coalesce(
      public.try_cast_date(v_req.payload->>'endDate'),
      public.try_cast_date(v_req.payload->>'end_date'),
      v_chk_start
    );

    if v_chk_start is not null and v_chk_end is not null then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'اعتماد طلب رسمي (' ||
               case
                 when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy')
                   then 'فاندي ترفيهي'
                 when v_req.request_type in ('mission', 'external_mission') or coalesce(v_req.payload->>'missionType', '') = 'mission'
                   then 'مأمورية عمل'
                 when v_req.request_type in ('convoy', 'field_convoy')
                   then 'قافلة ميدانية'
                 when v_req.request_type like '%leave%'
                   then 'إجازة معتمدة'
                 else v_req.request_type
               end || ') يغطي هذا اليوم',
             notes = coalesce(notes || ' | ', '') || 'أُلغيت الغرامة تلقائياً لاعتماد طلب ' ||
               case
                 when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy')
                   then 'فاندي ترفيهي'
                 else v_req.request_type
               end,
             updated_at = now()
       where employee_id = v_req.employee_id
         and work_date between v_chk_start and v_chk_end
         and status in ('pending_payment', 'doubled', 'suspended');

      get diagnostics v_cancelled_pens = row_count;
    end if;
  end if;

  -- ب) إسقاط الغرامات وتصفير دقائق التأخير ورفع الحظر فوراً عند اعتماد الأذونات وتصاريح العمل وأعذار التأخير
  if v_req.request_type in ('early_permit', 'late_permit', 'attendance_permit', 'permit', 'permission', 'errand', 'late_excuse') then
    v_eff_date := coalesce(
      public.try_cast_date(v_req.payload->>'permitDate'),
      public.try_cast_date(v_req.payload->>'date'),
      public.try_cast_date(v_req.payload->>'startDate'),
      public.try_cast_date(v_req.payload->>'start_date'),
      public.try_cast_date(v_req.payload->>'workDate'),
      v_req.created_at::date
    );

    if v_eff_date is not null then
      -- 1. إلغاء أي غرامة فورية مسجلة على الموظف في هذا اليوم تلقائياً
      with cancelled as (
        update public.instant_attendance_penalties
           set status = 'cancelled',
               cancelled_reason = 'اعتماد ' ||
                 case
                   when v_req.request_type = 'late_excuse' then 'عذر تأخير رسمي'
                   when v_req.request_type in ('early_permit', 'late_permit', 'permit', 'permission') then 'إذن عمل معتمد'
                   else 'طلب رسمي'
                 end || ' (طلب #' || v_req.request_number || ')',
               notes = coalesce(notes || ' | ', '') || 'أُلغيت الغرامة تلقائياً لاعتماد ' ||
                 case
                   when v_req.request_type = 'late_excuse' then 'عذر التأخير'
                   else 'إذن العمل'
                 end,
               updated_at = now()
         where employee_id = v_req.employee_id
           and work_date = v_eff_date
           and status in ('pending_payment', 'doubled', 'suspended')
         returning id
      )
      select count(*) into v_cancelled_pens from cancelled;

      -- 2. تصفير دقائق التأخير في سجل الحضور اليومي
      update public.attendance_daily
         set late_minutes = 0,
             status = case when status in ('late', 'unexcused_absent', 'absent') then 'present' else status end,
             updated_at = now()
       where employee_id = v_req.employee_id
         and work_date = v_eff_date;

      -- 3. رفع الإيقاف عن حساب الموظف فوراً إذا لم يعد لديه غرامات أخرى معلقة
      if not exists (
        select 1 from public.instant_attendance_penalties
        where employee_id = v_req.employee_id
          and status in ('doubled', 'suspended')
      ) then
        update public.employees
           set status = 'active',
               is_active = true,
               updated_at = now()
         where id = v_req.employee_id
           and status = 'suspended';

        update public.profiles
           set status = 'active',
               updated_at = now()
         where employee_id = v_req.employee_id
           and status = 'suspended';
      end if;

      -- 4. محاولة إسقاط ساعات العمل إن كان هناك أي أثر
      begin
        perform public.auto_waive_penalty_if_completed_eight_hours(v_req.employee_id, v_eff_date);
      exception when others then
        null;
      end;
    end if;
  end if;

  -- ج) تصحيح البصمة
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'approved', coalesce(p_comment, 'معتمد مع الطلب'));
      exception when others then
        update public.attendance_corrections
        set status = 'approved',
            reviewed_by = coalesce(reviewed_by, v_me),
            reviewed_at = coalesce(reviewed_at, now()),
            review_note = coalesce(review_note, p_comment)
        where id = v_correction_id;
      end;
    end if;
  end if;

  -- د) تنشيط الإجازة
  if v_req.request_type = 'leave' then
    begin
      perform public.activate_approved_leave(v_req.id);
    exception when others then
      null;
    end;
  end if;

  -- إشعار الموظف بالاعتماد
  perform public.notify_employee(
    v_req.employee_id,
    '🎉 تم اعتماد طلبك بنجاح',
    coalesce(v_req.title, '') || ' — تم الاعتماد بواسطة ' || v_actor_role_name ||
      case when v_cancelled_pens > 0 then ' (وتم إسقاط غرامات التأخير لهذا اليوم تلقائياً)' else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'requestId', v_req.id, 'penaltiesCancelled', v_cancelled_pens)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;

comment on function public.decide_request(uuid, text, text) is
  '0731: تحديث decide_request لإلغاء الغرامة الفورية وتصفير دقائق التأخير ورفع الحظر فوراً عند اعتماد عذر التأخير أو إذن العمل.';
