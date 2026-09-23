-- =====================================================================
-- 0547: الحصانة الدائمة والاستثناء القطعي للحساب الرئيسي والمسؤول العام للنظام
--       (يحيى جمال السبع - 01154869616 / +201154869616)
-- =====================================================================
-- يضمن هذا الترحيل بشكل دائم وقاطع:
-- 1. فك الحظر والتعليق فورياً عن حساب يحيى جمال السبع وإلغاء أي غرامات مسجلة له.
-- 2. إعفاء دائم ومطلق من الحضور والانصراف (is_attendance_exempt = true).
-- 3. إعفاء دائم ومطلق من الغرامات الفورية (is_penalty_exempt = true).
-- 4. حظر قاطع لأي محاولة تعديل حالة الموظف أو البروفايل إلى 'suspended' عبر Triggers ذاتية الحماية.
-- 5. حظر قاطع لتسجيل أي غرامة في جدول instant_attendance_penalties للحساب الرئيسي.
-- 6. تحديث get_my_access_context() لضمان عدم إرجاع isSuspended = true نهائياً للأدمن الرئيسي.
-- 7. تحديث auto_generate_instant_penalties و auto_escalate_instant_penalties لاستثناء الحساب قطعياً.
-- =====================================================================

begin;

-- 1. فك الحظر فورياً وإلغاء الغرامات السابقة
update public.employees
   set status = 'active',
       is_active = true,
       is_attendance_exempt = true,
       is_penalty_exempt = true,
       updated_at = now()
 where id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
    or phone_e164 in ('+201154869616', '01154869616')
    or employee_code in ('+201154869616', '01154869616')
    or user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960';

update public.profiles
   set status = 'active',
       updated_at = now()
 where id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
    or employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9';

update public.instant_attendance_penalties
   set status = 'cancelled',
       cancelled_reason = 'إعفاء دائم واستثناء قطعي - الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع)',
       updated_at = now()
 where employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
    or employee_id in (select id from public.employees where phone_e164 in ('+201154869616', '01154869616') or user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960');

-- 2. تحديث دالة فحص الإعفاء الدائم من الحضور
create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_attendance_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 0. الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع)
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_rec.full_name_ar ilike '%يحيى%جمال%' then
    return true;
  end if;

  -- 1. فحص العلم في جدول employees
  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 2. شبكة أمان كبار المسؤولين
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02',
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- محمد عبدالباسط ( ابو عمار )
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- عبدالله احمد نصر
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229')
    or v_rec.full_name_ar ilike '%محمد يوسف%'
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%الباسل%'
    or v_rec.full_name_ar ilike '%عبدالله%نصر%' then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, anon, service_role;

-- 3. تحديث دالة فحص الإعفاء الدائم من الغرامات الفورية
create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  -- 0. الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع)
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9' then
    return true;
  end if;

  -- 1. أي موظف معفى من الحضور فهو معفى حكماً من الغرامات
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, phone_e164, full_name_ar, is_penalty_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_rec.full_name_ar ilike '%يحيى%جمال%' then
    return true;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  -- 3. فحص هاني احمد نصير وشبكة أمان
  if p_employee_id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
     or v_rec.employee_code = '+201012141949'
     or v_rec.full_name_ar ilike '%هاني%نصير%' then
    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, anon, service_role;

-- 4. تريجر الحصانة المطلقة على جدول public.employees
create or replace function public.tg_admin_immunity_employees_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or NEW.phone_e164 in ('+201154869616', '01154869616')
     or NEW.employee_code in ('+201154869616', '01154869616')
     or NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.full_name_ar ilike '%يحيى%جمال%' then
    NEW.status := 'active';
    NEW.is_active := true;
    NEW.is_attendance_exempt := true;
    NEW.is_penalty_exempt := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_admin_immunity_employees on public.employees;
create trigger tg_admin_immunity_employees
before insert or update on public.employees
for each row
execute function public.tg_admin_immunity_employees_fn();

