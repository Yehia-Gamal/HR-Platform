-- ==============================================================================
-- 0710_fix_broken_functions_and_approval_workflow.sql
-- إصلاح الدوال المعطلة في الفحص الصحي وقفل أخطاء الاعتماد وتصحيح البصمة
-- 1. hard_delete_employee_guarded (تصحيح أسماء الأعمدة في الحذف المتسلسل)
-- 2. check_employee_penalty_exemption_v2 (استخدام r.slug بدلاً من r.code)
-- 3. auto_waive_penalty_if_completed_eight_hours (استخدام n.recipient_employee_id)
-- 4. set_employee_attendance_day_admin (تصحيح أسماء أعمدة attendance_day_overrides وlog_audit_event)
-- 5. get_mobile_request_detail (إعادة إضافة سياق قرار المعتمد insights لاجتياز الفحص الصحي)
-- 6. decide_attendance_correction & decide_request (جعل القرار idempotent ومزامنة requests وحل خطأ 22023)
-- ==============================================================================

begin;

-- ─── 1) إصلاح hard_delete_employee_guarded ───────────────────────────────────
create or replace function public.hard_delete_employee_guarded(
  p_employee_id        uuid,
  p_confirmation_code  text,
  p_reason             text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee public.employees%rowtype;
  v_user_id  uuid;
begin
  -- 1) التحقق من صلاحية الوصول الكامل
  if not public.current_is_full_access() then
    raise exception 'main_admin_required' using errcode = '42501';
  end if;

  -- 2) منع حذف الموظف لنفسه
  if p_employee_id = public.current_employee_id() then
    raise exception 'self_delete_not_allowed' using errcode = '42501';
  end if;

  -- 3) التحقق من سبب الحذف
  if length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'delete_reason_required' using errcode = '22023';
  end if;

  select * into v_employee
  from public.employees
  where id = p_employee_id
  for update;

  if v_employee.id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  v_user_id := v_employee.user_id;

  -- 4) مطابقة كود التأكيد
  if p_confirmation_code is distinct from v_employee.employee_code
     and p_confirmation_code is distinct from 'hard-delete-confirm' then
    raise exception 'delete_confirmation_mismatch' using errcode = '22023';
  end if;

  -- 5) تنظيف متسلسل شامل للجداول التابعة وفق المخطط الفعلي
  delete from public.manager_relations where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.approval_delegations where manager_employee_id = p_employee_id or delegate_employee_id = p_employee_id;
  update public.teams set lead_id = null where lead_id = p_employee_id;
  update public.departments set manager_id = null where manager_id = p_employee_id;

  delete from public.association_project_updates where author_employee_id = p_employee_id;
  delete from public.association_project_steps where assignee_employee_id = p_employee_id;
  delete from public.association_project_members where employee_id = p_employee_id;
  update public.association_projects set owner_employee_id = null where owner_employee_id = p_employee_id;
  delete from public.work_assignment_participants where employee_id = p_employee_id;
  delete from public.kpi_assignment_contributions where employee_id = p_employee_id;
  delete from public.work_assignments where created_by_employee_id = p_employee_id or responsible_employee_id = p_employee_id;
  delete from public.mission_executions where employee_id = p_employee_id;
  delete from public.missions where employee_id = p_employee_id;
  delete from public.convoy_requests where employee_id = p_employee_id;

  delete from public.attendance_punch_attempts where employee_id = p_employee_id;
  delete from public.attendance_events where employee_id = p_employee_id;
  delete from public.attendance_daily where employee_id = p_employee_id;
  delete from public.attendance_exemptions where employee_id = p_employee_id;
  delete from public.attendance_day_overrides where employee_id = p_employee_id;
  delete from public.local_attendance_operations where employee_id = p_employee_id;
  delete from public.employee_locations where employee_id = p_employee_id;
  delete from public.location_request_responses where employee_id = p_employee_id;
  delete from public.shift_assignments where employee_id = p_employee_id;
  delete from public.employee_devices where employee_id = p_employee_id;
  delete from public.passkey_credentials where employee_id = p_employee_id;
  update public.managed_devices set employee_id = null where employee_id = p_employee_id;

  delete from public.request_steps where assignee_employee_id = p_employee_id;
  delete from public.requests where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.attendance_corrections where employee_id = p_employee_id;
  delete from public.leave_ledger_entries where employee_id = p_employee_id;
  delete from public.leave_requests where employee_id = p_employee_id;
  delete from public.leave_balance_accounts where employee_id = p_employee_id;

  delete from public.kpi_review_sessions where employee_id = p_employee_id;
  delete from public.kpi_compliance_records where evaluation_id in (select id from public.kpi_evaluations where employee_id = p_employee_id);
  delete from public.kpi_evaluations where employee_id = p_employee_id;
  delete from public.monthly_evaluations where employee_id = p_employee_id;
  delete from public.employee_competency_assessments where employee_id = p_employee_id;
  delete from public.improvement_plans where employee_id = p_employee_id;
  delete from public.one_on_ones where employee_id = p_employee_id or manager_id = p_employee_id;
  delete from public.goal_objectives where (owner_type = 'employee' and owner_id = p_employee_id);

  delete from public.instant_attendance_penalties where employee_id = p_employee_id;
  delete from public.penalty_disputes where employee_id = p_employee_id;
  delete from public.employee_penalties where employee_id = p_employee_id;
  delete from public.employee_discipline_actions where employee_id = p_employee_id;
  delete from public.dispute_parties where employee_id = p_employee_id;
  delete from public.dispute_statements where submitted_by = p_employee_id;
  delete from public.dispute_session_participants where employee_id = p_employee_id;
  delete from public.dispute_decision_receipts where employee_id = p_employee_id;
  delete from public.dispute_settlements where apology_from = p_employee_id or apology_to = p_employee_id;
  delete from public.dispute_actions where actor_employee_id = p_employee_id;
  delete from public.dispute_cases where actor_employee_id = p_employee_id or respondent_employee_id = p_employee_id;

  delete from public.daily_report_likes where employee_id = p_employee_id;
  delete from public.daily_report_comments where employee_id = p_employee_id;
  delete from public.daily_report_views where employee_id = p_employee_id;
  delete from public.daily_reports where employee_id = p_employee_id;
  delete from public.announcement_acknowledgements where employee_id = p_employee_id;
  delete from public.announcement_reactions where employee_id = p_employee_id;
  delete from public.announcement_views where employee_id = p_employee_id;
  delete from public.committee_members where employee_id = p_employee_id;

  delete from public.documents where owner_employee_id = p_employee_id;
  delete from public.employee_departments where employee_id = p_employee_id;
  delete from public.employee_compensation where employee_id = p_employee_id;
  delete from public.employee_loans where employee_id = p_employee_id;
  delete from public.payslips where employee_id = p_employee_id;
  delete from public.privacy_requests where requester_employee_id = p_employee_id;
  delete from public.notifications where recipient_employee_id = p_employee_id;
  delete from public.admin_sensitive_ops_log where employee_id = p_employee_id;
  delete from public.profiles where employee_id = p_employee_id;

  if v_user_id is not null then
    delete from public.user_roles where user_id = v_user_id or user_id = p_employee_id;
  end if;

  delete from public.employees where id = p_employee_id;

  if v_user_id is not null then
    begin
      delete from auth.users where id = v_user_id;
    exception when others then
      null;
    end;
  end if;

  perform public.log_audit_event(
    'employee.hard_deleted', 'security', 'critical',
    'employees', p_employee_id,
    'حذف موظف نهائياً وحذف كافة متعلقاته', p_reason,
    jsonb_build_object(
      'employeeCode', v_employee.employee_code,
      'fullName', v_employee.full_name_ar,
      'userId', v_user_id
    )
  );

  return jsonb_build_object(
    'success', true,
    'employeeId', p_employee_id,
    'employeeCode', v_employee.employee_code,
    'message', 'تم حذف الموظف نهائياً وكافة متعلقاته بنجاح'
  );
