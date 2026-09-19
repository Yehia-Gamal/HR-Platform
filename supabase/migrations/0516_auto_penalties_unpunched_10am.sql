-- =====================================================================
-- 0516: تفعيل وضبط نظام الخصومات التلقائية لمن لم يبصم حتى 10:00 ص
-- =====================================================================
-- 1) ضبط أيام العمل الرسمية: السبت إلى الخميس، ويوم الجمعة فقط راحة أسبوعية (isodow = 5).
-- 2) التفعيل التلقائي الفوري لمن لم يسجل بصمة بحلول 10:00 ص (بعد انتهاء فترة السماح 10:15 ص).
-- 3) التحديث والتصعيد المتزامن مع تزايد وقت التأخير (20 ج.م -> 50 ج.م -> 150 ج.م).
-- 4) المزامنة اللحظية فور تسجيل الموظف للبصمة عبر trigger على attendance_daily.
-- 5) ضبط جدولة الكرون لتعمل كل 10 دقائق من 09:00 ص حتى 07:00 م بتوقيت القاهرة.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تحديث دالة توليد/مزامنة الغرامة الفورية مع دعم سبب الخصم والتصعيد اللحظي
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح)
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- التحقق من الموظف
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and is_deleted = false and is_active = true;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود أو غير نشط' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- حساب المبلغ بحسب الشرائح
  v_amount := public.calc_instant_penalty_amount(p_late_minutes);

  -- إذا كان التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15 = 0 ج.م)
  if v_amount <= 0.00 then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isGracePeriod', true,
      'amount', 0,
      'message', 'التأخير ضمن فترة السماح الرسمية (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة'
    );
  end if;

  v_default_notes := coalesce(p_notes, 'تأخير عن موعد العمل الرسمي (10:00 ص)');

  -- محاولة الإدخال
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, notes, created_by
  ) values (
    p_employee_id, p_work_date, p_late_minutes,
    v_amount, v_amount, 'EGP',
    'pending_payment', 'initial', v_default_notes, auth.uid()
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- إذا كانت الغرامة مسجلة مسبقاً لهذا اليوم:
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    -- إذا كانت لا تزال قيد السداد وكان المبلغ الجديد أكبر (تصعيد شريحة تأخير):
    if v_row.status = 'pending_payment' and v_amount > v_row.current_amount then
      update public.instant_attendance_penalties
         set late_minutes = p_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      -- إشعار بتصعيد الشريحة
      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        v_emp_name || ': تزايد التأخير إلى ' || p_late_minutes || ' دقيقة — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'workDate', p_work_date::text,
          'lateMinutes', p_late_minutes,
          'amount', v_amount,
          'channel', 'instant_penalty'
        )
      );
    elsif v_row.status = 'pending_payment' and p_notes is not null then
      -- تحديث الملاحظات ودقائق التأخير الفعلية عند البصمة
      update public.instant_attendance_penalties
         set late_minutes = p_late_minutes,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'status', v_row.status,
      'currentAmount', v_row.current_amount,
      'notes', v_row.notes
    );
  end if;

  -- سجل التدقيق للغرامة الجديدة
  perform public.log_audit_event(
    'instant_penalty.issued', 'financial', 'warning',
    'instant_attendance_penalties', v_row.id,
    'غرامة تأخير فورية: ' || v_emp_name || ' (' || v_default_notes || ') — ' || v_amount || ' ج.م',
    null,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'lateMinutes', p_late_minutes,
      'amount', v_amount,
      'notes', v_default_notes
    )
  );

  -- إشعار المعنيين
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ غرامة تأخير فورية',
    v_emp_name || ': ' || v_default_notes || ' — غرامة فورية ' || v_amount || ' ج.م مطلوب سدادها اليوم.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'workDate', p_work_date::text,
      'lateMinutes', p_late_minutes,
      'amount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'employeeId', v_row.employee_id,
    'workDate', v_row.work_date,
    'lateMinutes', v_row.late_minutes,
    'originalAmount', v_row.original_amount,
    'currentAmount', v_row.current_amount,
    'status', v_row.status,
    'alreadyExists', false
  );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 2) ترقية الدالة التلقائية للتحقق من الحضور وتطبيق الخصم لمن لم يبصم
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_now_cairo::date;
  v_time_cairo time := v_now_cairo::time;
  v_isodow integer := extract(isodow from v_now_cairo)::integer;
  v_elapsed_mins integer;
  v_processed integer := 0;
  v_emp record;
  v_att record;
  v_penalty_minutes integer;
  v_notes text;
