-- 0616: ضبط سياسة يحيى — غرامات طبيعية عند التأخير + حماية الحساب من الإيقاف
-- =====================================================================
-- السياسة المطلوبة:
--   ✅ يحيى يأخذ غرامة إذا تأخر فعلاً (مثل أي موظف)
--   ✅ الحساب محمي من الإيقاف والتعليق نهائياً
--   ✅ لا يُوقف عن العمل أبداً
--   ❌ لا إعفاء دائم من الغرامات
-- =====================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. تحديث trigger الحصانة الإدارية — حماية الحساب فقط بدون إعفاء الغرامات
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.tg_admin_immunity_employees_fn()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or NEW.phone_e164 in ('+201154869616', '01154869616')
     or NEW.employee_code in ('+201154869616', '01154869616')
     or NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.full_name_ar ilike '%يحيى%جمال%' then
    -- الحساب نشط دائماً ولا يُوقف عن العمل نهائياً
    NEW.status := 'active';
    NEW.is_active := true;
    -- ★ لا نتدخل في is_penalty_exempt — نتركه كما هو في قاعدة البيانات ★
    -- الموظف يأخذ غرامة عادية إذا تأخر فعلاً
  end if;
  return NEW;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 2. إزالة الإعفاء من سجل يحيى — يخضع للغرامات كأي موظف عادي
-- ═══════════════════════════════════════════════════════════════════════
update employees
set is_penalty_exempt = false,
    updated_at = now()
where id = 'b452c987-ae08-4e12-8433-272cc66c85f9';


-- ═══════════════════════════════════════════════════════════════════════
-- 3. تحصين auto_escalate — لا يوقف حساب يحيى أبداً لكن الغرامة تبقى
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
begin
  -- قفل استشاري يمنع تشغيلين متزامنين
  perform pg_advisory_xact_lock(hashtext('auto_escalate_instant_penalties'));

  -- ═══ المرحلة 0: إلغاء أي غرامات لموظفين معفيين فعلاً (ليس يحيى) ═══
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
    -- فحص الإعفاء الديناميكي قبل الإيقاف
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             cancelled_reason = 'إعفاء معتمد: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      update public.employees set status = 'active', is_active = true where id = v_rec.employee_id;
      update public.profiles set status = 'active' where employee_id = v_rec.employee_id;
      continue;
    end if;

    -- ★ حساب يحيى (المسؤول العام) — الغرامة تبقى لكن الحساب لا يُعلَّق أبداً ★
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
      -- الغرامة تبقى مضاعفة ومستحقة لكن الحساب لا يُوقف
      update public.instant_attendance_penalties
         set escalation_level = 'doubled',
             current_amount = 500.00,
             notes = coalesce(notes || ' | ', '') || 'الحساب محمي من الإيقاف — الغرامة مستحقة',
             updated_at = now()
       where id = v_rec.id
         and status <> 'cancelled';
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

    -- 2) غلق الحساب ووقف الموظف عن العمل
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


-- ═══════════════════════════════════════════════════════════════════════
-- 4. تحديث trigger حارس الجدول — لا يمنع غرامات يحيى
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.tg_prevent_admin_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- فحص: هل الموظف معفى دائماً من الغرامات؟
  if public.is_employee_penalty_exempt(NEW.employee_id)
     or public.is_employee_attendance_exempt(NEW.employee_id) then

    if TG_OP = 'INSERT' then
      -- منع إدراج أي غرامة جديدة للموظف المعفى تماماً
      raise notice 'tg_prevent_admin_penalty: blocked INSERT for exempt employee %', NEW.employee_id;
      return null;
    elsif TG_OP = 'UPDATE' then
      -- السماح بتحديث الحالة إلى ملغاة فقط
      if NEW.status <> 'cancelled' then
        NEW.status := 'cancelled';
        NEW.cancelled_reason := coalesce(
          nullif(trim(coalesce(NEW.cancelled_reason, '')), ''),
          'إلغاء تلقائي: الموظف معفى من الغرامات بقرار إداري دائم'
        );
      end if;
      return NEW;
    end if;
  end if;
  return NEW;
end;
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 5. تحديث is_employee_penalty_exempt — يحيى ليس معفى (العمود false)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select
    -- الأولوية 1: العلم المباشر في سجل الموظف (ديناميكي بالكامل)
    exists (
      select 1 from public.employees e
      where e.id = p_employee_id
        and e.is_penalty_exempt = true
    )
    -- الأولوية 2: المعفى من الحضور بالكامل (الشيخ محمد + أبو عمار)
    or public.is_employee_attendance_exempt(p_employee_id)
    -- الأولوية 3: طاقم العيادات
    or public.is_clinic_staff_exempt(p_employee_id)
    -- الأولوية 4: قائمة الاستثناءات الصريحة
    or p_employee_id in (
      'cc893835-ceb3-44b8-b4c4-9802c38e3195', -- عبد الملك محمد يوسف
      '41751008-afdd-4537-a6db-05021f1c1e00', -- ياسين طارق الباسل
      'c61c2a26-19db-49fb-ad8b-ace2d8a765af', -- عبدالله احمد نصر
      '8e21d363-f87c-4c80-b06d-1b84a2dd3804', -- هاني احمد نصير
      'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- عبدالعزيز طارق محمود الباسل
      '8c529e5b-112d-45d2-9fb1-721b73086351'  -- محمد عبده رجب مزار
    );
$function$;


-- ═══════════════════════════════════════════════════════════════════════
-- 6. إعادة تحميل PostgREST schema cache
-- ═══════════════════════════════════════════════════════════════════════
notify pgrst, 'reload schema';

commit;