-- 5. تريجر الحصانة المطلقة على جدول public.profiles
create or replace function public.tg_admin_immunity_profiles_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or exists (select 1 from public.employees e where e.id = NEW.employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    NEW.status := 'active';
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_admin_immunity_profiles on public.profiles;
create trigger tg_admin_immunity_profiles
before insert or update on public.profiles
for each row
execute function public.tg_admin_immunity_profiles_fn();

-- 6. تريجر منع تسجيل أي غرامة في جدول instant_attendance_penalties للحساب الرئيسي
create or replace function public.tg_prevent_admin_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or public.is_employee_penalty_exempt(NEW.employee_id)
     or exists (select 1 from public.employees e where e.id = NEW.employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    -- إلغاء إنشاء الغرامة نهائياً وبلا استثناء
    return null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_prevent_admin_penalty on public.instant_attendance_penalties;
create trigger tg_prevent_admin_penalty
before insert on public.instant_attendance_penalties
for each row
execute function public.tg_prevent_admin_penalty_fn();

-- 7. تحديث get_my_access_context() مع الحصانة المطلقة للحساب الرئيسي
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
  -- تعليق الموظف
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code, e.photo_url,
         p.status, e.status
    into v_employee_id, v_display_name, v_employee_code, v_photo_url,
         v_profile_status, v_employee_status
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id;

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  -- ═══ الحصانة المطلقة للأدمن الرئيسي (يحيى جمال السبع) ═══
  if v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_employee_code in ('+201154869616', '01154869616')
     or exists (select 1 from public.employees e where e.id = v_employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  end if;

  -- ═══ فحص إيقاف الموظف عن العمل (يستثنى منه الأدمن الرئيسي قطعياً) ═══
  if not v_is_immune_admin and (coalesce(v_profile_status, '') = 'suspended' or coalesce(v_employee_status, '') = 'suspended') then
    v_is_suspended := true;

    -- فحص الغرامة الفورية المتسببة في الإيقاف (500 ج.م)
    select p.current_amount into v_suspension_amount
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id
      and p.status = 'suspended'
    order by p.created_at desc
    limit 1;

    if found then
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := coalesce(v_suspension_amount, 500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    else
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    end if;

    return jsonb_build_object(
      'userId', v_user_id,
      'employeeId', v_employee_id,
      'displayName', v_display_name,
      'employeeCode', v_employee_code,
      'photoUrl', v_photo_url,
      'roles', '[]'::jsonb,
      'permissions', '[]'::jsonb,
      'workspaces', '[]'::jsonb,
      'defaultWorkspace', 'employee',
      'isSuspended', true,
      'suspensionReason', v_suspension_reason,
      'suspensionMessage', v_suspension_message,
      'suspensionAmount', v_suspension_amount,
      'attendancePolicy', jsonb_build_object(
        'attendanceRequired', false,
        'selfPunchEnabled', false,
        'liveLocationResponseEnabled', false
      )
    );
  end if;

  if v_profile_status not in ('active', 'pending') then
    raise exception 'حساب المستخدم غير نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id
    and ur.effective_from <= now()
    and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access() or v_is_immune_admin;
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_is_immune_admin or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- ═══ مساحات العمل ═══
  if v_employee_id is not null and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'manager');
  end if;
  if v_is_operations and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'field_operations');
  end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  -- ═══ المساحة الافتراضية ═══
  if v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_hr then
    v_default_workspace := 'hr';
  elsif v_is_operations then
    v_default_workspace := 'field_operations';
  elsif v_is_manager then
    v_default_workspace := 'manager';
  elsif v_employee_id is not null then
    v_default_workspace := 'employee';
  else
    raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'isSuspended', false,
    'suspensionReason', null,
    'suspensionMessage', null,
    'suspensionAmount', null,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not v_is_immune_admin and v_employee_id is not null,
      'selfPunchEnabled', true,
      'liveLocationResponseEnabled', not v_is_executive and not v_is_immune_admin and v_employee_id is not null
    )
  );
end;
$function$;

revoke all on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;

comment on function public.get_my_access_context() is
  '0547: دعم الحصانة الدائمة والاستثناء المطلق للحساب الرئيسي والمسؤول العام للنظام من أي تعليق أو حظر';

commit;
