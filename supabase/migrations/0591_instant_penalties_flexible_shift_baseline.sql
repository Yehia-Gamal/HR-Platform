-- =====================================================================
-- 0591: غرامات «لم يسجل بصمة الحضور بعد» على الورديات المرنة (0588)
--
-- 0588 جعل الدوام مرناً: الوردية تُختار بوقت الحضور (حتى 09:30 → 9–5،
-- حتى 10:30 → 10–6، بعدها → 11–7) فمن يحضر 10:45 أو 11:10 ليس متأخراً.
-- لكن مولّد الغرامات الدوري (كل 10 دقائق) بقي على الدوام الثابت 10:00:
--  • يغرّم كل من لم يبصم بعد 10:15 ويعدّ الدقائق من 10:00، فيصل 150 ج.م
--    (70 دقيقة) في 11:10 لموظف ما زال أمامه أن يحضر على وردية 11–7.
--  • وعند حضوره لا تنقص الغرامة (generate_instant_penalty يرفع فقط).
--  • ويشمل حسابات «مدعوّة» لم تُفعَّل بعد ولا تستطيع البصم أصلاً.
-- الإصلاح:
--  1) من لم يبصم يُحسب تأخيره من بداية ورديته المسندة إن وُجدت، وإلا من آخر
--     بداية وردية مرنة نشطة (11:00) بعد فترة سماحها — فالغرامة المؤقتة لا تتجاوز
--     أبداً ما سيستحقه فعلاً لو بصم الآن، ثم ترتفع عند بصمته إلى تأخيره الفعلي.
--  2) لا غرامة «عدم بصم» إلا لحساب نشط (status = active).
--  3) تصحيح غرامات اليوم المؤقتة المحسوبة من 10:00: تُخفَّض إلى المستحق وفق
--     الوردية المرنة (أو التأخير الفعلي لمن بصم)، وتُلغى إن لم يتجاوز السماح.
--     لا ترفع أي غرامة، ولا تمس المدفوع/المضاعف/المعلّق.
-- حالة التأخير الفعلي عند البصم (الحالة أ) كما هي: التأخير مخزَّن من سياسة 0588.
-- =====================================================================

begin;

CREATE OR REPLACE FUNCTION public.auto_generate_instant_penalties()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_exempt jsonb;
  v_pen record;
  v_flex_start time;
  v_flex_grace integer;
  v_start time;
  v_grace integer;
  v_start_label text;
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1. استثناء عطلة الجمعة
  if v_isodow = 5 then
    return 0;
  end if;

  -- 2. استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة لموظفين لديهم إذن أو مأمورية أو إجازة معتمدة لذلك اليوم
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
       and p.work_date >= v_today - 3
  loop
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_pen.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             updated_at = now()
       where id = v_pen.id;

      -- رفع التعليق إن لم تكن هناك غرامات مضاعفة أخرى غير معفى منها
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = v_pen.employee_id
           and status in ('doubled', 'suspended')
           and id != v_pen.id
      ) then
        update public.employees set is_active = true, status = 'active' where id = v_pen.employee_id;
        update public.profiles set status = 'active' where employee_id = v_pen.employee_id;
      end if;
    end if;
  end loop;

  -- 4. 0591: آخر بداية وردية مرنة نشطة (0588) — من لم يبصم بعد قد يحضر عليها بلا تأخير
  select s.start_time, coalesce(s.grace_in_minutes, 15)
    into v_flex_start, v_flex_grace
    from public.shifts s
   where s.is_active and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7')
   order by s.start_time desc
   limit 1;
  if v_flex_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_flex_start, v_flex_grace
      from public.shifts s
     where s.id = public.default_shift_id();
  end if;
  v_flex_start := coalesce(v_flex_start, '10:00'::time);
  v_flex_grace := coalesce(v_flex_grace, 15);

  -- 5. فحص الموظفين: يشمل جميع الموظفين النشطين، وكذلك من حضر اليوم وسجل بصمة متأخرة
  for v_emp in
    select e.id as employee_id, e.full_name_ar, e.is_active, e.status as emp_status
      from public.employees e
     where coalesce(e.is_deleted, false) = false
       and (
         e.is_active = true
         or exists (
           select 1 from public.attendance_daily ad
            where ad.employee_id = e.id
              and ad.work_date = v_today
         )
       )
  loop
    -- فحص الإعفاء اليومي المعتمد (إذن حضور، إجازة، مأمورية، قافلة)
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    -- فحص سجل الحضور اليومي للموظف
    v_att := null;
    select ad.id, ad.status, ad.late_minutes, ad.first_check_in into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today
     limit 1;

    -- إذا كانت حالة السجل تشير إلى إجازة أو مأمورية أو عذر رسمي
    if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- الحالة أ: الموظف بصم حضوراً ولديه تأخير فعلي (من سياسة الوردية المرنة) أكثر من فترة السماح
    if v_att.id is not null and v_att.first_check_in is not null then
      if coalesce(v_att.late_minutes, 0) > 15 then
        -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى)
        v_penalty_minutes := least(120, coalesce(v_att.late_minutes, 0));
        v_notes := case
          when coalesce(v_att.late_minutes, 0) >= 120 then
            'تأخير حضور فعلي تجاوز ساعتين (حُصر عند الحد الأقصى 120 دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
          else
            'تأخير حضور فعلي (' || v_penalty_minutes || ' دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
        end;

        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
      continue;
    end if;

    -- الحالة ب: لم يسجل بصمة حضور بعد.
    -- 0591: لا غرامة لحساب غير نشط (معلّق، أو مدعوّ لم يفعّل حسابه فلا يستطيع البصم)
    if v_emp.is_active = false or v_emp.emp_status is distinct from 'active' then
      continue;
    end if;

    -- 0591: بداية ورديته المسندة إن وُجدت، وإلا آخر بداية وردية مرنة
    v_start := null;
    v_grace := null;
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_start, v_grace
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_emp.employee_id
       and sa.is_active
       and sa.effective_from <= v_today
       and (sa.effective_to is null or sa.effective_to >= v_today)
     order by sa.effective_from desc
     limit 1;
    v_start := coalesce(v_start, v_flex_start);
    v_grace := coalesce(v_grace, v_flex_grace);

    v_elapsed_mins := floor(extract(epoch from (v_time_cairo - v_start)) / 60)::integer;
    if v_elapsed_mins <= v_grace then
      continue;
    end if;

    v_start_label := to_char(v_start, 'FMHH12:MI') || case when v_start < '12:00'::time then ' ص' else ' م' end;
    -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى) مهما تأخر الوقت في اليوم
    v_penalty_minutes := least(120, v_elapsed_mins);
    v_notes := case
      when v_elapsed_mins >= 120 then
        'تأخير عن بداية الوردية (' || v_start_label || ') — حُصر عند الحد الأقصى ساعتان (120 دقيقة) لعدم تسجيل البصمة حتى الآن'
      else
        'تأخير عن بداية الوردية (' || v_start_label || ') — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')'
    end;

    perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

