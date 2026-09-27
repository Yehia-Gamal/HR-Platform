-- =====================================================================
-- 0566: لوحة الشرف — حساب صحيح ومضبوط (إعادة بناء كنونية لـ get_honor_board)
--
-- أخطاء 0565 كما ظهرت للمستخدم:
--  1) «الأسبوع الحالي» كان CURRENT_DATE-7 → CURRENT_DATE = 8 أيام تقويمية،
--     فظهر «حضور كامل 8 يوماً» في أسبوع.
--  2) أيام الحضور كانت تُعدّ حتى في الجمعة/العطلات بينما المقام أيام العمل فقط؛
--     فتتجاوز النسبة 100% وتتصدّر (عُرضت 100% بعد القصّ)، فسبق من حضر يومين
--     من حضر 7 أيام. وكان اليوم الجاري يُحسب يوم عمل متوقعاً قبل أن يبدأ الدوام.
--  3) التقارير: الترتيب بعدد تقارير الفترة لكن العرض يسقط إلى العدد الكلي منذ
--     البداية لمن لا تقارير له في الفترة («9 تقريراً» تحت «2 تقارير»).
--  4) المأموريات: جدول missions يضم المأموريات فقط دون القوافل والفاندي، ومن
--     لا مأموريات له يُعرض له عدد أيام الدوام بدل المأموريات.
--  5) CURRENT_DATE بتوقيت الخادم (UTC) لا القاهرة.
--
-- التعريف الجديد (موثّق هنا لأن اللوحة يراها كل الموظفين):
--  • الفترة: الأسبوع = من السبت الماضي حتى اليوم (بداية أسبوع العمل في مصر)؛
--    الشهر = من أول الشهر حتى اليوم. كل التواريخ بتوقيت القاهرة.
--  • يوم العمل المتوقع للموظف: يوم في الفترة ليس جمعة ولا عطلة رسمية، وبعد
--    تاريخ تعيينه؛ الأيام الماضية كلها، واليوم الجاري فقط إن سجّل فيه حضوراً
--    (فلا يُحسب غائباً صباحاً قبل بدء الدوام).
--  • الإجازة المعتمدة في يوم عمل تُطرح من المقام (لا تُعاقب ولا تُكافأ).
--  • نسبة الانضباط = أيام الحضور في أيام العمل ÷ (أيام العمل − الإجازات)،
--    لا تتجاوز 100%. الحضور في جمعة/عطلة لا يرفع النسبة بل يُذكر كجهد إضافي
--    ويكسر التعادل. الترتيب: النسبة ↓ ثم أيام الحضور ↓ ثم دقائق التأخير ↑ ثم
--    الأيام الإضافية ↓. المعفيّون من البصمة والإدارة التنفيذية خارج الترتيب.
--  • المأموريات الميدانية: طلبات مأمورية/قافلة/فاندي **معتمدة** تتقاطع مع الفترة
--    (payload.startDate/endDate)؛ الترتيب بعددها ثم بمجموع أيامها.
--  • التقارير اليومية: عدد التقارير المرفوعة في الفترة فقط؛ من لا تقارير له
--    في الفترة لا يظهر.
-- =====================================================================

begin;