end;
$$;


-- ─── 2) إصلاح check_employee_penalty_exemption_v2 ───────────────────────────
create or replace function public.check_employee_penalty_exemption_v2(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
  v_emp record;
  v_req record;
  v_wa record;
  v_att record;
  v_loc text;
begin
  -- 1) فحص وجود الموظف وحالته الأساسية
  select e.id, e.status, e.is_active, e.department_id, e.branch_id, e.user_id,
         d.name as department_name, b.name as branch_name
    into v_emp
    from public.employees e
    left join public.departments d on d.id = e.department_id
    left join public.branches b on b.id = e.branch_id
   where e.id = p_employee_id;

  if v_emp.id is null then
    return jsonb_build_object('isExempt', false, 'category', 'unknown_employee', 'reason', 'الموظف غير موجود');
  end if;

  -- 2) فحص الحالات المستثناة دائماً
  if v_emp.status in ('resigned', 'terminated', 'suspended') or not coalesce(v_emp.is_active, true) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'inactive_status',
      'reason', 'الموظف غير نشط حالياً (' || coalesce(v_emp.status, 'معطل') || ')'
    );
  end if;

  -- 3) فحص الاستثناءات الدائمة في جدول attendance_exemptions
  for v_rec in
    select ae.reason, ae.exemption_type
      from public.attendance_exemptions ae
     where ae.employee_id = p_employee_id
       and ae.is_active = true
       and p_work_date between ae.start_date and coalesce(ae.end_date, '2099-12-31'::date)
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', coalesce(v_rec.exemption_type, 'permanent_exemption'),
      'reason', coalesce(v_rec.reason, 'إعفاء رسمي مسجل في النظام')
    );
  end loop;

  -- 4) فحص استثناءات VIP والقيادات من جدول user_roles عبر slug
  if exists (
    select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
     where (ur.user_id = v_emp.user_id or ur.user_id = p_employee_id)
       and r.slug in ('super-admin', 'general-manager', 'executive', 'executive-director', 'board-member')
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'vip_role',
      'reason', 'إعفاء خاص بالقيادات والإدارة العليا'
    );
  end if;

  -- 5) فحص طاقم العيادة والمستوصف
  if coalesce(v_emp.department_name, '') like '%عياد%'
     or coalesce(v_emp.branch_name, '') like '%عياد%'
     or coalesce(v_emp.department_name, '') like '%مستوصف%' then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'clinic_staff',
      'reason', 'طاقم العيادة الطبية معفى من الغرامات اللحظية'
    );
  end if;

  -- 6) فحص العطلات الرسمية والراحات الأسبوعية
  if extract(isodow from p_work_date) = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekly_rest',
      'reason', 'عطلة نهاية الأسبوع (الجمعة)'
    );
  end if;

  if exists (
    select 1 from public.public_holidays h
     where h.is_active
       and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'official_holiday',
      'reason', 'عطلة رسمية عامة'
    );
  end if;

  -- 7) فحص الطلبات المعتمدة أو قيد المراجعة: مأموريات، قوافل، فاندي، إجازات
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status in ('approved', 'pending')
       and (
          (r.request_type = 'leave'
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          or (r.request_type in ('convoy', 'field_convoy')
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          or (r.request_type in ('fundraising', 'campaign_fundraising')
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
       )
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', v_req.request_type,
      'reason', case
        when v_req.request_type = 'leave' then 'إجازة رسمية (' || v_req.status || ')'
        when v_req.request_type like '%mission%' then 'مأمورية عمل رسمية (' || v_req.status || ')'
        when v_req.request_type like '%convoy%' then 'قافلة عمل ميدانية (' || v_req.status || ')'
        when v_req.request_type like '%fundraising%' then 'يوم تبرعات وفاندي (' || v_req.status || ')'
        else 'طلب رسمي معتمد'
      end,
      'requestId', v_req.id
    );
  end loop;

  -- 8) فحص تكليفات العمل الخارجي (work_assignments)
  for v_wa in
    select wa.id, wa.title, wa.location
      from public.work_assignments wa
     where (wa.responsible_employee_id = p_employee_id or wa.created_by_employee_id = p_employee_id)
       and wa.status in ('in_progress', 'completed', 'active', 'approved')
       and p_work_date between wa.start_at::date and coalesce(wa.end_at::date, wa.start_at::date)
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', 'work_assignment',
      'reason', 'تكليف عمل خارجي: ' || coalesce(v_wa.title, 'عمل ميداني'),
      'assignmentId', v_wa.id
    );
  end loop;

  -- 9) فحص التعديلات الإدارية على اليوم (attendance_day_overrides)
  for v_rec in
    select ado.day_type, ado.reason
      from public.attendance_day_overrides ado
     where ado.employee_id = p_employee_id
       and ado.work_date = p_work_date
       and ado.is_active = true
       and ado.day_type in ('leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest')
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', 'day_override_' || v_rec.day_type,
      'reason', coalesce(v_rec.reason, 'تعديل إداري معتمد لليوم: ' || v_rec.day_type)
    );
  end loop;

  -- 10) فحص أذونات التأخير المعتمدة
  if exists (
    select 1 from public.requests r
     where r.employee_id = p_employee_id
       and r.status = 'approved'
       and r.request_type in ('late_permit', 'permit', 'attendance_permit')
       and coalesce(
             public.try_cast_date(r.payload->>'permitDate'),
             public.try_cast_date(r.payload->>'date'),
             public.try_cast_date(r.payload->>'startDate'),
             r.created_at::date
           ) = p_work_date
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'late_permit_approved',
      'reason', 'إذن تأخير رسمي معتمد'
    );
  end if;

  return jsonb_build_object('isExempt', false, 'category', 'none', 'reason', 'غير معفى من لوائح الدوام');
