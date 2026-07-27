-- 0079: V23 §3.2 — لا صلاحية فردية للمستخدم.
-- يثبت أن الصلاحيات تمر حصريًا عبر الأدوار (roles) ولا يوجد ربط مباشر
-- بين المستخدمين والصلاحيات. السلسلة الصحيحة:
--   user_roles → roles → role_permissions → permissions
-- هذا القيد المعماري يمنع منح صلاحيات فردية خارج نظام الأدوار.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- (1) لا يوجد جدول user_permissions (الربط المباشر ممنوع)
-- =====================================================================
select hasnt_table('public', 'user_permissions',
  'لا يوجد جدول user_permissions — الصلاحيات تمر عبر الأدوار فقط');

-- =====================================================================
-- (2) الجداول الأربعة الأساسية لسلسلة الصلاحيات موجودة
-- =====================================================================
select has_table('public', 'roles',
  'جدول الأدوار موجود');
select has_table('public', 'permissions',
  'جدول الصلاحيات موجود');
select has_table('public', 'user_roles',
  'جدول ربط المستخدمين بالأدوار موجود');
select has_table('public', 'role_permissions',
  'جدول ربط الأدوار بالصلاحيات موجود');

-- =====================================================================
-- (3) user_roles يشير للأدوار (وليس للصلاحيات مباشرة)
-- =====================================================================
select has_column('public', 'user_roles', 'role_id',
  'user_roles يحتوي عمود role_id');
select col_is_fk('public', 'user_roles', 'role_id',
  'user_roles.role_id مفتاح أجنبي (يشير للأدوار)');

-- =====================================================================
-- (4) role_permissions يربط الأدوار بالصلاحيات (الوسيط الوحيد)
-- =====================================================================
select has_column('public', 'role_permissions', 'role_id',
  'role_permissions يحتوي عمود role_id');
select has_column('public', 'role_permissions', 'permission_id',
  'role_permissions يحتوي عمود permission_id');
select col_is_fk('public', 'role_permissions', 'role_id',
  'role_permissions.role_id مفتاح أجنبي');
select col_is_fk('public', 'role_permissions', 'permission_id',
  'role_permissions.permission_id مفتاح أجنبي');

-- =====================================================================
-- (5) لا يوجد عمود permission_id في user_roles (منع التجاوز)
-- =====================================================================
select hasnt_column('public', 'user_roles', 'permission_id',
  'user_roles لا يحتوي عمود permission_id — لا ربط مباشر بالصلاحيات');

select * from finish();
rollback;
