-- =====================================================================
-- 0406: الملخص التنفيذي الأسبوعي للحضور (كرون أحد 08:00 توقيت القاهرة)
-- =====================================================================
-- يُكمل 0390 (الذي يُجدول تقريراً عبر جدول scheduled_reports) بمسار مستقل
-- مباشر: دالة SECURITY DEFINER تُحتسب إحصاءات آخر 7 أيام، وتُدرج إشعاراً
-- لكل مستخدم يملك صلاحية reports.attendance.read أو دور full-access،
-- وتُرجع JSONB بالملخص الكامل.
--
--   * دالة SECURITY DEFINER (كرون نظامي).
--   * search_path = public, pg_temp.
--   * جدولة pg_cron كل أحد 08:00 توقيت القاهرة.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (1) generate_weekly_executive_summary: الحساب + الإشعار + إرجاع JSONB.
--     تُحتسب الإحصاءات لأخر 7 أيام متتالية (today-7 .. today-1) من
--     attendance_daily للموظفين النشطين.
-- ---------------------------------------------------------------------
create or replace function public.generate_weekly_executive_summary()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_end        date      := (v_local::date) - 1;   -- أمس
  v_start      date      := v_end - 6;            -- آخر 7 أيام شاملة
  v_period_id  text      := to_char(v_start, 'YYYY-MM-DD') || '_' || to_char(v_end, 'YYYY-MM-DD');
  v_total_emp  integer;
  v_summary    jsonb;
  v_top_late   jsonb;
  v_absent_gt3 jsonb;
  v_body       text;
  v_notif_id   uuid;
  v_recipients bigint;
  v_sent       integer := 0;
  v_result     jsonb;
begin
  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('reports.attendance.read')) then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  -- إجمالي الموظفين النشطين (قاعدة المقام للنسب).
  select count(*) into v_total_emp
  from public.employees e
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active';

  -- الملخص: إجمالي سجلات/أيام + عدد لكل حالة.
  select jsonb_build_object(
    'startDate',     v_start,
    'endDate',       v_end,
    'periodId',      v_period_id,
    'activeEmployees', v_total_emp,
    'totalDayRecords', count(*),
    'present',       count(*) filter (where ad.status = 'present'),
    'late',           count(*) filter (where ad.status = 'late'),
    'absent',         count(*) filter (where ad.status = 'absent'),
    'onLeave',        count(*) filter (where ad.status = 'on_leave'),
    'holiday',        count(*) filter (where ad.status = 'holiday'),
    'weekend',        count(*) filter (where ad.status = 'weekend'),
    'partial',        count(*) filter (where ad.status = 'partial'),
    'totalLateMinutes',  coalesce(sum(ad.late_minutes), 0),
    'totalEarlyLeaveMinutes', coalesce(sum(ad.early_leave_minutes), 0),
    'totalOvertimeMinutes',  coalesce(sum(ad.overtime_minutes), 0)
  ) into v_summary
  from public.attendance_daily ad
  join public.employees e on e.id = ad.employee_id
  where ad.work_date between v_start and v_end
    and e.is_active = true
    and e.is_deleted = false;

  -- نسب معدّلة على عدد أيام العمل الفعلية (present+late+absent+partial)
  v_summary := v_summary || jsonb_build_object(
    'workdayRecords',
      coalesce((v_summary->>'present')::int,0)
      + coalesce((v_summary->>'late')::int,0)
      + coalesce((v_summary->>'absent')::int,0)
      + coalesce((v_summary->>'partial')::int,0),
    'presentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'present')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'lateRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'late')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'absentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'absent')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'onLeaveRate',
      case when coalesce(v_total_emp,0) * 7 = 0 then 0
           else round(100.0 * coalesce((v_summary->>'onLeave')::int,0)
             / (coalesce(v_total_emp,0) * 7), 2) end
  );

  -- أعلى 5 موظفين تكراراً في التأخير.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'lateDays',     t.late_days,
    'totalLateMinutes', t.total_late_minutes
  ) order by t.late_days desc, t.total_late_minutes desc), '[]'::jsonb) into v_top_late
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'late') as late_days,
      coalesce(sum(ad.late_minutes) filter (where ad.status = 'late'), 0) as total_late_minutes
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'late') > 0
    order by late_days desc, total_late_minutes desc
    limit 5
  ) t;

  -- موظفون تجاوزوا 3 أيام غياب في الأسبوع.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'absentDays',   t.absent_days
  ) order by t.absent_days desc, t.full_name_ar), '[]'::jsonb) into v_absent_gt3
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'absent') as absent_days
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'absent') > 3
    order by absent_days desc, full_name_ar
  ) t;

  -- النتيجة النهائية.
  v_result := jsonb_build_object(
    'generatedAt', now(),
    'summary',     v_summary,
    'topLateEmployees',     v_top_late,
    'absentGt3Employees',   v_absent_gt3
  );

  -- صياغة جسم الإشعار (عربي، مختصر).
  v_body := 'الملخص الأسبوعي للحضور (' || to_char(v_start, 'DD/MM/YYYY') || ' - '
             || to_char(v_end, 'DD/MM/YYYY') || '): '
             || 'حضور ' || coalesce((v_summary->>'present')::text,'0')
             || '، تأخر ' || coalesce((v_summary->>'late')::text,'0')
             || '، غياب ' || coalesce((v_summary->>'absent')::text,'0')
             || '، إجازة ' || coalesce((v_summary->>'onLeave')::text,'0')
             || '. نسبة التأخر ' || coalesce((v_summary->>'lateRate')::text,'0') || '%'
             || '، نسبة الغياب ' || coalesce((v_summary->>'absentRate')::text,'0') || '%.'
             || ' أعلى المتأخرين: ' || coalesce(
                (select string_agg(x->>'employeeName', '، ')
                 from jsonb_array_elements(v_top_late) as x),
                'لا يوجد')
             || '.';

  -- إدراج إشعار لكل مستخدم يملك reports.attendance.read أو دور full-access.
  -- نُحدّد المستخدمين عبر user_roles المرتبطة بـ role_permissions/permissions
  -- أو بـ roles.is_full_access=true. ونحلّ employee_id عبر profiles.
  with recipients as (
    -- full-access
    select distinct ur.user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where r.is_full_access = true
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
    union
    -- مالكو reports.attendance.read
    select distinct ur.user_id
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p        on p.id = rp.permission_id
    where p.code = 'reports.attendance.read'
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
  ),
  enriched as (
    select
      r.user_id,
      p.employee_id
    from recipients r
    left join public.profiles p on p.id = r.user_id
  )
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
  )
  select
    e.user_id,
    e.employee_id,
    'الملخص الأسبوعي للحضور',
    v_body,
    'system',
    'normal',
    '/reports/attendance',
    'weekly_executive_summary',
    null,
    jsonb_build_object(
      'periodId', v_period_id,
      'startDate', v_start,
      'endDate',   v_end,
      'summary',   v_summary,
      'topLateEmployees',   v_top_late,
      'absentGt3Employees', v_absent_gt3,
      'kind', 'weekly_executive_summary',
      'deepLink', 'ahlashabab://action/reports/attendance?start='
        || to_char(v_start,'YYYY-MM-DD') || '&end=' || to_char(v_end,'YYYY-MM-DD')
    )
  from enriched e
  where not exists (
    -- منع التكرار: إشعار سابق لنفس (المستخدم/الفترة)
    select 1
    from public.notifications n
    where n.recipient_user_id = e.user_id
      and n.entity_type = 'weekly_executive_summary'
      and (n.metadata->>'periodId') = v_period_id
  );

  get diagnostics v_recipients = row_count;
  v_sent := v_recipients::integer;

  perform public.log_audit_event(
    'reports.weekly_executive_summary_generated', 'operations', 'info',
    'attendance_daily', null, 'توليد الملخص التنفيذي الأسبوعي للحضور', null,
    jsonb_build_object(
      'periodId', v_period_id,
      'recipientsNotified', v_sent,
      'summary', v_summary
    )
  );

  return v_result || jsonb_build_object(
    'recipientsNotified', v_sent,
    'notificationBody', v_body
  );
