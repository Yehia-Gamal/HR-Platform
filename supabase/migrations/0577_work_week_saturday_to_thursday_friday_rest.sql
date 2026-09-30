/* 0577_work_week_saturday_to_thursday_friday_rest.sql
   ─────────────────────────────────────────────────────────────────────────────
   توحيد دورة أسبوع العمل: السبت إلى الخميس (والراحة الأسبوعية: الجمعة فقط)
   ─────────────────────────────────────────────────────────────────────────────
   بناءً على التوجيه الإداري الصارم:
   1. أسبوع العمل يبدأ رسمياً يوم السبت (Saturday) وينتهي يوم الخميس (Thursday).
   2. يوم الراحة الأسبوعية الوحيد هو يوم الجمعة (Friday / isodow = 5).
   3. يوم السبت هو يوم عمل رسمي نشط لا يُستثنى من التنبيهات أو الغرامات.
   4. ضبط احتساب التصعيد (اليوم الثاني: مضاعفة لـ 500 ج.م، اليوم الثالث: وقف العمل + 500 ج.م)
      ليعتمد على أيام العمل الفعلية المنقضية (مع استبعاد الجمعة والعطلات الرسمية).
   5. تحديث دالة تنبيه التأخير auto_notify_late_attendance لتعمل السبت وتستثني الجمعة فقط.
   6. تحديث لوحة التحليلات get_analytics_dashboard لتبدأ أسبوعها من السبت وتستبعد الجمعة فقط.
   7. تحديث إعدادات penalty_settings ليكون weekends = ["Friday"]، وضبط سقف الـ 120 دقيقة.
   8. حماية الحساب الإداري ليحيى جمال السبع مستمرة ونافذة قطعياً.
*/

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث إعدادات الغرامات penalty_settings (الجمعة فقط عطلة، وتأكيد شرائح التأخير)
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.penalty_settings (setting_key, setting_value, description)
values
  ('weekends', to_jsonb(array['Friday']), 'أيام العطلة الأسبوعية الرسمية (الجمعة فقط؛ بداية الأسبوع السبت ونهايته الخميس)'),
  ('tiers', to_jsonb('[{"min_late":16,"max_late":30,"amount":20,"label":"تأخير حتى 30 دقيقة (20 ج.م)"},{"min_late":31,"max_late":119,"amount":50,"label":"تأخير ساعة وحتى أقل من ساعتين (50 ج.م)"},{"min_late":120,"max_late":120,"amount":150,"label":"ساعتان كحد أقصى (150 ج.م)"}]'::jsonb), 'شرائح الغرامات حسب دقائق التأخير (محصورة عند ساعتين 120 دقيقة بحد أقصى)')
on conflict (setting_key) do update
set setting_value = excluded.setting_value,
    description = excluded.description,
    updated_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث دالة التنبيه بالتأخر auto_notify_late_attendance