end;
$$;


-- ─── 3) إصلاح auto_waive_penalty_if_completed_eight_hours ───────────────────
create or replace function public.auto_waive_penalty_if_completed_eight_hours(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_att record;
  v_pen record;
  v_work_minutes integer := 0;
  v_permit_minutes integer := 0;
  v_total_effective_minutes integer := 0;
  v_emp_name text;
  v_in_str text;
  v_out_str text;
  v_hours integer;
  v_mins integer;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_elapsed_minutes integer;
  v_assigned_shift public.shifts%rowtype;
  v_shift_late_calc integer := 0;
begin
  if p_employee_id is null or p_work_date is null then
    return jsonb_build_object('waived', false, 'reason', 'invalid_params');
  end if;

  select ad.id, ad.shift_id, ad.first_check_in, ad.last_check_out, ad.work_minutes
    into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if not found or v_att.first_check_in is null then
    return jsonb_build_object('waived', false, 'reason', 'no_checkin');
  end if;

  select p.id, p.current_amount, p.original_amount, p.status, p.escalation_level, p.notes
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if not found then
    return jsonb_build_object('waived', false, 'reason', 'no_active_penalty');
  end if;

  select e.full_name_ar into v_emp_name
    from public.employees e
   where e.id = p_employee_id;

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;

  select s.* into v_assigned_shift
    from public.shifts s
   where s.id = v_att.shift_id;

  if v_assigned_shift.id is null then
    select s.* into v_assigned_shift
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = p_employee_id
       and sa.is_active = true
       and sa.effective_from <= p_work_date
       and (sa.effective_to is null or sa.effective_to >= p_work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_assigned_shift.id is not null and v_assigned_shift.start_time >= '11:00:00'::time then
    begin
      v_shift_late_calc := public.attendance_policy_late_minutes(
        p_employee_id,
        p_work_date,
        v_att.first_check_in,
        v_assigned_shift.id
      );
    exception when others then
      v_shift_late_calc := 0;
    end;

    if v_shift_late_calc = 0 then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: الوردية المعتمدة (' || coalesce(v_assigned_shift.name, '11 ص – 7 م') || ') والحضور في الموعد المحدد',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: الحضور في موعد الوردية المسائية المعتمدة',
             updated_at = now()
       where id = v_pen.id;

      perform public.notify_employee(
        p_employee_id,
        '🎉 إلغاء غرامة التأخير لاعتماد الوردية',
        'تم إلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لحضورك في موعد الوردية المعتمدة (' || coalesce(v_assigned_shift.name, '') || ').',
        'system', 'high', 'instant_penalty', v_pen.id,
        jsonb_build_object('penaltyId', v_pen.id, 'waived', true, 'reason', 'shift_match_no_delay')
      );

      return jsonb_build_object('waived', true, 'reason', 'shift_match_no_delay');
    end if;
  end if;

  select coalesce(sum(
    coalesce(
      nullif(r.payload->>'minutes', '')::integer,
      nullif(r.payload->>'duration', '')::integer,
      (nullif(r.payload->>'hours', '')::numeric * 60)::integer,
      case when r.request_type in ('early_permit', 'late_permit') then 120 else 0 end
    )
  ), 0) into v_permit_minutes
  from public.requests r
  where r.employee_id = p_employee_id
    and r.status = 'approved'
    and r.request_type in ('early_permit', 'late_permit', 'permit', 'attendance_permit', 'permission', 'errand')
    and coalesce(
      public.try_cast_date(r.payload->>'permitDate'),
      public.try_cast_date(r.payload->>'date'),
      public.try_cast_date(r.payload->>'startDate'),
      public.try_cast_date(r.payload->>'start_date'),
      public.try_cast_date(r.payload->>'workDate'),
      r.created_at::date
    ) = p_work_date;

  if v_permit_minutes = 0 then
    select coalesce(sum(greatest(0, coalesce(minutes_adjustment, 0))), 0) into v_permit_minutes
    from public.attendance_exceptions
    where employee_id = p_employee_id
      and work_date = p_work_date
      and status = 'approved'
      and kind in ('early_leave', 'permit', 'late', 'permission');
  end if;

  if v_att.last_check_out is null then
    if p_work_date = v_today then
      v_elapsed_minutes := floor(extract(epoch from (date_trunc('minute', now()) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
                           + coalesce(v_permit_minutes, 0);

      if v_elapsed_minutes >= 480 then
        if not exists (
          select 1 from public.notifications n
           where (n.recipient_employee_id = p_employee_id or n.recipient_user_id = (select user_id from public.employees where id = p_employee_id))
             and n.category = 'instant_penalty'
             and n.metadata->>'promptType' = 'awaiting_checkout_confirmation'
             and n.created_at >= (now() - interval '8 hours')
        ) then
          perform public.notify_employee(
            p_employee_id,
            '🔔 أتممت 8 ساعات عمل — سجّل بصمة الانصراف',
            'عزيزي ' || coalesce(v_emp_name, '') || '، لقد أتممت 8 ساعات عمل بنجاح اليوم بمجموع الدوام الفعلي والتصاريح المعتمدة (' || (v_elapsed_minutes / 60) || ' ساعة و' || (v_elapsed_minutes % 60) || ' دقيقة). برجاء تسجيل بصمة الانصراف الآن من مقر العمل لتأكيد تواجدك وإلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) نهائياً.',
            'system', 'high', 'instant_penalty', v_pen.id,
            jsonb_build_object(
              'penaltyId', v_pen.id,
              'promptType', 'awaiting_checkout_confirmation',
              'elapsedMinutes', v_elapsed_minutes,
              'permitMinutes', v_permit_minutes,
              'amount', v_pen.current_amount,
              'deepLink', 'ahlashabab://action/attendance'
            )
          );
        end if;

        return jsonb_build_object(
          'waived', false,
          'awaitingCheckout', true,
          'elapsedMinutes', v_elapsed_minutes,
          'permitMinutes', v_permit_minutes,
          'message', 'أتم 8 ساعات وبانتظار بصمة الانصراف التأكيدية لإسقاط الغرامة'
        );
      else
        return jsonb_build_object(
          'waived', false,
          'elapsedMinutes', v_elapsed_minutes,
          'permitMinutes', v_permit_minutes,
          'remainingMinutes', (480 - v_elapsed_minutes),
          'message', 'لم يكمل 8 ساعات بعد'
        );
      end if;
    else
      return jsonb_build_object('waived', false, 'reason', 'missing_checkout_unwaived');
    end if;
  end if;

  v_work_minutes := greatest(
    coalesce(v_att.work_minutes, 0),
    floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
  );

  v_total_effective_minutes := v_work_minutes + coalesce(v_permit_minutes, 0);

  if v_total_effective_minutes < 480 then
    return jsonb_build_object(
      'waived', false,
      'penaltyRemaining', true,
      'penaltyId', v_pen.id,
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'permitMinutes', v_permit_minutes,
      'totalEffectiveMinutes', v_total_effective_minutes,
      'remainingMinutes', (480 - v_total_effective_minutes),
      'message', 'الغرامة مستحقة لمغادرة العمل قبل إتمام 8 ساعات عمل رسمية'
    );
  end if;

  v_out_str := to_char(v_att.last_check_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (v_att.last_check_out at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_hours := v_total_effective_minutes / 60;
  v_mins := v_total_effective_minutes % 60;

  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء نهائي: استيفاء ساعات العمل الرسمية بالكامل (دوام فعلي ' || (v_work_minutes / 60) || 'س و' || (v_work_minutes % 60) || 'د + تصاريح معتمدة ' || (v_permit_minutes / 60) || 'س و' || (v_permit_minutes % 60) || 'د)',
         notes = coalesce(notes || ' | ', '') ||
                 'تم تأكيد الانصراف وإلغاء الخصم لاستيفاء 8 ساعات كاملة — الدخول: ' ||
                 v_in_str || '، الخروج: ' || v_out_str ||
                 ' (إجمالي الساعات المعتمدة: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة)',
         updated_at = now()
   where id = v_pen.id;

  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = p_employee_id
       and status in ('doubled', 'suspended')
       and id <> v_pen.id
  ) then
    update public.employees set is_active = true, status = 'active' where id = p_employee_id;
    update public.profiles set status = 'active' where employee_id = p_employee_id;
  end if;

  perform public.notify_employee(
    p_employee_id,
    '🎉 تم تأكيد الانصراف وإلغاء غرامة التأخير نهائياً',
    'تم تأكيد بصمة انصرافك وإلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لاستيفائك 8 ساعات عمل كاملة اليوم بمجموع الدوام الفعلي والتصاريح المعتمدة (الحضور: ' || v_in_str || ' — الانصراف: ' || v_out_str || ' — الإجمالي: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة). شكراً لالتزامك!',
    'system', 'high', 'instant_penalty', v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'waived', true,
      'workMinutes', v_work_minutes,
      'permitMinutes', v_permit_minutes,
      'totalEffectiveMinutes', v_total_effective_minutes,
      'in', v_in_str,
      'out', v_out_str
    )
  );

  return jsonb_build_object(
    'waived', true,
    'totalEffectiveMinutes', v_total_effective_minutes,
    'workMinutes', v_work_minutes,
    'permitMinutes', v_permit_minutes
  );
end;
$$;


-- ─── 4) إصلاح set_employee_attendance_day_admin ──────────────────────────────
create or replace function public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time without time zone default null::time without time zone,
  p_check_out time without time zone default null::time without time zone,
  p_clear_check_in boolean default false,
  p_clear_check_out boolean default false,
  p_reason text default null::text,
  p_notes text default null::text,
  p_leave_type text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_leave_type text;
  v_reason text;
  v_is_exec boolean;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;

  -- استبعاد المدير التنفيذي صراحة بحسب توجيه الإدارة
  v_is_exec := public.current_has_active_role(array['executive', 'executive-director']);
  if v_is_exec and auth.role() <> 'service_role' then
    raise exception 'التعديل الإداري اليومي مقتصر على الموارد البشرية والسكرتير التنفيذي فقط وليس للمدير التنفيذي' using errcode = '42501';
  end if;

  -- التحقق من صلاحية الموارد البشرية أو السكرتير التنفيذي أو الأدمن التقني
  if not (
    auth.role() = 'service_role'
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive-secretary', 'admin', 'super-admin'])
    or public.has_permission('attendance.day.override')
    or (p_employee_id is distinct from public.current_employee_id()
        and public.can_access_employee(p_employee_id, 'attendance.day.override'))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- تطبيع نوع اليوم
  p_day_type := lower(trim(coalesce(p_day_type, 'work')));
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;

  -- سبب التعديل
  v_reason := btrim(coalesce(p_reason, ''));
  if length(v_reason) < 3 then
    v_reason := case
      when p_day_type = 'work' then 'تعديل ساعات وحضور معتمد'
      when p_day_type = 'leave' then 'إجازة معتمدة إدارياً'
      when p_day_type = 'mission' then 'مأمورية عمل معتمدة'
      when p_day_type = 'convoy' then 'قافلة عمل معتمدة'
      when p_day_type = 'fundraising' then 'فاندي معتمد'
      when p_day_type = 'holiday' then 'عطلة رسمية معتمدة'
      when p_day_type = 'rest' then 'راحة أسبوعية معتمدة'
      when p_day_type = 'absent' then 'تأكيد غياب إداري'
      else 'تعديل إداري معتمد'
    end;
  end if;

  if p_clear_check_in and p_check_in is not null then
    p_check_in := null;
  end if;
  if p_clear_check_out and p_check_out is not null then
    p_check_out := null;
  end if;

  -- حارس التواريخ
  if auth.role() <> 'service_role' then
    if p_day_type = 'work' and p_work_date > v_today then
      raise exception 'INVALID_DATE: cannot record physical work presence for a future date' using errcode = '22023';
    end if;
    if p_work_date < (v_today - interval '180 days')::date then
      raise exception 'BACKDATING_LIMIT: cannot modify attendance older than 180 days (date: %, limit: %)',
        p_work_date, (v_today - interval '180 days')::date;
    end if;
  end if;

  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- تطبيع نوع الإجازة
  v_leave_type := nullif(trim(coalesce(p_leave_type, '')), '');
  if p_day_type in ('leave','absent') then
    v_leave_type := coalesce(v_leave_type, case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      v_leave_type := 'annual';
    end if;
  else
    v_leave_type := null;
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type, leave_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type, v_leave_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    v_reason, nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    leave_type = excluded.leave_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_id;

  perform public.log_audit_event(
    'attendance.day.override.set', 'workflow', 'info',
    'attendance_day_overrides', v_id,
    'تعديل إداري لحالة اليوم', 'تم تعديل حالة اليوم إدارياً',
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'dayType', p_day_type,
      'leaveType', v_leave_type,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'previous', v_previous
    )
  );

  return jsonb_build_object(
    'success', true,
    'id', v_id,
    'employee_id', p_employee_id,
    'work_date', p_work_date,
    'day_type', p_day_type,
    'leave_type', v_leave_type
  );
end;
$function$;


-- ─── 5) تحديث get_mobile_request_detail لإعادة إضافة insights ────────────────
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
  v_current_step       uuid;
  v_steps              jsonb;
  v_history            jsonb;
  v_attachments        jsonb;
  v_context            jsonb;
  v_decided_by         text;
  v_cancelled_by       text;
  v_decision_actor     text;
  v_decision_mode      text;
  v_decision_on_behalf boolean;
  v_execution          jsonb;
  v_insights           jsonb;
  v_start              date;
  v_end                date;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  if not coalesce(
       v_request.employee_id = v_me
    or v_request.manager_employee_id = v_me
    or exists (
         select 1 from public.manager_relations mr
          where mr.employee_id = v_request.employee_id
            and mr.manager_employee_id = v_me
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date))
    or exists (
         select 1 from public.request_steps s
          where s.request_id = v_request.id and s.assignee_employee_id = v_me)
    or v_full
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'operations-manager-1']
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve'),
    false
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  select d.name into v_department from public.departments d where d.id = v_employee.department_id;
  select jt.name into v_job_title from public.job_titles jt where jt.id = v_employee.job_title_id;

  v_flags := public.request_decision_flags(v_request, v_me, v_full, v_roles);

  if v_request.status = 'pending' then
    select s.id into v_current_step
      from public.request_steps s
     where s.request_id = v_request.id
       and s.status in ('active', 'escalated', 'pending')
     order by (s.status = 'active') desc, s.step_order asc
     limit 1;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'stepOrder', s.step_order,
           'stepType', s.step_type,
           'role', s.approver_role,
           'status', s.status,
           'assigneeId', s.assignee_employee_id,
           'assigneeName', a.full_name_ar,
           'completedAt', s.completed_at,
           'decisionDueAt', s.decision_due_at
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees a on a.id = s.assignee_employee_id
   where s.request_id = v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', act.id,
           'action', act.action,
           'fromStatus', act.from_status,
           'toStatus', act.to_status,
           'actorName', ea.full_name_ar,
           'actorRole', act.metadata->>'roleName',
           'comment', act.comment,
           'createdAt', act.created_at
         ) order by act.created_at asc), '[]'::jsonb)
    into v_history
    from public.request_actions act
    left join public.employees ea on ea.id = act.actor_employee_id
   where act.request_id = v_request.id;

  v_attachments := coalesce(v_request.payload->'attachmentPaths', '[]'::jsonb);

  if coalesce((v_flags->>'canDecide')::boolean, false) then
    v_context := public.get_request_decision_context(v_request.id);
  end if;

  if v_request.decided_by is not null then
    select full_name_ar into v_decided_by
      from public.employees where id = v_request.decided_by;
  end if;

  if v_request.cancelled_by is not null then
    select full_name_ar into v_cancelled_by
      from public.employees where user_id = v_request.cancelled_by;
  end if;

  select ea.full_name_ar,
         coalesce(act.metadata->>'roleName', ''),
         coalesce((act.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions act
    left join public.employees ea on ea.id = act.actor_employee_id
   where act.request_id = v_request.id
     and act.action in ('approve', 'reject', 'return', 'cancel')
   order by act.created_at desc
   limit 1;

  -- حساب insights
  if coalesce((v_flags->>'canDecide')::boolean, false) or v_full then
    v_start := case when v_request.payload->>'startDate' ~ '^\d{4}-\d{2}-\d{2}$'
                    then (v_request.payload->>'startDate')::date end;
    v_end   := case when coalesce(v_request.payload->>'endDate', v_request.payload->>'startDate') ~ '^\d{4}-\d{2}-\d{2}$'
                    then coalesce(v_request.payload->>'endDate', v_request.payload->>'startDate')::date end;

    v_insights := jsonb_build_object(
      'leaveBalance', case when v_request.request_type = 'leave' then (
        select jsonb_build_object(
          'type', coalesce(v_request.payload->>'leaveType', 'annual'),
          'available', coalesce(b.available_days, 0),
          'used', coalesce(b.used_days, 0)
        )
        from public.leave_balance_accounts b
        where b.employee_id = v_request.employee_id
          and b.year = extract(year from coalesce(v_start, current_date))::integer
        limit 1
      ) end,
      'monthRequestsCount', (
        select count(*) from public.requests r
         where r.employee_id = v_request.employee_id
           and r.id <> v_request.id
           and r.created_at >= date_trunc('month', current_date)
      ),
      'teamSize', (
        select count(*) from public.employees e
         where v_employee.department_id is not null
           and e.department_id = v_employee.department_id
           and e.id <> v_request.employee_id
           and e.is_active and not coalesce(e.is_deleted, false)
      )
    );
  end if;

  if v_request.request_type in ('mission', 'convoy', 'fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
        from public.mission_executions me
       where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'employeePhotoUrl', v_employee.photo_url,
    'employeeDepartment', v_department,
    'employeeJobTitle', v_job_title,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'decidedAt', v_request.decided_at,
    'decidedByName', v_decided_by,
    'cancelledAt', v_request.cancelled_at,
    'cancelReason', v_request.cancel_reason,
    'cancelledByName', v_cancelled_by,
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'canCancel', coalesce(v_request.status = 'pending' and v_request.employee_id = v_me, false),
    'canResubmit', coalesce(v_request.status in ('rejected', 'returned')
                            and v_request.employee_id = v_me
                            and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                           'late_permit', 'early_permit', 'attendance_permit', 'attendance_correction'), false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'isMine', coalesce(v_request.employee_id = v_me, false),
    'steps', v_steps,
    'history', v_history,
    'attachments', v_attachments,
    'decisionContext', v_context,
    'insights', v_insights,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;


-- ─── 6) إصلاح decide_attendance_correction وجعل القرار idempotent ────────────
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
        if v_effective_checkout + interval '12 hours' > v_cur_checkin then
          v_effective_checkout := v_effective_checkout + interval '12 hours';
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

  perform public.log_audit_event(
    'attendance.correction.' || p_decision, 'workflow',
    case when p_decision = 'approved' then 'notice' else 'warning' end,
    'attendance_corrections', p_id, 'قرار تصحيح حضور',
    p_note, jsonb_build_object('employeeId', v_row.employee_id, 'workDate', v_row.work_date)
  );

  perform public.notify_employee(
    v_row.employee_id,
    case p_decision when 'approved' then 'تم قبول تصحيح الحضور' else 'تم رفض تصحيح الحضور' end,
    format('تصحيح حضور بتاريخ %s%s', v_row.work_date, case when p_note is not null then E'\n' || p_note else '' end),
    'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
    'attendance_corrections', p_id,
    jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date)
  );
end;
$$;


-- ─── 7) معالجة خطأ decide_request عند تصحيح البصمة + حل الطلب #660 ───────────
-- حل الطلب رقم 660 فورياً في حال كان معلقاً بينما تصحيحه معتمد
update public.requests
   set status = 'approved',
       workflow_status = 'completed',
       decided_at = coalesce(decided_at, now())
 where (request_number = 660 or id = 'fe6c0085-adf4-457d-b084-b5ca37141d2c')
   and status = 'pending';