exception
  when others then
    perform public.log_audit_event(
      'reports.weekly_executive_summary_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل توليد الملخص التنفيذي الأسبوعي', null,
      jsonb_build_object('error', sqlerrm, 'periodId', v_period_id)
    );
    return jsonb_build_object('error', sqlerrm, 'periodId', v_period_id);
end;
$$;

revoke all on function public.generate_weekly_executive_summary()
  from public, anon, authenticated;
grant execute on function public.generate_weekly_executive_summary()
  to authenticated, service_role;

comment on function public.generate_weekly_executive_summary() is
  'يُحتسب أسبوعياً (كرون أحد 08:00 القاهرة): إحصاءات حضور آخر 7 أيام + أعلى 5 متأخرين + موظفو >3 غياب، ويُشعر كل مالك reports.attendance.read/full-access، ويُرجع JSONB بالملخص.';

-- ---------------------------------------------------------------------
-- (2) جدولة الكرون: كل أحد 08:00 توقيت القاهرة.
--    08:00 Africa/Cairo ≈ 05:00 UTC (صيفاً) أو 06:00 UTC (شتاءً).
--    pg_cron لا يدعم توقيتاً ديناميكياً، لذا نُجدول أحد 05:00 UTC لضمان
--    التشغيل في نافذة 08:00 القاهرة عبر تغيّر التوقيت الصيفي/الشتوي.
--    (isodow: الأحد=7.) آمن: إن غاب pg_cron تُتجاوز الجدولة دون كسر الترحيل.
-- ---------------------------------------------------------------------
do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل؛ تُخطّى جدولة الملخص الأسبوعي. شغّل generate_weekly_executive_summary() عبر مشغّل خارجي كل أحد 08:00 توقيت القاهرة.';
    return;
  end if;

  perform cron.unschedule(jobname)
  from cron.job
  where jobname = 'hr_weekly_executive_summary';

  perform cron.schedule(
    'hr_weekly_executive_summary', '0 5 * * 0',
    $job$ select public.generate_weekly_executive_summary() $job$
  );

  raise notice 'تمت جدولة الملخص التنفيذي الأسبوعي (hr_weekly_executive_summary) كل أحد 05:00 UTC ≈ 08:00 القاهرة.';
end
$cron$;

notify pgrst, 'reload schema';

commit;
