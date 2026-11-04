-- =====================================================================
-- 0725_exempt_specified_staff_from_clinic_restrictions.sql
-- =====================================================================
-- القرار الإداري الصريح:
-- 1. استثناء إسماعيل، عبدالله، حسام، يوسف رسمي، ومصطفى أحمد تماماً من أي حظر
--    أو قيود خاصة بالعيادات أو التيم الطبي؛ فيحق لهم تقديم طلبات الفاندي (Fun Day)،
--    القوافل الميدانية، المأموريات، الإجازات، والأذونات دون أي عائق أو حظر.
-- 2. حظر طلبات الفاندي والقوافل والأنشطة الميدانية مقصور حصراً ومشدداً على
--    موظفي العيادات أنفسهم (فريق الـ 6 بنات فقط: تمريض، معمل، استقبال).
-- 3. ضبط دالة is_clinic_staff_restricted_from_field المركزية وتحديث:
--    - submit_my_request
--    - _submit_request_for
--    - get_my_access_context
--    - get_employee_hierarchy_rank
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة مركزية تحدد حصراً موظفي العيادات المقيدين ميدانياً (الـ 6 بنات فقط)
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.is_clinic_staff_restricted_from_field(p_employee_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp record;
  v_has_clinic_staff_role boolean := false;
begin
  if p_employee_id is null then
    return false;
  end if;

  select e.id, e.full_name_ar, e.user_id, e.job_title_id, e.department_id,
         coalesce(jt.name, '') as job_title,
         coalesce(d.name, '') as dept_name
  into v_emp
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  where e.id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 1) استثناء صريح وحاسم بالاسم والمعرف للمستثنيين بقرار الإدارة:
  --    اسماعيل، عبدالله، حسام، يوسف رسمي، مصطفى أحمد
  if v_emp.id in (
    '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, -- مصطفى أحمد كمال الدين (مدير العيادات الطبية)
    'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid  -- يوسف رسمي شعبان (مدير مجمع وعيادات منيل شيحة)
  )
  or v_emp.full_name_ar ilike '%اسماعيل%'
  or v_emp.full_name_ar ilike '%إسماعيل%'
  or v_emp.full_name_ar ilike '%عبدالله%'
  or v_emp.full_name_ar ilike '%عبد الله%'
  or v_emp.full_name_ar ilike '%حسام%'
  or v_emp.full_name_ar ilike '%يوسف%رسمي%'
  or v_emp.full_name_ar ilike '%مصطف%أحمد%'
  or v_emp.full_name_ar ilike '%مصطفي%أحمد%' then
    return false;
  end if;

  -- 2) استثناء أي مسمى إداري أو قيادي أو إشرافي أو تنفيذي
  if v_emp.job_title ilike '%مدير%'
     or v_emp.job_title ilike '%مشرف%'
     or v_emp.job_title ilike '%رئيس%'
     or v_emp.job_title ilike '%مسؤول%'
     or v_emp.job_title ilike '%مسئول%'
     or v_emp.job_title ilike '%إداري%'
     or v_emp.job_title ilike '%اداري%'
     or v_emp.job_title ilike '%سكرتير%'
     or v_emp.job_title ilike '%منسق%' then
    return false;
  end if;

  -- 3) فحص دور clinic-staff الفعلي
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_emp.user_id
      and r.slug = 'clinic-staff'
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_has_clinic_staff_role;

  -- 4) الحظر يسري حصراً على موظفي العيادات (فريق الـ 6 بنات: تمريض، معمل، استقبال)
  if v_has_clinic_staff_role
     or v_emp.job_title in ('تمريض', 'دكتورة المعمل', 'موظف استقبال', 'ممرضة', 'فني معمل')
     or v_emp.full_name_ar ilike '%رحاب مجدي%'
     or v_emp.full_name_ar ilike '%ساميه%'
     or v_emp.full_name_ar ilike '%سامية%'
     or v_emp.full_name_ar ilike '%سمر احمد%'
     or v_emp.full_name_ar ilike '%سمر أحمد%'
     or v_emp.full_name_ar ilike '%سميرة سعيد%'
     or v_emp.full_name_ar ilike '%سميره سعيد%'
     or v_emp.full_name_ar ilike '%شروق عبد العليم%'
     or v_emp.full_name_ar ilike '%شروق عبدالعليم%' then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.is_clinic_staff_restricted_from_field(uuid) from public, anon;
