-- mig 0390: جدولة تلقائية للملخص التنفيذي الأسبوعي
-- يُنشئ سطراً في scheduled_reports إن لم يكن موجوداً،
-- ويجدول تشغيله كل أحد (run_weekday=0) الساعة 7:00 صباحاً بتوقيت القاهرة.
-- report_type = executive_daily يُولّد: الإجمالي + الحضور + النزاعات + الطلبات + KPI.

do $$
declare
  v_next timestamptz;
begin
  -- حساب أقرب أحد قادم الساعة 7:00
  v_next := date_trunc('week',
    now() at time zone 'Africa/Cairo' + interval '1 week'
  ) at time zone 'Africa/Cairo' + interval '7 hours';

  insert into public.scheduled_reports (
    code,
    name_ar,
    report_type,
    audience_scope,
    schedule_kind,
    timezone,
    run_hour,
    run_weekday,
    delivery_channels,
    active,
    next_run_at
  ) values (
    'EXEC_WEEKLY_SUMMARY',
    'الملخص التنفيذي الأسبوعي',
    'executive_daily',      -- generator موجود، يُولّد تقرير شامل
    'organization',
    'weekly',
    'Africa/Cairo',
    7,
    0,                      -- 0 = الأحد
    array['in_app', 'push']::text[],
    true,
    v_next
  ) on conflict (code) do update
      set
        active      = true,
        run_hour    = 7,
        run_weekday = 0,
        updated_at  = now();

  raise notice 'تمت جدولة الملخص التنفيذي الأسبوعي — أول تشغيل: %', v_next;
end;
$$;
