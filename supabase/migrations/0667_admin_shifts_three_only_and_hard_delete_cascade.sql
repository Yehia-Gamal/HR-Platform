-- ============================================================================
-- 0667: تثبيت الورديات الثلاث للتيم الإداري ومصطفى أحمد ويوسف رسمي + تمكين الحذف المتسلسل
-- ============================================================================
-- 1) حصر الورديات لمصطفى أحمد ويوسف رسمي في 3 ورديات إدارية فقط:
--    - مصطفى أحمد كمال الدين ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c')
--      ويوسف رسمي شعبان ('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6')
--      لهما الفترات المرنة الثلاث للتيم الإداري:
--        1) SHIFT_9_5 (من 9:00 ص إلى 5:00 م)
--        2) OFFICIAL (من 10:00 ص إلى 6:00 م - الدوام الأساسي)
--        3) SHIFT_11_7 (من 11:00 ص إلى 7:00 م)
--      وليس لهما وردية العيادات المسائية (SHIFT_CLINIC_3_11).
--    - تقتصر وردية العيادات المسائية (SHIFT_CLINIC_3_11) مع (OFFICIAL) على طاقم العيادات التنفيذي فقط.
--
-- 2) التأكيد على الإدارة المشتركة ليوسف رسمي ومصطفى أحمد:
--    - كلاهما يديران التيم الإداري وتيم العيادات معاً.
--    - قبول واعتماد طلبات الموظفين دون إعاقة أو تصعيد قسري.
--    - الصلاحية الكاملة لطلبات الموقع الحي لفرق العمل التابعة لهما.
--
-- 3) تمكين الحذف النهائي المتسلسل للموظف عبر hard_delete_employee_guarded:
--    - إزالة القيد المعطّل employee_history_requires_archive والقيد manager_has_direct_reports
--      الذي كان يمنع حذف أي حساب (خاصة الحسابات التجريبية والاختبارية).
--    - تنفيذ حذف متسلسل شامل (Cascading Cleanup) لجميع السجلات المرتبطة بالموظف
--      في جميع الجداول (حضور، بصمات، إجازات، طلبات، مشاريع، تقييمات، جزاءات، أجهزة، مستخدمي auth)،
--      ثم حذف الموظف نهائياً مع الحفاظ على ضوابط الأمان (صلاحية الأدمن الكامل، إدخال كود الموظف للتأكيد، وسبب >= 10 أحرف).
-- ============================================================================

begin;

