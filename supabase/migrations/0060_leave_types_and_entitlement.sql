-- =====================================================================
-- 0060: أنواع الإجازات القانونية + الكوتا + قاعدة الـ30 يومًا + إعدادات التصعيد
-- =====================================================================
-- المرجع: المواصفة الرسمية لنظام الإجازات (البنود 1، وقانون العمل المصري).
--   البند 1: حذف آمن لإجازتي «الوضع» و«رعاية الطفل» — لا تُزرعان، ودالة
--            حارس ترفض إنشاء أي نوع بهذين الكودين، مع تعطيل أي صف تاريخي
--            (is_active=false) دون حذف السجلات القديمة أو طلباتها.
--   الكوتا: اعتيادية 15، عارضة/طارئة 6، مرضية «يومان شهريًا» = 24/سنة.
--   قاعدة الـ30: من تعدّى 50 سنة أو تخطّت مدة عمله/تأمينه 10 سنوات يحصل
--                على 30 يومًا سنويًا (20 اعتيادية + 10 عارضة) بدل (15 + 6).
--   الإعدادات: مهلة تصعيد قرار الإجازة + دور المُصعَّد إليه + دور الإشعار.
-- ملاحظات معمارية:
--   * أعمدة العمر/التعيين موجودة على employees: birth_date, hire_date (0004).
--   * لا يوجد عمود لأقدمية التأمين؛ نعتمد hire_date كوكيل لمدة العمل/التأمين.
--   * كل شيء idempotent: on conflict(code) للأنواع، on conflict(key) للإعدادات.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الأنواع القانونية الأربعة (زرع idempotent)
--    annual = اعتيادية، casual = عارضة/طارئة، sick = مرضية، unpaid = بدون أجر.
--    ملاحظة: النظام القديم استخدم كود 'emergency' للعارضة؛ نضيف 'casual'
--    وندمج أي رصيد/أثر قديم منطقيًا عبر خريطة التوافق في 0061.
-- ---------------------------------------------------------------------
insert into public.leave_types
  (code, name_ar, name_en, description, is_paid, requires_attachment,
   max_days_per_year, min_notice_days, affects_balance, monthly_accrual_units,
   sort_order, is_active)
values
  ('annual', 'إجازة اعتيادية', 'Annual Leave',
   'الإجازة السنوية الاعتيادية وفق قانون العمل المصري.',
   true, false, 15, 0, true, 0, 10, true),
  ('casual', 'إجازة عارضة (طارئة)', 'Casual (Emergency) Leave',
   'إجازة عارضة/طارئة تُنفَّذ مباشرة دون موافقة المدير المباشر.',
   true, false, 6, 0, true, 0, 20, true),
  ('sick', 'إجازة مرضية', 'Sick Leave',
   'إجازة مرضية بمعدل يومين شهريًا (24 يومًا سنويًا).',
   true, true, 24, 0, true, 2, 30, true),
  ('unpaid', 'إجازة بدون أجر', 'Unpaid Leave',
   'إجازة بدون أجر لا تُحتسب ضمن الرصيد المدفوع.',
   false, false, null, 0, false, 0, 40, true)
on conflict (code) do update set
  name_ar             = excluded.name_ar,
  name_en             = excluded.name_en,
  description         = excluded.description,
  is_paid            = excluded.is_paid,
  requires_attachment = excluded.requires_attachment,
  max_days_per_year  = excluded.max_days_per_year,
  affects_balance    = excluded.affects_balance,
  monthly_accrual_units = excluded.monthly_accrual_units,
  sort_order         = excluded.sort_order,
  is_active          = true,
  updated_at         = now();

-- ---------------------------------------------------------------------
-- 2) حذف آمن للوضع/رعاية الطفل (البند 1)
--    تعطيل أي صف تاريخي إن وُجد؛ لا نحذف السجلات ولا طلباتها التاريخية.
-- ---------------------------------------------------------------------
update public.leave_types
  set is_active = false, updated_at = now()
  where code in ('maternity', 'childcare', 'child_care', 'maternity_leave',
                 'وضع', 'رعاية_طفل')
    and is_active = true;

