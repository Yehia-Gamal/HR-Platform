-- ================================================================================
-- 0352: Knowledge — managed categories, server-side search, edit permissions
-- ================================================================================
-- الأهداف:
--   1) جدول knowledge_categories (تصنيفات مُدارة) + ربط category_id بالمقالات.
--   2) صلاحية knowledge.manage لإدارة التصنيفات + منحها للأدوار الإدارية.
--   3) فهرس GIN trigram للبحث العربي server-side عبر RPC get_knowledge_catalog.
--   4) RPCs محمية security definer لإنشاء/تعديل/حذف التصنيفات.
-- الأنماط المتبعة: RLS مثل 0009، منح مثل 0344، فهارس مثل 0218، RPC مثل 0031.

BEGIN;

-- ============================================================================
-- 1) جدول التصنيفات المُدارة
-- ============================================================================
create table if not exists public.knowledge_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

comment on table public.knowledge_categories is 'تصنيفات قاعدة المعرفة المُدارة';

create index if not exists idx_knowledge_categories_active on public.knowledge_categories(is_active);

drop trigger if exists trg_knowledge_categories_updated_at on public.knowledge_categories;
create trigger trg_knowledge_categories_updated_at before update on public.knowledge_categories
  for each row execute function public.tg_set_updated_at();

-- ربط المقالات بالتصنيفات (يُحفظ category النصي القديم للتوافق، لكن الإدارة عبر category_id)
alter table public.knowledge_articles
  add column if not exists category_id uuid references public.knowledge_categories(id) on delete set null;

create index if not exists idx_knowledge_articles_category_id on public.knowledge_articles(category_id);

-- ============================================================================
-- 2) RLS على التصنيفات
--    - القراءة: للجميع المصادَق على النشط + للمديرين على الكل
--    - الكتابة/الحذف: knowledge.manage أو full access فقط
-- ============================================================================
alter table public.knowledge_categories enable row level security;

drop policy if exists knowledge_categories_select on public.knowledge_categories;
create policy knowledge_categories_select on public.knowledge_categories
  for select to authenticated
  using (is_active = true or public.has_permission('knowledge.manage') or public.current_is_full_access());

drop policy if exists knowledge_categories_insert on public.knowledge_categories;
create policy knowledge_categories_insert on public.knowledge_categories
  for insert to authenticated
  with check (public.has_permission('knowledge.manage') or public.current_is_full_access());

drop policy if exists knowledge_categories_update on public.knowledge_categories;
create policy knowledge_categories_update on public.knowledge_categories
  for update to authenticated
  using (public.has_permission('knowledge.manage') or public.current_is_full_access())
  with check (public.has_permission('knowledge.manage') or public.current_is_full_access());

drop policy if exists knowledge_categories_delete on public.knowledge_categories;
create policy knowledge_categories_delete on public.knowledge_categories
  for delete to authenticated
  using (public.has_permission('knowledge.manage') or public.current_is_full_access());

-- ============================================================================
-- 3) صلاحية knowledge.manage + منحها للأدوار الإدارية
-- ============================================================================
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive)
values ('knowledge.manage', 'knowledge', 'manage', 'manage', 'إدارة تصنيفات قاعدة المعرفة', 'normal', false)
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select
  r.id,
  p.id,
  'organization'
from public.roles r
cross join public.permissions p
where p.code = 'knowledge.manage'
  and r.slug in ('hr-manager', 'system-admin', 'hr-specialist', 'executive-director')
on conflict (role_id, permission_id, scope) do nothing;

-- ============================================================================
-- 4) فهرس GIN trigram للبحث العربي في العناوين والمحتوى
-- ============================================================================
create index if not exists idx_knowledge_articles_search_trgm
  on public.knowledge_articles using gin (title gin_trgm_ops, body gin_trgm_ops);

-- ============================================================================
-- 5) RPC: كتالوج البحث server-side (security definer + فحص داخلي)
--    - غير المدير: منشور فقط (مطابق لـ knowledge_articles_select_published)
--    - المدير (knowledge.write/knowledge.manage/full access): الكل + فلترة حالة
--    - العودة: articles (مع categoryName) + categories + counts
-- ============================================================================
create or replace function public.get_knowledge_catalog(
  p_query text default '',
  p_category_id uuid default null,
  p_status text default 'all',
  p_limit int default 50,
  p_offset int default 0
) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_manage boolean;
  v_q text;
  v_where text;
  v_articles jsonb;
