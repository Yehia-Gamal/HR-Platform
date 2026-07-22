-- =====================================================================
-- 0047: الاستحقاق الشهري للإجازات + مشغّل الجدولة (pg_cron)
-- =====================================================================
-- المشكلة (من الفحص العميق):
--   البنية الدفترية للإجازات (0026) ومعالج SLA (0026) وتنظيف الاحتفاظ
--   (0037) وطابور التقارير (0033) كلها موجودة كدوال، لكن لا مشغّل آلي
--   يستدعيها — فتبقى معطّلة عمليًا. كما لا توجد دالة استحقاق شهري تنشئ
--   قيود accrual في الدفتر رغم وجود entry_type='accrual'.
-- الحل:
--   1. حقل monthly_accrual_units على leave_types (معدل الاستحقاق الشهري).
--   2. دالة run_monthly_leave_accrual — service_role فقط، idempotent عبر
--      source_key فريد لكل (موظف/نوع/شهر)، لا تتجاوز الحد السنوي.
--   3. تفعيل pg_cron وجدولة الدوال الأربع بأمان، مع حارس يتجاهل الجدولة
--      إن لم تتوفر الإضافة (بيئة محلية) دون كسر الـmigration.
-- =====================================================================

-- 1) معدل الاستحقاق الشهري على نوع الإجازة
alter table public.leave_types
  add column if not exists monthly_accrual_units numeric(6,2) not null default 0;

comment on column public.leave_types.monthly_accrual_units is
  'وحدات الاستحقاق التلقائي شهريًا لهذا النوع (0 = بلا استحقاق دوري). لا يتجاوز التجميع max_days_per_year.';

-- =====================================================================
-- 2) دالة الاستحقاق الشهري (server-authored)
-- =====================================================================
create or replace function public.run_monthly_leave_accrual(
  p_year  integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer,
  p_month integer default extract(month from (now() at time zone 'Africa/Cairo'))::integer,
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count   integer := 0;
  v_row     record;
  v_key     text;
  v_ytd     numeric;
  v_grant   numeric;
begin
  -- محصور بالخادم الموثوق أو full access
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_month < 1 or p_month > 12 then
    raise exception 'INVALID_MONTH' using errcode = '22023';
  end if;

  for v_row in
    select e.id as employee_id, lt.id as leave_type_id,
           lt.monthly_accrual_units as rate, lt.max_days_per_year as cap
    from public.employees e
    cross join public.leave_types lt
    where e.is_active = true
      and e.status = 'active'
      and lt.is_active = true
      and lt.affects_balance = true
      and lt.monthly_accrual_units > 0
    limit greatest(1, least(p_limit, 50000))
  loop
    -- مفتاح idempotent فريد لكل موظف/نوع/شهر: لا استحقاق مزدوج ولو تكرر التشغيل
    v_key := format('leave:accrual:%s:%s:%s-%s',
                    v_row.employee_id, v_row.leave_type_id, p_year, lpad(p_month::text, 2, '0'));

    -- تجاوز الحد السنوي: لا نمنح ما يتخطى max_days_per_year (إن حُدّد)
    v_grant := v_row.rate;
    if v_row.cap is not null then
      select coalesce(sum(units), 0) into v_ytd
      from public.leave_ledger_entries
      where employee_id = v_row.employee_id
        and leave_type_id = v_row.leave_type_id
        and entry_type in ('opening','accrual','carryover')
        and extract(year from effective_date)::integer = p_year;
      v_grant := least(v_row.rate, greatest(0, v_row.cap - v_ytd));
    end if;

    if v_grant > 0 then
      -- apply_leave_ledger_entry يتجاهل التكرار عبر unique(source_key)
      perform public.apply_leave_ledger_entry(
        v_row.employee_id, v_row.leave_type_id, p_year,
        'accrual', v_grant, v_key, null,
        format('استحقاق شهري تلقائي %s-%s', p_year, lpad(p_month::text, 2, '0')),
        jsonb_build_object('year', p_year, 'month', p_month, 'rate', v_row.rate)
      );
      v_count := v_count + 1;
    end if;
  end loop;

  perform public.log_audit_event(
    'leave.accrual.run', 'hr', 'info', 'leave_ledger_entries', null,
    'تشغيل الاستحقاق الشهري للإجازات',
    format('السنة %s الشهر %s', p_year, p_month),
    jsonb_build_object('year', p_year, 'month', p_month, 'granted', v_count)
  );
  return v_count;
end $$;

comment on function public.run_monthly_leave_accrual(integer,integer,integer) is
  'server-authored: استحقاق شهري idempotent للإجازات، لا يتجاوز الحد السنوي، يُستدعى من pg_cron أو full access.';

revoke execute on function public.run_monthly_leave_accrual(integer,integer,integer) from public, anon, authenticated;
grant execute on function public.run_monthly_leave_accrual(integer,integer,integer) to service_role;

-- =====================================================================
-- 3) تفعيل pg_cron وجدولة المهام (حارس آمن)
-- =====================================================================
-- ملاحظة: pg_cron متاح على Supabase المُدار. في البيئات التي لا تملكه
-- (بعض إعدادات db reset المحلية) نتجاوز الجدولة دون كسر الترحيل، ويُشغّل
-- المشغّل الخارجي (Scheduled Edge Functions) الدوال نفسها بنفس التواقيع.
do $cron$
declare
  v_has_cron boolean;
begin
  select exists (select 1 from pg_available_extensions where name = 'pg_cron') into v_has_cron;
  if not v_has_cron then
    raise notice 'pg_cron غير متاح في هذه البيئة؛ تُشغّل المهام عبر مشغّل خارجي بنفس تواقيع الدوال.';
    return;
  end if;

  create extension if not exists pg_cron;

  -- إزالة الجداول السابقة إن وُجدت لجعل الترحيل idempotent
  perform cron.unschedule(jobname)
  from cron.job
  where jobname in ('hr_request_sla','hr_leave_accrual','hr_retention_cleanup','hr_scheduled_reports');

  -- معالج SLA: كل 10 دقائق
  perform cron.schedule('hr_request_sla', '*/10 * * * *',
    $job$ select public.process_request_sla(500); $job$);

  -- الاستحقاق الشهري: أول كل شهر 00:30 (توقيت الخادم UTC؛ الدالة تحسب شهر القاهرة)
  perform cron.schedule('hr_leave_accrual', '30 0 1 * *',
    $job$ select public.run_monthly_leave_accrual(); $job$);

  -- تنظيف السجلات العابرة المنتهية: يوميًا 02:00
  perform cron.schedule('hr_retention_cleanup', '0 2 * * *',
    $job$ select public.cleanup_expired_ephemeral_records(1000); $job$);

  -- طابور التقارير المستحقة: كل 15 دقيقة
  perform cron.schedule('hr_scheduled_reports', '*/15 * * * *',
    $job$ select public.queue_due_scheduled_reports(); $job$);

  raise notice 'تمت جدولة مهام pg_cron الأربع بنجاح.';
end
$cron$;

-- =====================================================================
-- نهاية Migration 0047
-- =====================================================================
