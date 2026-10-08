-- ============================================================================
-- 0658: تشغيل وصيانة — ملخص يومي للمدير، إغلاق المأموريات المنسية، تصعيد فوري
--        لغياب المدير، إغلاق الطلبات المنسية، تنظيف التصعيد المكرر، وفحص صحي
--        يومي يصل تنبيهه للإدارة
-- ============================================================================
-- ما وُجد على الإنتاج (2026-10-07):
--  • check_employee_penalty_exemption_v2 مكسورة (جداول غير موجودة) وغير مستدعاة
--    من أي دالة أو واجهة، وقابلة للتنفيذ لأي مستخدم مسجَّل → تُحذف.
--  • إشعار «غرامة تأخير لموظف بفريقك» يصل المدير مع كل تسجيل/تصعيد شريحة → ملخص
--    واحد يومي «ملخص فريقك اليوم» (المتأخرون + من بدأ مأموريته متى ومن أين).
--  • 81 تنفيذ مأمورية ما زال «جاريًا» من أيام سابقة مقابل 18 أُنهيت بتقرير →
--    تذكير قبل نهاية الدوام، وإغلاق تلقائي بعد انقضاء يومها، ويبقى بإمكان الموظف
--    كتابة التقرير 14 يومًا (submit_my_mission_report).
--  • process_request_sla تعيد تصعيد الخطوة الأولى كل 24 ساعة (سطر 'escalate'
--    وإشعارات جديدة وإعادة ضبط مهلة الخطوة 2): 2,726 سطرًا معظمها مكرر → تصعيد مرة
--    واحدة، وتنظيف المكرر (يُبقى الأول لكل دورة رفع ولكل جهة).
--  • طلب ينتظر مديرًا في إجازة حتى تنقضي مهلته → تصعيد فوري إن كان المعتمِد في
--    إجازة معتمدة اليوم.
--  • طلبات معلقة منذ أغسطس → إغلاق تلقائي (expired) لما انقضى موعده بأسبوع أو
--    مضى على تقديمه 30 يومًا (المأموريات/القوافل/الفاندي/الأذونات/تغيير الفترة؛
--    الإجازات والتصحيحات خارج النطاق لارتباطها بالأرصدة والسجلات).
--  • 202 تنبيه داخلي عن تعطل كرون الغرامات لم يصل أحدًا → فحص صحي يومي (7 ص):
--    وظائف القاعدة (plpgsql_check)، فشل المهام الدورية وتوقفها، علامات الإصلاحات
--    الحرجة (حماية من إعادة نسخ قديمة)، وتجربة فعلية تُلغى لتقديم طلب واعتماده
--    وصندوق الطلبات وكرون الغرامات؛ والنتيجة إشعار لمدير النظام إن وُجد خلل.
--    ملاحظة: التجربة تستهلك رقم طلب واحدًا يوميًا من التسلسل (لا يُحفظ أي طلب).
--  • دوال الإشعار الداخلية قابلة للاستدعاء من أي مستخدم مسجَّل (انتحال إشعارات) → تُغلق.
-- مواعيد الكرون مزدوجة (UTC) وكل دالة تتحقق من ساعة القاهرة وتمنع التكرار، فلا
-- يتأثر شيء بتغيّر التوقيت الصيفي.

create extension if not exists plpgsql_check with schema extensions;

-- ─── 1) حذف دالة الإعفاء المكسورة غير المستخدمة ─────────────────────────────
drop function if exists public.check_employee_penalty_exemption_v2(uuid, date);

-- ─── 2) هل الموظف في إجازة معتمدة في يوم ما (داخلية) ───────────────────────
create or replace function public.employee_on_leave(p_employee_id uuid, p_day date)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_employee_id is not null and (
       exists (
         select 1 from public.leave_requests lr
           join public.requests r on r.id = lr.request_id
          where lr.employee_id = p_employee_id
            and r.status = 'approved'
            and p_day between lr.start_date and lr.end_date)
    or exists (
         select 1 from public.attendance_daily ad
          where ad.employee_id = p_employee_id and ad.work_date = p_day
            and ad.status = 'on_leave')
    or exists (
         select 1 from public.attendance_day_overrides o
          where o.employee_id = p_employee_id and o.work_date = p_day
            and o.is_active and o.day_type = 'leave')
  );
$$;
comment on function public.employee_on_leave(uuid, date) is
  '0658: داخلية — الموظف في إجازة معتمدة/يوم إجازة في التاريخ (لتصعيد طلبات المدير الغائب).';
revoke all on function public.employee_on_leave(uuid, date) from public, anon, authenticated;

-- ─── 3) تنفيذ المأموريات: إغلاق تلقائي + تذكير + تقرير لاحق ──────────────────
alter table public.mission_executions add column if not exists auto_closed_at timestamptz;
comment on column public.mission_executions.auto_closed_at is
  '0658: وقت الإغلاق التلقائي بعد انقضاء يوم المأمورية دون إنهاء من الموظف.';

create or replace function public.auto_close_stale_missions(p_notify boolean default true)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_row   record;
  v_last  date;
  v_n     integer := 0;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  for v_row in
    select me.id, me.request_id, me.employee_id, me.started_at,
           r.title, r.request_type, r.payload
      from public.mission_executions me
      join public.requests r on r.id = me.request_id
     where me.status = 'in_progress'
       and me.started_at is not null
       and coalesce(public.try_cast_date(r.payload->>'endDate'),
                    (me.started_at at time zone 'Africa/Cairo')::date) < v_today
     for update of me skip locked
  loop
    v_last := greatest(coalesce(public.try_cast_date(v_row.payload->>'endDate'),
                                (v_row.started_at at time zone 'Africa/Cairo')::date),
                       (v_row.started_at at time zone 'Africa/Cairo')::date);
    update public.mission_executions
       set status = 'completed',
           ended_at = greatest(started_at,
                        least(now(), ((v_last + 1)::timestamp at time zone 'Africa/Cairo') - interval '1 minute')),
           report = coalesce(nullif(trim(report), ''), 'أُغلقت تلقائيًا بعد انقضاء يومها دون تقرير من الموظف'),
           auto_closed_at = now(),
           updated_at = now()
     where id = v_row.id;

    if p_notify then
      perform public.notify_employee(
        v_row.employee_id,
        'أُغلقت مأموريتك تلقائيًا — اكتب تقريرها',
        coalesce(v_row.title, 'مأمورية') || ' — انقضى يومها دون إنهاء. افتحها واكتب ما أنجزته (متاح 14 يومًا).',
        'request', 'normal', 'request', v_row.request_id,
        jsonb_build_object('kind', 'mission_auto_closed', 'deepLink', '/requests/' || v_row.request_id));
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.auto_close_stale_missions(boolean) is
  '0658: يغلق تنفيذ المأموريات «الجارية» بعد انقضاء آخر أيامها، دون أثر على الحضور.';
