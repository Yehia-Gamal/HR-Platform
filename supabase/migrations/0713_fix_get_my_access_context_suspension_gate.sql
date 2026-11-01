-- =====================================================================
-- 0713: إصلاح دالة get_my_access_context() لدعم تعليق الموظفين وتوجيههم لم. يحيى
-- =====================================================================
-- المشكلة السابقة:
-- عند تعليق موظف لعدم سداد الغرامة أو إدارياً، كانت دالة get_my_access_context
-- تستعلم فقط عن e.is_active = true مما يجعل v_employee_id فارغاً،
-- وتنتهي بـ raise exception 'لا توجد مساحة عمل معينة'.
-- هذا الاستثناء كان يمنع تطبيق الموبايل ولوحة الويب من استقبال حالة الإيقاف،
-- ويُظهر للموظف شاشة خطأ الاتصال الدائري: "جارٍ تحميل الصلاحيات... يبدو أن العملية تأخرت".
--
-- الحل في هذه الهجرة:
-- 1) فحص حالة الإيقاف (status = 'suspended' أو is_active = false أو profile suspended)
-- 2) إرجاع كائن سياق الإيقاف الرسمي الصريح:
--    - isSuspended: true
--    - status: 'suspended'
--    - suspensionMessage: 'تم إيقافك عن العمل، راجع المسؤول م. يحيى لسداد الغرامات التي عليك'
--    - suspensionAmount: إجمالي الغرامات المستحقة (أو 500 كحد أدنى)
--    - managerContact: بيانات التواصل مع م. يحيى (+201154869616)
-- 3) إزالة الـ raise exception 'لا توجد مساحة عمل معينة' واستبداله بضبط افتراضي آمن.
-- =====================================================================

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
  -- تعليق الموظف
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
begin
  if v_user_id is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  -- 1) جلب الموظف وبياناته (سواء كان نشطاً أو موقوفاً، بشرط ألا يكون محذوفاً)
  select e.id, e.full_name_ar, e.employee_code, e.photo_url, e.status, e.is_active
    into v_employee_id, v_display_name, v_employee_code, v_photo_url, v_employee_status, v_employee_is_active
  from public.employees e
  where e.user_id = v_user_id and not coalesce(e.is_deleted, false)
  limit 1;

  -- 2) جلب حالة الملف الشخصي
  select p.status into v_profile_status
  from public.profiles p
  where p.id = v_user_id;

  -- 3) الحسابات المحصنة من الإيقاف (الأدمن الرئيسي وم. يحيى)
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

  -- 4) فحص حالة الإيقاف للموظف
  if not v_is_immune_admin and (
    coalesce(v_employee_status, '') = 'suspended'
    or coalesce(v_profile_status, '') = 'suspended'
    or (coalesce(v_employee_is_active, true) = false and v_employee_id is not null)
  ) then
    v_is_suspended := true;

    -- حساب إجمالي الغرامات المستحقة أو المعلقة
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

  -- 5) إذا لم يكن موقوفاً: جلب الأدوار والصلاحيات كالمعتاد
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

  -- طاقم العيادات يقتصر على الموظفين فقط دون المديرين مصطفى أحمد ويوسف رسمي
  if v_employee_id is not null then
    v_is_clinic_staff := public.is_clinic_team_member(v_employee_id)
                         and v_employee_id not in (
                           '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                           'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                         );
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

