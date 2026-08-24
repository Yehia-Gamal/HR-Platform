-- 0458: إصلاح نافذة تجميع بصمة منتصف الليل + ترميم صفوف كشف الحضور المتأثرة
--
-- الجذر: في record_attendance_local_biometric و record_attendance_event
-- كان فرع اليوم غير الليلي يحسب حدود الفترة بالتحويل المعكوس:
--   v_work_date::timestamptz AT TIME ZONE v_tz   -- ينتج timestamp بلا منطقة
-- وعند مقارنته بـ event_at (timestamptz) يُفسَّر كـ UTC فينزاح نافذة اليوم
-- +3 ساعات: [03:00Z، 03:00Z+1d) بدل [21:00Z، 21:00Z+1d).
-- النتيجة: أي بصمة بين 00:00 و02:59 صباحاً بتوقيت القاهرة لا تدخل تجميع
-- يومها فيُنشأ صف attendance_daily فارغ مع بقاء الحدث في السجل، وتستمر
-- تنبيهات «نسيت البصمة» رغم التسجيل الفعلي.
--
-- الإصلاح: التحويل الصحيح من الوسم المحلي إلى timestamptz:
--   v_work_date::timestamp AT TIME ZONE v_tz
-- يطبَّق ديناميكياً على تعريفات الدوال كما هي على القاعدة عبر
-- pg_get_functiondev المكافئ (pg_get_functiondef) حفظاً للتوقيع والسمات.
--
-- ثم ترميم: إعادة احتساب حقول الكشف لآخر 90 يوماً للصفوف غير المكتملة
-- تسويتها من الأحداث المقبولة بنافذة القاهرة الصحيحة، دون المساس بحالات
-- الإجازات/الغياب/الراحة أو الصفوف المكتملة التسوية أو خفض أي حالة قائمة.

-- ═══════════════ 1) ترقيع دوال التسجيل ═══════════════
do $patch$
declare
  r record;
  fulldef text;
  newdef text;
  patched int := 0;
begin
  for r in
    select oid, proname
    from pg_proc
    where proname in ('record_attendance_local_biometric', 'record_attendance_event')
      and prosrc like '%v_work_date::timestamptz at time zone v_tz%'
  loop
    fulldef := pg_get_functiondef(r.oid);
    newdef := regexp_replace(
      fulldef,
      'v_period_start\s*:=\s*v_work_date::timestamptz at time zone v_tz',
      'v_period_start := v_work_date::timestamp at time zone v_tz'
    );
    newdef := regexp_replace(
      newdef,
      'v_period_end\s*:=\s*\(?v_work_date \+ 1\)?::timestamptz at time zone v_tz',
      'v_period_end := (v_work_date + 1)::timestamp at time zone v_tz'
    );
    if newdef <> fulldef then
      execute newdef;
      patched := patched + 1;
      raise notice 'patched %', r.proname;
    else
      raise notice 'no_change %', r.proname;
    end if;
  end loop;
  raise notice 'total_patched=%', patched;

  -- تحقق صارم: لا يجوز بقاء النمط المعكوس في أيٍّ من الدالتين
  if exists (
    select 1 from pg_proc
    where proname in ('record_attendance_local_biometric', 'record_attendance_event')
      and prosrc like '%::timestamptz at time zone v_tz%'
  ) then
    raise exception 'attendance_period_boundary_patch_incomplete';
  end if;

  -- تحقق موجب: النمط الصحيح حاضر في الدالة الحيوية للمسار المحلي
  if not exists (
    select 1 from pg_proc
    where proname = 'record_attendance_local_biometric'
      and prosrc like '%v_work_date::timestamp at time zone v_tz%'
  ) then
    raise exception 'attendance_period_boundary_fix_marker_missing';
  end if;
end
$patch$;

-- ═══════════════ 2) ترميم صفوف الكشف المتأثرة ═══════════════
with periods as (
  -- نافذة كل صف الصحيحة: [منتصف ليل work_date بالقاهرة، +1 يوم)
  select ad.id,
         ad.employee_id,
         (ad.work_date::timestamp at time zone 'Africa/Cairo')       as p_start,
         ((ad.work_date + 1)::timestamp at time zone 'Africa/Cairo') as p_end
  from public.attendance_daily ad
  where ad.is_finalized = false
    and ad.work_date >= (current_date - interval '90 days')::date
),
agg as (
  select pr.id,
         min(ae.event_at) filter (where ae.event_type = 'CHECK_IN')  as first_in,
         max(ae.event_at) filter (where ae.event_type = 'CHECK_OUT') as last_out
  from periods pr
  join public.attendance_events ae
    on ae.employee_id = pr.employee_id
   and ae.event_at >= pr.p_start
   and ae.event_at <  pr.p_end
   and ae.status in ('accepted','adjusted')
  group by pr.id
),
targets as (
  select ad.id,
         ad.first_check_in as cur_first,
         ad.last_check_out as cur_last,
         g.first_in,
         g.last_out
  from public.attendance_daily ad
  join periods pr on pr.id = ad.id
  left join agg g on g.id = ad.id
  where ad.status not in ('on_leave','holiday','weekend','absent')
    and (
      (ad.first_check_in is null and g.first_in is not null)
      or (ad.last_check_out is null and g.last_out is not null)
      or g.first_in is distinct from ad.first_check_in
      or g.last_out  is distinct from ad.last_check_out
    )
),
updated as (
  update public.attendance_daily ad set
    first_check_in = coalesce(t.first_in, t.cur_first),
    last_check_out = coalesce(t.last_out, t.cur_last),
    work_minutes   = case
                       when coalesce(t.first_in, t.cur_first) is not null
                        and coalesce(t.last_out,  t.cur_last) is not null
                         then greatest(0, floor(extract(epoch from
                              (coalesce(t.last_out, t.cur_last)
                             - coalesce(t.first_in,t.cur_first))) / 60))::int
                       else ad.work_minutes end,
    status         = case
                       -- رفع partial فقط عند اكتمال البصمتين؛ لا خفض لأي حالة قائمة
                       when ad.status = 'partial'
                            and coalesce(t.first_in, t.cur_first) is not null
                            and coalesce(t.last_out,  t.cur_last) is not null
                         then 'present'
                       else ad.status end,
    updated_at     = now()
  from targets t
  where ad.id = t.id
    and (t.first_in is not null or t.last_out is not null)
  returning 1
)
select count(*) as repaired_rows from updated;
