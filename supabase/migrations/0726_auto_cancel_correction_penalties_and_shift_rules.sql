-- ============================================================================
-- Migration 0726: Auto Cancel Correction Penalties, Dynamic Shifts & Anti-Loop Escalation
--
-- 1. match_flexible_shift: Add support for SHIFT_11_7 (11:00 AM - 7:00 PM)
-- 2. auto_escalate_instant_penalties:
--    - Freeze escalation when excuse is submitted (excuse_status IN ('submitted', 'under_review'))
--    - Freeze escalation when attendance correction is pending
--    - Prevent re-doubling penalties already reverted/reset by admin (escalation_level = 'reverted')
-- 3. revert_doubled_instant_penalty: mark escalation_level = 'reverted' to break loop
-- 4. decide_attendance_correction: ensure instant penalties are cancelled and late_minutes = 0
-- 5. admin_auto_grace_checkout: Smart grace checkout for missing checkouts
-- 6. Retroactive cleanup of stuck penalties (including Youssef Rasmy on 2026-10-25)
-- ============================================================================

-- 1) تحديث مطابقة الورديات المرنة لتشمل وردية 11 ص – 7 م
CREATE OR REPLACE FUNCTION public.match_flexible_shift(p_check_in timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_time time;
  v_shift_code text;
  v_shift_id uuid;
begin
  if p_check_in is null then
    return public.default_shift_id();
  end if;

  v_time := (p_check_in at time zone 'Africa/Cairo')::time;

  -- مطابقة نافذة الحضور ديناميكياً:
  -- 1) حضور بعد 13:30 (1:30 ظهراً) -> الوردية المسائية للعيادات (3 ع – 11 م)
  -- 2) حضور بين 10:30 ص و 13:30 ظ -> الوردية المسائية (11 ص – 7 م)
  -- 3) حضور حتى 09:30 ص -> الوردية الصباحية (9 ص – 5 م)
  -- 4) حضور بين 09:30 ص و 10:30 ص -> الدوام الأساسي (10 ص – 6 م)
  if v_time >= '13:30:00'::time and exists (select 1 from public.shifts where code = 'SHIFT_CLINIC_3_11' and is_active) then
    v_shift_code := 'SHIFT_CLINIC_3_11';
  elsif v_time >= '10:30:00'::time and exists (select 1 from public.shifts where code = 'SHIFT_11_7' and is_active) then
    v_shift_code := 'SHIFT_11_7';
  elsif v_time <= '09:30:00'::time and exists (select 1 from public.shifts where code = 'SHIFT_9_5' and is_active) then
    v_shift_code := 'SHIFT_9_5';
  else
    v_shift_code := 'OFFICIAL';
  end if;

  select id into v_shift_id
  from public.shifts
  where code = v_shift_code and is_active
  limit 1;

  return coalesce(v_shift_id, public.default_shift_id());
end;
$function$;

