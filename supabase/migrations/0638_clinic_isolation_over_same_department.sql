-- 0638: أولوية عزل الدور (العيادات) على منح رؤية زميل القسم
-- =====================================================================
-- الخلفية:
--   0474 منح «زميل القسم» رؤية أي هدف معزول بنفس القسم (زملاء الإدارة
--   الطبية المعزولة إدارياً)، و0572 أضاف العزل بالدور (clinic-staff) مع
--   اختبار يضمن: «الموظف العادي لا يرى موظف العيادات» — لكن القاعدة
--   القديمة كانت تعود قبلها فيتم تجاوز صمت العيادات لكل من يشارك
--   موظف العيادات قسماً غير معزول.
-- الإصلاح:
--   منح رؤية زميل القسم يقتصر على من عُزِل بعزل إداري
--   (departments.is_isolated = true). العزل بالدور (clinic-staff) لا
--   يُتجاوز لزميل القسم؛ تبقى استثناءات الدور (HR/تنفيذي/مدير
--   العيادات) وعلاقة المدير المباشر كما هي.
begin;

create or replace function public.can_view_isolated_employee(p_target uuid)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid := public.current_employee_id();
begin
  if not public.is_employee_isolated(p_target) then return true; end if;
  -- 0572: استثناءات الدور (HR/تنفيذي/مدير العيادات) تتجاوز العزل الإداري.
  if public.current_can_view_all_employees() then return true; end if;
  if v_me is null then return false; end if;
  -- 0638: زميل القسم — فقط إن كان عزل الهدف إدارياً (is_isolated)؛
  -- العزل بالدور (العيادات) لا يُتجاوز بمشاركة القسم.
  if exists (
    select 1
      from public.employees t
      join public.departments d on d.id = t.department_id
     where t.id = p_target
       and d.is_isolated
       and t.department_id = (select e.department_id from public.employees e where e.id = v_me)
  ) then return true; end if;
  -- المدير المباشر (علاقة إشراف سارية)
  if exists (
    select 1 from public.manager_relations mr
     where mr.employee_id = p_target
       and mr.manager_employee_id = v_me
       and mr.effective_from <= now()
       and (mr.effective_to is null or mr.effective_to > now())
  ) then return true; end if;
  return false;
end $function$;

comment on function public.can_view_isolated_employee(uuid) is
  'رؤية الهدف المعزول — 0638: زميل القسم يرى فقط من عُزِل عزلاً إدارياً؛ عزل الدور (عيادات) لا يتجاوزه إلا استثناءات الدور أو علاقة الإشراف';

commit;
