-- =====================================================================
-- 0405: تنبيه FCM تلقائي مجدول عند تأخر الموظف (09:30 توقيت القاهرة)
-- =====================================================================
-- يكمل ترحيل 0389 (الذي يُطلق حدث-اللحظة CHECK_IN). هنا مسار مجدول مستقل
-- يفحص attendance_daily.status='late' ليوم العمل الجاري الساعة 09:30 توقيت
-- القاهرة كل أيام العمل (الأحد..الخميس)، ويُبلغ المدير المباشر مرة واحدة فقط
-- لكل (موظف/يوم) عبر جدول notifications (الذي يُشغّل notification_jobs تلقائياً).
--
--   * دالة SECURITY DEFINER (كرون نظامي — لا يوجد current_employee_id).
--   * search_path = public, pg_temp.
--   * صلاحية الاستدعاء اليدوي: full-access أو attendance.record.manage
--     (الكرون يُسمح له ضمنياً عبر auth.uid() is null).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (1) auto_notify_late_attendance: النواة المشتركة بين الكرون والاستدعاء اليدوي.
--     تُرجع عدد الإشعارات المُدرجة. آمنة للتكرار: تتجاوز من أُبلغ عنهم مسبقاً.
-- ---------------------------------------------------------------------
create or replace function public.auto_notify_late_attendance()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=إثنين..7=أحد
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  -- عطلة نهاية الأسبوع: الجمعة(5) والسبت(6). لا شيء لنفعله.
  if v_isodow in (5, 6) then
    return 0;
  end if;

  for v_rec in
    select
      ad.employee_id,
      ad.late_minutes,
      e.full_name_ar      as employee_name,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e   on e.id = ad.employee_id
    -- المدير المباشر الوحيد لكل موظف: نفضّل 'primary' ثم أي علاقة فعّالة.
    left join lateral (
      select m.user_id as manager_user_id, m.id as manager_employee_id
      from public.manager_relations mr
      join public.employees m on m.id = mr.manager_employee_id
      where mr.employee_id = ad.employee_id
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
        and m.is_active = true
        and m.user_id is not null
      order by case mr.relation_type
                 when 'primary'    then 1
                 when 'functional' then 2
                 when 'dotted'     then 3
                 else 4
               end
      limit 1
    ) mgr on true
    where ad.work_date = v_today
      and ad.status    = 'late'
      and coalesce(ad.late_minutes, 0) > 0
      and e.is_active  = true
      and e.is_deleted = false
      and mgr.manager_user_id is not null
      and not exists (
        -- منع التكرار: إشعار سابق لنفس (المدير/الموظف/اليوم)
        select 1
        from public.notifications n
        where n.recipient_user_id = mgr.manager_user_id
          and n.entity_type = 'late_attendance_alert'
          and (n.metadata->>'employeeId') = ad.employee_id::text
          and (n.metadata->>'workDate')   = v_today::text
      )
    order by e.full_name_ar
  loop
    -- الـ trigger trg_notifications_queue_jobs يُضيف notification_jobs تلقائياً.
    insert into public.notifications (
      recipient_user_id,
      recipient_employee_id,
      title,
      body,
      category,
      priority,
      action_url,
      entity_type,
      entity_id,
      metadata
    ) values (
      v_rec.manager_user_id,
      v_rec.manager_employee_id,
      'تنبيه تأخر موظف',
      coalesce(v_rec.employee_name, 'الموظف') || ' تأخر عن مواجهة الوردية بمقدار ' ||
        v_rec.late_minutes::text || ' دقيقة',
      'system',
      'urgent',
      '/attendance',
      'late_attendance_alert',
      v_rec.employee_id,
      jsonb_build_object(
        'workDate',     v_today::text,
        'lateMinutes',  v_rec.late_minutes,
        'employeeId',   v_rec.employee_id::text,
        'managerEmployeeId', v_rec.manager_employee_id::text,
        'channel', 'late_attendance',
        'deepLink', 'ahlashabab://action/attendance?date=' || to_char(v_today, 'YYYY-MM-DD')
      )
    ) returning id into v_notif_id;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
exception
  when others then
    -- لا نعطّل الكرون؛ نسجّل الحادث ونُرجع 0.
    perform public.log_audit_event(
      'attendance.late_alert_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل تنبيه التأخر التلقائي', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$$;

revoke all on function public.auto_notify_late_attendance()
  from public, anon, authenticated;
grant execute on function public.auto_notify_late_attendance()
  to authenticated, service_role;

comment on function public.auto_notify_late_attendance() is
  'يُطلقها كرون 09:30 توقيت القاهرة كل أيام العمل: يُبلغ المدير المباشر عن كل موظف attendance_daily.status=late لليوم، مرة واحدة لكل (مدير/موظف/يوم).';

-- ---------------------------------------------------------------------
-- (2) check_late_attendance_now: غلاف للاستدعاء اليدوي (نفس المنطق).
--     مناسب للاختبار من قبل مالك صلاحية attendance.record.manage/full-access.
-- ---------------------------------------------------------------------
create or replace function public.check_late_attendance_now()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return public.auto_notify_late_attendance();
end;
$$;

revoke all on function public.check_late_attendance_now()
  from public, anon, authenticated;
grant execute on function public.check_late_attendance_now()
  to authenticated, service_role;

comment on function public.check_late_attendance_now() is
  'استدعاء يدوي لـ auto_notify_late_attendance (للاختبار/المراجعة الفورية).';

-- ---------------------------------------------------------------------
-- (3) جدولة الكرون: 09:30 توقيت القاهرة كل أيام العمل.
--    pg_cron يُجدول بتوقيت UTC. توقيت القاهرة = UTC+2 (شتاءً) أو UTC+3 (صيفاً)
--    لذا 09:30 القاهرة ≈ 06:30..07:30 UTC. نُجدول يومياً 06:30 UTC لضمان
--    التشغيل قبل/عند بداية النافذة، وتتولى الدالة فحص isodow not in (5,6)
--    فتتجاوز عطلة الجمعة/السبت دون إرسال. هذا يحمي من تقلّب توقيت الصيف/الشتاء.
--    آمن: إن غاب pg_cron تُتجاوز الجدولة دون كسر الترحيل.
-- ---------------------------------------------------------------------
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل؛ تُخطّى جدولة تنبيه التأخر. شغّل auto_notify_late_attendance() عبر مشغّل خارجي الساعة 09:30 توقيت القاهرة.';
    return;
  end if;

  perform cron.unschedule(jobname)
  from cron.job
  where jobname = 'hr_auto_late_attendance_alert';

  perform cron.schedule(
    'hr_auto_late_attendance_alert', '30 6 * * *',
    $job$ select public.auto_notify_late_attendance() $job$
  );

  raise notice 'تمت جدولة تنبيه التأخر التلقائي (hr_auto_late_attendance_alert) يومياً 06:30 UTC ≈ 09:30 القاهرة.';
end
$cron$;

notify pgrst, 'reload schema';

commit;