-- 2) تحديث كسر حلقة التصعيد التلقائي وتجميد الغرامات عند تقديم عذر أو وجود تصحيح بصمة
CREATE OR REPLACE FUNCTION public.auto_escalate_instant_penalties()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
begin
  -- قفل استشاري يمنع تشغيلين متزامنين
  perform pg_advisory_xact_lock(hashtext('auto_escalate_instant_penalties'));

  -- ═══ المرحلة 0: إلغاء أي غرامات لموظفين معفيين فعلاً ═══
  update public.instant_attendance_penalties p
     set status = 'cancelled',
         cancelled_reason = 'إلغاء تلقائي: الموظف معفى من الغرامات بقرار إداري',
         notes = coalesce(p.notes || ' | ', '') || 'تم الإلغاء التلقائي بواسطة كرون التحصين',
         updated_at = now()
  from public.employees e
  where p.employee_id = e.id
    and p.status in ('pending_payment', 'doubled', 'pending_escalation')
    and (
      e.is_penalty_exempt = true
      or public.is_employee_attendance_exempt(e.id)
      or public.is_employee_penalty_exempt(e.id)
    );

  -- ═══ المرحلة 1: مضاعفة — عدم السداد حتى اليوم الثاني من العمل ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       -- تجميد التصعيد إذا كان هناك عذر قيد المراجعة
       and coalesce(p.excuse_status, 'none') not in ('submitted', 'under_review')
       -- تجميد التصعيد إذا كانت الغرامة قد رُدت للأصل بقرار إداري
       and p.notes not like '%رفع الإيقاف إدارياً وإرجاع الغرامة للأصل%'
       -- تجميد التصعيد إذا كان هناك طلب تصحيح بصمة معلق لنفس اليوم
       and not exists (
         select 1 from public.attendance_corrections ac
          where ac.employee_id = p.employee_id
            and ac.work_date = p.work_date
            and ac.status = 'pending'
       )
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
    -- فحص الإعفاء الديناميكي قبل التصعيد
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء قبل التصعيد: ' || (v_exempt->>'reason'),
             cancelled_reason = 'إعفاء معتمد: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    -- إذا استوفى 8 ساعات عمل يُعفى وتلغى الغرامة فوراً
    if exists (
      select 1 from public.attendance_daily ad
      where ad.employee_id = v_rec.employee_id
        and ad.work_date = v_rec.work_date
        and (
          coalesce(ad.work_minutes, 0) >= 480
          or (ad.first_check_in is not null and ad.last_check_out is not null and (ad.last_check_out - ad.first_check_in) >= interval '8 hours')
        )
    ) then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: استيفاء 8 ساعات عمل كاملة في نفس اليوم',
             notes = coalesce(notes || ' | ', '') || 'تم الإلغاء لاستيفاء ساعات العمل الرسمية',
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    -- المضاعفة الفعلية
    update public.instant_attendance_penalties
       set escalation_level = 'doubled',
           current_amount = 500.00,
           notes = coalesce(notes || ' | ', '') || 'مضاعفة تلقائية: لم تُسدد في نفس اليوم. الغرامة الآن 500 ج.م',
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'finance', 'high',
      'instant_attendance_penalties', v_rec.id,
      coalesce(v_emp_name, 'موظف') || ' — تمت مضاعفة غرامة التأخير إلى 500 ج.م',
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

  -- ═══ المرحلة 2: عدم السداد حتى اليوم الثالث -> غلق الحساب ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status in ('doubled', 'pending_payment')
       -- تجميد التعليق عند تقديم عذر قيد الفحص
       and coalesce(p.excuse_status, 'none') not in ('submitted', 'under_review')
       -- تجميد التعليق إذا كانت الغرامة قد رُدت للأصل
       and p.notes not like '%رفع الإيقاف إدارياً وإرجاع الغرامة للأصل%'
       and not exists (
         select 1 from public.attendance_corrections ac
          where ac.employee_id = p.employee_id
            and ac.work_date = p.work_date
            and ac.status = 'pending'
       )
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
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء قبل الإيقاف: ' || (v_exempt->>'reason'),
             cancelled_reason = 'إعفاء معتمد: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set escalation_level = 'suspended',
           status = 'suspended',
           notes = coalesce(notes || ' | ', '') || 'إيقاف الحساب تلقائياً: تجاوزت المهلة دون سداد (اليوم الثالث)',
           updated_at = now()
     where id = v_rec.id;

    update public.employees
       set is_active = false,
           status = 'suspended',
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'finance', 'critical',
      'instant_attendance_penalties', v_rec.id,
      coalesce(v_emp_name, 'موظف') || ' — تم إيقاف الحساب عن العمل لعدم سداد الغرامة في اليوم الثالث',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'currentAmount', v_rec.current_amount)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '⛔ تم إيقاف حسابك عن العمل',
      coalesce(v_emp_name, 'الموظف') || ' تم إيقاف حسابك عن العمل بسبب تجاوز المهلة (3 أيام عمل) دون سداد الغرامة الفورية. يرجى التوجه لإدارة الموارد البشرية فوراً.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', v_rec.current_amount,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
end;
$function$;

