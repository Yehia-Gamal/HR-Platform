-- ═════════════════════════════════════════════════════════════════════════════
-- Migration 0581: منح «clinics-manager» ومساحة مدير لرؤساء الأقسام/مدير العيادات
-- ═════════════════════════════════════════════════════════════════════════════
-- السبب الجذري: مصطفى أحمد (مدير العيادات) دور «employee» فقط وقسمه الشخصي
-- يختلف عن أقسام فريقه → get_my_access_context لا يعرض مساحة manager.
-- (أ) get_my_access_context: إضافة 'clinics-manager' واستنتاج كونه مديراً
--     من departments.manager_id أو manager_relations فعّالة
-- (ب) can_access_employee: توسيع scope='department' ليشمل مدير قسم الهدف
-- (ج) منح clinics-manager لمصطفى أحمد (idempotent)
-- ═════════════════════════════════════════════════════════════════════════════

begin;

-- (1) get_my_access_context
CREATE OR REPLACE FUNCTION public.get_my_access_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path to 'public','auth','pg_temp'
AS
$$
DECLARE
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_profile_status text;
  v_employee_status text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يلزم تسجيل الدخول أولاً' USING errcode = '28000';
  END IF;

  SELECT p.employee_id, COALESCE(e.full_name_ar,'مستخدم النظام'), e.employee_code, e.photo_url, p.status, e.status
    INTO v_employee_id, v_display_name, v_employee_code, v_photo_url, v_profile_status, v_employee_status
  FROM public.profiles p
  LEFT JOIN public.employees e ON e.id = p.employee_id
  WHERE p.id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد ملف موظف نشط' USING errcode = '42501';
  END IF;

  IF v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     OR v_employee_code IN ('+201154869616','01154869616')
     OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id = v_employee_id AND (e.phone_e164 IN ('+201154869616','01154869616') OR e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) THEN
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  END IF;

  IF NOT v_is_immune_admin AND (COALESCE(v_profile_status,'')='suspended' OR COALESCE(v_employee_status,'')='suspended') THEN
    v_is_suspended := true;
    SELECT p.current_amount INTO v_suspension_amount
    FROM public.instant_attendance_penalties p
    WHERE p.employee_id = v_employee_id AND p.status = 'suspended'
    ORDER BY p.created_at DESC LIMIT 1;
    IF FOUND THEN
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := COALESCE(v_suspension_amount,500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    ELSE
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    END IF;
    RETURN jsonb_build_object('userId',v_user_id,'employeeId',v_employee_id,'displayName',v_display_name,'employeeCode',v_employee_code,'photoUrl',v_photo_url,'roles','[]'::jsonb,'permissions','[]'::jsonb,'workspaces','[]'::jsonb,'defaultWorkspace','employee','isSuspended',true,'suspensionReason',v_suspension_reason,'suspensionMessage',v_suspension_message,'suspensionAmount',v_suspension_amount,'attendancePolicy',jsonb_build_object('attendanceRequired',false,'selfPunchEnabled',false,'liveLocationResponseEnabled',false));
  END IF;

  IF v_profile_status NOT IN ('active','pending') THEN
    RAISE EXCEPTION 'حساب المستخدم غير نشط' USING errcode = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT r.slug ORDER BY r.slug), '{}'::text[])
    INTO v_roles
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = v_user_id AND ur.effective_from <= now() AND (ur.effective_to IS NULL OR ur.effective_to > now());

  v_is_full := public.current_is_full_access() OR v_is_immune_admin;
  IF v_is_full THEN
    v_permissions := array['*']::text[];
  ELSE
    SELECT COALESCE(array_agg(DISTINCT p.code ORDER BY p.code), '{}'::text[])
      INTO v_permissions
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE ur.user_id = v_user_id AND ur.effective_from <= now() AND (ur.effective_to IS NULL OR ur.effective_to > now()) AND (rp.effective_from IS NULL OR rp.effective_from <= now()) AND (rp.effective_to IS NULL OR rp.effective_to > now());
  END IF;

  v_is_executive := v_roles && array['executive-director','executive']::text[];
  v_is_operations := v_roles && array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']::text[];
  v_is_manager := v_is_operations OR v_roles && array['direct-manager','department-manager','branch-manager','clinics-manager']::text[];
  IF NOT v_is_manager AND v_employee_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.departments d WHERE d.manager_id = v_employee_id) OR EXISTS (
      SELECT 1 FROM public.manager_relations mr
      WHERE mr.manager_employee_id = v_employee_id AND mr.relation_type='primary'
        AND mr.effective_from <= now() AND (mr.effective_to IS NULL OR mr.effective_to > now())
    ) THEN
      v_is_manager := true;
    END IF;
  END IF;
  v_is_hr := v_roles && array['hr-manager','hr-specialist']::text[];
  v_is_main_admin := v_is_full OR v_is_immune_admin OR v_roles && array['admin','super-admin','super_admin','system-admin','technical-lead','executive-secretary']::text[];
  v_is_committee := v_roles && array['committee-member','committee-chair','committee-secretary']::text[];

  IF v_employee_id IS NOT NULL AND NOT v_is_executive THEN v_workspaces := array_append(v_workspaces,'employee'); END IF;
  IF v_is_manager AND NOT v_is_executive THEN v_workspaces := array_append(v_workspaces,'manager'); END IF;
  IF v_is_operations AND NOT v_is_executive THEN v_workspaces := array_append(v_workspaces,'field_operations'); END IF;
  IF v_is_executive THEN v_workspaces := array_append(v_workspaces,'executive'); END IF;
  IF v_is_hr OR v_is_main_admin THEN v_workspaces := array_append(v_workspaces,'hr'); END IF;
  IF v_is_main_admin THEN v_workspaces := array_append(v_workspaces,'main_admin'); END IF;
  IF v_is_committee AND NOT v_is_hr AND NOT v_is_main_admin THEN v_workspaces := array_append(v_workspaces,'committee'); END IF;

  IF v_is_main_admin THEN v_default_workspace := 'main_admin';
  ELSIF v_is_executive THEN v_default_workspace := 'executive';
  ELSIF v_is_hr THEN v_default_workspace := 'hr';
  ELSIF v_is_operations THEN v_default_workspace := 'field_operations';
  ELSIF v_is_manager THEN v_default_workspace := 'manager';
  ELSIF v_employee_id IS NOT NULL THEN v_default_workspace := 'employee';
  ELSE RAISE EXCEPTION 'لا توجد مساحة عمل معينة' USING errcode = '42501';
  END IF;

  RETURN jsonb_build_object('userId',v_user_id,'employeeId',v_employee_id,'displayName',v_display_name,'employeeCode',v_employee_code,'photoUrl',v_photo_url,'roles',to_jsonb(v_roles),'permissions',to_jsonb(v_permissions),'workspaces',to_jsonb(v_workspaces),'defaultWorkspace',v_default_workspace,'isSuspended',false,'suspensionReason',null,'suspensionMessage',null,'suspensionAmount',null,'attendancePolicy',jsonb_build_object('attendanceRequired',NOT v_is_executive AND NOT public.is_employee_attendance_exempt(v_employee_id) AND v_employee_id IS NOT NULL,'selfPunchEnabled',true,'liveLocationResponseEnabled',NOT v_is_executive AND NOT public.is_employee_attendance_exempt(v_employee_id) AND v_employee_id IS NOT NULL));