-- ---------------------------------------------------------------------
-- 3) دالة حارس: منع إنشاء/تفعيل أنواع الوضع أو رعاية الطفل مستقبلًا.
--    تعمل قبل الإدراج والتحديث على leave_types.
-- ---------------------------------------------------------------------
create or replace function public.tg_block_disabled_leave_types()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_blocked constant text[] := array[
    'maternity','childcare','child_care','maternity_leave','وضع','رعاية_طفل'
  ];
begin
  -- نسمح فقط بإبقائها معطّلة (is_active=false)؛ نمنع تفعيلها أو إنشاءها نشطة.
  if new.code = any (v_blocked) and coalesce(new.is_active, true) = true then
    raise exception 'LEAVE_TYPE_DISABLED_BY_POLICY: % (إجازة الوضع/رعاية الطفل ملغاة بالسياسة)', new.code
      using errcode = '42501';
  end if;
  return new;
end $$;

comment on function public.tg_block_disabled_leave_types() is
  'حارس السياسة: يمنع إنشاء/تفعيل أنواع إجازة الوضع ورعاية الطفل (البند 1 من المواصفة).';

drop trigger if exists trg_block_disabled_leave_types on public.leave_types;
create trigger trg_block_disabled_leave_types
  before insert or update on public.leave_types
  for each row execute function public.tg_block_disabled_leave_types();

-- ---------------------------------------------------------------------
-- 4) قاعدة الـ30 يومًا: الاستحقاق السنوي الفعّال للموظف.
--    يُرجع jsonb: { total, annual, casual, elevated(bool), reason }.
--      elevated=true عندما (العمر > 50) أو (مدة العمل/التأمين > 10 سنوات).
--      elevated → 30 (20 اعتيادية + 10 عارضة)، غير ذلك → 21 (15 + 6).
--    ملاحظة: المرضية ثابتة (24) ولا تتأثر بهذه القاعدة.
-- ---------------------------------------------------------------------
create or replace function public.effective_annual_entitlement(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_birth date;
  v_hire  date;
  v_age_years numeric;
  v_tenure_years numeric;
  v_elevated boolean := false;
  v_reason text := 'standard';
begin
  select birth_date, hire_date into v_birth, v_hire
  from public.employees where id = p_employee_id;

  if v_birth is not null then
    v_age_years := extract(year from age(p_as_of, v_birth));
  end if;
  if v_hire is not null then
    v_tenure_years := extract(year from age(p_as_of, v_hire));
  end if;

  if coalesce(v_age_years, 0) > 50 then
    v_elevated := true;
    v_reason := 'age_over_50';
  elsif coalesce(v_tenure_years, 0) > 10 then
    v_elevated := true;
    v_reason := 'tenure_over_10y';
  end if;

  if v_elevated then
    return jsonb_build_object(
      'total', 30, 'annual', 20, 'casual', 10,
      'elevated', true, 'reason', v_reason);
  end if;

  return jsonb_build_object(
    'total', 21, 'annual', 15, 'casual', 6,
    'elevated', false, 'reason', v_reason);
end $$;

comment on function public.effective_annual_entitlement(uuid, date) is
  'الاستحقاق السنوي الفعّال (قانون العمل المصري): 30 يومًا (20+10) لمن تعدّى 50 سنة أو 10 سنوات عمل، وإلا 21 (15+6). المرضية 24 ثابتة.';

revoke execute on function public.effective_annual_entitlement(uuid, date) from public;
grant execute on function public.effective_annual_entitlement(uuid, date) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5) فتح الرصيد السنوي وفق الاستحقاق الفعّال (opening entries idempotent).
--    يُشغّل بواسطة service_role/full-access (بداية السنة أو عند التعيين).
--    يمنح اعتيادية + عارضة حسب effective_annual_entitlement، ومرضية = 24.
-- ---------------------------------------------------------------------
create or replace function public.open_annual_leave_entitlement(
  p_employee_id uuid,
  p_year integer default extract(year from (now() at time zone 'Africa/Cairo'))::integer
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ent jsonb;
  v_annual_id uuid;
  v_casual_id uuid;
  v_sick_id uuid;
  v_count integer := 0;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  v_ent := public.effective_annual_entitlement(p_employee_id, make_date(p_year, 1, 1));
  select id into v_annual_id from public.leave_types where code = 'annual' and is_active;
  select id into v_casual_id from public.leave_types where code = 'casual' and is_active;
  select id into v_sick_id   from public.leave_types where code = 'sick'   and is_active;

  if v_annual_id is not null then
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_annual_id, p_year, 'opening',
      (v_ent->>'annual')::numeric,
      format('leave:opening:annual:%s:%s', p_employee_id, p_year),
      null, 'فتح رصيد الإجازة الاعتيادية السنوي',
      jsonb_build_object('entitlement', v_ent));
    v_count := v_count + 1;
  end if;

  if v_casual_id is not null then
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_casual_id, p_year, 'opening',
      (v_ent->>'casual')::numeric,
      format('leave:opening:casual:%s:%s', p_employee_id, p_year),
      null, 'فتح رصيد الإجازة العارضة السنوي',
      jsonb_build_object('entitlement', v_ent));
    v_count := v_count + 1;
  end if;

  if v_sick_id is not null then
    perform public.apply_leave_ledger_entry(
      p_employee_id, v_sick_id, p_year, 'opening', 24,
      format('leave:opening:sick:%s:%s', p_employee_id, p_year),
      null, 'فتح رصيد الإجازة المرضية السنوي (24 يومًا)',
      jsonb_build_object('annualSick', 24));
    v_count := v_count + 1;
  end if;

  perform public.log_audit_event(
    'leave.entitlement.opened', 'workflow', 'info',
    'leave_balance_accounts', p_employee_id,
    'فتح الرصيد السنوي للإجازات',
    format('السنة %s', p_year),
    jsonb_build_object('year', p_year, 'entitlement', v_ent));
  return v_count;
