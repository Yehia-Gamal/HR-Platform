-- 0612: إصلاح — توليد غرامات التأخير الفورية معطّل منذ تطبيق 0606
-- ===========================================================================
-- 0606 أعادت كتابة generate_instant_penalty فقرأت employees.salary/base_salary
-- (غير موجودين) → 42703 في كل استدعاء: كرون الغرامات (كل 10 دقائق) وتريجر
-- البصمة يتخطيانها بتحذير، فلا تُسجَّل أي غرامة تأخير منذ ~14:06 بتوقيت القاهرة.
-- وأسقطت أيضًا:
--   • فحص الصلاحية — مع منح EXECUTE لـ authenticated كان أي موظف سيستطيع
--     تسجيل غرامة على أي زميل عبر RPC فور إصلاح العمود بسذاجة؛
--   • calc_instant_penalty_amount (المبالغ الرسمية) لصالح شرائح مكتوبة يدويًا؛
--   • شكل الرد المعتمد (alreadyExists/message) ونص مهلة السداد الصحيح.
--
-- الإصلاح: استبدال كنوني كامل = نسخة 0586 المنشورة سابقًا حرفيًا (الصلاحية مع
-- استثناء تريجر البصمة، المبالغ الرسمية، سقف 120 دقيقة) + قصد 0606 الوحيد هنا:
-- لا إشعار «تصعيد» إلا عند الانتقال لشريحة مالية أعلى، وتحديث الدقائق بصمت.
-- ===========================================================================

begin;

CREATE OR REPLACE FUNCTION public.generate_instant_penalty(p_employee_id uuid, p_work_date date, p_late_minutes integer, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_effective_late_minutes integer;
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
  v_exempt jsonb;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح). 0586: الاستدعاء من تريجر
  -- البصمة (pg_trigger_depth() > 0) يجري داخل جلسة الموظف فكان هذا الفحص يرفضه
  -- ويُفشل البصمة؛ الاستدعاء المباشر من الواجهات ما زال يتطلب الصلاحية.
  if auth.uid() is not null
     and pg_trigger_depth() = 0
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- 1. فحص الإعفاء الشامل المعتمد لذلك اليوم
  v_exempt := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى من غرامات الحضور والانصراف: ' || (v_exempt->>'reason')
    );
  end if;

  -- 2. التحقق من وجود الموظف (دون اشتراط is_active للسماح بتسجيل غرامة من حضر متأخراً في اليوم 2 أو 3)
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and coalesce(is_deleted, false) = false;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- 3. حصر دقائق التأخير عند 120 دقيقة كحد أقصى (ساعتان فقط)
  v_effective_late_minutes := least(120, greatest(1, p_late_minutes));
  v_amount := public.calc_instant_penalty_amount(v_effective_late_minutes);

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

  v_default_notes := coalesce(p_notes, case
    when v_effective_late_minutes >= 120 then 'تأخير بلغ ساعتين (حُصر عند الحد الأقصى 120 دقيقة)'
    else 'تأخير عن موعد العمل الرسمي (10:00 ص)'
  end);

  -- محاولة الإدخال
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, notes, created_by
  ) values (
    p_employee_id, p_work_date, v_effective_late_minutes,
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

    -- 0612 (قصد 0606): التصعيد والإشعار عند الانتقال لشريحة مالية أعلى فقط؛
    -- زيادة الدقائق داخل الشريحة نفسها تُحدَّث بصمت — كان كرون الغرامات
    -- (كل 10 دقائق) يرسل إشعار «تصعيد» مع كل دقائق إضافية.
    if v_row.status = 'pending_payment' and v_amount > v_row.current_amount then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        v_emp_name || ': تزايد التأخير إلى ' || case when v_effective_late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_effective_late_minutes || ' دقيقة' end || ' — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'penaltyId', v_row.id::text,
          'lateMinutes', v_effective_late_minutes,
          'originalAmount', v_amount,
          'currentAmount', v_amount,
          'channel', 'instant_penalty',
          'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
        )
      );
    elsif v_row.status = 'pending_payment'
          and v_effective_late_minutes > coalesce(v_row.late_minutes, 0) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'amount', v_row.current_amount,
      'status', v_row.status,
      'lateMinutes', v_row.late_minutes,
      'message', 'توجد غرامة مسجلة مسبقاً لهذا اليوم'
    );
  end if;

  -- إشعار أصحاب الشأن
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ تسجيل غرامة تأخير حضور فورية',
    'تم تسجيل غرامة تأخير على ' || v_emp_name || ' بمبلغ ' || v_amount || ' ج.م (' || case when v_effective_late_minutes >= 120 then 'ساعتان — الحد الأقصى' else v_effective_late_minutes || ' دقيقة' end || ' تأخير). المهلة: نفس اليوم قبل المضاعفة إلى 500 ج.م غداً.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'penaltyId', v_row.id::text,
      'lateMinutes', v_effective_late_minutes,
      'originalAmount', v_amount,
      'currentAmount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'alreadyExists', false,
    'amount', v_amount,
    'status', 'pending_payment',
    'lateMinutes', v_effective_late_minutes,
    'message', 'تم تسجيل الغرامة الفورية بنجاح'
  );
end;
$function$;

revoke all on function public.generate_instant_penalty(uuid, date, integer, text) from public, anon;
grant execute on function public.generate_instant_penalty(uuid, date, integer, text) to authenticated, service_role;
comment on function public.generate_instant_penalty(uuid, date, integer, text) is
  '0612: نسخة 0586 + إشعار التصعيد عند الانتقال لشريحة أعلى فقط (قصد 0606).';

commit;
