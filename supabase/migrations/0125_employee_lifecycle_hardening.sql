-- ============================================================================
-- Migration 0125: تقوية دورة حياة الموظف — سد ثغرات الفحص الشامل.
--   • فحص تكرار الهاتف صريح في provision_employee_record (رسالة مفهومة).
--   • فهرس فريد جزئي على job_titles.name (lower) لمنع تكرار المسميات.
--   • تحديث provision_employee_record لاستخدام ON CONFLICT عند إنشاء مسمى.
--   • تعطيل soft_delete_employee القديم (يحيل لـ archive_employee_secure).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) فهرس فريد جزئي على اسم المسمى الوظيفي — يمنع تكرار المسميات
--    عند الإنشاء التلقائي في provision_employee_record.
-- ----------------------------------------------------------------------------
create unique index if not exists idx_job_titles_name_lower_active
  on public.job_titles (lower(name))
  where is_active = true;

-- ----------------------------------------------------------------------------
-- 2) تحديث provision_employee_record:
--    • فحص تكرار الهاتف صريح مع رسالة خطأ واضحة.
--    • المسمى الوظيفي: ON CONFLICT بدل SELECT+INSERT (يمنع race condition).
-- ----------------------------------------------------------------------------
create or replace function public.provision_employee_record(
  p_actor_user_id uuid,
  p_user_id uuid,
  p_full_name_ar text,
  p_full_name_en text,
  p_employee_code text,
  p_phone_e164 text,
  p_role_slug text,
  p_manager_employee_id uuid default null,
  p_department_id uuid default null,
  p_team_id uuid default null,
  p_branch_id uuid default null,
  p_work_site_id uuid default null,
  p_job_title_id uuid default null,
  p_position_id uuid default null,
  p_grade_id uuid default null,
  p_employment_type_id uuid default null,
  p_hire_date date default null,
  p_invitation_pending boolean default true,
  p_job_title_name text default null,
  p_photo_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_id uuid;
  v_profile_status text;
  v_employee_status text;
  v_employee_code text;
  v_job_title_id uuid;
  v_title_name text;
  v_title_code text;
begin
  if p_actor_user_id is null or p_user_id is null then
    raise exception 'actor and user are required';
  end if;

  select id into v_role_id
  from public.roles
  where slug = p_role_slug;

  if v_role_id is null then
    raise exception 'unknown role slug: %', p_role_slug using errcode = '22023';
  end if;

  -- كود الموظف: صريح إن وُجد، وإلا يُشتق من رقم الهاتف.
  v_employee_code := coalesce(nullif(trim(p_employee_code), ''), nullif(trim(p_phone_e164), ''));
  if v_employee_code is null then
    raise exception 'employee code or phone is required' using errcode = '22023';
  end if;

  -- فحص تكرار كود الموظف بين النشطين.
  if exists (
    select 1 from public.employees
    where employee_code = v_employee_code and is_active = true and is_deleted = false
  ) then
    raise exception 'employee code already exists' using errcode = '23505';
  end if;

  -- فحص تكرار الهاتف صريح مع رسالة مفهومة (بدل الاعتماد على constraint خام).
  if p_phone_e164 is not null and exists (
    select 1 from public.employees
    where phone_e164 = p_phone_e164 and is_active = true and is_deleted = false
  ) then
    raise exception 'phone number already belongs to an active employee' using errcode = '23505';
  end if;

  if p_manager_employee_id is not null and not exists (
    select 1 from public.employees
    where id = p_manager_employee_id and is_active = true and is_deleted = false
  ) then
    raise exception 'manager is not an active employee' using errcode = '23503';
  end if;

  -- المسمى الوظيفي: أولوية للمعرّف الصريح، وإلا مطابقة/إنشاء من الاسم الحر.
  v_job_title_id := p_job_title_id;
  v_title_name := nullif(trim(p_job_title_name), '');
  if v_job_title_id is null and v_title_name is not null then
    -- محاولة الإدراج أولاً مع ON CONFLICT لمنع التكرار عند التزامن.
    v_title_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    insert into public.job_titles (code, name, is_active, created_by)
    values (v_title_code, v_title_name, true, p_actor_user_id)
    on conflict ((lower(name))) where is_active = true
    do update set updated_at = now()
    returning id into v_job_title_id;
  end if;

  v_profile_status := case when p_invitation_pending then 'pending' else 'active' end;
  v_employee_status := case when p_invitation_pending then 'invited' else 'active' end;

  insert into public.employees (
    user_id, employee_code, full_name_ar, full_name_en, phone_e164,
    job_title_id, position_id, grade_id, department_id, team_id,
    branch_id, work_site_id, employment_type_id, hire_date,
    status, is_active, is_deleted, photo_url, created_by
  ) values (
    p_user_id, trim(v_employee_code), trim(p_full_name_ar), nullif(trim(p_full_name_en), ''),
    p_phone_e164, v_job_title_id, p_position_id, p_grade_id,
    p_department_id, p_team_id, p_branch_id, p_work_site_id,
    p_employment_type_id, p_hire_date, v_employee_status, true, false,
    nullif(trim(p_photo_url), ''), p_actor_user_id
  ) returning id into v_employee_id;

  insert into public.profiles (
    id, employee_id, primary_role_id, status, temporary_password,
    branch_id, department_id, team_id, created_by
  ) values (
    p_user_id, v_employee_id, v_role_id, v_profile_status, true,
    p_branch_id, p_department_id, p_team_id, p_actor_user_id
  );

  insert into public.user_roles (
    user_id, role_id, effective_from, granted_by
  ) values (
    p_user_id, v_role_id, now(), p_actor_user_id
  );

  if p_manager_employee_id is not null then
    insert into public.manager_relations (
      employee_id, manager_employee_id, relation_type,
      effective_from, created_by
    ) values (
      v_employee_id, p_manager_employee_id, 'primary',
      coalesce(p_hire_date, current_date), p_actor_user_id
    );
  end if;

  return jsonb_build_object(
    'employeeId', v_employee_id,
    'userId', p_user_id
  );
end;
$$;

-- الصلاحيات: service_role فقط (يُستدعى من edge function).
revoke all on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean, text, text
) to service_role;

-- ----------------------------------------------------------------------------
-- 3) تعطيل soft_delete_employee القديم — يحيل إلى archive_employee_secure
--    الذي يقفل الحساب ويعطّل الجلسات والأدوار والعلاقات الإدارية.
-- ----------------------------------------------------------------------------
drop function if exists public.soft_delete_employee(uuid);
drop function if exists public.soft_delete_employee(uuid);
create or replace function public.soft_delete_employee(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- يحيل إلى الدالة الآمنة التي تعالج كل التبعيات (auth, roles, manager_relations).
  perform public.archive_employee_secure(p_employee_id, 'deprecated soft_delete_employee redirect');
end;
$$;

