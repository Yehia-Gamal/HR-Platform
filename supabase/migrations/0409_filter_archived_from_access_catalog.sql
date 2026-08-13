-- 0409: إخفاء الموظفين المؤرشفين/المحذوفين من كتالوج إسنادات المستخدمين
-- ═════════════════════════════════════════════════════════════════════════
-- المشكلة: get_access_admin_catalog (0190) لا يُرشّح قسم users حسب
-- is_active/is_deleted، فيظهر الموظفون المؤرشفون والمحذوفون ناعماً في
-- قائمة "إسنادات المستخدمين" برغم أنهم ليسوا موظفين فعّالين — فوضى بصرية
-- وفرصة لإسناد أدوار لمن انتهت خدمته. اكتُشفت أصلاً عبر مستخدمَي اختبار
-- E2E معطوبَين (أسماء ???? مؤرشفة) ظهرا في القائمة.
--
-- الحل: إضافة WHERE على قسم users — يُعرض فقط:
--   • الملفات الشخصية بلا موظف مرتبط (e.id is null) — تُترك كما هي
--     دفاعياً (حسابات نظامية/يتيمة لا نُخفيها بالخطأ).
--   • الموظفون الفعّالون غير المحذوفين (is_active=true AND is_deleted=false).
--   يُخفى: المؤرشفون (is_active=false) والمحذوفون ناعماً (is_deleted=true).
--
-- ملاحظة: استخدمنا LEFT JOIN على قصد — شرط e.id is null يحفظ الملفات
-- اليتيمة. تغيير LEFT إلى INNER سيُسقط تلك الملفات وهذا غير مرغوب.
-- ═════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.get_access_admin_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.role.update','access.role.assign'])) then
    raise exception 'access catalog denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', case
          -- ── أدوار الوصول الكامل: إرجاع كل الصلاحيات ──
          when r.is_full_access then
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', 'organization',
                'requiresMfa', false,
                'requiresReason', false
              ) order by p.module, p.code)
              from public.permissions p
            ), '[]'::jsonb)
          -- ── أدوار عادية: فقط ما في role_permissions ──
          else
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
                'requiresReason', rp.requires_reason
              ) order by p.module, p.code)
              from public.role_permissions rp
              join public.permissions p on p.id = rp.permission_id
              where rp.role_id = r.id
            ), '[]'::jsonb)
        end,
        'assignments', (
          select count(*)
          from public.user_roles ur
          where ur.role_id = r.id
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action, 'name', coalesce(p.description, p.code), 'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'allowedScopes', array[
          'self','direct_reports','management_descendants','selected_employees',
          'team','department','selected_departments','branch','selected_branches',
          'organization','assigned_cases','workflow_inbox',
          'records_created_by_user','archive_readonly'
        ]
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr
      left join public.employees e on e.id = pr.employee_id
      -- ── إخفاء المؤرشفين/المحذوفين ناعماً (مع إبقاء الملفات اليتيمة) ──
      where e.id is null
         or (e.is_active = true and e.is_deleted = false)
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

-- إعادة المنح (التوقيع لم يتغير، لكن نُؤكد GRANT ونسحب من العامة).
revoke execute on function public.get_access_admin_catalog() from public;
grant execute on function public.get_access_admin_catalog() to authenticated;

-- إعادة تحميل مخطط PostgREST كي يلتقط جسم الدالة الجديد.
notify pgrst, 'reload schema';

commit;
