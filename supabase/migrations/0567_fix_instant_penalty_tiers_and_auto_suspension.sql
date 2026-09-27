-- =====================================================================
-- 0567: ضبط وتطبيق قواعد الخصومات الفورية والتصعيد التلقائي
-- =====================================================================
-- 1) شرائح الخصم اللحظي:
--    - حتى 15 دقيقة: فترة سماح رسمية (0 ج.م).
--    - تمام تأخير 30 دقيقة (16 إلى 30 دقيقة): 20 ج.م.
--    - تمام تأخير 1 ساعة وحتى قبل إتمام الساعتين (31 إلى 119 دقيقة): 50 ج.م.
--    - تمام التأخر ساعتين كاملتين فأكثر (120 دقيقة فأكثر، أو عدم الحضور): 150 ج.م.
--
-- 2) عدم السداد في نفس اليوم (المرحلة 1):
--    - تتضاعف الغرامة تلقائياً في اليوم التالي إلى 500 ج.م تدفع ثاني يوم.
--
-- 3) عدم السداد في اليوم الثاني (المرحلة 2):
--    - يتم غلق الحساب ووقف الموظف عن العمل تلقائياً حتى سداد الـ 500 ج.م.
--    - تعليق employees.status = 'suspended' و profiles.status = 'suspended'.
--    - حجب التطبيق مع رسالة التوجه للـ HR لسداد الـ 500 ج.م.
--
-- 4) عند سداد الـ 500 ج.م:
--    - يعاد فتح الحساب ورفع التعليق فوراً (employees.status = 'active').
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة حساب شريحة الغرامة الفورية من دقائق التأخير
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.calc_instant_penalty_amount(p_late_minutes integer)
returns numeric(12,2)
language sql immutable strict
set search_path = public, extensions, pg_temp
as $$
  select case
    when p_late_minutes is null or p_late_minutes <= 15 then 0.00   -- فترة سماح 15 دقيقة (10:00 - 10:15) بدون أي خصم
    when p_late_minutes <= 30                           then 20.00  -- تمام تأخير 30 دقيقة (16-30 دقيقة) = 20 ج.م
    when p_late_minutes < 120                           then 50.00  -- تمام تأخير 1 ساعة وحتى أقل من ساعتين (31-119 دقيقة) = 50 ج.م
    else 150.00                                                     -- تمام التأخر ساعتين كاملتين فأكثر (120 دقيقة فأكثر) = 150 ج.م
  end;
$$;

