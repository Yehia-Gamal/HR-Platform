-- =====================================================================
-- V23 وكيل 05 — فصل مهلة التصعيد: مدير تنفيذي 6 ساعات / بقية 12 ساعة
--
-- الوضع السابق: إعداد واحد leave_approval_escalation_hours = 24
-- V23: مهلتان مختلفتان حسب نوع المدير:
--   • المدير التنفيذي → 6 ساعات (leave_escalation_hours_executive)
--   • باقي المديرين → 12 ساعة (leave_escalation_hours_other)
--
-- التغييرات:
--   1) إدراج إعدادين جديدين في org_settings
--   2) تعليم الإعداد القديم deprecated
--   3) دالة مساعدة get_escalation_hours(p_manager_id)
--   4) مشغل BEFORE INSERT على requests لضبط decision_due_at
--
-- التراجع: حذف المشغل والدالة والإعدادات الجديدة
-- =====================================================================

-- =====================================================================
-- 1) إعدادات التصعيد الجديدة
-- =====================================================================
insert into public.org_settings (key, value, description)
values
  ('leave_escalation_hours_executive', '6',
   'V23: مهلة تصعيد الإجازة للمدير التنفيذي (ساعات)'),
  ('leave_escalation_hours_other', '12',
   'V23: مهلة تصعيد الإجازة لباقي المديرين (ساعات)')
on conflict (key) do nothing;

-- تعليم الإعداد القديم deprecated
update public.org_settings
set description = 'DEPRECATED by V23 — استبدل بـ leave_escalation_hours_executive + leave_escalation_hours_other'
where key = 'leave_approval_escalation_hours';

-- =====================================================================
-- 2) دالة مساعدة: get_escalation_hours(p_manager_id)
--    تُعيد عدد ساعات المهلة حسب نوع المدير
-- =====================================================================
create or replace function public.get_escalation_hours(p_manager_id uuid)
returns integer
language sql stable security definer set search_path = public, pg_temp
as $$
  select case
    when exists (
      select 1 from public.employee_roles er
        join public.roles r on r.id = er.role_id
      where er.employee_id = p_manager_id
        and er.is_active = true
        and r.slug = 'executive-director'
    )
    then coalesce(
      (select value::int from public.org_settings where key = 'leave_escalation_hours_executive'),
      6
    )
    else coalesce(
      (select value::int from public.org_settings where key = 'leave_escalation_hours_other'),
      12
    )
  end;
$$;

comment on function public.get_escalation_hours(uuid) is
  'V23: مهلة التصعيد حسب نوع المدير — تنفيذي=6س، غيره=12س';

-- =====================================================================
-- 3) مشغل BEFORE INSERT على requests لضبط decision_due_at تلقائيًا
-- =====================================================================
create or replace function public.tg_adjust_escalation_deadline()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_hours int;
  v_manager_id uuid;
begin
  -- فقط لطلبات الإجازة التي لها خطوة موافقة (step_order >= 1)
  if new.request_type = 'leave' and new.current_step_order >= 1 then
    -- جلب المدير المسؤول عن الخطوة الحالية
    select approver_id into v_manager_id
    from public.request_steps
    where request_id = new.id
      and step_order = new.current_step_order
    limit 1;

    if v_manager_id is not null then
      v_hours := public.get_escalation_hours(v_manager_id);
      new.decision_due_at := now() + (v_hours || ' hours')::interval;
    end if;
  end if;

  return new;
end;
$$;

-- ربط المشغل (DROP أولاً لتجنب التكرار)
drop trigger if exists trg_adjust_escalation_deadline on public.requests;
create trigger trg_adjust_escalation_deadline
  before insert on public.requests
  for each row
  execute function public.tg_adjust_escalation_deadline();

comment on trigger trg_adjust_escalation_deadline on public.requests is
  'V23: ضبط مهلة القرار تلقائيًا حسب نوع المدير (6 أو 12 ساعة)';
