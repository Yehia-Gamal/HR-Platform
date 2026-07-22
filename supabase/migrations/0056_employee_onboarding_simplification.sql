begin;

-- ============================================================================
-- Migration 0056: تبسيط رحلة إنشاء الموظف في لوحة الأدمن.
--   • بذرة الكيان القانوني والمجمّع الرئيسي (منيل شيحة) ومواقع العمل الأربعة.
--   • دلو تخزين عام لصور الموظفين (employee-avatars) مع سياسات الوصول.
--   • تحديث provision_employee_record لقبول اسم مسمى وظيفي حر (find-or-create)
--     ورابط صورة شخصية، مع اشتقاق كود الموظف من رقم الهاتف عند غيابه.
-- كل الكتابة خادمية ومدقّقة. الهجرة idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) ضمان وجود أدوار «المنصب» التي يعرضها الفورم (موظف/مدير/أوبريشن)
--    مستقلةً عن ملفات seed/، فالنشر بالهجرات وحدها يجب أن يفي بعقد الواجهة.
-- ----------------------------------------------------------------------------
insert into public.roles (slug, name_ar, name_en, is_system, is_full_access)
values
  ('direct-manager',     'مدير مباشر',  'Direct Manager',     true, false),
  ('operations-officer', 'ضابط عمليات', 'Operations Officer', true, false)
on conflict (slug) do nothing;

-- تفرّد كود الموظف يصبح جزئياً على النشطين فقط — متسقاً مع فهرس الهاتف
-- (ux_employees_phone_e164_active)، ليسمح بإعادة استخدام كود/هاتف موظف مُلغى.
drop index if exists public.ux_employees_employee_code;
create unique index if not exists ux_employees_employee_code
  on public.employees (employee_code)
  where is_active = true and is_deleted = false;

-- ----------------------------------------------------------------------------
-- 1) بذرة الكيان القانوني والمجمّع الرئيسي ومواقع العمل
-- ----------------------------------------------------------------------------
insert into public.legal_entities (code, name, name_en, country_code, currency_code, timezone, is_active)
values ('AHLA', 'أحلى شباب', 'Ahla Shabab', 'EG', 'EGP', 'Africa/Cairo', true)
on conflict (code) do update set
  name = excluded.name,
  name_en = excluded.name_en,
  country_code = excluded.country_code,
  currency_code = excluded.currency_code,
  timezone = excluded.timezone,
  is_active = true,
  updated_at = now();

-- المجمّع الرئيسي — يُعرض في الواجهة تحت مسمّى «مجمع».
insert into public.branches (legal_entity_id, code, name, name_en, city, timezone, is_headquarters, is_active)
select le.id, 'MAIN', 'مجمع أحلى شباب - منيل شيحة', 'Ahla Shabab Complex - Menyal Shiha',
       'الجيزة', 'Africa/Cairo', true, true
from public.legal_entities le
where le.code = 'AHLA'
on conflict (legal_entity_id, code) do update set
  name = excluded.name,
  name_en = excluded.name_en,
  city = excluded.city,
  timezone = excluded.timezone,
  is_headquarters = true,
  is_active = true,
  updated_at = now();

-- مواقع العمل الأربعة المطلوبة داخل المجمّع الرئيسي.
insert into public.work_sites (branch_id, code, name, site_type, is_active)
select b.id, v.code, v.name, v.site_type, true
from public.branches b
join public.legal_entities le on le.id = b.legal_entity_id and le.code = 'AHLA'
cross join (values
  ('ONSITE_FULL', 'العمل من خلال المجمع بدوام كامل', 'onsite_full_time'),
  ('ONSITE_PART', 'العمل من المجمع بدوام جزئي',      'onsite_part_time'),
  ('REMOTE',      'العمل من المنزل',                  'remote'),
  ('PART_TIME',   'العمل بدوام جزئي',                 'part_time')
) as v(code, name, site_type)
where b.code = 'MAIN'
on conflict (branch_id, code) do update set
  name = excluded.name,
  site_type = excluded.site_type,
  is_active = true,
  updated_at = now();

-- ----------------------------------------------------------------------------
-- 2) دلو تخزين عام لصور الموظفين + سياسات الوصول
--    عام للقراءة (الأفاتار يُعرض في اللوحة)، والكتابة/الحذف لمن يملك صلاحية
--    إدارة الموظفين فقط.
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-avatars', 'employee-avatars', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists employee_avatars_public_read on storage.objects;
create policy employee_avatars_public_read on storage.objects
  for select using (bucket_id = 'employee-avatars');

drop policy if exists employee_avatars_manage_write on storage.objects;
create policy employee_avatars_manage_write on storage.objects
  for insert to authenticated with check (
    bucket_id = 'employee-avatars'
    and (public.current_is_full_access() or public.has_permission('people.employee.create'))
  );

drop policy if exists employee_avatars_manage_update on storage.objects;
create policy employee_avatars_manage_update on storage.objects
  for update to authenticated using (
    bucket_id = 'employee-avatars'
    and (public.current_is_full_access() or public.has_permission('people.employee.create'))
  );

drop policy if exists employee_avatars_manage_delete on storage.objects;
create policy employee_avatars_manage_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'employee-avatars'
    and (public.current_is_full_access() or public.has_permission('people.employee.create'))
  );

-- ----------------------------------------------------------------------------
-- 3) تحديث provision_employee_record:
--    • p_job_title_name: اسم مسمى وظيفي حر (يُنشأ إن لم يوجد، أو يُطابق الموجود).
--    • p_photo_url: رابط الصورة الشخصية.
--    • اشتقاق كود الموظف من رقم الهاتف عند غياب كود صريح.
--    نضيف الوسيطين الجديدين بقيمة افتراضية للحفاظ على التوافق العكسي.
-- ----------------------------------------------------------------------------
-- إسقاط التوقيع القديم (18 وسيطة) صراحةً؛ التوقيع الجديد يضيف وسيطين فيصبح
-- overload منفصلاً لولا الإسقاط، ما يسبّب التباس اختيار الدالة.
drop function if exists public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean
);

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

  -- كود الموظف: صريح إن وُجد، وإلا يُشتق من رقم الهاتف (فريد بطبيعته).
  v_employee_code := coalesce(nullif(trim(p_employee_code), ''), nullif(trim(p_phone_e164), ''));
  if v_employee_code is null then
    raise exception 'employee code or phone is required' using errcode = '22023';
  end if;

  -- فحص التكرار بين الصفوف النشطة فقط — متسق مع فهرس الهاتف الجزئي، فيسمح
  -- بإعادة استخدام هاتف/كود موظف تُرك بعد إلغاء تنشيط موظف سابق.
  if exists (
    select 1 from public.employees
    where employee_code = v_employee_code and is_active = true and is_deleted = false
  ) then
    raise exception 'employee code already exists' using errcode = '23505';
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
    select id into v_job_title_id
    from public.job_titles
    where lower(name) = lower(v_title_name)
    limit 1;

    if v_job_title_id is null then
      -- كود مشتق فريد للمسمى الجديد.
      v_title_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      insert into public.job_titles (code, name, is_active, created_by)
      values (v_title_code, v_title_name, true, p_actor_user_id)
      returning id into v_job_title_id;
    end if;
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

revoke all on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean, text, text
) from public, anon, authenticated;
grant execute on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean, text, text
) to service_role;

commit;