revoke all on function public.auto_close_stale_missions(boolean) from public, anon, authenticated;

create or replace function public.remind_open_missions()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now   timestamp := now() at time zone 'Africa/Cairo';
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_row   record;
  v_n     integer := 0;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  -- جدول مزدوج (14 و15 UTC): التذكير بين 4 و7 مساءً بتوقيت القاهرة مرة واحدة
  if extract(hour from v_now) not between 16 and 18 or extract(isodow from v_today) = 5 then
    return 0;
  end if;

  for v_row in
    select me.request_id, me.employee_id, r.title
      from public.mission_executions me
      join public.requests r on r.id = me.request_id
     where me.status = 'in_progress'
       and (me.started_at at time zone 'Africa/Cairo')::date = v_today
       and coalesce(public.try_cast_date(r.payload->>'endDate'), v_today) <= v_today
       and not exists (
         select 1 from public.notifications n
          where n.recipient_employee_id = me.employee_id
            and n.entity_id = me.request_id
            and n.metadata->>'kind' = 'mission_report_reminder'
            and n.created_at > now() - interval '20 hours')
  loop
    perform public.notify_employee(
      v_row.employee_id,
      'لا تنسَ إنهاء المأمورية وكتابة تقريرها',
      coalesce(v_row.title, 'مأمورية') || ' — ما زالت جارية. عند الانتهاء اضغط «إنهاء المأمورية» واكتب ما أنجزته.',
      'request', 'normal', 'request', v_row.request_id,
      jsonb_build_object('kind', 'mission_report_reminder', 'deepLink', '/requests/' || v_row.request_id));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.remind_open_missions() is
  '0658: تذكير يومي (بعد الرابعة مساءً) لصاحب مأمورية اليوم الجارية بإنهائها وكتابة التقرير.';
revoke all on function public.remind_open_missions() from public, anon, authenticated;

create or replace function public.submit_my_mission_report(
  p_request_id uuid,
  p_report     text,
  p_outcome    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_exec public.mission_executions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  select * into v_exec from public.mission_executions where request_id = p_request_id for update;
  if not found then
    raise exception 'MISSION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_exec.employee_id <> v_me then
    raise exception 'MISSION_OWNER_ONLY' using errcode = '42501';
  end if;
  if v_exec.auto_closed_at is null then
    raise exception 'MISSION_NOT_AUTO_CLOSED' using errcode = '22023';
  end if;
  if v_exec.auto_closed_at < now() - interval '14 days' then
    raise exception 'MISSION_REPORT_WINDOW_CLOSED' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_report, ''))) < 3 then
    raise exception 'REPORT_TOO_SHORT' using errcode = '22023';
  end if;

  update public.mission_executions
     set report = trim(p_report),
         outcome = nullif(trim(coalesce(p_outcome, '')), ''),
         updated_at = now()
   where id = v_exec.id;
  return jsonb_build_object('ok', true, 'requestId', p_request_id);
end;
$$;
comment on function public.submit_my_mission_report(uuid, text, text) is
  '0658: تقرير مأمورية أُغلقت تلقائيًا — لصاحبها خلال 14 يومًا، بلا أثر على الحضور.';
revoke all on function public.submit_my_mission_report(uuid, text, text) from public, anon;
grant execute on function public.submit_my_mission_report(uuid, text, text) to authenticated;

-- ─── 4) إغلاق الطلبات المعلقة المنسية ───────────────────────────────────────
create or replace function public.expire_stale_requests(p_notify boolean default true)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_req   public.requests;
  v_n     integer := 0;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  for v_req in
    select r.*
      from public.requests r
     where r.status = 'pending'
       and r.request_type in ('mission', 'convoy', 'fundraising', 'late_permit', 'early_permit', 'shift_change')
       and (
            coalesce(public.try_cast_date(r.payload->>'endDate'),
                     public.try_cast_date(r.payload->>'permitDate'),
                     public.try_cast_date(r.payload->>'effectiveFrom'),
                     public.try_cast_date(r.payload->>'startDate'),
                     (r.created_at at time zone 'Africa/Cairo')::date) < v_today - 7
         or r.created_at < now() - interval '30 days')
     for update skip locked
  loop
    update public.requests
       set status = 'expired', workflow_status = 'terminated', updated_at = now()
     where id = v_req.id;
    update public.request_steps
       set status = 'skipped', updated_at = now()
     where request_id = v_req.id and status in ('active', 'escalated', 'pending');
    update public.workflow_instances
       set status = 'cancelled', completed_at = now(), updated_at = now()
     where request_id = v_req.id and status = 'running';
    insert into public.request_actions(request_id, actor_employee_id, action, from_status, to_status, comment)
    values (v_req.id, null, 'expire', 'pending', 'expired', 'أُغلق تلقائيًا: انقضى موعده دون قرار');

    if p_notify then
      perform public.notify_employee(
        v_req.employee_id,
        'أُغلق طلبك لانقضاء موعده',
        coalesce(v_req.title, 'طلب') || ' — لم يصدر فيه قرار حتى انقضى موعده فأُغلق تلقائيًا. قدّم طلبًا جديدًا إن لزم.',
        'request', 'normal', 'request', v_req.id,
        jsonb_build_object('kind', 'request_expired', 'deepLink', '/requests/' || v_req.id));
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.expire_stale_requests(boolean) is
  '0658: يغلق (expired) الطلبات المعلقة بعد أسبوع من انقضاء موعدها أو 30 يومًا من تقديمها.';
revoke all on function public.expire_stale_requests(boolean) from public, anon, authenticated;