--    السبت يوم عمل رسمي، ويوم الجمعة (isodow = 5) هو يوم العطلة الوحيد
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.auto_notify_late_attendance()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=إثنين..5=جمعة..6=سبت..7=أحد
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- قفل استشاري لمنع سباق التشغيلات المتزامنة
  perform pg_advisory_xact_lock(hashtext('auto_notify_late_attendance'));

  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  -- عطلة نهاية الأسبوع: الجمعة فقط (isodow = 5). السبت هو أول أيام أسبوع العمل.
  if v_isodow = 5 then
    return 0;
  end if;

  -- العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  for v_rec in
    select
      ad.employee_id,
      least(120, coalesce(ad.late_minutes, 0)) as late_minutes,
      e.full_name_ar      as employee_name,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e   on e.id = ad.employee_id
    -- المدير المباشر الوحيد لكل موظف
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
      and coalesce(ad.late_minutes, 0) > 15 -- تجاوز فترة السماح (15 دقيقة)
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
      coalesce(v_rec.employee_name, 'الموظف') || ' تأخر عن موعد الحضور الرسمي بمقدار ' ||
        case when v_rec.late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_rec.late_minutes::text || ' دقيقة' end,
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
    perform public.log_audit_event(
      'attendance.late_alert_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل تنبيه التأخر التلقائي', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$function$;

revoke all on function public.auto_notify_late_attendance() from public, anon;
grant execute on function public.auto_notify_late_attendance() to authenticated, service_role;

comment on function public.auto_notify_late_attendance() is
  'تنبيه المديرين بتأخر الموظفين (السبت إلى الخميس، الجمعة راحة، محصور عند ساعتين).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث لوحة التحليلات get_analytics_dashboard
--    الأسبوع يبدأ من السبت، والراحة الأسبوعية المستبعدة هي الجمعة فقط
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.get_analytics_dashboard(
  p_months_back integer default 6
)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  v_from_month   date;
  v_today        date;
  v_week_start   date;
  v_requests     jsonb;
  v_departments  jsonb;
  v_attendance   jsonb;
  v_kpi          jsonb;
begin
  if auth.uid() is null then
    raise exception 'ERR_UNAUTHENTICATED' using errcode = '28000';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.people.read')
    or public.has_permission('reports.hr.read')
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  v_today      := (now() at time zone 'Africa/Cairo')::date;
  v_from_month := date_trunc('month', v_today - (p_months_back || ' months')::interval)::date;

  -- بداية أسبوع العمل من السبت:
  -- في extract(dow): 0=أحد, 1=إثنين, 2=ثلاثاء, 3=أربعاء, 4=خميس, 5=جمعة, 6=سبت
  -- الإزاحة إلى السبت = (dow + 1) % 7
  v_week_start := v_today - ((extract(dow from v_today)::integer + 1) % 7);

  -- ── 1. حركة الطلبات الشهرية ──────────────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'month',        to_char(s.month, 'Mon YYYY'),
        'monthKey',     to_char(s.month, 'YYYY-MM'),
        'approved',     s.approved,
        'rejected',     s.rejected,
        'pending',      s.pending,
        'cancelled',    s.cancelled
      )
      order by s.month
    ),
    '[]'::jsonb
  )
  into v_requests
  from (
    select
      date_trunc('month', month)::date as month,
      sum(approved)   as approved,
      sum(rejected)   as rejected,
      sum(pending)    as pending,
      sum(cancelled)  as cancelled
    from public.mv_monthly_request_stats
    where month >= v_from_month
    group by date_trunc('month', month)
  ) s;

  -- ── 2. توزيع الموظفين حسب الأقسام ───────────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',  h.department_name,
        'value', h.active_count
      )
      order by h.active_count desc
    ),
    '[]'::jsonb
  )
  into v_departments
  from public.mv_department_headcount h
  where h.active_count > 0;

  -- ── 3. اتجاه الحضور (أيام العمل في الأسبوع الحالي من السبت حتى اليوم) ──
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name',    to_char(day_date, 'Dy'),
        'date',    day_date,
        'present', coalesce(present_count, 0),
        'late',    coalesce(late_count,    0),
        'absent',  coalesce(absent_count,  0)
      )
      order by day_date
    ),
    '[]'::jsonb
  )
  into v_attendance
  from (
    select
      d.day_date,
      count(*) filter (
        where ad.status in ('present', 'present_late')
          and ad.status not in ('weekend', 'holiday')
      ) as present_count,
      count(*) filter (
        where ad.status = 'present_late'
          and ad.status not in ('weekend', 'holiday')
      ) as late_count,
      count(*) filter (
        where ad.status in ('absent', 'absent_excused')
          and ad.status not in ('weekend', 'holiday')
      ) as absent_count
    from generate_series(v_week_start, v_today, '1 day'::interval) as d(day_date)
    left join public.attendance_daily ad on ad.work_date = d.day_date::date
    where extract(isodow from d.day_date) <> 5   -- الجمعة فقط راحة أسبوعية
    group by d.day_date
  ) w;

  -- ── 4. متوسطات KPI (آخر 6 دورات منتهية) ─────────────────────────────
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'subject',    k.criterion_name,
        'actual',     round(k.avg_score::numeric, 1),
        'target',     k.max_score
      )
      order by k.criterion_name
    ),
    '[]'::jsonb
  )
  into v_kpi
  from (
    select
      kc.name_ar                                    as criterion_name,
      avg(ks.score / nullif(kc.max_score, 0) * 100) as avg_score,
      100                                           as max_score
    from public.kpi_cycles c
    join public.kpi_evaluations ke  on ke.cycle_id = c.id
    join public.kpi_scores ks       on ks.evaluation_id = ke.id
    join public.kpi_criteria kc     on kc.id = ks.criterion_id
    where c.status in ('closed', 'locked')
      and c.period_month >= (v_today - '6 months'::interval)::date
      and ke.final_score is not null
      and ks.reviewer_stage in ('executive', 'manager')
    group by kc.name_ar
    having count(*) >= 3
  ) k;

  return jsonb_build_object(
    'monthlyRequests',       coalesce(v_requests,    '[]'::jsonb),
    'departmentDistribution',coalesce(v_departments, '[]'::jsonb),
    'attendanceTrend',       coalesce(v_attendance,  '[]'::jsonb),
    'kpiScores',             coalesce(v_kpi,         '[]'::jsonb),
    'generatedAt',           now() at time zone 'Africa/Cairo'
  );
end;
$$;