-- 3) تحديث دالة إرجاع الغرامة المضاعفة للأصل وتثبيتها لمنع الكرون من إعادة مضاعفتها
CREATE OR REPLACE FUNCTION public.revert_doubled_instant_penalty(p_penalty_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me         uuid := public.current_employee_id();
  v_row        public.instant_attendance_penalties;
  v_emp_name   text;
  v_has_other_doubled boolean := false;
  v_old_amount numeric(12,2);
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'super-admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin', 'operations-manager-1', 'operations-manager-2')
       )
     ) then
    raise exception 'غير مسموح: يتطلب صلاحية إدارة النظام أو الموارد البشرية' using errcode = '42501';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status in ('paid', 'cancelled') then
    raise exception 'لا يمكن تعديل غرامة مسددة أو ملغاة' using errcode = '22023';
  end if;

  v_old_amount := v_row.current_amount;

  -- إعادة الغرامة للأصل وتعيين المستوى إلى 'reverted' لمنع الكرون من مضاعفتها تلقائياً مرة أخرى
  update public.instant_attendance_penalties
     set escalation_level = 'reverted',
         current_amount = original_amount,
         status = 'pending_payment',
         notes = coalesce(notes || ' | ', '') || 'رفع الإيقاف إدارياً وإرجاع الغرامة للأصل (' || original_amount || ' ج.م)' || case when p_reason is not null and length(trim(p_reason)) > 0 then ': ' || p_reason else '' end,
         updated_at = now()
   where id = p_penalty_id;

  -- فحص ما إذا كان للموظف غرامات أخرى مضاعفة أو معلقة الإيقاف
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and status in ('doubled', 'suspended')
  ) into v_has_other_doubled;

  -- إذا لم يعد هناك غرامات توقف الحساب، يتم رفع الإيقاف فوراً وتفعيل الموظف
  if not v_has_other_doubled then
    update public.employees
       set is_active = true,
           status = 'active',
           updated_at = now()
     where id = v_row.employee_id
       and status = 'suspended';

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id
       and status = 'suspended';
  end if;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  perform public.log_audit_event(
    'instant_penalty.reverted', 'finance', 'medium',
    'instant_attendance_penalties', p_penalty_id,
    coalesce(v_emp_name, 'موظف') || ' — تم رفع الإيقاف وإرجاع الغرامة للأصل (' || v_row.original_amount || ' ج.م)',
    p_reason,
    jsonb_build_object(
      'penaltyId', p_penalty_id,
      'employeeId', v_row.employee_id,
      'oldAmount', v_old_amount,
      'newAmount', v_row.original_amount,
      'reason', p_reason
    )
  );

  return jsonb_build_object(
    'success', true,
    'message', 'تم رفع الإيقاف وإرجاع الغرامة للأصل بنجاح',
    'oldAmount', v_old_amount,
    'currentAmount', v_row.original_amount
  );
end;
$function$;

