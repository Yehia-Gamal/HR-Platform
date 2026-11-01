-- 0716_prevent_duplicate_leaves_and_cap_monthly_permits.sql
-- قفل حماية الإجازات (منع التكرار والتداخل وسحب الأذونات المتعارضة)
-- وضع سقف صارم للأذونات الشهرية (4 أذونات شهرياً لكل موظف)
-- تصحيح مزامنة تواريخ بصمة الانصراف وتفاصيل طلبات التصحيح

begin;

-- ─── 1) دالة قفل حماية الإجازات ومنع التداخل ──────────────────────────────────
create or replace function public.trg_fn_prevent_leave_overlap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start date;
  v_end   date;
begin
  if new.request_type = 'leave' and new.status in ('pending', 'approved') then
    v_start := nullif(coalesce(new.payload->>'startDate', new.payload->>'start_date'), '')::date;
    v_end   := nullif(coalesce(new.payload->>'endDate', new.payload->>'end_date'), '')::date;

    if v_start is not null and v_end is not null then
      -- التحقق من عدم وجود إجازة أخرى معتمدة أو قيد المراجعة تتداخل مع نفس الفترة
      if exists (
        select 1 from public.requests r
        where r.employee_id = new.employee_id
          and r.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.request_type = 'leave'
          and r.status in ('pending', 'approved')
          and nullif(coalesce(r.payload->>'startDate', r.payload->>'start_date'), '')::date <= v_end
          and nullif(coalesce(r.payload->>'endDate', r.payload->>'end_date'), '')::date >= v_start
      ) then
        raise exception 'يوجد بالفعل طلب إجازة آخر مسجل (معتمد أو قيد المراجعة) يغطي نفس هذا اليوم أو الفترة' using errcode = '22023';
      end if;

      -- سحب/إلغاء أي أذونات متداخلة في نفس أيام الإجازة
      update public.requests
      set status = case when status = 'approved' then 'cancelled' else 'withdrawn' end,
          review_note = case
            when status = 'approved' then 'تم إلغاء الإذن تلقائياً نظراً لاعتماد إجازة كاملة في نفس اليوم'
            else 'تم سحب الإذن تلقائياً نظراً لتقديم طلب إجازة في نفس اليوم'
          end,
          updated_at = now()
      where employee_id = new.employee_id
        and request_type in ('late_permit', 'early_permit', 'attendance_permit')
        and status in ('pending', 'approved')
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date >= v_start
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date <= v_end;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_leave_overlap on public.requests;
create trigger trg_prevent_leave_overlap
  before insert or update of payload, status, request_type on public.requests
  for each row
  execute function public.trg_fn_prevent_leave_overlap();

-- ─── 2) دالة فرض سقف الأذونات الشهري (4 أذونات كحد أقصى) ──────────────────────
create or replace function public.trg_fn_enforce_permit_monthly_cap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_permit_date date;
  v_month_count integer;
begin
  if new.request_type in ('late_permit', 'early_permit', 'attendance_permit')
     and new.status in ('pending', 'approved') then
    v_permit_date := nullif(coalesce(new.payload->>'permitDate', new.payload->>'date'), '')::date;

    if v_permit_date is not null then
      -- 1) التحقق من عدم وجود إجازة معتمدة أو معلقة في نفس يوم الإذن
      if exists (
        select 1 from public.requests r
        where r.employee_id = new.employee_id
          and r.request_type = 'leave'
          and r.status in ('pending', 'approved')
          and nullif(coalesce(r.payload->>'startDate', r.payload->>'start_date'), '')::date <= v_permit_date
          and nullif(coalesce(r.payload->>'endDate', r.payload->>'end_date'), '')::date >= v_permit_date
      ) then
        raise exception 'لا يمكن طلب إذن في يوم مسجل كإجازة (معتمدة أو قيد المراجعة)' using errcode = '22023';
      end if;

      -- 2) التحقق من عدم وجود إذن آخر في نفس اليوم
      if exists (
        select 1 from public.requests r
        where r.employee_id = new.employee_id
          and r.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.request_type in ('late_permit', 'early_permit', 'attendance_permit')
          and r.status in ('pending', 'approved')
          and nullif(coalesce(r.payload->>'permitDate', r.payload->>'date'), '')::date = v_permit_date
      ) then
        raise exception 'يوجد بالفعل إذن آخر مسجل (معتمد أو قيد المراجعة) في نفس هذا اليوم' using errcode = '22023';
      end if;

      -- 3) التحقق من السقف الشهري (4 أذونات كحد أقصى للشهر الميلادي)
      select count(*) into v_month_count
      from public.requests r
      where r.employee_id = new.employee_id
        and r.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
        and r.request_type in ('late_permit', 'early_permit', 'attendance_permit')
        and r.status in ('pending', 'approved')
        and date_trunc('month', nullif(coalesce(r.payload->>'permitDate', r.payload->>'date'), '')::date) = date_trunc('month', v_permit_date);

      if v_month_count >= 4 then
        raise exception 'لقد استنفدت الحد الأقصى للأذونات المسموح بها هذا الشهر (4 أذونات شهرياً كحد أقصى)' using errcode = '22023';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_permit_monthly_cap on public.requests;
create trigger trg_enforce_permit_monthly_cap
  before insert or update of payload, status, request_type on public.requests
  for each row
  execute function public.trg_fn_enforce_permit_monthly_cap();

