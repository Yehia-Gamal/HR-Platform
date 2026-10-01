-- =====================================================================
-- 0584: تعديل شرائح غرامات التأخير الفورية
-- =====================================================================
-- بناءً على التوجيه الإداري المباشر:
-- 1. أول ربع ساعة سماح (10:00 إلى 10:15) = 0 ج.م (بدون أي خصم).
-- 2. من 10:16 وحتى الساعة 10:30 (16 إلى 30 دقيقة) = خصم 20 جنيه.
-- 3. من 10:31 وحتى الساعة 11:00 (31 إلى 60 دقيقة) = خصم 50 جنيه.
-- 4. من 11:01 وحتى الساعة 12:00 (61 إلى 120 دقيقة محصورة عند ساعتين كحد أقصى) = خصم 150 جنيه.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) تحديث دالة حساب مبلغ الغرامة الفورية calc_instant_penalty_amount
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.calc_instant_penalty_amount(p_late_minutes integer)
returns numeric(12,2)
language sql
immutable strict
set search_path = public, extensions, pg_temp
as $$
  select case
    when p_late_minutes is null or p_late_minutes <= 15 then 0.00    -- أول ربع ساعة سماح (10:00 إلى 10:15)
    when p_late_minutes <= 30                           then 20.00   -- من 10:16 وحتى 10:30 (16-30 دقيقة) = خصم 20 جنيه
    when p_late_minutes <= 60                           then 50.00   -- من 10:31 وحتى 11:00 (31-60 دقيقة) = خصم 50 جنيه
    else 150.00                                                      -- من 11:01 وحتى 12:00 (61-120 دقيقة محصورة عند ساعتين كحد أقصى) = خصم 150 جنيه
  end;
$$;

revoke all on function public.calc_instant_penalty_amount(integer) from public, anon;
grant execute on function public.calc_instant_penalty_amount(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث دالة تسجيل الغرامة الفورية مع ضبط الملاحظات على الشرائح الجديدة
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.record_instant_attendance_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_effective_late_minutes integer;
  v_amount numeric(12,2);
  v_default_notes text;
  v_row public.instant_attendance_penalties;
  v_exempt_check jsonb;
  v_emp_name text;
  v_mgr_user_id uuid;
begin
  if auth.role() <> 'service_role' and not public.current_is_admin_or_hr() then
    raise exception 'غير مصرح بتسجيل الغرامات الفورية' using errcode = '42501';
  end if;

  if p_employee_id is null or p_work_date is null then
    raise exception 'معرف الموظف وتاريخ العمل مطلوبان' using errcode = '22023';
  end if;

  -- 1. فحص الإعفاء الدائم للقيادات وطاقم العيادات المعفى
  if public.is_employee_penalty_exempt(p_employee_id)
     or public.is_employee_attendance_exempt(p_employee_id) then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى رسمياً من الغرامات بقرار الإدارة'
    );
  end if;

  -- 2. فحص الإعفاء التشغيلي ليوم العمل
  v_exempt_check := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt_check->>'isExempt')::boolean, false) then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى من الغرامة لهذا اليوم: ' || coalesce(v_exempt_check->>'reason', 'إعفاء رسمي')
    );
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
    when v_effective_late_minutes <= 30 then 'تأخير حتى 10:30 (خصم 20 ج.م)'
    when v_effective_late_minutes <= 60 then 'تأخير من 10:31 وحتى 11:00 (خصم 50 ج.م)'
    when v_effective_late_minutes >= 120 then 'تأخير بلغ ساعتين (حُصر عند الحد الأقصى 120 دقيقة — خصم 150 ج.م)'
    else 'تأخير من 11:01 وحتى 12:00 (خصم 150 ج.م)'
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

    -- إذا كانت لا تزال قيد السداد وكان التأخير/المبلغ الجديد أكبر:
    if v_row.status = 'pending_payment' and (v_amount > v_row.current_amount or v_effective_late_minutes > coalesce(v_row.late_minutes, 0)) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
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
      'message', 'تم تحديث/التحقق من الغرامة المسجلة مسبقاً لهذا اليوم بمبلغ ' || v_row.current_amount || ' ج.م'
    );
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'alreadyExists', false,
    'amount', v_row.current_amount,
    'status', v_row.status,
    'message', 'تم تسجيل الغرامة الفورية بنجاح بمبلغ ' || v_row.current_amount || ' ج.م'
  );
end;
$$;

revoke all on function public.record_instant_attendance_penalty(uuid, date, integer, text) from public, anon;
grant execute on function public.record_instant_attendance_penalty(uuid, date, integer, text) to authenticated, service_role;

commit;
