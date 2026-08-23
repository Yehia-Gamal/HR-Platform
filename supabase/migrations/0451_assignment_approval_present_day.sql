-- =====================================================================
-- 0451: قبول المأمورية/التكليف = يوم عمل عادي (present)
-- ---------------------------------------------------------------------
-- المطلوب: عند اعتماد mission/convoy/fundraising يُسجَّل الموظف
-- «يعمل» ويُحتسب اليوم يومَ عملٍ عاديًا — دون انتظار بصمة.
--
-- التنفيذ:
--   أ) trigger على requests: عند التحول إلى approved يُنشئ صفوف
--      attendance_daily بحالة 'present' لكل أيام الفترة — إدراج فقط
--      للأيام الغائبة (ON CONFLICT DO NOTHING) حتى لا يمس بصمات
--      فعلية أو إجازات أو تعديلات إدارية قائمة.
--   ب) backfill لكل الطلبات المعتمدة سابقًا التي تفتقد صفوفها.
--
-- ملاحظة الإلغاء: سحب/إلغاء التكليف لا يحذف الصفوف تلقائيًا (اليوم قد
-- يكون عملًا فعليًا) — التصحيح يدوي من المشغّل عند الحاجة، اتساقًا مع
-- سلوك بقية أنواع الطلبات.
-- =====================================================================

begin;

create or replace function public.tg_assignment_day_present()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_start date;
  v_end   date;
  v_day   date;
  v_guard integer := 0;
begin
  if new.request_type not in ('mission','convoy','fundraising') then
    return new;
  end if;
  if new.status = 'approved' and old.status is distinct from 'approved' then
    v_start := public._payload_date(new.payload, 'startDate');
    v_end   := coalesce(public._payload_date(new.payload, 'endDate'), v_start);
    if v_start is null then
      return new;
    end if;
    v_day := v_start;
    while v_day <= v_end and v_guard < 90 loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values (new.employee_id, v_day, 'present')
      on conflict (employee_id, work_date) do nothing;
      v_day  := v_day + 1;
      v_guard := v_guard + 1;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists trg_assignment_day_present on public.requests;
create trigger trg_assignment_day_present
  after insert or update of status on public.requests
  for each row execute function public.tg_assignment_day_present();

-- ─── Backfill: المعتمدة سابقًا ذات الأيام الفاقدة ──────────────────────
do $$
declare
  r record;
  v_day date;
  v_end date;
  v_guard integer;
begin
  for r in
    select req.id, req.employee_id,
           public._payload_date(req.payload,'startDate') as start_date,
           coalesce(public._payload_date(req.payload,'endDate'),
                    public._payload_date(req.payload,'startDate')) as end_date
      from public.requests req
     where req.status = 'approved'
       and req.request_type in ('mission','convoy','fundraising')
       and public._payload_date(req.payload,'startDate') is not null
  loop
    v_day   := r.start_date;
    v_end   := coalesce(r.end_date, r.start_date);
    v_guard := 0;
    while v_day <= v_end and v_guard < 90 loop
      insert into public.attendance_daily(employee_id, work_date, status)
      values (r.employee_id, v_day, 'present')
      on conflict (employee_id, work_date) do nothing;
      v_day := v_day + 1;
      v_guard := v_guard + 1;
    end loop;
  end loop;
end $$;

commit;