revoke all on function public.calc_instant_penalty_amount(integer) from public, anon;
grant execute on function public.calc_instant_penalty_amount(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث جدول إعدادات الغرامات (penalty_settings) بالقيم الصحيحة
-- ─────────────────────────────────────────────────────────────────────

insert into public.penalty_settings (setting_key, setting_value, description)
values
  ('grace_minutes', to_jsonb(15), 'فترة السماح بالدقائق بعد موعد الحضور'),
  ('shift_start', to_jsonb('10:00'::text), 'موعد بداية الدوام'),
  ('tiers', to_jsonb('[{"min_late":16,"max_late":30,"amount":20,"label":"تأخير حتى 30 دقيقة (20 ج.م)"},{"min_late":31,"max_late":119,"amount":50,"label":"تأخير ساعة وحتى أقل من ساعتين (50 ج.م)"},{"min_late":120,"max_late":9999,"amount":150,"label":"تمام التأخر ساعتين كاملتين فأكثر (150 ج.م)"}]'::jsonb), 'شرائح الغرامات حسب دقائق التأخير'),
  ('doubled_amount', to_jsonb(500), 'مبلغ الغرامة المضاعفة (عدم السداد)'),
  ('max_days_before_escalation', to_jsonb(2), 'عدد الأيام قبل التصعيد إلى غلق الحساب والتعليق')
on conflict (setting_key) do update
set setting_value = excluded.setting_value,
    updated_at = now();

-- ─────────────────────────────────────────────────────────────────────
-- 3) دالة التصعيد التلقائي: المضاعفة إلى 500 ج.م ثم غلق الحساب والتعليق
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
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

  -- ═══ المرحلة 1: عدم السداد في نفس اليوم -> مضاعفة الغرامة إلى 500 ج.م تدفع ثاني يوم ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    -- فحص الإعفاء قبل المضاعفة
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
      coalesce(v_emp_name, 'الموظف') || ' لم تسدد غرامة التأخير في نفس اليوم. تمت مضاعفة الغرامة إلى 500 ج.م تدفع اليوم (ثاني يوم). في حال عدم السداد اليوم، سيتم غلق الحساب ووقفك عن العمل تلقائياً.',
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

  -- ═══ المرحلة 2: عدم السداد في اليوم الثاني -> غلق الحساب ووقف الموظف عن العمل حتى السداد ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status in ('doubled', 'pending_payment')
       and p.work_date < v_today - 1
  loop
    -- فحص الإعفاء قبل التعليق
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

    -- استثناء الحسابات ذات الحصانة الإدارية الكاملة
    if exists (
      select 1 from public.employees e
      where e.id = v_rec.employee_id
        and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')
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

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
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
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثاني',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', 500.00, 'workDate', v_rec.work_date)
    );

    -- 3) إشعار عاجل للموظف
    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 إيقاف عن العمل وغلق الحساب',
      'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م. توجه إلى قسم الـ HR لسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', 500.00,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    -- 4) إرسال إشعار لكامل الفريق
    perform public.notify_employee(
      e.id,
      '🚫 إشعار إيقاف موظف عن العمل',
      'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
      'system',
      'urgent',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'suspendedEmployeeName', v_emp_name,
        'amount', 500,
        'channel', 'team_suspension_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_rec.employee_id;

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$function$;

comment on function public.auto_escalate_instant_penalties() is
  '0567: تصعيد الغرامات الفورية: مضاعفة إلى 500 ج.م في اليوم الثاني لعدم السداد في نفس اليوم، وغلق الحساب والتعليق التلقائي عند عدم السداد في اليوم الثاني حتى سداد الـ 500 ج.م.';

-- ─────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة تأكيد السداد لضمان رفع التعليق وفتح الحساب فوراً
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.confirm_instant_penalty_payment(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_my_name text;
  v_current_balance numeric(12,2) := 0;
  v_new_balance numeric(12,2) := 0;
  v_was_suspended boolean := false;
  v_has_other_suspended boolean := false;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve'])
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'executive', 'executive-secretary', 'executive-director', 'system-admin')
       )
     ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
    if v_me is null then
      select id into v_me from public.employees where user_id = auth.uid();
    end if;
  end if;

  if v_me is null then
    select id into v_me from public.employees where is_active = true and is_deleted = false order by created_at limit 1;
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_row.status = 'paid' then
    raise exception 'الغرامة مدفوعة بالفعل ومودعة في صندوق الزمالة' using errcode = '22023';
  end if;

  if v_row.status = 'cancelled' then
    raise exception 'الغرامة ملغاة ولا يمكن تحصيلها' using errcode = '22023';
  end if;

  v_was_suspended := (v_row.status = 'suspended');

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  select full_name_ar into v_my_name
    from public.employees where id = v_me;

  -- 1) تحديث حالة الغرامة إلى مدفوعة
  update public.instant_attendance_penalties
     set status = 'paid',
         paid_at = now(),
         confirmed_by = v_me,
         suspension_lifted_at = case when v_was_suspended then now() else suspension_lifted_at end,
         suspension_lifted_by = case when v_was_suspended then v_me else suspension_lifted_by end,
         notes = coalesce(p_notes, notes),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- 2) رفع التعليق فوراً إن لم توجد غرامات معلقة أخرى للموظف
  select exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_row.employee_id
       and id <> p_penalty_id
       and status = 'suspended'
  ) into v_has_other_suspended;

  if not v_has_other_suspended then
    update public.employees
       set status = 'active',
           is_active = true,
           updated_at = now()
     where id = v_row.employee_id;

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_row.employee_id;
  end if;

  -- 3) توريد المبلغ لصندوق الزمالة والتكافل
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0)
    into v_current_balance
    from public.fellowship_fund_transactions;

  v_new_balance := v_current_balance + v_row.current_amount;

  insert into public.fellowship_fund_transactions(
    employee_id, amount, transaction_type, source,
    balance_after, notes, reference_id, created_by
  ) values (
    v_row.employee_id,
    v_row.current_amount,
    'inflow',
    'instant_penalty',
    v_new_balance,
    'سداد غرامة فورية ليوم ' || v_row.work_date || ' (تأخير ' || v_row.late_minutes || ' دقيقة) — المحصّل: ' || coalesce(v_my_name, 'HR'),
    v_row.id,
    v_me
  );

  -- 4) سجل التدقيق
  perform public.log_audit_event(
    'instant_penalty.paid', 'financial', 'info',
    'instant_attendance_penalties', v_row.id,
    'سداد غرامة فورية: ' || v_emp_name || ' — ' || v_row.current_amount || ' ج.م تم توريدها لصندوق الزمالة' || case when v_was_suspended and not v_has_other_suspended then ' (تم رفع التعليق وإعادة فتح الحساب)' else '' end,
    null,
    jsonb_build_object(
      'penaltyId', v_row.id,
      'employeeId', v_row.employee_id,
      'amount', v_row.current_amount,
      'confirmedBy', v_me,
      'fellowshipNewBalance', v_new_balance,
      'wasSuspended', v_was_suspended,
      'suspensionLifted', not v_has_other_suspended
    )
  );

  -- 5) إشعار الموظف
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم سداد الغرامة الفورية بنجاح',
    'تم تأكيد سداد غرامة التأخير بقيمة ' || v_row.current_amount || ' ج.م وإيداعها في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_suspended then '. تم رفع الإيقاف وإعادة فتح حسابك بنجاح ومباشرة العمل.' else '.' end,
    'instant_penalty_paid',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'channel', 'instant_penalty_paid',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'success', true,
    'id', v_row.id,
    'penaltyId', v_row.id,
    'status', 'paid',
    'currentAmount', v_row.current_amount,
    'wasSuspended', v_was_suspended,
    'suspensionLifted', not v_has_other_suspended,
    'fellowshipBalance', v_new_balance,
    'message', 'تم تأكيد السداد وإيداع ' || v_row.current_amount || ' ج.م في صندوق الزمالة والتكافل' || case when v_was_suspended and not v_has_other_suspended then ' وتمت إعادة تفعيل حساب الموظف.' else '.' end
  );
end;
$$;

revoke all on function public.confirm_instant_penalty_payment(uuid, text) from public, anon;
grant execute on function public.confirm_instant_penalty_payment(uuid, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث زر الفحص اليدوي اللحظي ليشمل الفحص والتصعيد معاً
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.trigger_check_instant_penalties_now()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_gen_count integer;
  v_esc_count integer;
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1) فحص وتطبيق غرامات اليوم
  v_gen_count := public.auto_generate_instant_penalties();

  -- 2) فحص وتطبيق التصعيد والمضاعفة والتعليق للغرامات غير المسددة
  v_esc_count := public.auto_escalate_instant_penalties();

  return jsonb_build_object(
    'success', true,
    'generatedCount', v_gen_count,
    'escalatedCount', v_esc_count,
    'totalProcessed', v_gen_count + v_esc_count,
    'serverTimeCairo', to_char(v_now_cairo, 'YYYY-MM-DD HH12:MI:SS AM'),
    'message', 'تم فحص الحضور وتطبيق الغرامات والتصعيد بنجاح (المولدة: ' || v_gen_count || '، المصعدة: ' || v_esc_count || ')'
  );
end;
$$;

grant execute on function public.trigger_check_instant_penalties_now() to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