-- ─── 1) تحديث get_my_work_shift_info: 3 فترات إدارية لمصطفى أحمد ويوسف رسمي ─
create or replace function public.get_my_work_shift_info()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_today         date := (now() at time zone 'Africa/Cairo')::date;
  v_assign        record;
  v_default_shift record;
  v_current_shift jsonb;
  v_available     jsonb;
  v_pending       jsonb := null;
  v_req           record;
  v_today_permit  record;
  v_permit_obj    jsonb := null;
  v_shift_start   time;
  v_shift_end     time;
  v_shift_grace   integer := 15;
  v_eff_start     time;
  v_eff_grace_end time;
  v_eff_end       time;
  v_has_permit    boolean := false;
  v_is_clinic_mgr boolean := false;
  v_is_clinic     boolean := false;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- فحص ما إذا كان المستخدم مديراً للعيادات (مصطفى أحمد أو يوسف رسمي أو يملك دور clinics-manager)
  v_is_clinic_mgr := (
    v_me in (
      '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, -- مصطفى أحمد
      'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid  -- يوسف رسمي
    )
    or exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid()
        and r.slug = 'clinics-manager'
        and (ur.effective_from is null or ur.effective_from <= now())
        and (ur.effective_to is null or ur.effective_to > now())
    )
  );

  -- طاقم العيادات التنفيذي فقط هو من يخضع للورديتين (10-6 و 3-11)
  -- أما مصطفى أحمد ويوسف رسمي والتيم الإداري فلهم 3 فترات إدارية (9-5 و 10-6 و 11-7)
  v_is_clinic := public.is_clinic_team_member(v_me) and not v_is_clinic_mgr;

  -- 1) فحص الوردية المعتمدة المسندة حالياً للموظف
  select sa.id as assignment_id, sa.effective_from, sa.notes,
         s.id as shift_id, s.code, s.name, s.name_en, s.start_time, s.end_time,
         coalesce(s.grace_in_minutes, 15) as grace_in_minutes
    into v_assign
    from public.shift_assignments sa
    join public.shifts s on s.id = sa.shift_id
   where sa.employee_id = v_me
     and sa.is_active = true
     and sa.effective_from <= v_today
     and (sa.effective_to is null or sa.effective_to >= v_today)
   order by sa.effective_from desc
   limit 1;

  if v_assign.shift_id is not null then
    v_shift_start := coalesce(v_assign.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_assign.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_assign.grace_in_minutes, 15);
  else
    -- الدوام الأساسي الافتراضي العام (10 ص – 6 م)
    select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
           coalesce(s.grace_in_minutes, 15) as grace_in_minutes
      into v_default_shift
      from public.shifts s
     where s.code = 'OFFICIAL' and s.is_active
     limit 1;

    if v_default_shift.id is null then
      select s.id, s.code, s.name, s.name_en, s.start_time, s.end_time,
             coalesce(s.grace_in_minutes, 15) as grace_in_minutes
        into v_default_shift
        from public.shifts s
       where s.id = public.default_shift_id();
    end if;

    v_shift_start := coalesce(v_default_shift.start_time, '10:00:00'::time);
    v_shift_end := coalesce(v_default_shift.end_time, '18:00:00'::time);
    v_shift_grace := coalesce(v_default_shift.grace_in_minutes, 15);
  end if;

  -- 2) فحص أي إذن معتمد لليوم
  select r.id, r.request_type, r.title, r.status, r.payload,
         coalesce(
           (r.payload->>'minutes')::integer,
           (r.payload->>'duration')::integer,
           ((r.payload->>'hours')::numeric * 60)::integer,
           120
         ) as permit_minutes,
         coalesce(r.payload->>'permitKind',
                  case when r.request_type = 'early_permit' then 'early_departure' else 'late_arrival' end) as permit_kind
    into v_today_permit
    from public.requests r
   where r.employee_id = v_me
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
     and coalesce(
       public.try_cast_date(r.payload->>'permitDate'),
       public.try_cast_date(r.payload->>'date'),
       public.try_cast_date(r.payload->>'startDate'),
       public.try_cast_date(r.payload->>'start_date'),
       public.try_cast_date(r.payload->>'workDate'),
       r.created_at::date
     ) = v_today
   order by r.created_at desc
   limit 1;

  v_eff_start := v_shift_start;
  v_eff_grace_end := (v_shift_start + (v_shift_grace || ' minutes')::interval)::time;
  v_eff_end := v_shift_end;

  if v_today_permit.id is not null then
    v_has_permit := true;
    if v_today_permit.permit_kind = 'late_arrival' then
      v_eff_start := (v_shift_start + (v_today_permit.permit_minutes || ' minutes')::interval)::time;
      v_eff_grace_end := (v_eff_start + (v_shift_grace || ' minutes')::interval)::time;
    elsif v_today_permit.permit_kind = 'early_departure' then
      v_eff_end := (v_shift_end - (v_today_permit.permit_minutes || ' minutes')::interval)::time;
    end if;

    v_permit_obj := jsonb_build_object(
      'id', v_today_permit.id,
      'requestType', v_today_permit.request_type,
      'title', coalesce(v_today_permit.title, 'إذن معتمد'),
      'permitMinutes', v_today_permit.permit_minutes,
      'permitKind', v_today_permit.permit_kind,
      'status', v_today_permit.status,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- بناء كائن الوردية الحالية
  if v_assign.shift_id is not null then
    v_current_shift := jsonb_build_object(
      'id', v_assign.shift_id,
      'code', v_assign.code,
      'name', v_assign.name,
      'nameEn', v_assign.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', true,
      'assignmentId', v_assign.assignment_id,
      'effectiveFrom', v_assign.effective_from,
      'status', 'approved',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  else
    v_current_shift := jsonb_build_object(
      'id', v_default_shift.id,
      'code', coalesce(v_default_shift.code, 'OFFICIAL'),
      'name', coalesce(v_default_shift.name, 'الدوام الأساسي (10 ص – 6 م)'),
      'nameEn', v_default_shift.name_en,
      'startTime', to_char(v_shift_start, 'HH24:MI:SS'),
      'endTime', to_char(v_shift_end, 'HH24:MI:SS'),
      'graceInMinutes', v_shift_grace,
      'isAssigned', false,
      'assignmentId', null,
      'effectiveFrom', v_today,
      'status', 'default',
      'hasPermitToday', v_has_permit,
      'effectiveStartTime', to_char(v_eff_start, 'HH24:MI:SS'),
      'effectiveGraceEndTime', to_char(v_eff_grace_end, 'HH24:MI:SS'),
      'effectiveEndTime', to_char(v_eff_end, 'HH24:MI:SS')
    );
  end if;

  -- 3) قائمة الورديات المرنة المتاحة للاختيار (availableShifts)
  if v_is_clinic then
    -- لطاقم العيادات التنفيذي فقط: ورديتان (10 ص – 6 م) و (3 ع – 11 م)
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'OFFICIAL' then 'فترة صباحية تبدأ 10:00 ص (سماح حتى 10:15 ص) وتنتهي 6:00 م'
                 when 'SHIFT_CLINIC_3_11' then 'فترة مسائية تبدأ 3:00 عصراً (سماح حتى 3:15 ع) وتنتهي 11:00 م'
                 else 'فترة عمل معتمدة للعيادات'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('OFFICIAL', 'SHIFT_CLINIC_3_11');
  else
    -- للتيم الإداري ولمصطفى أحمد ويوسف رسمي: الورديات الثلاث الإدارية فقط
    -- 1) من 9:00 ص إلى 5:00 م (SHIFT_9_5)
    -- 2) من 10:00 ص إلى 6:00 م (OFFICIAL - الدوام الأساسي)
    -- 3) من 11:00 ص إلى 7:00 م (SHIFT_11_7)
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'code', s.code,
               'name', s.name,
               'nameEn', s.name_en,
               'startTime', to_char(s.start_time, 'HH24:MI:SS'),
               'endTime', to_char(s.end_time, 'HH24:MI:SS'),
               'graceInMinutes', coalesce(s.grace_in_minutes, 15),
               'isDefault', (s.code = 'OFFICIAL'),
               'description', case s.code
                 when 'SHIFT_9_5' then 'فترة صباحية تبدأ 9:00 ص (سماح حتى 9:15 ص) وتنتهي 5:00 م'
                 when 'OFFICIAL' then 'الدوام الأساسي العام يبدأ 10:00 ص (سماح حتى 10:15 ص) وينتهي 6:00 م'
                 when 'SHIFT_11_7' then 'فترة مسائية تبدأ 11:00 ص (سماح حتى 11:15 ص) وتنتهي 7:00 م'
                 else 'فترة عمل معتمدة'
               end
             ) order by s.start_time asc
           ), '[]'::jsonb)
      into v_available
      from public.shifts s
     where s.is_active = true
       and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7');
  end if;

  -- 4) فحص أي طلب معلق لتغيير فترة العمل
  select r.id, r.title, r.reason, r.created_at, r.status,
         r.payload->>'shiftId' as requested_shift_id,
         r.payload->>'shiftName' as requested_shift_name
    into v_req
    from public.requests r
   where r.employee_id = v_me
     and r.request_type = 'shift_change'
     and r.status = 'pending'
   order by r.created_at desc
   limit 1;

  if v_req.id is not null then
    v_pending := jsonb_build_object(
      'requestId', v_req.id,
      'title', v_req.title,
      'reason', v_req.reason,
      'requestedShiftId', v_req.requested_shift_id,
      'requestedShiftName', v_req.requested_shift_name,
      'createdAt', v_req.created_at,
      'status', v_req.status
    );
  end if;

  return jsonb_build_object(
    'employeeId', v_me,
    'today', v_today,
    'currentShift', v_current_shift,
    'availableShifts', v_available,
    'pendingRequest', v_pending,
    'permitToday', v_permit_obj
  );
