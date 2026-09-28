-- 0574: إدارة المسميات الوظيفية (عرض/إنشاء/تعديل/حذف)
-- ===========================================================================
-- يوجد 48 مسمياً وظيفياً مع صيغ مكررة/بلا استخدام ولا توجد واجهة لإدارتها.
-- get_job_titles_overview: قائمة المسميات مع عدد الموظفين والمناصب (STABLE).
-- upsert_job_title: إنشاء أو تعديل أو تعطيل — صلاحية organization.job_title.manage.
-- delete_job_title: حذف نهائي فقط إن لم يرتبط بأي موظف أو منصب؛ وإلا رفض برسالة
-- عربية تذكر السبب (الجداول المرتبطة كلها ON DELETE SET NULL — يُمنع الضار لا المنفع).

create or replace function public.get_job_titles_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'organization.entity.read','organization.org_chart.read',
      'organization.department.manage','organization.position.manage',
      'organization.job_title.manage','organization.unit.manage'
    ])
  ) then
    raise exception 'عرض المسميات الوظيفية مرفوض' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', jt.id, 'code', jt.code, 'name', jt.name, 'nameEn', jt.name_en,
      'active', jt.is_active,
      'employeeCount', (select count(*) from public.employees e where e.job_title_id = jt.id and not e.is_deleted),
      'positionCount', (select count(*) from public.positions p where p.job_title_id = jt.id)
    ) order by jt.is_active desc, jt.name)
    from public.job_titles jt
  ), '[]'::jsonb);
end;
$$;

create or replace function public.upsert_job_title(
  p_id uuid,
  p_code text,
  p_name text,
  p_name_en text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_code text;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.job_title.manage')) then
    raise exception 'إدارة المسميات الوظيفية مرفوضة' using errcode = '42501';
  end if;
  if nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'الكود والمسمى الوظيفي مطلوبان' using errcode = '22023';
  end if;
  v_code := upper(trim(p_code));
  if exists (
    select 1 from public.job_titles jt
    where upper(jt.code) = v_code and jt.id is distinct from p_id
  ) then
    raise exception 'كود المسمى الوظيفي مستخدم لغيره' using errcode = '23505';
  end if;
  if p_id is null then
    insert into public.job_titles (code, name, name_en, is_active, created_by)
    values (v_code, trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_is_active, true), auth.uid())
    returning id into v_id;
  else
    update public.job_titles set
      code = v_code,
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'المسمى الوظيفي غير موجود' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.delete_job_title(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_blockers text[] := array[]::text[];
begin
  if not (public.current_is_full_access() or public.has_permission('organization.job_title.manage')) then
    raise exception 'إدارة المسميات الوظيفية مرفوضة' using errcode = '42501';
  end if;

  select jt.name into v_name from public.job_titles jt where jt.id = p_id;
  if v_name is null then
    raise exception 'المسمى الوظيفي غير موجود' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.employees e where e.job_title_id = p_id and not e.is_deleted) then
    v_blockers := v_blockers || 'موظفون حاملون له';
  end if;
  if exists (select 1 from public.positions p where p.job_title_id = p_id) then
    v_blockers := v_blockers || 'مناصب مرتبطة به';
  end if;

  if array_length(v_blockers, 1) > 0 then
    raise exception 'لا يمكن حذف المسمى الوظيفي «%» لأنه مرتبط بـ: %',
      v_name, array_to_string(v_blockers, '، ') using errcode = '23514';
  end if;

  delete from public.job_titles where id = p_id;
end;
$$;

revoke execute on function public.get_job_titles_overview() from public, anon;
grant execute on function public.get_job_titles_overview() to authenticated;

revoke execute on function public.upsert_job_title(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.upsert_job_title(uuid, text, text, text, boolean) to authenticated;

revoke execute on function public.delete_job_title(uuid) from public, anon;
grant execute on function public.delete_job_title(uuid) to authenticated;