-- ─── 5) «ملخص فريقك اليوم» للمدير المباشر ──────────────────────────────────
create or replace function public.send_manager_daily_digest(p_force boolean default false)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now    timestamp := now() at time zone 'Africa/Cairo';
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_mgr    record;
  v_late   text;
  v_late_n integer;
  v_unpaid integer;
  v_miss   text;
  v_miss_n integer;
  v_body   text;
  v_n      integer := 0;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  -- جدول مزدوج (9:30 و10:30 UTC): يُرسل بعد 12:00 ظهرًا بتوقيت القاهرة مرة واحدة يوميًا
  if not p_force and (extract(hour from v_now) < 12 or extract(isodow from v_today) = 5) then
    return 0;
  end if;

  for v_mgr in
    select distinct mr.manager_employee_id as id
      from public.manager_relations mr
      join public.employees e on e.id = mr.employee_id
      join public.employees m on m.id = mr.manager_employee_id
     where mr.relation_type = 'primary'
       and mr.effective_from <= v_today
       and (mr.effective_to is null or mr.effective_to >= v_today)
       and e.is_active and not e.is_deleted
       and m.is_active and not m.is_deleted
       and mr.manager_employee_id <> mr.employee_id
  loop
    if exists (
      select 1 from public.notifications n
       where n.recipient_employee_id = v_mgr.id
         and n.metadata->>'kind' = 'manager_daily_digest'
         and n.metadata->>'day' = v_today::text) then
      continue;
    end if;

    with team as (
      select mr.employee_id
        from public.manager_relations mr
       where mr.manager_employee_id = v_mgr.id
         and mr.relation_type = 'primary'
         and mr.effective_from <= v_today
         and (mr.effective_to is null or mr.effective_to >= v_today)
    ),
    late as (
      select e.full_name_ar as name, p.late_minutes
        from public.instant_attendance_penalties p
        join team t on t.employee_id = p.employee_id
        join public.employees e on e.id = p.employee_id
       where p.work_date = v_today
         and p.status in ('pending_payment', 'doubled', 'suspended')
       order by p.late_minutes desc, e.full_name_ar
    )
    select count(*),
           string_agg(name || ' (' ||
             case when late_minutes >= 120 then 'ساعتان فأكثر'
                  when late_minutes >= 60 then 'أكثر من ساعة'
                  else late_minutes || ' د' end || ')', '، ')
      into v_late_n, v_late
      from (select * from late limit 8) x;
    select count(*) into v_late_n
      from public.instant_attendance_penalties p
     where p.work_date = v_today
       and p.status in ('pending_payment', 'doubled', 'suspended')
       and p.employee_id in (
         select mr.employee_id from public.manager_relations mr
          where mr.manager_employee_id = v_mgr.id and mr.relation_type = 'primary'
            and mr.effective_from <= v_today
            and (mr.effective_to is null or mr.effective_to >= v_today));

    select count(*) into v_unpaid
      from public.instant_attendance_penalties p
     where p.work_date < v_today
       and p.status in ('doubled', 'suspended')
       and p.employee_id in (
         select mr.employee_id from public.manager_relations mr
          where mr.manager_employee_id = v_mgr.id and mr.relation_type = 'primary'
            and mr.effective_from <= v_today
            and (mr.effective_to is null or mr.effective_to >= v_today));

    with team as (
      select mr.employee_id
        from public.manager_relations mr
       where mr.manager_employee_id = v_mgr.id
         and mr.relation_type = 'primary'
         and mr.effective_from <= v_today
         and (mr.effective_to is null or mr.effective_to >= v_today)
    ),
    miss as (
      select e.full_name_ar as name, r.created_at,
             coalesce(nullif(trim(r.payload->'startLocation'->>'address'), ''),
                      nullif(trim(r.payload->>'location'), ''), 'دون وجهة') as place,
             r.created_at > public.employee_lateness_deadline(r.employee_id, v_today) as late
        from public.requests r
        join team t on t.employee_id = r.employee_id
        join public.employees e on e.id = r.employee_id
       where r.request_type = 'mission'
         and r.status not in ('rejected', 'cancelled', 'returned', 'expired')
         and (r.created_at at time zone 'Africa/Cairo')::date = v_today
       order by r.created_at
    )
    select count(*),
           string_agg(name || ' ' || to_char(created_at at time zone 'Africa/Cairo', 'FMHH12:MI')
                      || case when (created_at at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end
                      || case when late then ' (بعد موعد الدوام)' else '' end
                      || ' — ' || left(place, 40), '، ')
      into v_miss_n, v_miss
      from (select * from miss limit 8) x;

    if coalesce(v_late_n, 0) = 0 and coalesce(v_miss_n, 0) = 0 and coalesce(v_unpaid, 0) = 0 then
      continue;
    end if;

    v_body := concat_ws(E'\n',
      case when v_late_n > 0 then 'المتأخرون اليوم (' || v_late_n || '): ' || v_late end,
      case when v_miss_n > 0 then 'مأموريات اليوم (' || v_miss_n || '): ' || v_miss end,
      case when v_unpaid > 0 then 'غرامات سابقة لم تُسدَّد بعد: ' || v_unpaid end);

    perform public.notify_employee(
      v_mgr.id,
      'ملخص فريقك اليوم',
      v_body,
      'attendance', 'normal', 'instant_penalty', null,
      jsonb_build_object('kind', 'manager_daily_digest', 'day', v_today::text,
                         'lateCount', coalesce(v_late_n, 0), 'missionCount', coalesce(v_miss_n, 0),
                         'unpaidCount', coalesce(v_unpaid, 0),
                         'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.send_manager_daily_digest(boolean) is
  '0658: ملخص يومي واحد للمدير: متأخرو فريقه اليوم، مأمورياتهم (الوقت والمكان)، والغرامات غير المسددة.';
revoke all on function public.send_manager_daily_digest(boolean) from public, anon, authenticated;

-- ─── 6) الفحص الصحي اليومي ─────────────────────────────────────────────────
create table if not exists public.system_health_runs (
  id       uuid primary key default gen_random_uuid(),
  ran_at   timestamptz not null default now(),
  ok       boolean not null,
  checks   integer not null default 0,
  failures jsonb not null default '[]'::jsonb
);
alter table public.system_health_runs enable row level security;
revoke all on table public.system_health_runs from public, anon, authenticated;
comment on table public.system_health_runs is '0658: نتائج الفحص الصحي اليومي (القراءة عبر get_system_health للإدارة).';

create or replace function public.run_system_health_check(p_notify boolean default true, p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now      timestamp := now() at time zone 'Africa/Cairo';
  v_fail     jsonb := '[]'::jsonb;
  v_checks   integer := 0;
  v_rec      record;
  v_step     text;
  v_emp      uuid;
  v_emp_user uuid;
  v_mgr_user uuid;
  v_req      public.requests;
  v_json     jsonb;
  v_lines    text;
  v_admin    record;
begin
  if auth.uid() is not null and not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  -- جدول مزدوج (4 و5 UTC): يعمل في السابعة صباحًا بتوقيت القاهرة مرة واحدة يوميًا
  if not p_force then
    if extract(hour from v_now) <> 7 then
      return jsonb_build_object('skipped', true);
    end if;
    if exists (select 1 from public.system_health_runs
                where (ran_at at time zone 'Africa/Cairo')::date = v_now::date) then
      return jsonb_build_object('skipped', true, 'reason', 'already_ran_today');
    end if;
  end if;

  -- 1) وظائف قاعدة البيانات: أخطاء أعمدة/جداول/دوال مفقودة تظهر فقط عند التنفيذ
  v_checks := v_checks + 1;
  for v_rec in
    select p.proname, min(c.message) as message
      from pg_proc p
      join pg_language l on l.oid = p.prolang and l.lanname = 'plpgsql'
      cross join lateral extensions.plpgsql_check_function_tb(
        p.oid::regprocedure, fatal_errors => false, other_warnings => false,
        extra_warnings => false, performance_warnings => false) c
     where p.pronamespace = 'public'::regnamespace
       and p.prorettype <> 'trigger'::regtype
       and c.level = 'error'
     group by p.proname
  loop
    v_fail := v_fail || jsonb_build_object('check', 'code', 'item', v_rec.proname,
                                           'detail', left(v_rec.message, 160));
  end loop;

  -- 2) مهام دورية فشلت خلال 24 ساعة
  v_checks := v_checks + 1;
  for v_rec in
    select j.jobname, count(*) as n, max(left(d.return_message, 140)) as msg
      from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid
     where d.start_time > now() - interval '24 hours'
       and d.status = 'failed'
     group by j.jobname
  loop
    v_fail := v_fail || jsonb_build_object('check', 'cron', 'item', v_rec.jobname,
                                           'detail', v_rec.n || ' × ' || coalesce(v_rec.msg, ''));
  end loop;

  -- 3) مهام حرجة لم تنجح خلال نافذتها
  v_checks := v_checks + 1;
  for v_rec in
    select x.job
      from (values
        ('hr_auto_generate_instant_penalties', interval '30 hours'),
        ('hr_request_sla', interval '2 hours'),
        ('hr_notification_dispatch', interval '1 hour'),
        ('association_projects_stalled_alert', interval '50 hours'),
        ('association_project_step_deadlines', interval '50 hours')
      ) as x(job, win)
     where not exists (
       select 1 from cron.job_run_details d
         join cron.job j on j.jobid = d.jobid
        where j.jobname = x.job
          and d.status = 'succeeded'
          and d.start_time > now() - x.win)
  loop
    v_fail := v_fail || jsonb_build_object('check', 'cron_stale', 'item', v_rec.job, 'detail', '');
  end loop;

  -- 4) حماية الإصلاحات الحرجة من الاستبدال بنسخ قديمة
  v_checks := v_checks + 1;
  for v_rec in
    select x.fn, x.label
      from (values
        ('get_request_inbox', '(v.status = ''pending'') desc', 'ترتيب صندوق الطلبات'),
        ('resubmit_my_request', '''submit'', v_from_status', 'إعادة رفع الطلب'),
        ('is_employee_exempt_from_instant_penalty', 'employee_lateness_deadline', 'قاعدة تأخير المأموريات'),
        ('start_my_mission', 'attendance_policy_late_minutes', 'تأخير بدء المأمورية'),
        ('get_mobile_request_detail', '''insights''', 'سياق قرار المعتمِد'),
        ('process_request_sla', 'employee_on_leave', 'تصعيد غياب المدير'),
        ('_notify_instant_penalty_stakeholders', 'v_digest', 'ملخص غرامات الفريق')
      ) as x(fn, marker, label)
     where not exists (
       select 1 from pg_proc p
        where p.pronamespace = 'public'::regnamespace
          and p.proname = x.fn
          and strpos(p.prosrc, x.marker) > 0)
  loop
    v_fail := v_fail || jsonb_build_object('check', 'regression', 'item', v_rec.fn, 'detail', v_rec.label);
  end loop;

  -- 5) تجربة فعلية تُلغى بالكامل: تقديم مأمورية، صندوق المدير، التفاصيل، الاعتماد،
  --    ثم كرون الغرامات.
  v_checks := v_checks + 1;
  begin
    v_step := 'اختيار موظف للتجربة';
    select e.id, e.user_id, m.user_id
      into v_emp, v_emp_user, v_mgr_user
      from public.employees e
      join public.manager_relations mr
        on mr.employee_id = e.id and mr.relation_type = 'primary'
       and mr.effective_from <= current_date
       and (mr.effective_to is null or mr.effective_to >= current_date)
      join public.employees m on m.id = mr.manager_employee_id
     where e.is_active and not e.is_deleted and e.user_id is not null
       and m.is_active and not m.is_deleted and m.user_id is not null
       and m.id <> e.id
       and not public.is_clinic_team_member(e.id)
     order by e.created_at
     limit 1;
    if v_emp is null then
      raise exception 'لا يوجد موظف صالح للتجربة';
    end if;

    v_step := 'تقديم طلب';
    perform set_config('request.jwt.claim.sub', v_emp_user::text, true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_emp_user, 'role', 'authenticated')::text, true);
    v_req := public.submit_my_request('mission', 'فحص صحة النظام الآلي',
      'تجربة آلية يومية — تُلغى ولا تُحفظ', jsonb_build_object('location', 'فحص صحة النظام'),
      gen_random_uuid());
    if v_req.id is null then
      raise exception 'لم يُنشأ الطلب';
    end if;

    v_step := 'صندوق طلبات المدير';
    perform set_config('request.jwt.claim.sub', v_mgr_user::text, true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mgr_user, 'role', 'authenticated')::text, true);
    v_json := public.get_request_inbox(50);
    if not exists (select 1 from jsonb_array_elements(v_json) x where x->>'id' = v_req.id::text) then
      raise exception 'الطلب الجديد لا يظهر في صندوق المدير';
    end if;

    v_step := 'تفاصيل الطلب';
    v_json := public.get_mobile_request_detail(v_req.id);
    if not coalesce((v_json->>'canDecide')::boolean, false) then
      raise exception 'المدير لا يملك قرار طلب فريقه';
    end if;

    v_step := 'اعتماد الطلب';
    perform public.decide_request(v_req.id, 'approve', 'فحص آلي');
    if (select status from public.requests where id = v_req.id) <> 'approved' then
      raise exception 'لم يُعتمد الطلب';
    end if;

    v_step := 'حساب الغرامات';
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    perform public.auto_generate_instant_penalties();

    raise exception using errcode = 'P0001', message = 'HEALTH_SMOKE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'HEALTH_SMOKE_ROLLBACK' then
      v_fail := v_fail || jsonb_build_object('check', 'smoke', 'item', v_step, 'detail', left(sqlerrm, 160));
    end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  -- 6) تنبيهات النظام المفتوحة الحرجة
  v_checks := v_checks + 1;
  for v_rec in
    select alert_key, title from public.system_alerts
     where status = 'open' and severity in ('P0', 'P1')
  loop
    v_fail := v_fail || jsonb_build_object('check', 'alert', 'item', v_rec.alert_key, 'detail', v_rec.title);
  end loop;

  insert into public.system_health_runs(ok, checks, failures)
  values (jsonb_array_length(v_fail) = 0, v_checks, v_fail);

  if jsonb_array_length(v_fail) > 0 and p_notify then
    select string_agg(
             case f->>'check'
               when 'code' then '• وظيفة معطلة في قاعدة البيانات: ' || (f->>'item')
               when 'cron' then '• مهمة دورية فشلت: ' || (f->>'item') || ' (' || split_part(f->>'detail', ' ', 1) || ' مرة)'
               when 'cron_stale' then '• مهمة دورية متوقفة: ' || (f->>'item')
               when 'regression' then '• إصلاح سابق استُبدل بنسخة قديمة: ' || (f->>'detail')
               when 'smoke' then '• تعذّر تنفيذ عملية أساسية: ' || (f->>'item')
               else '• تنبيه نظام مفتوح: ' || coalesce(f->>'detail', f->>'item')
             end, E'\n')
      into v_lines
      from (select f from jsonb_array_elements(v_fail) f limit 12) s;

    for v_admin in
      select distinct e.id
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        join public.employees e on e.user_id = ur.user_id
       where r.slug = 'admin'
         and (ur.effective_from is null or ur.effective_from <= now())
         and (ur.effective_to is null or ur.effective_to > now())
         and e.is_active and not e.is_deleted
    loop
      perform public.notify_employee(
        v_admin.id,
        '⚠️ الفحص الصحي اليومي: يوجد ' || jsonb_array_length(v_fail) || ' خلل',
        v_lines,
        'system', 'urgent', null, null,
        jsonb_build_object('kind', 'system_health_alert', 'failures', jsonb_array_length(v_fail)));
    end loop;
  end if;

  return jsonb_build_object('ok', jsonb_array_length(v_fail) = 0, 'checks', v_checks, 'failures', v_fail);
end;
$$;
comment on function public.run_system_health_check(boolean, boolean) is
  '0658: فحص صحي يومي (7 ص القاهرة): وظائف القاعدة، المهام الدورية، علامات الإصلاحات، تجربة فعلية تُلغى، وتنبيه مدير النظام.';
revoke all on function public.run_system_health_check(boolean, boolean) from public, anon, authenticated;

create or replace function public.get_system_health(p_limit integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'runs', coalesce((
      select jsonb_agg(jsonb_build_object('ranAt', h.ran_at, 'ok', h.ok, 'checks', h.checks, 'failures', h.failures)
                       order by h.ran_at desc)
        from (select * from public.system_health_runs order by ran_at desc
              limit greatest(1, least(coalesce(p_limit, 14), 90))) h), '[]'::jsonb),
    'openAlerts', coalesce((
      select jsonb_agg(jsonb_build_object('key', a.alert_key, 'severity', a.severity, 'title', a.title,
                                          'lastSeenAt', a.last_seen_at, 'occurrences', a.occurrences)
                       order by a.last_seen_at desc)
        from public.system_alerts a where a.status = 'open'), '[]'::jsonb));
end;
$$;
comment on function public.get_system_health(integer) is '0658: نتائج الفحص الصحي والتنبيهات المفتوحة — لمدير النظام.';
revoke all on function public.get_system_health(integer) from public, anon;
grant execute on function public.get_system_health(integer) to authenticated;

-- ─── 7) الدوال المعاد تعريفها من أجسامها الحية ─────────────────────────────
CREATE OR REPLACE FUNCTION public.process_request_sla(p_limit integer DEFAULT 200)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_target   uuid;
  v_role     text;
  v_today    date := (now() at time zone 'Africa/Cairo')::date;
  v_absent   boolean;
  v_due      boolean;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      rs.assignee_employee_id,
      rs.escalation_deadline,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and (
        (rs.status in ('active', 'escalated')
         and rs.escalation_deadline is not null
         and rs.escalation_deadline < now())
        -- 0658: المدير المباشر في إجازة اليوم — لا ينتظر الطلب انقضاء مهلته
        or (rs.status = 'active' and rs.step_order = 1
            and public.employee_on_leave(coalesce(rs.assignee_employee_id, r.manager_employee_id), v_today))
      )
    order by rs.escalation_deadline nulls first
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    v_due := v_row.escalation_deadline is not null and v_row.escalation_deadline < now();
    v_absent := not v_due and v_row.step_order = 1 and v_row.step_status = 'active';

    -- ── ★ استثناء طاقم العيادات: يبقى كل شيء بالعيادات حصراً لدى مصطفى أحمد ★ ──
    -- لا يتم رفع الأمر لمدير التشغيل (أبو عمار) بعد ساعتين كما في باقي السيستم
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then
      -- 0658: الغياب وحده لا يرسل تذكيرات العيادات (كل 10 دقائق) — المهلة فقط
      if not v_due then
        continue;
      end if;

      -- إرسال تذكير دوري لمدير العيادات مصطفى أحمد فقط، وإعادة جدولة المهلة 24 ساعة
      if v_row.manager_employee_id is not null then
        perform public.notify_employee(
          v_row.manager_employee_id,
          'تذكير: طلب من طاقم العيادات بانتظار قرارك',
          coalesce(v_row.title, '') || ' — يحتاج قرارك كمدير مباشر.',
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'clinic_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours',
            updated_at = now()
      where id = v_row.step_id;

      continue;
    end if;

    -- ── الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد ──
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير). المدير المباشر لم يبتّ والطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── الخطوة 1 (المدير المباشر العام): تصعيد إلى الخطوة 2 (أبو عمار) ──
    -- 0658: الخطوة المصعَّدة سابقًا لا تُصعَّد ثانية (كانت تُعاد كل 24 ساعة فتكرر
    -- سطر 'escalate' والإشعارات وتعيد ضبط مهلة الخطوة 2) — تذكيرها من فرع الخطوة 2.
    if v_row.step_status = 'escalated' then
      update public.request_steps
        set escalation_deadline = null, updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = null,
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        case when v_absent then 'تصعيد تلقائي — المدير المباشر في إجازة اليوم'
             else 'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)' end,
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role,
                           'reason', case when v_absent then 'manager_on_leave' else 'timeout' end)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      if v_next.status is distinct from 'active' then
        perform public.notify_executive_fullscreen(
          'تصعيد طلب — للمتابعة',
          coalesce(v_row.title, ''),
          'request',
          'request', v_row.request_id,
          '/requests/' || v_row.request_id,
          jsonb_build_object(
            'escalation', 'executive_notify',
            'tier', v_next.step_order
          )
        );
      end if;
    else
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;
exception
  when others then
    insert into public.cron_health_log(job_name, rows_affected, status, detail)
    values ('process_request_sla', 0, 'error', sqlerrm);
    raise;
end;
$function$;

CREATE OR REPLACE FUNCTION public._notify_instant_penalty_stakeholders(p_employee_id uuid, p_title text, p_body text, p_entity_type text, p_entity_id uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_mgr_id uuid;
  v_emp_name text;
  v_mgr_title text;
  v_mgr_body text;
  v_is_suspension boolean;
  v_digest boolean;
begin
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id;

  v_is_suspension := (p_entity_type = 'instant_penalty_suspended' or p_title like '%إيقاف%');
  -- 0658: تسجيل/تصعيد غرامة التأخير يصل المدير في «ملخص فريقك اليوم» مرة واحدة
  -- (send_manager_daily_digest) بدل إشعار لكل موظف ولكل شريحة.
  v_digest := not v_is_suspension
              and (p_title like '⚠️ تسجيل غرامة%' or p_title like '⚠️ تصعيد غرامة%');

  -- 1) إشعار الموظف نفسه بالصيغة المباشرة
  perform public.notify_employee(
    p_employee_id,
    p_title,
    p_body,
    'system',
    'urgent',
    p_entity_type,
    p_entity_id,
    p_metadata
  );

  -- 2) إشعار المدير المباشر بصيغة واضحة تحدد اسم الموظف (لا صيغة "تم إيقافك أنت")
  select mr.manager_employee_id into v_mgr_id
    from public.manager_relations mr
    join public.employees m on m.id = mr.manager_employee_id
   where mr.employee_id = p_employee_id
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
     and m.is_active = true
   order by case mr.relation_type
              when 'primary' then 1 when 'functional' then 2 else 3
            end
   limit 1;

  if not v_digest and v_mgr_id is not null and v_mgr_id <> p_employee_id then
    v_mgr_title := case
      when v_is_suspension then '🚫 إشعار إيقاف موظف عن العمل'
      else '⚠️ غرامة تأخير لموظف بفريقك'
    end;

    v_mgr_body := case
      when v_is_suspension then
        'إشعار إداري: تم إيقاف ' || coalesce(v_emp_name, 'موظف') || ' عن العمل مؤقتاً لعدم سداد غرامة التأخير (500 ج.م).'
      else
        'إشعار لفريقك: تم تسجيل/تحديث غرامة تأخير على ' || coalesce(v_emp_name, 'موظف') || '.'
    end;

    perform public.notify_employee(
      v_mgr_id,
      v_mgr_title,
      v_mgr_body,
      'attendance',
      'high',
      p_entity_type,
      p_entity_id,
      jsonb_build_object(
        'employeeId', p_employee_id::text,
        'employeeName', v_emp_name,
        'penaltyId', p_entity_id::text
      ) || coalesce(p_metadata, '{}'::jsonb)
    );
  end if;

  -- 3) إشعار مسؤولي الموارد البشرية فقط عند الإيقاف عن العمل الحرج (وليس في كل تأخير روتيني)
  if v_is_suspension then
    perform public.notify_employees_with_permission(
      'payroll.run.manage',
      '🚫 إشعار إيقاف موظف عن العمل',
      'تم إيقاف الموظف ' || coalesce(v_emp_name, 'موظف') || ' وغلق حسابه لعدم سداد الغرامة لليوم الثالث.',
      'system',
      'urgent',
      p_entity_type,
      p_entity_id,
      p_metadata,
      p_employee_id
    );
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_mobile_request_detail(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
  v_current_step       uuid;
  v_steps              jsonb;
  v_history            jsonb;
  v_attachments        jsonb;
  v_context            jsonb;
  v_decided_by         text;
  v_cancelled_by       text;
  v_decision_actor     text;
  v_decision_mode      text;
  v_decision_on_behalf boolean;
  v_execution          jsonb;
  v_insights           jsonb;
  v_start              date;
  v_end                date;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  -- coalesce: حساب بلا موظف كان يمرّ لأن not (null or false) = null
  if not coalesce(
       v_request.employee_id = v_me
    or v_request.manager_employee_id = v_me
    or exists (
         select 1 from public.manager_relations mr
          where mr.employee_id = v_request.employee_id
            and mr.manager_employee_id = v_me
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date))
    or exists (
         select 1 from public.request_steps s
          where s.request_id = v_request.id and s.assignee_employee_id = v_me)
    or v_full
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'operations-manager-1']
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve'),
    false
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  select d.name into v_department from public.departments d where d.id = v_employee.department_id;
  select jt.name into v_job_title from public.job_titles jt where jt.id = v_employee.job_title_id;

  v_flags := public.request_decision_flags(v_request, v_me, v_full, v_roles);

  if v_request.status = 'pending' then
    select s.id into v_current_step
      from public.request_steps s
     where s.request_id = v_request.id
       and s.status in ('active', 'escalated', 'pending')
     order by (s.status = 'active') desc, s.step_order
     limit 1;
  end if;

  -- المراحل: الفاعل والتعليق للخطوة التي بُتّ فيها فقط (السحب يضع فاعلًا على
  -- الخطوات المتخطاة)، والإرجاع يُسجَّل rejected على الخطوة فيُميَّز هنا.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'order', s.step_order,
           'name', s.name_ar,
           'roleSlug', s.assignee_role_slug,
           'status', s.status,
           'decision', case
               when s.status = 'approved' then 'approved'
               when s.status = 'rejected' and v_request.status = 'returned' then 'returned'
               when s.status = 'rejected' then 'rejected'
             end,
           'comment', case when s.status in ('approved', 'rejected') then nullif(trim(s.comment), '') end,
           'decidedAt', case when s.status in ('approved', 'rejected') then s.acted_at end,
           'actorName', case when s.status in ('approved', 'rejected') then actor.full_name_ar end,
           'dueAt', s.due_at,
           'escalatedAt', s.escalated_at,
           'isCurrent', s.id is not distinct from v_current_step
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = p_request_id;

  -- سجل الإجراءات: التصعيد الآلي يتكرر كل دورة مهلة — يُعرض أوله في كل دورة
  -- رفع مع عدد التكرار، ونصوصه الآلية (بعضها تالف تاريخيًا) لا تُرجَع.
  with base as (
    select a.*,
           sum((a.action = 'submit')::int) over (
             order by a.created_at, a.id
             rows between unbounded preceding and current row) as cycle_no
      from public.request_actions a
     where a.request_id = p_request_id
       and a.action in ('submit', 'approve', 'reject', 'return', 'request_changes',
                        'cancel', 'withdraw', 'escalate', 'expire', 'reassign')
  ),
  ranked as (
    select b.*,
           row_number() over w as rn,
           count(*) over w as cnt
      from base b
    window w as (
      partition by b.cycle_no, b.action,
                   coalesce(b.metadata->>'targetRole', b.metadata->>'escalatedToRole', '')
      order by b.created_at, b.id
      rows between unbounded preceding and unbounded following)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'action', x.action,
           'at', x.created_at,
           'actorName', case when x.action in ('escalate', 'expire') then null else actor.full_name_ar end,
           'comment', case when x.action in ('approve', 'reject', 'return', 'request_changes',
                                             'cancel', 'withdraw', 'reassign')
                           then nullif(trim(x.comment), '') end,
           'stepOrder', st.step_order,
           'stepName', st.name_ar,
           'stepRole', st.assignee_role_slug,
           'targetRole', coalesce(x.metadata->>'targetRole', x.metadata->>'escalatedToRole'),
           'repeat', case when x.action = 'escalate' then x.cnt end,
           'isResubmit', x.action = 'submit' and x.from_status in ('rejected', 'returned')
         ) order by x.created_at, x.id), '[]'::jsonb)
    into v_history
    from ranked x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.action <> 'escalate' or x.rn = 1;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
         ) order by a.created_at), '[]'::jsonb)
    into v_attachments
    from public.attachments a
   where a.entity_type = 'request' and a.entity_id = p_request_id;

  -- البديل والتعارضات (حُذفت منذ 0628). للدالة تحقق وصول أضيق؛ عند رفضها لا
  -- يسقط عرض الطلب كله.
  begin
    v_context := public.get_request_decision_context(p_request_id);
  exception when others then
    v_context := null;
  end;

  select e.full_name_ar into v_decided_by from public.employees e where e.id = v_request.decided_by;
  select e.full_name_ar into v_cancelled_by from public.employees e where e.id = v_request.cancelled_by;

  select e.full_name_ar, a.metadata->>'decisionMode',
         coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions a
    left join public.employees e on e.id = a.actor_employee_id
   where a.request_id = p_request_id and a.action in ('approve', 'reject', 'return')
   order by a.created_at desc
   limit 1;

  -- سياق القرار لغير صاحب الطلب (اجتاز شرط الوصول أعلاه: مدير/موارد بشرية/
  -- تشغيل/إدارة). التواريخ تُحلَّل بحماية CASE حتى لا يُسقط تاريخ تالف العرض.
  if not coalesce(v_request.employee_id = v_me, false) then
    v_start := case
      when coalesce(v_request.payload->>'startDate', v_request.payload->>'permitDate') ~ '^\d{4}-\d{2}-\d{2}$'
      then coalesce(v_request.payload->>'startDate', v_request.payload->>'permitDate')::date
    end;
    v_end := case
      when v_request.payload->>'endDate' ~ '^\d{4}-\d{2}-\d{2}$'
      then (v_request.payload->>'endDate')::date
      else v_start
    end;

    v_insights := jsonb_build_object(
      'leaveBalance', case when v_request.request_type = 'leave' then (
        select jsonb_build_object(
                 'name', lt.name_ar,
                 'available', coalesce(a.opening_units + a.accrued_units + a.adjusted_units
                                       + a.carryover_units - a.consumed_units - a.reserved_units, 0),
                 'reserved', coalesce(a.reserved_units, 0),
                 'consumed', coalesce(a.consumed_units, 0))
          from public.leave_types lt
          left join public.leave_balance_accounts a
            on a.leave_type_id = lt.id
           and a.employee_id = v_request.employee_id
           and a.balance_year = extract(year from coalesce(v_start,
                 (now() at time zone 'Africa/Cairo')::date))::int
         where lt.code = v_request.payload->>'leaveType'
         limit 1
      ) end,
      'month', (
        select jsonb_build_object(
                 'total', count(*),
                 'missions', count(*) filter (where r.request_type in ('mission', 'convoy', 'fundraising')),
                 'leaves', count(*) filter (where r.request_type = 'leave'),
                 'permits', count(*) filter (where r.request_type in ('late_permit', 'early_permit')),
                 'rejected', count(*) filter (where r.status in ('rejected', 'returned')),
                 'pending', count(*) filter (where r.status = 'pending'))
          from public.requests r
         where r.employee_id = v_request.employee_id
           and r.id <> v_request.id
           and r.status <> 'cancelled'
           and r.created_at >= (date_trunc('month', now() at time zone 'Africa/Cairo')
                                at time zone 'Africa/Cairo')
      ),
      'teamSize', (
        select count(*) from public.employees e
         where v_employee.department_id is not null
           and e.department_id = v_employee.department_id
           and e.id <> v_request.employee_id
           and e.is_active and not e.is_deleted
      ),
      'teamAway', case when v_start is not null and v_employee.department_id is not null then (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'name', t.full_name_ar, 'type', t.request_type, 'status', t.status)
                 order by t.status, t.full_name_ar), '[]'::jsonb)
          from (
            select distinct on (e.id) e.full_name_ar, r.request_type, r.status
              from public.requests r
              join public.employees e on e.id = r.employee_id
             where e.department_id = v_employee.department_id
               and e.id <> v_request.employee_id
               and e.is_active and not e.is_deleted
               and r.status in ('approved', 'pending')
               and r.request_type in ('leave', 'mission', 'convoy', 'fundraising')
               and (case when r.payload->>'startDate' ~ '^\d{4}-\d{2}-\d{2}$'
                         then (r.payload->>'startDate')::date end) <= v_end
               and (case when coalesce(r.payload->>'endDate', r.payload->>'startDate') ~ '^\d{4}-\d{2}-\d{2}$'
                         then coalesce(r.payload->>'endDate', r.payload->>'startDate')::date end) >= v_start
             order by e.id, (r.status = 'approved') desc
          ) t
      ) end
    );
  end if;

  if v_request.request_type in ('mission', 'convoy', 'fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome,
             me.auto_closed_at as "autoClosedAt"
        from public.mission_executions me
       where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'employeePhotoUrl', v_employee.photo_url,
    'employeeDepartment', v_department,
    'employeeJobTitle', v_job_title,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'decidedAt', v_request.decided_at,
    'decidedByName', v_decided_by,
    'cancelledAt', v_request.cancelled_at,
    'cancelReason', v_request.cancel_reason,
    'cancelledByName', v_cancelled_by,
    'isMine', coalesce(v_request.employee_id = v_me, false),
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'canCancel', v_request.status = 'pending' and coalesce(v_request.employee_id = v_me, false),
    -- عقد 0452: المالك على طلب مرفوض/مُعاد من الأنواع القابلة لإعادة الرفع
    'canResubmit', v_request.status in ('rejected', 'returned')
                   and coalesce(v_request.employee_id = v_me, false)
                   and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                  'late_permit', 'early_permit'),
    'steps', v_steps,
    'history', v_history,
    'attachments', v_attachments,
    'decisionContext', v_context,
    'insights', v_insights,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$function$;


-- ─── 8) تنظيف سطور التصعيد المكررة (يبقى الأول لكل دورة رفع ولكل جهة) ──────────
with base as (
  select a.id, a.request_id, a.action, a.metadata, a.created_at,
         sum((a.action = 'submit')::int) over (
           partition by a.request_id order by a.created_at, a.id
           rows between unbounded preceding and current row) as cycle_no
    from public.request_actions a
   where a.request_id in (select request_id from public.request_actions where action = 'escalate')
),
ranked as (
  select id,
         row_number() over (
           partition by request_id, cycle_no,
                        coalesce(metadata->>'targetRole', metadata->>'escalatedToRole', '')
           order by created_at, id) as rn
    from base
   where action = 'escalate'
)
delete from public.request_actions a
 using ranked k
 where a.id = k.id and k.rn > 1;

-- الخطوات المصعَّدة سابقًا لا تُعاد معالجتها
update public.request_steps
   set escalation_deadline = null, updated_at = now()
 where status = 'escalated' and escalation_deadline is not null;

-- ─── 9) تسوية المتراكم: المأموريات الجارية من أيام سابقة والطلبات المنسية ────
select public.auto_close_stale_missions(false);
select public.expire_stale_requests(false);

-- ─── 11) سد ثغرة: دوال الإشعار الداخلية كانت قابلة للاستدعاء من أي مستخدم مسجَّل ───
-- (أي موظف كان يستطيع إرسال إشعار بأي عنوان ومحتوى لأي موظف أو إشعار ملء الشاشة
--  للمدير التنفيذي). لا تستدعيها أي واجهة ولا دالة بصلاحية المستدعي — كلها من دوال
--  SECURITY DEFINER المملوكة لـ postgres، فلا يتأثر أي مسار.
revoke all on function public.notify_employee(uuid, text, text, text, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.notify_user(uuid, text, text, text, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.notify_employees_with_permission(text, text, text, text, text, text, uuid, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.notify_executive_fullscreen(text, text, text, text, uuid, text, jsonb, boolean) from public, anon, authenticated;
revoke all on function public._notify_instant_penalty_stakeholders(uuid, text, text, text, uuid, jsonb) from public, anon, authenticated;

-- ─── 10) المواعيد (UTC مزدوجة؛ كل دالة تتحقق من ساعة القاهرة وتمنع التكرار) ──
select cron.schedule('hr_system_health_check', '0 4,5 * * *', $c$select public.run_system_health_check()$c$);
select cron.schedule('hr_manager_daily_digest', '30 9,10 * * *', $c$select public.send_manager_daily_digest()$c$);
select cron.schedule('hr_mission_report_reminder', '0 14,15 * * *', $c$select public.remind_open_missions()$c$);
select cron.schedule('hr_mission_auto_close', '30 22 * * *', $c$select public.auto_close_stale_missions()$c$);
select cron.schedule('hr_expire_stale_requests', '15 2 * * *', $c$select public.expire_stale_requests()$c$);