begin
  -- الكرون مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1. استثناء عطلة نهاية الأسبوع الرسمية: الجمعة فقط (5)
  if v_isodow = 5 then
    return 0;
  end if;

  -- 2. استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- 3. قبل انتهاء فترة السماح (10:15 ص): لا توجد غرامات
  if v_time_cairo <= '10:15:00'::time then
    return 0;
  end if;

  -- حساب الدقائق المنقضية منذ بداية الدوام الرسمي (10:00 ص)
  v_elapsed_mins := floor(extract(epoch from (v_time_cairo - '10:00:00'::time)) / 60)::integer;
  if v_elapsed_mins <= 15 then
    return 0;
  end if;

  -- 4. فحص جميع الموظفين النشطين المطالبين بالدوام اليوم
  for v_emp in
    select e.id as employee_id, e.full_name_ar
      from public.employees e
     where e.is_active = true
       and e.is_deleted = false
       -- استثناء من لديه إجازة معتمدة اليوم
       and not exists (
         select 1
           from public.leave_requests lr
           join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id
            and r.status in ('approved', 'completed')
            and v_today between lr.start_date and lr.end_date
       )
       -- استثناء من لديه طلب مأمورية / راحة / إجازة معتمد اليوم
       and not exists (
         select 1
           from public.requests r
          where r.employee_id = e.id
            and r.status in ('approved', 'completed')
            and r.request_type in ('leave', 'mission', 'remote_work', 'compensation')
            and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                            and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date)
       )
  loop
    -- فحص سجل الحضور اليومي للموظف
    select ad.first_check_in, ad.late_minutes, ad.status
      into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today;

    if v_att.first_check_in is not null then
      -- الحالة أ: الموظف بصم حضوراً بالفعل:
      -- نتحقق هل بصم متأخراً بعد فترة السماح (> 15 دقيقة)؟
      if coalesce(v_att.late_minutes, 0) > 15 then
        v_penalty_minutes := v_att.late_minutes;
        v_notes := 'تأخير حضور فعلي: ' || v_penalty_minutes || ' دقيقة (سجل بصمته ' || to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM') || ')';
        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
    else
      -- الحالة ب: الموظف لم يبصم حتى الآن والساعة تجاوزت 10:15 ص:
      -- يُسجل عليه الخصم تلقائياً بحسب الوقت المنقضي منذ 10:00 ص
      v_penalty_minutes := v_elapsed_mins;
      v_notes := 'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')';
      perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
      v_processed := v_processed + 1;
    end if;
  end loop;

  return v_processed;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.auto_generate_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل الفحص التلقائي لغرامات التأخير وعدم البصمة', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today, 'timeCairo', v_time_cairo)
    );
    return 0;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Trigger متزامن على attendance_daily للتطبيق اللحظي فور تسجيل البصمة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.trg_fn_instant_penalty_on_punch()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- إذا كانت البصمة متأخرة بأكثر من 15 دقيقة
  if NEW.first_check_in is not null and coalesce(NEW.late_minutes, 0) > 15 then
    perform public.generate_instant_penalty(
      NEW.employee_id,
      NEW.work_date,
      NEW.late_minutes,
      'تأخير حضور فعلي: ' || NEW.late_minutes || ' دقيقة'
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_instant_penalty_on_punch on public.attendance_daily;
create trigger trg_instant_penalty_on_punch
after insert or update of first_check_in, late_minutes
on public.attendance_daily
for each row
execute function public.trg_fn_instant_penalty_on_punch();

-- ─────────────────────────────────────────────────────────────────────
-- 4) دالة استدعاء يدوي إداري فوري مع تقرير استجابة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.trigger_check_instant_penalties_now()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  v_count := public.auto_generate_instant_penalties();

  return jsonb_build_object(
    'success', true,
    'processedCount', v_count,
    'serverTimeCairo', to_char(v_now_cairo, 'YYYY-MM-DD HH12:MI:SS AM'),
    'message', 'تم فحص الحضور وتطبيق/تحديث الغرامات التلقائية بنجاح. إجمالي المعاملات المعالجة: ' || v_count
  );
end;
$$;

grant execute on function public.trigger_check_instant_penalties_now() to authenticated;
grant execute on function public.generate_instant_penalty(uuid, date, integer, text) to authenticated, service_role;
grant execute on function public.auto_generate_instant_penalties() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) ضبط وإعادة تفعيل جدولة الكرون في pg_cron
-- ─────────────────────────────────────────────────────────────────────

do $cron$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron غير مفعّل.';
    return;
  end if;

  -- 1) التصعيد اليومي: 05:00 UTC ≈ 08:00 ص بتوقيت القاهرة
  perform cron.unschedule(jobname)
    from cron.job
   where jobname = 'hr_auto_escalate_instant_penalties';

  perform cron.schedule(
    'hr_auto_escalate_instant_penalties', '0 5 * * *',
    $job$ select public.auto_escalate_instant_penalties() $job$
  );

  -- 2) الإنشاء والتطبيق التلقائي: كل 10 دقائق خلال فترة العمل
  -- 06:00 إلى 16:00 UTC ≈ 09:00 ص إلى 07:00 م بتوقيت القاهرة
  perform cron.unschedule(jobname)
    from cron.job
   where jobname = 'hr_auto_generate_instant_penalties';

  perform cron.schedule(
    'hr_auto_generate_instant_penalties', '*/10 6-16 * * *',
    $job$ select public.auto_generate_instant_penalties() $job$
  );

  raise notice 'تم تحديث وتفعيل جدولة الكرون: فحص وتطبيق الغرامات كل 10 دقائق من 09:00 ص حتى 07:00 م بتوقيت القاهرة.';
end
$cron$;

notify pgrst, 'reload schema';

commit;
