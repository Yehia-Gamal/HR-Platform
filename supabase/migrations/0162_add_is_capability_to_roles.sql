-- 0162: إضافة عمود is_capability لجدول الأدوار
-- الغرض: التمييز بين الأدوار الأساسية (employee, hr-manager, …) والأدوار الإضافية
-- (capability roles) مثل عضوية اللجان التي تُضاف فوق الدور الأساسي.
-- هذا يمنع ظهور أدوار اللجان في قائمة اختيار الدور عند إنشاء موظف جديد.

alter table public.roles
  add column if not exists is_capability boolean not null default false;

comment on column public.roles.is_capability
  is 'true = دور إضافي (capability) يُضاف فوق الدور الأساسي — مثل عضوية اللجان.';

-- تعيين الأدوار الحالية للجان كـ capability
update public.roles
set is_capability = true, updated_at = now()
where slug in ('committee-member', 'committee-chair')
  and is_capability = false;