grant execute on function public.is_clinic_staff_restricted_from_field(uuid) to authenticated, service_role;

comment on function public.is_clinic_staff_restricted_from_field(uuid) is
  '0725: فحص تقييد الموظف من الأنشطة الميدانية والفاندي (محصور على الـ 6 بنات، ومستثنى منه إسماعيل وعبدالله وحسام ويوسف ومصطفى).';

-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث submit_my_request لرفع الحظر عن المستثنيين وحصره على الـ 6 بنات فقط
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_idempotency_key uuid default null::uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                    uuid := public.current_employee_id();
  v_manager               uuid;
  v_row                   public.requests;
  v_payload               jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today                 date := (now() at time zone 'Africa/Cairo')::date;
  v_min_allowed_date      date := (v_today - interval '365 days')::date;
  v_day_mark              boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date            date;
  v_end_date              date;
  v_permit_date           date;
  v_minutes               integer;
  v_leave_type            text;
  v_leave_type_id         uuid;
  v_affects               boolean;
  v_days                  numeric;
  v_substitute            uuid;
  v_correction_date       date;
  v_correction_type       text;
  v_corrected_time        text;
  v_permit_kind           text;
  v_is_clinic             boolean := false;
  v_effective_reason      text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- الحظر الميداني مقصور حصراً على الـ 6 بنات بطاقم العيادات، ومستثنى منه إسماعيل وعبدالله وحسام ومصطفى ويوسف
  v_is_clinic := public.is_clinic_staff_restricted_from_field(v_me);

  if v_is_clinic and p_request_type in ('mission', 'convoy', 'fundraising') then
    raise exception 'طلبات المأموريات والقوافل والأنشطة الميدانية غير متاحة لطاقم العيادات' using errcode = '22023';
  end if;

  if p_idempotency_key is not null then
    select * into v_row
    from public.requests
    where employee_id = v_me
      and payload ->> 'clientId' = p_idempotency_key::text
      and created_at > now() - interval '10 minutes';
    if found then
      return v_row;
    end if;
    v_payload := v_payload || jsonb_build_object('clientId', p_idempotency_key::text);
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  -- معالجة سبب الطلب: الفاندي لا يشترط سبباً وله قيمة افتراضية
  v_effective_reason := trim(coalesce(p_reason, ''));
  if p_request_type = 'fundraising' and (v_effective_reason = '' or length(v_effective_reason) < 3) then
    v_effective_reason := 'يوم ترفيهي للموظفين لقضاء عطلة على حساب العمل';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(v_effective_reason) < 3 then
    raise exception 'العنوان وسبب الطلب مطلوبان (3 أحرف على الأقل)' using errcode = '22023';
  end if;

  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'تعديل حالة اليوم يتطلب تاريخاً صالحاً' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'تعديل حالة اليوم يكون ليوم واحد فقط' using errcode = '22023';
    end if;
    if v_start_date < v_min_allowed_date then
      raise exception 'تعديل حالة اليوم متاح للأيام خلال آخر 365 يوماً فقط' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'لا يمكن تعديل حالة الأيام المستقبلية' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type = 'unpaid' then
          raise exception 'لا يمكن للموظف طلب إجازة بدون راتب ذاتياً؛ تُمنح فقط بقرار من إدارة الموارد البشرية' using errcode = '22023';
        end if;
        if v_leave_type not in ('annual','casual','sick','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية الإجازة مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم إجازة تسبق أكثر من سنة' using errcode = '22023';
        end if;

        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'نوع الإجازة غير نشط أو غير معروف: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual' and v_start_date >= v_today));

      -- ─── مأمورية ───────────────────────────────────────────────────────────
      when 'mission' then
        v_start_date := coalesce(nullif(v_payload->>'startDate', '')::date, v_today);
        v_end_date   := coalesce(nullif(v_payload->>'endDate', '')::date, v_start_date);
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم مأمورية تسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية المأمورية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(nullif(trim(coalesce(v_payload->>'location', '')), ''), 'مأمورية عمل خارجية'),
          'days', ((v_end_date - v_start_date) + 1),
          'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
          'startedAtCreation', case when v_day_mark then false else true end);

      -- ─── قافلة / فاندي ───────────────────────────────────────────────────
      when 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ النهاية يجب ألا يسبق البداية' using errcode = '22023';
        end if;
        if v_start_date < v_min_allowed_date then
          raise exception 'لا يمكن تقديم تكليف يسبق أكثر من سنة' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', coalesce(
            nullif(trim(coalesce(v_payload->>'location', '')), ''),
            case when p_request_type = 'convoy' then 'قافلة ميدانية' else 'يوم ترفيهي للموظفين' end
          ),
          'days', ((v_end_date - v_start_date) + 1));

      -- ─── إذن تأخير صباحي ──────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitType', 'late_permit',
          'permitDate', v_permit_date,
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر ─────────────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitType', 'early_permit',
          'permitDate', v_permit_date,
          'minutes', v_minutes);

      -- ─── إذن عام / فترات ──────────────────────────────────────────────────
      when 'attendance_permit' then
        v_permit_kind := coalesce(nullif(v_payload->>'permitType', ''), 'midday_permit');
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_min_allowed_date then
          raise exception 'تاريخ الإذن يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitType', v_permit_kind,
          'permitDate', v_permit_date,
          'minutes', v_minutes);

      -- ─── تصحيح بصمة حضور / انصراف ─────────────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := nullif(v_payload->>'correctionType', '');
        v_corrected_time  := nullif(v_payload->>'correctedTime', '');
        if v_correction_date is null then
          raise exception 'تاريخ التصحيح مطلوب' using errcode = '22023';
        end if;
        if v_correction_date < v_min_allowed_date then
          raise exception 'تاريخ التصحيح يسبق أكثر من سنة' using errcode = '22023';
        end if;
        if v_correction_type not in ('in_punch', 'out_punch', 'both') then
          raise exception 'نوع التصحيح غير صالح' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime',  v_corrected_time);

      -- ─── تغيير وردية ───────────────────────────────────────────────────────
      when 'shift_change' then
        null;

      -- ─── طلب عام ───────────────────────────────────────────────────────────
      when 'generic' then
        null;
    end case;
  end;

  v_manager := public.resolve_request_approver(v_me);

  return public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    p_title,
    v_effective_reason,
    v_payload
  );