-- صيغة العدد العربية الصحيحة: 1 تقرير، 2 تقريران، 3–10 تقارير، 11+ تقريراً.
create or replace function public._ar_count(p_n bigint, p_one text, p_two text, p_few text, p_many text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $ar$
  select case
    when p_n = 2 then p_two
    when p_n % 100 between 3 and 10 then p_n || ' ' || p_few
    when p_n = 1 or p_n % 100 in (0, 1, 2) then p_n || ' ' || p_one
    else p_n || ' ' || p_many
  end;
$ar$;
revoke all on function public._ar_count(bigint, text, text, text, text) from public, anon;

create or replace function public.get_honor_board(p_period text default 'month', p_category text default 'attendance')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_start  date;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if p_period = 'week' then
    -- السبت = 6 في extract(dow): السبت الماضي (أو اليوم إن كان سبتاً)
    v_start := v_today - ((extract(dow from v_today)::int + 1) % 7);
  else
    v_start := date_trunc('month', v_today)::date;
  end if;

  if p_category = 'attendance' then
    with days as (
      select d::date as day,
             (extract(dow from d) <> 5
              and not exists (
                select 1 from public.public_holidays h
                where h.is_active
                  and d::date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
              )) as is_workday
      from generate_series(v_start, v_today, interval '1 day') d
    ),
    staff as (
      select e.id, e.full_name_ar, e.photo_url, e.hire_date,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not coalesce(e.is_attendance_exempt, false)
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    ),
    grid as (
      -- كل (موظف × يوم) في الفترة بعد تاريخ تعيينه، مع سجل الحضور إن وُجد
      select s.id as employee_id, dy.day, dy.is_workday, ad.status,
             coalesce(ad.late_minutes, 0) as late_minutes
      from staff s
      cross join days dy
      left join public.attendance_daily ad on ad.employee_id = s.id and ad.work_date = dy.day
      where s.hire_date is null or dy.day >= s.hire_date
    ),
    per_emp as (
      select g.employee_id,
             count(*) filter (where g.is_workday and (g.day < v_today or g.status is not null)) as workdays,
             count(*) filter (where g.is_workday and g.status = 'on_leave') as leave_days,
             count(*) filter (where g.is_workday and g.status in ('present','attended','excused','mission','missing_checkout')) as present_days,
             count(*) filter (where not g.is_workday and g.status in ('present','attended','excused','mission','missing_checkout')) as extra_days,
             coalesce(sum(g.late_minutes) filter (where g.status in ('present','attended','excused','mission','missing_checkout')), 0) as late_minutes
      from grid g
      group by g.employee_id
    ),
    scored as (
      select s.*, p.*,
             greatest(p.workdays - p.leave_days, 0) as expected,
             case when p.workdays - p.leave_days > 0
                  then least(p.present_days::numeric / (p.workdays - p.leave_days), 1)
                  else 0 end as ratio
      from per_emp p join staff s on s.id = p.employee_id
      where p.present_days > 0
    ),
    ranked as (
      select row_number() over (
               order by ratio desc, present_days desc, late_minutes asc, extra_days desc, full_name_ar asc
             ) as rank,
             sc.*
      from scored sc
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement',
               case
                 when present_days >= expected and late_minutes = 0
                   then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل بدون أي تأخير'
                 when present_days >= expected
                   then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل (تأخير '
                        || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
                 else 'حضور ' || present_days || ' من ' || expected || ' يوم عمل'
                      || case when late_minutes > 0
                              then ' (تأخير ' || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
                              else '' end
               end
               || case when extra_days > 0
                       then ' + ' || public._ar_count(extra_days, 'يوم إضافي', 'يومان إضافيان', 'أيام إضافية', 'يوماً إضافياً')
                       else '' end,
             'metric', round(ratio * 100)::int || '% انضباط',
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  elsif p_category = 'missions' then
    with field as (
      select r.employee_id,
             greatest((r.payload->>'startDate')::date, v_start) as s,
             least(coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date), v_today) as e
      from public.requests r
      where r.request_type in ('mission', 'convoy', 'fundraising')
        and r.status = 'approved'
        and r.payload ? 'startDate'
        and (r.payload->>'startDate')::date <= v_today
        and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date) >= v_start
    ),
    per_emp as (
      select employee_id, count(*) as missions, sum(e - s + 1) as field_days
      from field group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.missions desc, p.field_days desc, e.full_name_ar asc) as rank,
             e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.missions, p.field_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement', public._ar_count(missions, 'مأمورية ميدانية معتمدة', 'مأموريتان ميدانيتان معتمدتان', 'مأموريات ميدانية معتمدة', 'مأمورية ميدانية معتمدة')
                            || ' بإجمالي ' || public._ar_count(field_days, 'يوم عمل ميداني', 'يوما عمل ميداني', 'أيام عمل ميداني', 'يوم عمل ميداني'),
             'metric', public._ar_count(missions, 'مأمورية', 'مأموريتان', 'مأموريات', 'مأمورية'),
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  else
    with per_emp as (
      select employee_id, count(*) as reports, count(distinct report_date) as report_days
      from public.daily_reports
      where report_date between v_start and v_today
      group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.reports desc, p.report_days desc, e.full_name_ar asc) as rank,
             e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.reports, p.report_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement', 'رفع ' || public._ar_count(reports, 'تقرير يومي', 'تقريرين يوميين', 'تقارير يومية', 'تقريراً يومياً')
                            || ' في ' || public._ar_count(report_days, 'يوم', 'يومين', 'أيام', 'يوماً'),
             'metric', public._ar_count(reports, 'تقرير', 'تقريران', 'تقارير', 'تقريراً'),
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;
  end if;

  return coalesce(v_result, '[]'::jsonb);
end;
$fn$;

revoke execute on function public.get_honor_board(text, text) from public, anon;
grant execute on function public.get_honor_board(text, text) to authenticated, service_role;

commit;