-- ─── تصحيح غرامات اليوم المؤقتة المحسوبة من 10:00 ص ──────────────────────
do $reconcile$
declare
  v_now timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_flex_start time;
  v_flex_grace integer;
  v_start time;
  v_grace integer;
  v_target integer;
  v_amount numeric;
  v_label text;
  v_cancelled integer := 0;
  v_reduced integer := 0;
  r record;
begin
  select s.start_time, coalesce(s.grace_in_minutes, 15)
    into v_flex_start, v_flex_grace
    from public.shifts s
   where s.is_active and s.code in ('SHIFT_9_5', 'OFFICIAL', 'SHIFT_11_7')
   order by s.start_time desc
   limit 1;
  v_flex_start := coalesce(v_flex_start, '10:00'::time);
  v_flex_grace := coalesce(v_flex_grace, 15);

  for r in
    select p.id, p.employee_id, p.late_minutes, p.current_amount,
           ad.first_check_in, coalesce(ad.late_minutes, 0) as ad_late
      from public.instant_attendance_penalties p
      left join public.attendance_daily ad on ad.employee_id = p.employee_id and ad.work_date = p.work_date
     where p.work_date = v_today
       and p.status = 'pending_payment'
       and coalesce(p.escalation_level, 'initial') = 'initial'
       and p.notes like 'تأخير عن موعد العمل (10:00 ص)%'
  loop
    if r.first_check_in is not null then
      -- بصم بعد تسجيل الغرامة المؤقتة: المستحق هو تأخيره الفعلي وفق ورديته المرنة
      v_target := r.ad_late;
      v_label := 'تأخير حضور فعلي: ' || r.ad_late || ' دقيقة';
    else
      v_start := null;
      v_grace := null;
      select s.start_time, coalesce(s.grace_in_minutes, 15)
        into v_start, v_grace
        from public.shift_assignments sa
        join public.shifts s on s.id = sa.shift_id
       where sa.employee_id = r.employee_id
         and sa.is_active
         and sa.effective_from <= v_today
         and (sa.effective_to is null or sa.effective_to >= v_today)
       order by sa.effective_from desc
       limit 1;
      v_start := coalesce(v_start, v_flex_start);
      v_grace := coalesce(v_grace, v_flex_grace);
      v_target := floor(extract(epoch from (v_now::time - v_start)) / 60)::integer;
      if v_target <= v_grace then
        v_target := 0;
      end if;
      v_label := 'تأخير عن بداية الوردية (' || to_char(v_start, 'FMHH12:MI')
                 || case when v_start < '12:00'::time then ' ص' else ' م' end
                 || ') — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now, 'HH12:MI AM') || ')';
    end if;

    v_target := least(120, greatest(0, v_target));
    v_amount := public.calc_instant_penalty_amount(v_target);

    if v_amount <= 0 then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'تصحيح تلقائي: حُسب التأخير من 10:00 ص والدوام مرن حتى 11:00 ص — لا تأخير يتجاوز فترة السماح',
             notes = coalesce(notes || ' | ', '') || 'أُلغيت تلقائياً: الوردية المرنة (0591)',
             updated_at = now()
       where id = r.id;
      v_cancelled := v_cancelled + 1;
    elsif v_target < coalesce(r.late_minutes, 0) or v_amount < r.current_amount then
      update public.instant_attendance_penalties
         set late_minutes = v_target,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_label,
             updated_at = now()
       where id = r.id;
      v_reduced := v_reduced + 1;
    end if;
  end loop;

  if v_cancelled + v_reduced > 0 then
    perform public.log_audit_event(
      'attendance.instant_penalty.flexible_reconcile', 'operations', 'info',
      'instant_attendance_penalties', null,
      'تصحيح غرامات اليوم على الورديات المرنة',
      'غرامات «لم يسجل البصمة» حُسبت من 10:00 ص؛ أعيد حسابها من بداية الوردية المرنة',
      jsonb_build_object('workDate', v_today, 'cancelled', v_cancelled, 'reduced', v_reduced)
    );
  end if;
end;
$reconcile$;

commit;