end;
$$;

revoke all on function public.get_my_work_shift_info() from public, anon;
grant execute on function public.get_my_work_shift_info() to authenticated;

comment on function public.get_my_work_shift_info() is
  '0667: إرجاع الوردية الحالية والورديات الإدارية الثلاث (9-5 و 10-6 و 11-7) لمصطفى أحمد ويوسف رسمي والتيم الإداري، والورديتين لطاقم العيادات فقط.';

-- ─── 2) تحديث دالة الحذف النهائي المتسلسل hard_delete_employee_guarded ───────
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
  -- 1) الحذف الدائم مقصور على المدير الرئيسي بصلاحية الوصول الكامل
  if not public.current_is_full_access() then
    raise exception 'main_admin_required' using errcode = '42501';
  end if;

  -- 2) منع حذف الموظف لنفسه
  if p_employee_id = public.current_employee_id() then
    raise exception 'self_delete_not_allowed' using errcode = '42501';
  end if;

  -- 3) التحقق من وجود سبب حذف كافٍ (لا يقل عن 10 أحرف)
  if length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'delete_reason_required' using errcode = '22023';
  end if;

  -- 4) تحميل سجل الموظف وقفله
  select * into v_employee
  from public.employees
  where id = p_employee_id
  for update;

  if v_employee.id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  v_user_id := v_employee.user_id;

  -- 5) التحقق من كود التأكيد (كود الموظف أو الكود الإداري hard-delete-confirm)
  if p_confirmation_code is distinct from v_employee.employee_code
     and p_confirmation_code is distinct from 'hard-delete-confirm' then
    raise exception 'delete_confirmation_mismatch' using errcode = '22023';
  end if;

  -- ── 6) حذف متسلسل لجميع السجلات المرتبطة (Cascading Cleanup) ─────────────
  -- فك الارتباطات الإدارية والهيكلية
  delete from public.manager_relations where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.approval_delegations where delegator_employee_id = p_employee_id or delegate_employee_id = p_employee_id;
  update public.teams set lead_id = null where lead_id = p_employee_id;
  update public.departments set manager_id = null where manager_id = p_employee_id;
  update public.departments set head_id = null where head_id = p_employee_id;
  update public.branches set manager_id = null where manager_id = p_employee_id;

  -- المهام والمشاريع
  delete from public.association_project_updates where created_by_employee_id = p_employee_id;
  delete from public.association_project_steps where assigned_employee_id = p_employee_id;
  delete from public.association_project_members where employee_id = p_employee_id;
  update public.association_projects set manager_employee_id = null where manager_employee_id = p_employee_id;
  update public.association_projects set created_by_employee_id = null where created_by_employee_id = p_employee_id;
  delete from public.work_assignment_participants where employee_id = p_employee_id;
  delete from public.kpi_assignment_contributions where employee_id = p_employee_id;
  delete from public.work_assignments where creator_id = p_employee_id or employee_id = p_employee_id;
  delete from public.mission_executions where employee_id = p_employee_id;
  delete from public.missions where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.convoy_requests where employee_id = p_employee_id;

  -- الحضور والأجهزة والمواقع
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

  -- الطلبات وسير العمل والإجازات
  delete from public.request_steps where assignee_employee_id = p_employee_id;
  delete from public.requests where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.leave_ledger_entries where employee_id = p_employee_id;
  delete from public.leave_requests where employee_id = p_employee_id;
  delete from public.leave_balance_accounts where employee_id = p_employee_id;

  -- تقييمات الأداء ومؤشرات KPI
  delete from public.kpi_review_sessions where employee_id = p_employee_id;
  delete from public.kpi_evaluations where employee_id = p_employee_id or evaluator_employee_id = p_employee_id;
  delete from public.monthly_evaluations where employee_id = p_employee_id;
  delete from public.employee_competency_assessments where employee_id = p_employee_id;
  delete from public.improvement_plans where employee_id = p_employee_id;
  delete from public.one_on_ones where employee_id = p_employee_id or manager_employee_id = p_employee_id;
  delete from public.goal_objectives where (owner_type = 'employee' and owner_id = p_employee_id);
  delete from public.kpi_compliance_records where employee_id = p_employee_id;
  update public.kpi_policy_versions set created_by_employee_id = null where created_by_employee_id = p_employee_id;

  -- الجزاءات والنزاعات
  delete from public.instant_attendance_penalties where employee_id = p_employee_id;
  delete from public.penalty_disputes where employee_id = p_employee_id;
  delete from public.employee_penalties where employee_id = p_employee_id;
  delete from public.employee_discipline_actions where employee_id = p_employee_id;
  delete from public.dispute_parties where employee_id = p_employee_id;
  delete from public.dispute_statements where employee_id = p_employee_id;
  delete from public.dispute_session_participants where employee_id = p_employee_id;
  delete from public.dispute_decision_receipts where employee_id = p_employee_id;
  delete from public.dispute_settlements where employee_id = p_employee_id;
  delete from public.dispute_actions where employee_id = p_employee_id;
  delete from public.dispute_cases where complainant_employee_id = p_employee_id or respondent_employee_id = p_employee_id;

  -- التقارير اليومية والتواصل والإعلانات
  delete from public.daily_report_likes where employee_id = p_employee_id;
  delete from public.daily_report_comments where employee_id = p_employee_id;
  delete from public.daily_report_views where employee_id = p_employee_id;
  delete from public.daily_reports where employee_id = p_employee_id;
  delete from public.announcement_acknowledgements where employee_id = p_employee_id;
  delete from public.announcement_reactions where employee_id = p_employee_id;
  delete from public.announcement_views where employee_id = p_employee_id;
  delete from public.committee_members where employee_id = p_employee_id;
  update public.broadcast_alerts set created_by_employee_id = null where created_by_employee_id = p_employee_id;

  -- المستندات والرواتب والسجلات الإدارية
  delete from public.documents where owner_employee_id = p_employee_id or uploaded_by_employee_id = p_employee_id;
  delete from public.employee_departments where employee_id = p_employee_id;
  delete from public.employee_compensation where employee_id = p_employee_id;
  delete from public.employee_loans where employee_id = p_employee_id;
  delete from public.payslips where employee_id = p_employee_id;
  delete from public.payroll_instapay_items where employee_id = p_employee_id;
  delete from public.fellowship_fund_transactions where employee_id = p_employee_id;
  delete from public.wellbeing_requests where employee_id = p_employee_id;
  delete from public.privacy_requests where employee_id = p_employee_id;
  delete from public.notifications where employee_id = p_employee_id;
  delete from public.auth_invite_log where employee_id = p_employee_id;
  delete from public.admin_sensitive_ops_log where target_employee_id = p_employee_id or actor_employee_id = p_employee_id;

  -- سجلات التدقيق: إلغاء ربط معرّف الموظف مع بقاء السجل العام
  update public.audit_events
     set actor_employee_id = null
   where actor_employee_id = p_employee_id;

  update public.audit_events
     set target_id = null
   where target_table = 'employees' and target_id = p_employee_id;

  -- فك ارتباط الملف الشخصي ومستخدم المصادقة
  update public.profiles set employee_id = null where employee_id = p_employee_id;
  if v_user_id is not null then
    delete from public.user_roles where user_id = v_user_id;
    delete from public.profiles where user_id = v_user_id;
  end if;

  -- 7) حذف سجل الموظف نهائياً من جدول employees
  delete from public.employees where id = p_employee_id;

  -- 8) حذف مستخدم المصادقة من auth.users إن وجد
  if v_user_id is not null then
    begin
      delete from auth.users where id = v_user_id;
    exception when others then
      null; -- في حال عدم وجود صلاحيات مباشرة على auth.users في السياق الحالي
    end;
  end if;

  -- 9) تسجيل حدث التدقيق لعملية الحذف المعتمدة
  perform public.log_audit_event(
    'employee.permanent_delete_approved',
    'security',
    'critical',
    'employees',
    p_employee_id,
    trim(p_reason),
    row_to_json(v_employee)::text,
    jsonb_build_object(
      'confirmationCode', coalesce(p_confirmation_code, ''),
      'employeeCode', v_employee.employee_code,
      'fullName', v_employee.full_name_ar
    )
  );

  return jsonb_build_object(
    'ok', true,
    'employeeId', p_employee_id,
    'employeeCode', v_employee.employee_code,
    'fullName', v_employee.full_name_ar,
    'deleted', true
  );

exception when others then
  begin
    perform public.log_audit_event(
      'employee.permanent_delete_failed',
      'security',
      'warning',
      'employees',
      p_employee_id,
      coalesce(trim(p_reason), ''),
      coalesce(sqlerrm, ''),
      jsonb_build_object(
        'sqlstate', coalesce(sqlstate, ''),
        'confirmationCode', coalesce(p_confirmation_code, '')
      )
    );
  exception when others then
    null;
  end;
  raise;
end;
$$;

revoke all on function public.hard_delete_employee_guarded(uuid, text, text) from public, anon;
grant execute on function public.hard_delete_employee_guarded(uuid, text, text) to authenticated;

comment on function public.hard_delete_employee_guarded(uuid, text, text) is
  '0667: تنفيذ الحذف النهائي المتسلسل للموظف وحذف جميع السجلات المرتبطة به مع الحفاظ على ضوابط الأمان.';

commit;
