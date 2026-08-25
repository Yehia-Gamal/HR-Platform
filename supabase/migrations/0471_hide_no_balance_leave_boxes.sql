begin;

-- =====================================================================
-- 0471: إخفاء أنواع الإجازات بلا رصيد من صناديق الأرصدة
-- ---------------------------------------------------------------------
-- طلب الإدارة: بطاقة «الرصيد الطبي» (24) تُزال — الإجازة المرضية بلا حد
-- وتُطلب مباشرة، وكذلك «الإجازة بدون أجر» ليس لها رصيد وتُطلب مباشرة.
-- الاستثناء من القائمة: annual / casual / weekly_rest_comp (أرصدة حقيقية).
-- ملاحظة: لا نعتمد affects_balance لأن بدل الراحة الأسبوعية أعلامه
-- affects_balance=false لكن له رصيد حقيقي ممنوح — الاستثناء بالكود أدق.
-- المصدر: get_my_leave_balances يغذي بوكسات الموبايل (طلباتي + الخدمة
-- الذاتية) وأي عرض ويب للأرصدة — الفلترة هنا تغني عن تعديل كل واجهة.
-- =====================================================================

create or replace function public.get_my_leave_balances(p_year integer default extract(year from current_date)::integer)
returns table(leave_type_id uuid,code text,name_ar text,available_units numeric,reserved_units numeric,consumed_units numeric,expires_at date)
language sql stable security definer set search_path=public,pg_temp as $$
  select lt.id,lt.code,lt.name_ar,
    coalesce(a.opening_units+a.accrued_units+a.adjusted_units+a.carryover_units-a.consumed_units-a.reserved_units,0),
    coalesce(a.reserved_units,0),coalesce(a.consumed_units,0),a.expires_at
  from public.leave_types lt
  left join public.leave_balance_accounts a on a.leave_type_id=lt.id and a.employee_id=public.current_employee_id() and a.balance_year=p_year
  where lt.is_active=true
    and lt.code not in ('sick','unpaid')
  order by lt.sort_order,lt.name_ar
$$;

comment on function public.get_my_leave_balances(integer) is
  '0471: أرصدة الإجازات المعروضة للموظف — تُستثنى الأنواع بلا رصيد يُعرض (sick/unpaid: تُطلب مباشرة بلا حد)؛ تبقى annual/casual/weekly_rest_comp.';

revoke execute on function public.get_my_leave_balances(integer) from public;
grant execute on function public.get_my_leave_balances(integer) to authenticated;

commit;