end;
$$;

revoke all on function public.submit_my_request(text, text, text, jsonb, uuid) from public, anon;
grant execute on function public.submit_my_request(text, text, text, jsonb, uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) تحديث _submit_request_for لربط مسار العيادات بالـ 6 بنات فقط
-- ─────────────────────────────────────────────────────────────────────
create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_def               public.workflow_definitions;
  v_row               public.requests;
  v_first_step        public.workflow_steps;
  v_step_id           uuid;
  v_is_clinic         boolean := false;
  v_is_mgr_executive  boolean := false;
  v_emp_name          text;
  v_two_names         text;
  v_req_label         text;
  v_due               timestamptz;
  v_esc               timestamptz;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  select e.full_name_ar into v_emp_name from public.employees e where e.id = p_employee_id;
  v_two_names := trim(split_part(coalesce(v_emp_name, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_name, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_name, ''), 'موظف');
  end if;
  v_req_label := public.request_type_label(p_request_type);

  -- فحص طاقم العيادات المقيد (الـ 6 بنات فقط دون المديرين والتيم الإداري)
  v_is_clinic := public.is_clinic_staff_restricted_from_field(p_employee_id);

  -- تحديد المدير المعتمد
  if v_is_clinic then
    if p_manager_employee_id is null or p_manager_employee_id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
       ) then
      p_manager_employee_id := coalesce(
        public.resolve_request_approver(p_employee_id),
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid
      );
    end if;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- فحص إذا كان المدير المباشر هو المدير التنفيذي (الشيخ محمد يوسف أو دور تنفيذي)
  v_is_mgr_executive := (
    p_manager_employee_id = '7b0740fa-66ba-4616-8674-3dbd8e14109e'::uuid
    or public.is_employee_executive(p_manager_employee_id)
  );

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
      select * into v_def from public.workflow_definitions
        where code like 'medical_%' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null and public.is_employee_isolated(p_employee_id) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  if v_def.id is not null then
    if v_is_mgr_executive then
      v_due := now() + interval '5 minutes';
      v_esc := v_due;
    else
      v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
      if v_def.auto_escalate and not v_is_clinic then
        v_esc := v_due;
      end if;
    end if;
  else
    v_due := case when v_is_mgr_executive then now() + interval '5 minutes' else now() + interval '48 hours' end;
    v_esc := case when v_is_mgr_executive then v_due else null end;
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id,
      ws.id,
      ws.step_order,
      ws.name_ar,
      ws.step_type,
      case
        when ws.assignee_type = 'manager' then p_manager_employee_id
        when ws.assignee_type = 'specific_employee' then ws.specific_employee_id
        else null
      end,
      case
        when ws.assignee_type = 'role' then ws.role_slug
        else null
      end,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case
        when ws.step_order = 1 then
          case
            when v_is_mgr_executive then now() + interval '5 minutes'
            else now() + make_interval(hours => coalesce(ws.sla_hours, 48))
          end
        else null
      end,
      case
        when ws.step_order = 1 and coalesce(ws.auto_escalate, false) and not v_is_clinic then
          case
            when v_is_mgr_executive then now() + interval '5 minutes'
            else now() + make_interval(hours => coalesce(ws.sla_hours, 48))
          end
        else null
      end,
      auth.uid()
    from public.workflow_steps ws
    where ws.workflow_definition_id = v_def.id
    order by ws.step_order;

    update public.requests
    set current_step_id = (
      select rs.id from public.request_steps rs
      where rs.request_id = v_row.id and rs.step_order = 1
      limit 1
    )
    where id = v_row.id;
  end if;

  return v_row;