revoke all on function public.get_analytics_dashboard(integer) from public, anon;
grant execute on function public.get_analytics_dashboard(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة التصعيد التلقائي auto_escalate_instant_penalties
--    بناءً على أيام العمل الفعلية المنقضية (الجمعة راحة رسمية ولا تصعيد فيها):
--    - اليوم الثاني من العمل (غداً): مضاعفة لـ 500 ج.م
--    - اليوم الثالث من العمل: وقف العمل وغلق الحساب + 500 ج.م
--    - حماية حساب يحيى جمال السبع مستمرة ونافذة قطعياً من أي وقف أو تعليق
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_now_cairo::date;
  v_isodow integer := extract(isodow from v_now_cairo)::integer;
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- يوم الجمعة (5) راحة أسبوعية رسمية — لا تصعيد في أيام الراحة
  if v_isodow = 5 then
    return 0;
  end if;

  -- ═══ المرحلة 1: عدم السداد في نفس اليوم -> مضاعفة الغرامة إلى 500 ج.م تدفع في اليوم الثاني ═══
  -- تنطبق بعد انقضاء يوم عمل واحد على الأقل (اليوم الثاني / غداً)
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and (
         select count(*)::integer
           from generate_series(p.work_date + 1, v_today, '1 day'::interval) d
          where extract(isodow from d)::integer <> 5
            and not exists (
              select 1 from public.public_holidays h
               where h.holiday_date = d::date
            )
       ) >= 1
  loop
    -- فحص الإعفاء المعتمد قبل المضاعفة
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص المضاعفة: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'warning',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م لعدم السداد في نفس اليوم',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount, 'currentAmount', 500.00)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم تسدد غرامة التأخير في نفس اليوم. تمت مضاعفة الغرامة إلى 500 ج.م تدفع اليوم (ثاني يوم عمل). في حال عدم السداد لليوم الثالث، سيتم غلق الحساب ووقفك عن العمل تلقائياً.',
      'instant_penalty_doubled',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'originalAmount', v_rec.original_amount,
        'newAmount', 500,
        'channel', 'instant_penalty_doubled',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  -- ═══ المرحلة 2: عدم السداد حتى اليوم الثالث من العمل -> غلق الحساب ووقف الموظف عن العمل مع غرامة 500 ج.م ═══
  -- تنطبق بعد انقضاء يومي عمل على الأقل (اليوم الثالث من العمل)
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status in ('doubled', 'pending_payment')
       and (
         select count(*)::integer
           from generate_series(p.work_date + 1, v_today, '1 day'::interval) d
          where extract(isodow from d)::integer <> 5
            and not exists (
              select 1 from public.public_holidays h
               where h.holiday_date = d::date
            )
       ) >= 2
  loop
    -- فحص الإعفاء المعتمد قبل التعليق
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;

      -- رفع أي تعليق إن وجد
      update public.employees set status = 'active', is_active = true where id = v_rec.employee_id;
      update public.profiles set status = 'active' where employee_id = v_rec.employee_id;
      continue;
    end if;

    -- استثناء الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع) من وقف العمل وغلق الحساب قطعياً
    -- الغرامة تظل قائمة ومضاعفة بـ 500 ج.م ولكن الحساب يظل نشطاً ومحمياً
    if exists (
      select 1 from public.employees e
      where e.id = v_rec.employee_id
        and (
          e.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
          or e.phone_e164 in ('+201154869616', '01154869616')
          or e.employee_code in ('+201154869616', '01154869616')
          or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
          or e.full_name_ar ilike '%يحيى%جمال%'
        )
    ) then
      continue;
    end if;

    -- 1) تحديث سجل الغرامة إلى معلق (500 ج.م)
    update public.instant_attendance_penalties
       set status = 'suspended',
           escalation_level = 'suspended',
           current_amount = 500.00,
           suspended_at = now(),
           updated_at = now()
     where id = v_rec.id;

    -- 2) غلق الحساب ووقف الموظف عن العمل (المرحلة الثالثة)
    update public.employees
       set status = 'suspended',
           is_active = false,
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'security', 'critical',
      'instant_attendance_penalties', v_rec.id,
      'وقف العمل وغلق الحساب: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة التأخير (500 ج.م) بحلول اليوم الثالث من العمل',
      null,
      jsonb_build_object(
        'employeeId', v_rec.employee_id,
        'penaltyId', v_rec.id,
        'amount', 500.00,
        'action', 'work_suspension_and_account_lock'
      )
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 تم وقفك عن العمل وغلق حسابك',
      coalesce(v_emp_name, 'الموظف') || ' تم وقفك عن العمل وغلق حسابك على النظام فوراً لعدم سداد غرامة التأخير (500 ج.م) بحلول اليوم الثالث من العمل. يرجى التوجه إلى إدارة الموارد البشرية والمالية لتسوية الوضع.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', 500,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
end;
$function$;

revoke all on function public.auto_escalate_instant_penalties() from public, anon;
grant execute on function public.auto_escalate_instant_penalties() to authenticated, service_role;

comment on function public.auto_escalate_instant_penalties() is
  'تصعيد غرامات التأخير غير المسددة حسب أيام العمل (السبت-الخميس): اليوم الثاني 500 ج، اليوم الثالث وقف العمل وغلق الحساب.';