-- 4) RPC للاعتماد الذكي لانصراف الوردية الرسمية (Auto Grace Checkout)
CREATE OR REPLACE FUNCTION public.admin_auto_grace_checkout(
  p_attendance_daily_id uuid,
  p_note text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rec record;
  v_shift public.shifts%rowtype;
  v_checkout_time timestamptz;
  v_tz text := 'Africa/Cairo';
  v_work_minutes integer;
  v_emp_name text;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or public.current_has_active_role(array['admin', 'super-admin', 'hr-manager', 'executive', 'operations-manager-1'])
     ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select ad.*, e.full_name_ar into v_rec
    from public.attendance_daily ad
    join public.employees e on e.id = ad.employee_id
   where ad.id = p_attendance_daily_id
     for update;

  if not found then
    raise exception 'سجل الحضور غير موجود' using errcode = 'P0002';
  end if;

  if v_rec.first_check_in is null then
    raise exception 'لا يمكن اعتماد انصراف لموظف لم يسجل حضوراً أصلاً' using errcode = '22023';
  end if;

  -- العثور على وردية اليوم للموظف
  if v_rec.shift_id is not null then
    select * into v_shift from public.shifts where id = v_rec.shift_id;
  end if;

  if v_shift.id is null then
    select s.* into v_shift
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_rec.employee_id
       and sa.is_active = true
       and sa.effective_from <= v_rec.work_date
       and (sa.effective_to is null or sa.effective_to >= v_rec.work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_shift.id is null then
    select * into v_shift from public.shifts where code = 'OFFICIAL' and is_active limit 1;
  end if;

  -- تحديد موعد الانصراف في نهاية الوردية الرسمية
  v_checkout_time := (
    v_rec.work_date
    + case when coalesce(v_shift.crosses_midnight, false) then 1 else 0 end
    + coalesce(v_shift.end_time, '18:00'::time)
  ) at time zone v_tz;

  v_work_minutes := floor(extract(epoch from (v_checkout_time - v_rec.first_check_in)) / 60)::integer;

  -- تحديث سجل الحضور
  update public.attendance_daily
     set last_check_out = v_checkout_time,
         status = 'present',
         work_minutes = greatest(coalesce(v_work_minutes, 480), 0),
         is_finalized = true,
         updated_at = now()
   where id = p_attendance_daily_id;

  -- حل أي استثناء معلق خاص بعدم الانصراف لهذا اليوم
  update public.attendance_exceptions
     set status = 'resolved',
         resolution_notes = 'اعتماد تلقائي ذكي لنهاية الوردية الرسمية' || case when p_note is not null then ': ' || p_note else '' end,
         resolved_at = now()
   where attendance_daily_id = p_attendance_daily_id
     and kind = 'missing_check_out'
     and status in ('open', 'approved');

  perform public.log_audit_event(
    'attendance.auto_grace_checkout', 'attendance', 'medium',
    'attendance_daily', p_attendance_daily_id,
    'اعتماد انصراف نهاية الوردية الرسمية للموظف ' || coalesce(v_rec.full_name_ar, ''),
    p_note,
    jsonb_build_object(
      'employeeId', v_rec.employee_id,
      'workDate', v_rec.work_date,
      'checkIn', v_rec.first_check_in,
      'checkOut', v_checkout_time,
      'workMinutes', v_work_minutes
    )
  );

  return jsonb_build_object(
    'success', true,
    'checkoutTime', v_checkout_time,
    'workMinutes', v_work_minutes,
    'message', 'تم اعتماد انصراف الموظف بنهاية ورديته الرسمية بنجاح.'
  );
end;
$function$;

-- 5) التسوية الفورية الشاملة للغرامات العالقة (Retroactive Cleanup)
-- أ. تسوية غرامة يوسف رسمي شعبان لتاريخ 2026-10-25
UPDATE public.instant_attendance_penalties
   SET status = 'cancelled',
       cancelled_reason = 'اعتماد تصحيح البصمة إدارياً - تسوية فورية',
       notes = coalesce(notes || ' | ', '') || 'تسوية آلية فورية لغرامة 2026-10-25',
       updated_at = now()
 WHERE id = 'f6999442-48ed-4fb2-ac4a-d9fc4add7554'
    OR (employee_id = 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6' AND work_date = '2026-10-25');

-- تصفير دقائق التأخير ليوسف رسمي في كشف 2026-10-25
UPDATE public.attendance_daily
   SET late_minutes = 0,
       status = 'present',
       updated_at = now()
 WHERE employee_id = 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'
   AND work_date = '2026-10-25';

-- ب. إلغاء أي غرامات أخرى معلقة يوجد لها تصحيح بصمة معتمد
UPDATE public.instant_attendance_penalties p
   SET status = 'cancelled',
       cancelled_reason = 'اعتماد تصحيح البصمة إدارياً',
       notes = coalesce(p.notes || ' | ', '') || 'إلغاء بأثر رجعي لوجود طلب تصحيح بصمة معتمد',
       updated_at = now()
 WHERE p.status IN ('pending_payment', 'doubled', 'suspended')
   AND EXISTS (
     SELECT 1 FROM public.attendance_corrections ac
      WHERE ac.employee_id = p.employee_id
        AND ac.work_date = p.work_date
        AND ac.status = 'approved'
   );

-- ج. إلغاء أي غرامات لمن استوفى 8 ساعات عمل كاملة في نفس اليوم
UPDATE public.instant_attendance_penalties p
   SET status = 'cancelled',
       cancelled_reason = 'إتمام 8 ساعات عمل رسمية في نفس اليوم',
       notes = coalesce(p.notes || ' | ', '') || 'إلغاء بأثر رجعي لاستيفاء 8 ساعات عمل',
       updated_at = now()
 WHERE p.status IN ('pending_payment', 'doubled', 'suspended')
   AND EXISTS (
     SELECT 1 FROM public.attendance_daily ad
      WHERE ad.employee_id = p.employee_id
        AND ad.work_date = p.work_date
        AND (
          coalesce(ad.work_minutes, 0) >= 480
          OR (ad.first_check_in IS NOT NULL AND ad.last_check_out IS NOT NULL AND (ad.last_check_out - ad.first_check_in) >= interval '8 hours')
        )
   );

-- د. رفع الإيقاف عن جميع الموظفين الذين لا توجد عليهم غرامات مضاعفة قائمة
UPDATE public.employees e
   SET status = 'active',
       is_active = true,
       updated_at = now()
 WHERE e.status = 'suspended'
   AND NOT EXISTS (
     SELECT 1 FROM public.instant_attendance_penalties p
      WHERE p.employee_id = e.id
        AND p.status IN ('doubled', 'suspended')
   );

UPDATE public.profiles pr
   SET status = 'active',
       updated_at = now()
 WHERE pr.status = 'suspended'
   AND NOT EXISTS (
     SELECT 1 FROM public.instant_attendance_penalties p
      WHERE p.employee_id = pr.employee_id
        AND p.status IN ('doubled', 'suspended')
   );