-- ─── 3) تحديث دالة decide_attendance_correction لضمان دقة يوم العمل ───────────
create or replace function public.decide_attendance_correction(
  p_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.attendance_corrections;
  v_me  uuid := public.current_employee_id();
  v_effective_checkout timestamptz;
begin
  select * into strict v_row from public.attendance_corrections where id = p_id for update;

  if not (
    auth.role() = 'service_role'
    or public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','hr-manager','operations-manager-1'])
    or (
      v_row.employee_id is distinct from v_me
      and (
        public.can_access_employee(v_row.employee_id, 'attendance.correction.review')
        or public.is_manager_of(v_me, v_row.employee_id)
        or exists (
          select 1 from public.requests r
          where (r.payload->>'correctionId')::uuid = v_row.id
            and (r.manager_employee_id = v_me or r.created_by = auth.uid())
        )
      )
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- إن كان القرار قد اتُّخذ مسبقاً بنفس الحالة، نخرج بنجاح (idempotent)
  if v_row.status = p_decision then
    return;
  end if;

  if v_row.status <> 'pending' or p_decision not in ('approved','rejected') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  if p_decision = 'rejected' and length(trim(coalesce(p_note, '')))<3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  v_effective_checkout := v_row.requested_check_out;
  if v_effective_checkout is not null then
    declare
      v_cur_checkin timestamptz;
    begin
      select first_check_in into v_cur_checkin from public.attendance_daily
       where employee_id = v_row.employee_id and work_date = v_row.work_date;
      if v_cur_checkin is not null and v_effective_checkout < v_cur_checkin then
        if v_effective_checkout + interval '1 day' > v_cur_checkin then
          v_effective_checkout := v_effective_checkout + interval '1 day';
        end if;
      end if;
    end;
  end if;

  update public.attendance_corrections
  set status = p_decision,
      reviewed_by = v_me,
      reviewed_at = now(),
      review_note = p_note,
      requested_check_out = v_effective_checkout,
      updated_at = now()
  where id = p_id;

  if p_decision = 'approved' then
    insert into public.attendance_daily(
      employee_id, work_date, first_check_in, last_check_out, status, is_finalized, created_by
    ) values (
      v_row.employee_id, v_row.work_date, v_row.requested_check_in, v_effective_checkout,
      coalesce(v_row.requested_status, 'present'), false, auth.uid()
    )
    on conflict (employee_id, work_date) do update
      set first_check_in = coalesce(v_row.requested_check_in, attendance_daily.first_check_in),
          last_check_out = coalesce(v_effective_checkout, attendance_daily.last_check_out),
          status = coalesce(v_row.requested_status, 'present'),
          updated_at = now();
  end if;

  -- مزامنة الطلب المرتبط إن وجد
  update public.requests
     set status = case when p_decision = 'approved' then 'approved' else 'rejected' end,
         workflow_status = case when p_decision = 'approved' then 'completed' else 'terminated' end,
         decided_at = now()
   where (payload->>'correctionId')::uuid = p_id
     and status = 'pending';

  perform public.notify_employee(
    v_row.employee_id,
    case when p_decision = 'approved' then 'تم قبول تصحيح الحضور' else 'تم رفض تصحيح الحضور' end,
    'تصحيح حضور بتاريخ ' || v_row.work_date || case when p_note is not null then ' — ' || p_note else '' end,
    'attendance', 'normal', 'attendance_correction', p_id,
    jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date)
  );
end;
$$;

revoke all on function public.decide_attendance_correction(uuid, text, text) from public, anon;
grant execute on function public.decide_attendance_correction(uuid, text, text) to authenticated, service_role;

-- ─── 4) تحديث دالة decide_request للتأكد من فحص قفل الإجازات وسحب الأذونات ─────
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
  v_eff_date        date;
  v_chk_start       date;
  v_chk_end         date;
begin
  if v_me is null then
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

  -- صلاحيات الاعتماد
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
        and mr.effective_from <= current_date
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

  if v_is_clinic_mgr or v_is_exec or v_is_hr or v_is_operations or v_is_direct_mgr then
    v_authorized := true;
  end if;

  if not v_authorized then
    select s.* into v_step
    from public.request_steps s
    where s.request_id = p_request_id and s.status in ('active','escalated')
    order by s.step_order limit 1;

    if v_step.id is not null and v_step.approver_employee_id = v_me then
      v_authorized := true;
    end if;
  end if;

  if not v_authorized then
    raise exception 'not_authorized_for_step' using errcode = '42501';
  end if;

  if v_step.id is null then
    select s.* into v_step
    from public.request_steps s
    where s.request_id = p_request_id and s.status in ('active','escalated')
    order by s.step_order limit 1;
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

  -- اعتماد (approve):
  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  update public.request_steps
  set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and status in ('active', 'pending', 'escalated');

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = p_comment,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- تنفيذ الآثار الجانبية:
  if v_req.request_type in ('early_permit', 'late_permit', 'attendance_permit', 'permit') then
    v_eff_date := coalesce(
      public.try_cast_date(v_req.payload->>'permitDate'),
      public.try_cast_date(v_req.payload->>'date'),
      public.try_cast_date(v_req.payload->>'startDate'),
      v_req.created_at::date
    );
    begin
      if v_eff_date is not null then
        perform public.auto_waive_penalty_if_completed_eight_hours(v_req.employee_id, v_eff_date);
      end if;
    exception when others then
      null;
    end;
  end if;

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

  if v_req.request_type = 'leave' then
    begin
      perform public.activate_approved_leave(v_req.id);
    exception when others then
      null;
    end;
  end if;

  perform public.notify_employee(
    v_req.employee_id,
    '🎉 تم اعتماد طلبك بنجاح',
    coalesce(v_req.title, '') || ' — تم الاعتماد بواسطة ' || v_actor_role_name,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;

commit;