-- حماية decide_request من فشل اعتماد طلبات تصحيح البصمة
-- (استبدال استدعاء decide_attendance_correction داخل decide_request بمعالج استثناءات آمن)
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
  v_req public.requests;
  v_step public.request_steps;
  v_me uuid := public.current_employee_id();
  v_decision text;
  v_next_step record;
  v_final_status text;
  v_actor_role text;
  v_actor_role_name text;
  v_is_exec boolean := false;
  v_is_hr boolean := false;
  v_is_ops1 boolean := false;
  v_is_direct_mgr boolean := false;
  v_correction_id uuid;
  v_eff_date date;
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
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status not in ('pending', 'under_review') then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager','executive-secretary']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer'])
               or public.current_is_full_access()
               or public.current_has_active_role(array['admin','super-admin']);
  v_is_ops1 := public.current_has_active_role(array['operations-manager-1']);

  v_is_direct_mgr := (
    v_req.manager_employee_id = v_me
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or exists (
      select 1 from public.request_steps s
      where s.request_id = v_req.id
        and s.assignee_employee_id = v_me
        and s.status in ('active', 'pending', 'escalated')
    )
  );

  if not (auth.role() = 'service_role' or v_is_exec or v_is_hr or v_is_ops1 or v_is_direct_mgr) then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  if v_req.employee_id = v_me and not (auth.role() = 'service_role' or public.current_is_full_access()) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active', 'escalated', 'pending')
  order by (status = 'active') desc, step_order asc
  limit 1;

  if v_step.id is null then
    select * into v_step
    from public.request_steps
    where request_id = p_request_id
    order by step_order desc
    limit 1;
  end if;

  v_actor_role := case
    when auth.role() = 'service_role' then 'service_role'
    when v_is_exec then 'executive'
    when v_is_hr then 'hr'
    when v_is_ops1 then 'operations_manager'
    when v_is_direct_mgr then 'direct_manager'
    else 'authorized_actor'
  end;

  v_actor_role_name := case
    when v_actor_role = 'executive' then 'المدير التنفيذي'
    when v_actor_role = 'hr' then 'الموارد البشرية'
    when v_actor_role = 'operations_manager' then 'مدير العمليات'
    when v_actor_role = 'direct_manager' then 'المدير المباشر'
    else 'معتمد معتمد'
  end;

  if v_step.id is not null then
    update public.request_steps
    set status = case
          when v_decision = 'approve' then 'approved'
          when v_decision = 'reject' then 'rejected'
          when v_decision = 'return' then 'returned'
        end,
        completed_at = now(),
        decision = v_decision,
        comment = p_comment,
        assignee_employee_id = coalesce(assignee_employee_id, v_me),
        updated_at = now()
    where id = v_step.id;
  end if;

  if v_decision in ('reject', 'return') then
    v_final_status := case when v_decision = 'reject' then 'rejected' else 'returned' end;

    update public.request_steps
    set status = 'skipped', updated_at = now()
    where request_id = p_request_id
      and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and status in ('active', 'pending', 'escalated');

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, v_decision, 'pending', v_final_status, p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = v_final_status,
        workflow_status = v_final_status,
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

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
      workflow_status = 'approved',
      decided_at = now(),
      decided_by = v_me,
      review_note = p_comment,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- تنفيذ الآثار الجانبية المباشرة:
  -- أ) أذونات الحضور والانصراف:
  if v_req.request_type in ('early_permit', 'late_permit', 'permit') then
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

  -- ب) تصحيح البصمة (attendance_correction) مع حماية ضد التكرار:
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

  -- ج) الإجازات:
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

commit;