END;
$$;
revoke all on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;
comment on function public.get_my_access_context() is 'واجهة سياق الوصول + 0581: تضمين clinics-manager ورؤساء الأقسام';

-- (2) can_access_employee: توسيع department scope ليشمل مدير قسم الهدف
CREATE OR REPLACE FUNCTION public.can_access_employee(p_employee_id uuid, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public','pg_temp'
AS
$$
declare
  v_me uuid;
  v_scope text;
  v_ovr jsonb;
  v_target_dept uuid;
  v_target_branch uuid;
  v_target_team uuid;
  v_allowed boolean := false;
begin
  if p_employee_id is null then return false; end if;
  if public.current_is_full_access() then return true; end if;
  v_me := public.current_employee_id();
  if v_me is null then return false; end if;
  if v_me = p_employee_id then return true; end if;
  if p_code is null then
    return exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_me and mr.employee_id = p_employee_id
        and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;
  select e.department_id, e.branch_id, e.team_id into v_target_dept, v_target_branch, v_target_team from public.employees e where e.id = p_employee_id;
  if not found then return false; end if;
  for v_scope, v_ovr in
    select rp.scope, coalesce(ur.scope_override,'{}'::jsonb)
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid() and p.code = p_code
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now()) and (rp.effective_to is null or rp.effective_to > now())
  loop
    case v_scope
      when 'organization' then v_allowed := true; exit;
      when 'self' then if v_me = p_employee_id then v_allowed := true; exit; end if;
      when 'direct_reports' then
        if exists (select 1 from public.manager_relations mr where mr.manager_employee_id = v_me and mr.employee_id = p_employee_id and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())) then v_allowed := true; exit; end if;
      when 'management_descendants' then if public.is_management_descendant(v_me,p_employee_id) then v_allowed := true; exit; end if;
      when 'department' then
        if v_target_dept is not null then
          if (select e.department_id from public.employees e where e.id = v_me) = v_target_dept then v_allowed := true; exit; end if;
          if exists (select 1 from public.departments d where d.id = v_target_dept and d.manager_id = v_me) then v_allowed := true; exit; end if;
        end if;
      when 'branch' then if v_target_branch is not null and v_target_branch = (select e.branch_id from public.employees e where e.id = v_me) then v_allowed := true; exit; end if;
      when 'team' then if v_target_team is not null and v_target_team = (select e.team_id from public.employees e where e.id = v_me) then v_allowed := true; exit; end if;
      when 'selected_departments' then if v_target_dept is not null and coalesce(v_ovr->'department_ids','[]'::jsonb) ? v_target_dept::text then v_allowed := true; exit; end if;
      when 'selected_branches' then if v_target_branch is not null and coalesce(v_ovr->'branch_ids','[]'::jsonb) ? v_target_branch::text then v_allowed := true; exit; end if;
      when 'selected_employees' then if coalesce(v_ovr->'employee_ids','[]'::jsonb) ? p_employee_id::text then v_allowed := true; exit; end if;
      else null;
    end case;
  end loop;

  if v_allowed and public.is_employee_isolated(p_employee_id) and not public.can_view_isolated_employee(p_employee_id) then
    return false;
  end if;

  return v_allowed;
end;
$$;

-- (3) منح دور clinics-manager لمصطفى أحمد (idempotent)
with role_c as (
  select id from public.roles where slug='clinics-manager' limit 1
), me as (
  select user_id from public.employees where id='4120ce3a-8999-453e-8d9d-acd8f3b5f04c' limit 1
), exists_ur as (
  select ur.id from public.user_roles ur, me, role_c
  where ur.user_id=me.user_id and ur.role_id=role_c.id and ur.effective_from<=now() and (ur.effective_to is null or ur.effective_to>now())
)
insert into public.user_roles (user_id, role_id, granted_by, effective_from)
select me.user_id, role_c.id, '00000000-0000-0000-0000-000000000000'::uuid, now() at time zone 'Africa/Cairo'
from me, role_c
where not exists (select 1 from exists_ur);

commit;