end $$;

comment on function public.open_annual_leave_entitlement(uuid, integer) is
  'فتح رصيد الإجازات السنوي (اعتيادية/عارضة حسب الاستحقاق الفعّال + مرضية 24) — service_role/full-access، idempotent.';

revoke execute on function public.open_annual_leave_entitlement(uuid, integer) from public, authenticated;
grant execute on function public.open_annual_leave_entitlement(uuid, integer) to service_role;

-- ---------------------------------------------------------------------
-- 6) إعدادات التصعيد (system_settings) — قابلة للتعديل من السكرتير التنفيذي.
--    * leave_approval_escalation_hours: مهلة قرار المدير المباشر قبل التصعيد.
--    * leave_escalation_target_role: دور المُصعَّد إليه (افتراضي ضابط العمليات).
--    * leave_escalation_notify_role: دور الإشعار عند التصعيد (السكرتير التنفيذي).
--    * executive_director_role: دور المدير التنفيذي (الشيخ محمد) — لتحديد مسار
--      «بالإنابة» دون تثبيت شخص في الكود.
-- ---------------------------------------------------------------------
insert into public.system_settings (key, value, value_type, group_name, label_ar, description, is_editable)
values
  ('leave_approval_escalation_hours', '24'::jsonb, 'number', 'requests',
   'مهلة تصعيد قرار الإجازة (ساعات)',
   'عدد الساعات قبل تصعيد طلب الإجازة إذا لم يتخذ المدير المباشر قرارًا.', true),
  ('leave_escalation_target_role', '"operations-officer"'::jsonb, 'string', 'requests',
   'دور المُصعَّد إليه',
   'الدور الذي يُوجَّه إليه الطلب عند انتهاء مهلة المدير المباشر.', true),
  ('leave_escalation_notify_role', '"executive-secretary"'::jsonb, 'string', 'requests',
   'دور الإشعار عند التصعيد',
   'الدور الذي يُشعَر عند تصعيد أي طلب (السكرتير التنفيذي).', true),
  ('executive_director_role', '"executive-director"'::jsonb, 'string', 'requests',
   'دور المدير التنفيذي',
   'دور المدير التنفيذي لتحديد مسار القرار بالإنابة عند تأخره.', true)
on conflict (key) do update set
  label_ar    = excluded.label_ar,
  description = excluded.description,
  updated_at  = now();

-- =====================================================================
-- نهاية Migration 0060
-- =====================================================================
