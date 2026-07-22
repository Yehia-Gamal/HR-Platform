begin;

-- ============================================================================
-- Migration 0057: توقيت العمل الرسمي + تذكيرات البصمة.
--   • بذرة الوردية الرسمية (10ص–6م) طوال السنة + ورديتَي رمضان (9ص–3ع، 10ص–4ع)
--     تُبدَّل يدويًا: يكفي تفعيل الوردية الرمضانية وإيقاف العادية خلال رمضان.
--   • تبسيط تعريف الوردية: overload لـ save_shift_admin يولّد الكود تلقائيًا من
--     الاسم/التوقيت، فلا حاجة لإدخال كود يدوي من اللوحة.
--   • generate_punch_reminders(): تنشئ إشعارات تذكير بالبصمة (قبل بداية الدوام،
--     تنبيه تأخير بعد البداية، قبل نهاية الدوام) لكل موظف نشط عبر خطّ الإشعارات
--     القائم (notifications → notification_jobs → notification-dispatcher).
--   • جدولة cron كل 5 دقائق عبر pg_net (بنفس أسلوب 0049/0051، آمنة محليًا).
-- كل الكتابة خادمية ومدقّقة. الهجرة idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) بذرة الورديات: الرسمية + رمضان. الكود ثابت للتمييز، الاسم = توقيت العمل.
--    الوردية الرسمية نشطة افتراضيًا؛ ورديتا رمضان غير نشطتين حتى تُفعَّلا يدويًا.
-- ----------------------------------------------------------------------------
insert into public.shifts (code, name, name_en, start_time, end_time, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
values
  ('OFFICIAL',      'الدوام الرسمي (10 ص – 6 م)',        'Official (10:00–18:00)', '10:00', '18:00', 0, 15, 0, true),
  ('RAMADAN_9_3',   'دوام رمضان (9 ص – 3 ع)',           'Ramadan (09:00–15:00)',  '09:00', '15:00', 0, 15, 0, false),
  ('RAMADAN_10_4',  'دوام رمضان (10 ص – 4 ع)',          'Ramadan (10:00–16:00)',  '10:00', '16:00', 0, 15, 0, false)
on conflict (code) do update set
  name = excluded.name,
  name_en = excluded.name_en,
  start_time = excluded.start_time,
  end_time = excluded.end_time,
  grace_in_minutes = excluded.grace_in_minutes,
  updated_at = now();

-- ----------------------------------------------------------------------------
-- 2) overload مبسّط لـ save_shift_admin بلا كود: يولّد الكود تلقائيًا.
--    يبقى الـ overload الأصلي (بالكود) كما هو للتوافق العكسي.
-- ----------------------------------------------------------------------------
create or replace function public.save_shift_admin(
  p_shift_id uuid,
  p_name text,
  p_start time,
  p_end time,
  p_break_minutes integer default 0,
  p_grace_in integer default 15,
  p_grace_out integer default 0,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  if p_shift_id is null then
    -- كود مشتق فريد (لا يظهر في اللوحة، للتمييز الداخلي فقط).
    v_code := 'SH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  else
    select code into v_code from public.shifts where id = p_shift_id;
    v_code := coalesce(v_code, 'SH-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)));
  end if;

  -- نعيد الاستخدام للـ overload الأصلي (يفحص الصلاحية ويكتب سجل التدقيق).
  return public.save_shift_admin(
    p_shift_id, v_code, p_name, p_start, p_end,
    greatest(coalesce(p_break_minutes, 0), 0),
    greatest(coalesce(p_grace_in, 0), 0),
    greatest(coalesce(p_grace_out, 0), 0),
    p_active
  );
end;
$$;

revoke execute on function public.save_shift_admin(uuid, text, time, time, integer, integer, integer, boolean) from public;
grant execute on function public.save_shift_admin(uuid, text, time, time, integer, integer, integer, boolean) to authenticated;

comment on function public.save_shift_admin(uuid, text, time, time, integer, integer, integer, boolean) is
  'حفظ وردية بلا كود يدوي (يُولَّد تلقائيًا). الاسم يمثّل توقيت العمل. يعيد استخدام النسخة ذات الكود للفحص والتدقيق.';

-- ----------------------------------------------------------------------------
-- 3) generate_punch_reminders(): إنشاء تذكيرات البصمة.
--    تُنفَّذ خادميًا (SECURITY DEFINER)، وتُستدعى إما بواسطة service_role/cron
--    أو مالك صلاحية comms.notification.send. تحسب التوقيت بتوقيت القاهرة.
--    ثلاثة أنواع لكل موظف نشط في يوم عمل (أحد–خميس افتراضيًا):
--      • before_in : خلال [بداية-15د، بداية) ولم يسجّل حضورًا بعد.
--      • late_in   : بعد (بداية + سماحية) ولم يسجّل حضورًا.
--      • before_out: خلال [نهاية-15د، نهاية) وسجّل حضورًا ولم ينصرف.
--    منع التكرار: لا يُنشأ إشعار لنفس (المستخدم/اليوم/النوع) أكثر من مرة.
-- ----------------------------------------------------------------------------
create or replace function public.generate_punch_reminders(p_lead_minutes integer default 15)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created integer := 0;
  v_now_cairo timestamptz := now();
  v_local timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_local::date;
  v_now_time time := v_local::time;
  v_dow integer := extract(isodow from v_local)::integer;  -- 1=إثنين .. 7=أحد
  v_lead integer := greatest(coalesce(p_lead_minutes, 15), 1);
  v_shift record;
  v_emp record;
  v_daily public.attendance_daily;
  v_kind text;
  v_title text;
  v_body text;
begin
  -- مسموح فقط لعملية خادمية (service_role) أو مالك صلاحية إرسال الإشعارات.
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة والسبت عطلة (يوم العمل: الأحد=7 والإثنين..الخميس=1..4).
  if v_dow in (5, 6) then
    return 0;
  end if;

  -- الوردية الرسمية الحالية: النشطة الأحدث تحديثًا (تبديل رمضان يدوي).
  select * into v_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  if v_shift.id is null then
    return 0;
  end if;

  for v_emp in
    select e.id as employee_id, e.user_id
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
  loop
    -- سجل اليوم (إن وُجد) للموظف: مصدر الحقيقة لبصمة الدخول/الخروج.
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id and work_date = v_today;

    v_kind := null;

    -- قبل نهاية الدوام: بصم دخولًا ولم ينصرف.
    if v_now_time >= (v_shift.end_time - make_interval(mins => v_lead))
       and v_now_time < v_shift.end_time
       and v_daily.first_check_in is not null
       and v_daily.last_check_out is null then
      v_kind := 'before_out';
      v_title := 'تذكير بالانصراف';
      v_body := 'اقترب موعد نهاية الدوام (' || to_char(v_shift.end_time, 'HH12:MI AM') || '). لا تنسَ تسجيل بصمة الانصراف.';

    -- تنبيه تأخير: تجاوز البداية + السماحية ولم يبصم دخولًا.
    elsif v_now_time >= (v_shift.start_time + make_interval(mins => coalesce(v_shift.grace_in_minutes, 0)))
       and v_now_time < v_shift.end_time
       and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'late_in';
      v_title := 'أنت متأخر عن الدوام';
      v_body := 'بدأ الدوام الساعة ' || to_char(v_shift.start_time, 'HH12:MI AM') || ' ولم تُسجّل بصمة الحضور بعد. يُرجى تسجيلها في أقرب وقت.';

    -- قبل بداية الدوام: خلال فترة اللِّيد ولم يبصم دخولًا.
    elsif v_now_time >= (v_shift.start_time - make_interval(mins => v_lead))
       and v_now_time < v_shift.start_time
       and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'before_in';
      v_title := 'اقترب موعد الدوام';
      v_body := 'يبدأ الدوام الساعة ' || to_char(v_shift.start_time, 'HH12:MI AM') || '. جهّز نفسك لتسجيل بصمة الحضور.';
    end if;

    if v_kind is null then
      continue;
    end if;

    -- منع التكرار: نفس (المستخدم/اليوم/النوع) مرة واحدة.
    if exists (
      select 1 from public.notifications n
      where n.recipient_user_id = v_emp.user_id
        and n.entity_type = 'punch_reminder'
        and n.metadata->>'kind' = v_kind
        and (n.metadata->>'workDate') = v_today::text
    ) then
      continue;
    end if;

    insert into public.notifications (
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, metadata
    ) values (
      v_emp.user_id, v_emp.employee_id, v_title, v_body,
      'system',
      case when v_kind = 'late_in' then 'high' else 'normal' end,
      '/attendance', 'punch_reminder', v_shift.id,
      jsonb_build_object('kind', v_kind, 'workDate', v_today::text, 'shiftId', v_shift.id)
    );
    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$$;

revoke all on function public.generate_punch_reminders(integer) from public, anon, authenticated;
grant execute on function public.generate_punch_reminders(integer) to service_role;

comment on function public.generate_punch_reminders(integer) is
  'تُنشئ تذكيرات بصمة الحضور/الانصراف لكل موظف نشط حسب الوردية الرسمية النشطة (توقيت القاهرة). ثلاثة أنواع بلا تكرار: before_in / late_in / before_out. تُستدعى عبر cron أو مالك صلاحية إرسال الإشعارات.';

-- ----------------------------------------------------------------------------
-- 4) جدولة cron كل 5 دقائق عبر pg_net (SQL مباشر داخل قاعدة البيانات — لا HTTP).
--    generate_punch_reminders دالة DB، فلا حاجة لاستدعاء Edge؛ نجدولها مباشرة.
--    آمنة محليًا: إن غاب pg_cron تُتجاوز دون كسر الترحيل.
-- ----------------------------------------------------------------------------
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل؛ تُخطّى جدولة تذكيرات البصمة. شغّل generate_punch_reminders() عبر مشغّل خارجي كل 5 دقائق.';
    return;
  end if;

  perform cron.unschedule(jobname)
  from cron.job
  where jobname = 'hr_punch_reminders';

  perform cron.schedule(
    'hr_punch_reminders', '*/5 * * * *',
    $job$ select public.generate_punch_reminders(15) $job$
  );

  raise notice 'تمت جدولة تذكيرات البصمة (hr_punch_reminders) كل 5 دقائق.';
end
$cron$;

commit;