end;
$$;

revoke all on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) تحديث get_my_access_context لحصر isClinicStaff على الـ 6 بنات فقط
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.get_my_access_context()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_employee_status text;
  v_employee_is_active boolean;
  v_profile_status text;
  v_roles text[] := '{}';
  v_permissions text[] := '{}';
  v_workspaces text[] := '{}';
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_immune_admin boolean := false;
  v_is_executive boolean := false;
  v_is_operations boolean := false;
  v_is_manager boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_clinic_staff boolean := false;
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
begin
  if v_user_id is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  select e.id, e.full_name_ar, e.employee_code, e.photo_url, e.status, e.is_active
    into v_employee_id, v_display_name, v_employee_code, v_photo_url, v_employee_status, v_employee_is_active
  from public.employees e
  where e.user_id = v_user_id and not coalesce(e.is_deleted, false)
  limit 1;

  select p.status into v_profile_status
  from public.profiles p
  where p.id = v_user_id;

  v_is_immune_admin := exists (
    select 1 from public.employees e
    where e.user_id = v_user_id
      and not coalesce(e.is_deleted, false)
      and e.id in (
        'd0000000-0000-4000-8000-000000000001'::uuid,
        'd0000000-0000-4000-8000-000000000002'::uuid,
        'b452c987-ae08-4e12-8433-272cc66c85f9'::uuid -- م. يحيى جمال السبع
      )
  );

  if not v_is_immune_admin and (
    coalesce(v_employee_status, '') = 'suspended'
    or coalesce(v_profile_status, '') = 'suspended'
    or (coalesce(v_employee_is_active, true) = false and v_employee_id is not null)
  ) then
    v_is_suspended := true;

    select coalesce(sum(p.current_amount), 500.00) into v_suspension_amount
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id
      and (p.status in ('suspended', 'doubled', 'pending_payment') or p.escalation_level in ('doubled', 'suspended'));

    if v_suspension_amount is null or v_suspension_amount <= 0 then
      v_suspension_amount := 500.00;
    end if;

    v_suspension_reason := 'penalty_unpaid';
    v_suspension_message := 'تم إيقافك عن العمل، راجع المسؤول م. يحيى لسداد الغرامات التي عليك';

    return jsonb_build_object(
      'userId', v_user_id,
      'employeeId', v_employee_id,
      'displayName', coalesce(v_display_name, 'موظف المنظومة'),
      'employeeCode', v_employee_code,
      'photoUrl', v_photo_url,
      'roles', '[]'::jsonb,
      'permissions', '[]'::jsonb,
      'workspaces', '[]'::jsonb,
      'defaultWorkspace', 'employee',
      'isSuspended', true,
      'status', 'suspended',
      'suspensionReason', v_suspension_reason,
      'suspensionMessage', v_suspension_message,
      'suspensionAmount', v_suspension_amount,
      'managerContact', jsonb_build_object(
        'name', 'م. يحيى جمال السبع',
        'phone', '+201154869616',
        'whatsapp', '201154869616'
      ),
      'attendancePolicy', jsonb_build_object(
        'attendanceRequired', false,
        'selfPunchEnabled', false,
        'liveLocationResponseEnabled', false
      )
    );
  end if;

  select coalesce(array_agg(r.slug order by r.slug), '{}'::text[]),
         bool_or(coalesce(r.is_full_access, false))
    into v_roles, v_is_full
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());

  if v_is_full or v_is_immune_admin then
    select coalesce(array_agg(p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.permissions p;
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now()) and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director','executive']::text[];
  v_is_operations := v_roles && array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']::text[];
  v_is_manager := v_is_operations
                  or v_roles && array['direct-manager','department-manager','branch-manager','clinics-manager']::text[]
                  or (v_employee_id is not null and v_employee_id in (
                        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                        'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                      ));

  if not v_is_manager and v_employee_id is not null then
    if exists (select 1 from public.departments d where d.manager_id = v_employee_id) or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_employee_id and mr.relation_type='primary'
        and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())
    ) then
      v_is_manager := true;
    end if;
  end if;

  v_is_hr := v_roles && array['hr-manager','hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_is_immune_admin or v_roles && array['admin','super-admin','super_admin','system-admin','technical-lead','executive-secretary']::text[];
  v_is_committee := v_roles && array['committee-member','committee-chair','committee-secretary']::text[];

  -- طاقم العيادات يقتصر حصراً على موظفي العيادات (الـ 6 بنات فقط) دون المديرين والتيم الإداري
  if v_employee_id is not null then
    v_is_clinic_staff := public.is_clinic_staff_restricted_from_field(v_employee_id);
  end if;

  if v_employee_id is not null and not v_is_executive then v_workspaces := array_append(v_workspaces,'employee'); end if;
  if v_is_manager and not v_is_executive then v_workspaces := array_append(v_workspaces,'manager'); end if;
  if v_is_operations and not v_is_executive then v_workspaces := array_append(v_workspaces,'field_operations'); end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces,'executive'); end if;
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces,'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces,'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then v_workspaces := array_append(v_workspaces,'committee'); end if;

  if v_is_main_admin then v_default_workspace := 'main_admin';
  elsif v_is_executive then v_default_workspace := 'executive';
  elsif v_is_hr then v_default_workspace := 'hr';
  elsif v_is_operations then v_default_workspace := 'field_operations';
  elsif v_is_manager then v_default_workspace := 'manager';
  elsif v_employee_id is not null then v_default_workspace := 'employee';
  else v_default_workspace := 'employee';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', coalesce(v_display_name, ''),
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'isSuspended', false,
    'status', 'active',
    'suspensionReason', null,
    'suspensionMessage', null,
    'suspensionAmount', null,
    'managerContact', null,
    'isClinicStaff', v_is_clinic_staff,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null,
      'selfPunchEnabled', true,
      'liveLocationResponseEnabled', not v_is_executive and not public.is_employee_attendance_exempt(v_employee_id) and v_employee_id is not null
    )
  );