begin
  v_manage := public.current_is_full_access() or public.has_any_permission(array['knowledge.write','knowledge.manage']);

  v_q := coalesce(lower(trim(p_query)), '');
  v_where := ' where true';

  if v_q <> '' then
    v_where := v_where || format(
      ' and (lower(coalesce(title,'''')) like %L or lower(coalesce(category,'''')) like %L or lower(coalesce(body,'''')) like %L)',
      '%' || v_q || '%', '%' || v_q || '%', '%' || v_q || '%'
    );
  end if;

  if p_category_id is not null then
    v_where := v_where || format(' and category_id = %L', p_category_id);
  end if;

  if v_manage then
    if p_status = 'published' then
      v_where := v_where || ' and is_published = true';
    elsif p_status = 'draft' then
      v_where := v_where || ' and is_published = false';
    end if;
  else
    v_where := v_where || ' and is_published = true';
  end if;

  execute format('
    select coalesce(jsonb_agg(row_to_json(t) order by t.updated_at desc nulls last), ''[]''::jsonb)
    from (
      select a.id, a.title, a.category, a.body, a.is_published,
             a.author_employee_id, a.created_at, a.updated_at, a.created_by,
             a.category_id, c.name as category_name
      from public.knowledge_articles a
      left join public.knowledge_categories c on c.id = a.category_id
      %s
      limit %s offset %s
    ) t', v_where, p_limit, p_offset) into v_articles;

  return jsonb_build_object(
    'articles', v_articles,
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'slug', c.slug, 'name', c.name,
        'description', c.description, 'is_active', c.is_active, 'created_at', c.created_at)
        order by c.name) from public.knowledge_categories c
    ), '[]'::jsonb),
    'publishedCount', (select count(*) from public.knowledge_articles where is_published = true),
    'draftCount', (select count(*) from public.knowledge_articles where is_published = false),
    'manage', v_manage,
    'lastUpdatedAt', now()
  );
end $$;

revoke execute on function public.get_knowledge_catalog(text,uuid,text,int,int) from public;
grant execute on function public.get_knowledge_catalog(text,uuid,text,int,int) to authenticated;

-- ============================================================================
-- 6) RPCs إدارة التصنيفات (security definer + فحص knowledge.manage)
-- ============================================================================
create or replace function public.upsert_knowledge_category(
  p_id uuid default null,
  p_slug text default null,
  p_name text default null,
  p_description text default null,
  p_is_active boolean default true
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('knowledge.manage')) then
    raise exception 'FORBIDDEN';
  end if;
  if p_slug is null or p_name is null then
    raise exception 'slug and name are required';
  end if;

  if p_id is null then
    insert into public.knowledge_categories (slug, name, description, is_active, created_by)
    values (lower(btrim(p_slug)), trim(p_name), nullif(btrim(coalesce(p_description,'')),''), p_is_active, auth.uid())
    returning id into v_id;
  else
    update public.knowledge_categories
       set slug = lower(btrim(p_slug)), name = trim(p_name),
           description = nullif(btrim(coalesce(p_description,'')),''),
           is_active = p_is_active
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'NOT_FOUND';
    end if;
  end if;
  return v_id;
end $$;

create or replace function public.delete_knowledge_category(p_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not (public.current_is_full_access() or public.has_permission('knowledge.manage')) then
    raise exception 'FORBIDDEN';
  end if;
  delete from public.knowledge_categories where id = p_id;
end $$;

revoke execute on function public.upsert_knowledge_category(uuid,text,text,text,boolean) from public;
grant execute on function public.upsert_knowledge_category(uuid,text,text,text,boolean) to authenticated;
revoke execute on function public.delete_knowledge_category(uuid) from public;
grant execute on function public.delete_knowledge_category(uuid) to authenticated;

-- ============================================================================
-- 7) تقوية RLS على المقالات: المديرون الجدد (knowledge.manage) يستطيعون القراءة/الكتابة
-- ============================================================================
drop policy if exists knowledge_articles_select_manage on public.knowledge_articles;
create policy knowledge_articles_select_manage on public.knowledge_articles
  for select to authenticated
  using (
    author_employee_id = public.current_employee_id()
    or public.has_permission('knowledge.write')
    or public.has_permission('knowledge.manage')
    or public.current_is_full_access()
  );

drop policy if exists knowledge_articles_insert on public.knowledge_articles;
create policy knowledge_articles_insert on public.knowledge_articles
  for insert to authenticated
  with check (public.has_permission('knowledge.write') or public.has_permission('knowledge.manage') or author_employee_id = public.current_employee_id());

drop policy if exists knowledge_articles_update on public.knowledge_articles;
create policy knowledge_articles_update on public.knowledge_articles
  for update to authenticated
  using (author_employee_id = public.current_employee_id() or public.has_permission('knowledge.write') or public.has_permission('knowledge.manage'))
  with check (author_employee_id = public.current_employee_id() or public.has_permission('knowledge.write') or public.has_permission('knowledge.manage'));

drop policy if exists knowledge_articles_delete on public.knowledge_articles;
create policy knowledge_articles_delete on public.knowledge_articles
  for delete to authenticated
  using (public.has_permission('knowledge.write') or public.has_permission('knowledge.manage') or public.current_is_full_access());

NOTIFY pgrst, 'Reload schema';

COMMIT;
