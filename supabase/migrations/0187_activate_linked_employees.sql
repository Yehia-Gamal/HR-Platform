-- 0187: تفعيل جميع الموظفين الذين لديهم حسابات مربوطة
-- ═══════════════════════════════════════════════════════════════════
-- المشكلة: provision_employee_record ينشئ الموظف بحالة 'invited'
-- افتراضيًا (p_invitation_pending = true). كثير من الموظفين لم
-- تتحول حالتهم إلى 'active' رغم أن لديهم حسابات user مربوطة.
-- هذا يمنعهم من الظهور في دورات KPI وعمليات أخرى.
--
-- الحل: تفعيل كل موظف لديه user_id مربوط ولم يُحذف.
-- ═══════════════════════════════════════════════════════════════════

begin;

-- 0) تعطيل triggers الحماية مؤقتاً (المايقريشن تعمل بدون auth context)
alter table public.employees disable trigger trg_employees_protect_job_fields;
alter table public.profiles  disable trigger trg_profiles_protect_sensitive;

-- 1) تفعيل الموظفين المربوطين بحسابات
do $$
declare
  v_count integer;
begin
  update public.employees
  set    status     = 'active',
         updated_at = now()
  where  is_active   = true
    and  is_deleted  = false
    and  status     != 'active'
    and  user_id    is not null;

  get diagnostics v_count = row_count;
  raise notice 'activated % employees with linked user accounts', v_count;
end $$;

-- 2) تحديث profiles المرتبطة أيضًا
update public.profiles
set    status     = 'active',
       updated_at = now()
where  status    != 'active'
  and  employee_id in (
    select id from public.employees
    where status = 'active' and is_active = true and is_deleted = false
  );

-- 3) تسجيل الحدث في سجل التدقيق
do $$
declare
  v_active_count integer;
  v_total_count  integer;
begin
  select count(*) filter (where status = 'active' and is_active and not is_deleted),
         count(*) filter (where is_active and not is_deleted)
  into   v_active_count, v_total_count
  from   public.employees;

  raise notice 'employee status after migration: %/% active', v_active_count, v_total_count;

  -- سجل تدقيق
  if exists (select 1 from pg_proc where proname = 'log_audit_event') then
    perform public.log_audit_event(
      'employee.bulk_activate',
      'admin',
      'notice',
      'employees',
      null,
      format('تفعيل الموظفين المربوطين بحسابات: %s/%s نشط', v_active_count, v_total_count),
      null,
      jsonb_build_object('active_count', v_active_count, 'total_count', v_total_count)
    );
  end if;
end $$;

-- 4) إعادة تفعيل triggers الحماية
alter table public.employees enable trigger trg_employees_protect_job_fields;
alter table public.profiles  enable trigger trg_profiles_protect_sensitive;

commit;