end;
$function$;

revoke execute on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث get_employee_hierarchy_rank لضمان عدم إلحاق المستثنيين بالرتبة 7
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.get_employee_hierarchy_rank(
  p_name text,
  p_job_title text,
  p_department text
)
returns integer
language plpgsql
immutable
as $function$
declare
  n text := coalesce(trim(p_name), '');
  t text := lower(coalesce(trim(p_job_title), ''));
  d text := lower(coalesce(trim(p_department), ''));
  v_is_med_mgr boolean;
  v_is_exempt_admin boolean;
begin
  -- 1 — الشيخ محمد يوسف
  if n ilike '%الشيخ محمد%' or n ilike '%ألشيخ محمد%'
     or n = 'محمد يوسف' or n ilike 'محمد يوسف %'
     or t ilike '%مدير تنفيذي%' or (t ilike '%مدير%' and t ilike '%تنفيذي%')
     or t = 'ceo' or t ilike '%chief executive%' then
    return 1;
  end if;

  -- 2 — يحيى السبع
  if n ilike '%يحيى%' or n ilike '%يحيي%' or n ilike '%السبع%'
     or t ilike '%سكرتير%' or t ilike '%المساعد التنفيذي%'
     or t ilike '%executive secretary%' or t ilike '%executive assistant%' then
    return 2;
  end if;

  -- 3 — أبو عمار
  if n ilike '%ابو عمار%' or n ilike '%أبو عمار%'
     or n ilike 'محمد عبدالباسط%' or n ilike 'محمد عبد الباسط%'
     or ((t ilike '%أوبريشن%' or t ilike '%تشغيل%' or t ilike '%operations%') and (t ilike '%1%' or t ilike '%أول%' or t ilike '%رئيسي%')) then
    return 3;
  end if;

  -- 4 — ياسر
  if n ilike '%ياسر%'
     or ((t ilike '%أوبريشن%' or t ilike '%تشغيل%' or t ilike '%operations%') and (t ilike '%2%' or t ilike '%ثاني%' or t ilike '%مساعد%')) then
    return 4;
  end if;

  -- هل هو من مديري العيادات؟ (مصطفى أحمد كمال الدين، يوسف رسمي شعبان)
  v_is_med_mgr := n ilike '%مصطفي%أحمد%' or n ilike '%مصطفى%أحمد%' or n ilike '%يوسف%رسمي%'
                  or t ilike '%مدير مجمع%' or (d ilike '%عياد%' and t ilike '%مدير%');

  -- هل هو من التيم الإداري المستثنى؟ (إسماعيل، عبدالله، حسام)
  v_is_exempt_admin := n ilike '%اسماعيل%' or n ilike '%إسماعيل%'
                       or n ilike '%عبدالله%' or n ilike '%عبد الله%'
                       or n ilike '%حسام%'
                       or t ilike '%مشرف%' or t ilike '%مسؤول%' or t ilike '%مسئول%'
                       or t ilike '%إداري%' or t ilike '%اداري%' or t ilike '%منسق%';

  -- 7 — تيم البنات بتوع الطاقم الطبي (حصراً الـ 6 بنات: تمريض، معمل، استقبال)
  if not v_is_med_mgr and not v_is_exempt_admin then
    if t ilike '%تمريض%' or t ilike '%معمل%' or t ilike '%دكتورة المعمل%' or t ilike '%استقبال%'
       or n ilike '%رحاب مجدي%' or n ilike '%ساميه%' or n ilike '%سامية%' or n ilike '%سمر احمد%' or n ilike '%سمر أحمد%'
       or n ilike '%سميرة سعيد%' or n ilike '%سميره سعيد%' or n ilike '%شروق عبد العليم%' or n ilike '%شروق عبدالعليم%' then
      return 7;
    end if;
  end if;

  -- 5 — باقي المديرين
  if t ilike '%مدير%' or t ilike '%manager%' or t ilike '%head%' or t ilike '%lead%'
     or t ilike '%director%' or t ilike '%رئيس%' or t ilike '%نائب%' or t ilike '%وكيل%'
     or v_is_med_mgr then
    return 5;
  end if;

  -- 6 — باقي الموظفين (يشمل التيم الإداري إسماعيل وعبدالله وحسام)
  return 6;
end;
$function$;

revoke execute on function public.get_employee_hierarchy_rank(text, text, text) from public, anon;
grant execute on function public.get_employee_hierarchy_rank(text, text, text) to authenticated, service_role;

commit;

