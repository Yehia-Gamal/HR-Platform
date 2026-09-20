-- =====================================================================
-- 0535: الحزمة التطويرية المتقدمة لمنظومة أحلى شباب
-- =====================================================================
-- 1) مسار التظلمات والأعذار اللحظية للغرامات الفورية
-- 2) مسار السداد الإلكتروني (InstaPay / المحافظ) مع إرفاق الإيصالات
-- 3) موجز واتساب الذكي اليومي للإدارة العليا
-- 4) لوحة شرف فرسان الانضباط الشهرية
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) توسيع جدول instant_attendance_penalties بالأعمدة الجديدة
-- ─────────────────────────────────────────────────────────────────────

alter table public.instant_attendance_penalties
  add column if not exists excuse_status text not null default 'none',
  add column if not exists excuse_text text,
  add column if not exists excuse_attachment_url text,
  add column if not exists excuse_submitted_at timestamptz,
  add column if not exists excuse_reviewed_by uuid references public.employees(id) on delete set null,
  add column if not exists excuse_reviewed_at timestamptz,
  add column if not exists excuse_notes text,
  add column if not exists payment_method text not null default 'cash',
  add column if not exists receipt_attachment_url text,
  add column if not exists receipt_submitted_at timestamptz,
  add column if not exists receipt_reference_number text;

-- إضافة قيد فحص حالة العذر وطريقة الدفع إن لم تكن موجودة
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'chk_instant_penalty_excuse_status'
       and conrelid = 'public.instant_attendance_penalties'::regclass
  ) then
    alter table public.instant_attendance_penalties
      add constraint chk_instant_penalty_excuse_status
      check (excuse_status in ('none', 'submitted', 'approved', 'rejected'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'chk_instant_penalty_payment_method'
       and conrelid = 'public.instant_attendance_penalties'::regclass
  ) then
    alter table public.instant_attendance_penalties
      add constraint chk_instant_penalty_payment_method
      check (payment_method in ('cash', 'instapay', 'vodafone_cash', 'bank_transfer', 'wallet'));
  end if;
end $$;

-- فهارس لتحسين سرعة الاستعلام عن الأعذار والإيصالات
create index if not exists idx_instant_penalties_excuse_status
  on public.instant_attendance_penalties(excuse_status)
  where excuse_status <> 'none';

create index if not exists idx_instant_penalties_receipt
  on public.instant_attendance_penalties(receipt_submitted_at)
  where receipt_attachment_url is not null;


-- ─────────────────────────────────────────────────────────────────────
-- 2) دالة تقديم عذر فوري للغرامة (بواسطة الموظف)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.submit_instant_penalty_excuse(
  p_penalty_id uuid,
  p_reason text,
  p_attachment_url text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول لتقديم عذر' using errcode = '42501';
  end if;

  if p_reason is null or trim(p_reason) = '' then
    raise exception 'سبب العذر مطلوب' using errcode = '22023';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  -- التحقق من الهوية: الموظف صاحب الغرامة أو مسؤول كامل الصلاحيات
  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
  end if;

  if v_me is null or (v_row.employee_id <> v_me and not public.current_is_full_access()) then
    raise exception 'غير مصرح لك بتقديم عذر لهذه الغرامة' using errcode = '42501';
  end if;

  if v_row.status in ('paid', 'cancelled') then
    raise exception 'لا يمكن تقديم عذر لغرامة ملغاة أو مسددة مسبقاً' using errcode = '22023';
  end if;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  update public.instant_attendance_penalties
     set excuse_status = 'submitted',
         excuse_text = trim(p_reason),
         excuse_attachment_url = p_attachment_url,
         excuse_submitted_at = now(),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- إشعار مسؤولي الموارد البشرية والإدارة
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '📩 تظلم / عذر جديد لغرامة تأخير',
    coalesce(v_emp_name, 'الموظف') || ' قدم عذراً لغرامة يوم ' || to_char(v_row.work_date, 'YYYY-MM-DD') || ': ' || substring(trim(p_reason) from 1 for 80),
    'instant_penalty_excuse_submitted',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'penaltyId', v_row.id::text,
      'amount', v_row.current_amount,
      'channel', 'instant_penalty_excuse'
    )
  );

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'excuseStatus', v_row.excuse_status,
    'message', 'تم تقديم العذر بنجاح وجارٍ مراجعته من قبل الموارد البشرية'
  );
end;
$$;

grant execute on function public.submit_instant_penalty_excuse(uuid, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 3) دالة مراجعة واعتماد أو رفض العذر (بواسطة الإدارة / HR)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.review_instant_penalty_excuse(
  p_penalty_id uuid,
  p_action text, -- 'approved' or 'rejected'
  p_notes text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_reviewer uuid := public.current_employee_id();
  v_reviewer_name text;
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_was_suspended boolean;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or exists (
         select 1 from public.user_roles ur
         join public.roles r on r.id = ur.role_id
         where ur.user_id = auth.uid()
           and r.slug in ('admin', 'hr-manager', 'hr-specialist', 'executive', 'executive-director', 'general-manager')
       )
       or public.has_any_permission(array['payroll.run.manage', 'attendance.record.manage'])
     ) then
    raise exception 'غير مصرح لك بمراجعة الأعذار والتظلمات' using errcode = '42501';
  end if;

  if p_action not in ('approved', 'rejected') then
    raise exception 'الإجراء غير صالح. يجب أن يكون approved أو rejected' using errcode = '22023';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_reviewer is null and auth.uid() is not null then
    select employee_id into v_reviewer from public.profiles where id = auth.uid();
  end if;

  select full_name_ar into v_reviewer_name
    from public.employees where id = v_reviewer;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  v_was_suspended := (v_row.status = 'suspended');

  if p_action = 'approved' then
    -- قبول العذر -> إلغاء الغرامة فوراً
    update public.instant_attendance_penalties
       set status = 'cancelled',
           excuse_status = 'approved',
           excuse_reviewed_by = v_reviewer,
           excuse_reviewed_at = now(),
           excuse_notes = p_notes,
           notes = coalesce(notes || ' | ', '') || 'تم قبول العذر بواسطة ' || coalesce(v_reviewer_name, 'الإدارة') || coalesce(': ' || p_notes, ''),
           suspension_lifted_at = case when v_was_suspended then now() else suspension_lifted_at end,
           suspension_lifted_by = case when v_was_suspended then v_reviewer else suspension_lifted_by end,
           updated_at = now()
     where id = p_penalty_id
    returning * into v_row;

    -- إذا كان الموظف معلقاً يتم فك التعليق فوراً
    if v_was_suspended then
      update public.employees
         set status = 'active', is_active = true, updated_at = now()
       where id = v_row.employee_id;

      update public.profiles
         set status = 'active', updated_at = now()
       where employee_id = v_row.employee_id;
    end if;

    -- إشعار الموظف بقبول العذر
    perform public.notify_employee(
      v_row.employee_id,
      '✅ تم قبول عذرك وإلغاء الغرامة',
      'وافقت الموارد البشرية على عذرك لغرامة يوم ' || to_char(v_row.work_date, 'YYYY-MM-DD') || ' وتم إلغاء الغرامة بالكامل' ||
        case when v_was_suspended then ' ورفع التعليق عن حسابك.' else '.' end,
      'system',
      'normal',
      'instant_penalty_excuse_approved',
      v_row.id,
      jsonb_build_object('penaltyId', v_row.id::text, 'channel', 'instant_penalty')
    );

    perform public.log_audit_event(
      'instant_penalty.excuse_approved', 'financial', 'info',
      'instant_attendance_penalties', v_row.id,
      'قبول عذر وإلغاء غرامة: ' || coalesce(v_emp_name, 'موظف') || ' — ' || v_row.current_amount || ' ج.م',
      null,
      jsonb_build_object('penaltyId', v_row.id, 'employeeId', v_row.employee_id, 'notes', p_notes)
    );

  else
    -- رفض العذر
    update public.instant_attendance_penalties
       set excuse_status = 'rejected',
           excuse_reviewed_by = v_reviewer,
           excuse_reviewed_at = now(),
           excuse_notes = p_notes,
           notes = coalesce(notes || ' | ', '') || 'تم رفض العذر' || coalesce(': ' || p_notes, ''),
           updated_at = now()
     where id = p_penalty_id
    returning * into v_row;

    -- إشعار الموظف برفض العذر
    perform public.notify_employee(
      v_row.employee_id,
      '❌ تم رفض عذر التأخير',
      'عذراً، لم تتم الموافقة على عذر غرامة يوم ' || to_char(v_row.work_date, 'YYYY-MM-DD') || coalesce(' (السبب: ' || p_notes || ')', '') || '. يرجى سرعة السداد.',
      'system',
      'normal',
      'instant_penalty_excuse_rejected',
      v_row.id,
      jsonb_build_object('penaltyId', v_row.id::text, 'amount', v_row.current_amount, 'channel', 'instant_penalty')
    );

  end if;

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'status', v_row.status,
    'excuseStatus', v_row.excuse_status,
    'message', case when p_action = 'approved' then 'تم قبول العذر وإلغاء الغرامة بنجاح' else 'تم رفض العذر وإشعار الموظف' end
  );
end;
$$;

grant execute on function public.review_instant_penalty_excuse(uuid, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 4) دالة رفع إيصال السداد الإلكتروني (InstaPay / المحفظة)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.submit_instant_penalty_receipt(
  p_penalty_id uuid,
  p_payment_method text,
  p_receipt_url text,
  p_reference_number text default null
)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.instant_attendance_penalties;
  v_emp_name text;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول' using errcode = '42501';
  end if;

  if p_receipt_url is null or trim(p_receipt_url) = '' then
    raise exception 'صورة إيصال التحويل مطلوبة' using errcode = '22023';
  end if;

  select * into v_row
    from public.instant_attendance_penalties
   where id = p_penalty_id;

  if not found then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_me is null and auth.uid() is not null then
    select employee_id into v_me from public.profiles where id = auth.uid();
  end if;

  if v_me is null or (v_row.employee_id <> v_me and not public.current_is_full_access()) then
    raise exception 'غير مصرح لك برفع إيصال لهذه الغرامة' using errcode = '42501';
  end if;

  if v_row.status in ('paid', 'cancelled') then
    raise exception 'الغرامة مدفوعة أو ملغاة بالفعل' using errcode = '22023';
  end if;

  select full_name_ar into v_emp_name
    from public.employees where id = v_row.employee_id;

  update public.instant_attendance_penalties
     set payment_method = coalesce(p_payment_method, 'instapay'),
         receipt_attachment_url = trim(p_receipt_url),
         receipt_reference_number = p_reference_number,
         receipt_submitted_at = now(),
         updated_at = now()
   where id = p_penalty_id
  returning * into v_row;

  -- إشعار مسؤولي الحسابات
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '💳 إيصال سداد إلكتروني جديد',
    coalesce(v_emp_name, 'الموظف') || ' رفع إيصال تحويل (' || coalesce(p_payment_method, 'InstaPay') || ') لسداد غرامة ' || v_row.current_amount || ' ج.م. بانتظار التأكيد.',
    'instant_penalty_receipt_submitted',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'penaltyId', v_row.id::text,
      'amount', v_row.current_amount,
      'channel', 'instant_penalty'
    )
  );

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'receiptUrl', v_row.receipt_attachment_url,
    'message', 'تم رفع إيصال السداد بنجاح وجارٍ التحقق منه من قبل المحاسب'
  );
end;
$$;

grant execute on function public.submit_instant_penalty_receipt(uuid, text, text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 5) دالة إنتاج موجز واتساب الذكي اليومي للإدارة العليا
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.generate_executive_daily_digest(p_date date default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_day_name text;
  v_total_active int := 0;
  v_present int := 0;
  v_missions int := 0;
  v_convoys int := 0;
  v_fandy int := 0;
  v_leaves int := 0;
  v_absent int := 0;
  v_penalties_issued int := 0;
  v_penalties_issued_amount numeric(12,2) := 0.00;
  v_penalties_paid int := 0;
  v_penalties_paid_amount numeric(12,2) := 0.00;
  v_fund_balance numeric(12,2) := 0.00;
  v_missions_list text := '';
  v_text text;
begin
  -- أسماء الأيام بالعربية
  v_day_name := case extract(isodow from v_date)
    when 1 then 'الاثنين'
    when 2 then 'الثلاثاء'
    when 3 then 'الأربعاء'
    when 4 then 'الخميس'
    when 5 then 'الجمعة'
    when 6 then 'السبت'
    when 7 then 'الأحد'
  end;

  -- إجمالي النشطين (باستثناء المعفيين كلياً من الحضور)
  select count(*) into v_total_active
    from public.employees e
   where e.status = 'active' and coalesce(e.is_deleted, false) = false
     and not public.is_employee_attendance_exempt(e.id);

  -- الحضور الفعلي
  select count(distinct ae.employee_id) into v_present
    from public.attendance_events ae
   where ae.event_at::date = v_date and ae.event_type = 'CHECK_IN'
     and not public.is_employee_attendance_exempt(ae.employee_id);

  -- الإجازات
  select count(distinct r.employee_id) into v_leaves
    from public.requests r
   where r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
     and r.status in ('approved', 'completed')
     and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                    and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date);

  -- المأموريات والقوافل والفاندي
  select count(distinct r.employee_id) into v_missions
    from public.requests r
   where r.request_type in ('mission', 'external_mission', 'administrative_mission')
     and r.status in ('approved', 'completed')
     and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                    and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date);

  select count(distinct r.employee_id) into v_convoys
    from public.requests r
   where (r.request_type in ('convoy', 'field_convoy') or coalesce(r.payload->>'missionType', '') = 'convoy')
     and r.status in ('approved', 'completed')
     and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                    and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date);

  select count(distinct r.employee_id) into v_fandy
    from public.requests r
   where (r.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(r.payload->>'missionType', '') = 'fundraising')
     and r.status in ('approved', 'completed')
     and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                    and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date);

  v_absent := greatest(0, v_total_active - v_present - v_leaves - v_missions - v_convoys - v_fandy);

  -- الغرامات الصادرة والمدفوعة لهذا اليوم
  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_issued, v_penalties_issued_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status in ('pending_payment', 'doubled', 'paid');

  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_paid, v_penalties_paid_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status = 'paid';

  -- رصيد صندوق الزمالة الحالي
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0.00)
    into v_fund_balance
    from public.fellowship_fund_transactions;

  -- تجميع أسماء أبرز المتواجدين في مهام ميدانية
  select string_agg('• ' || e.full_name_ar || ' (' || coalesce(q.request_type, 'مهمة') || ')', E'\n')
    into v_missions_list
    from (
      select distinct r.employee_id, r.request_type
        from public.requests r
       where r.request_type in ('mission', 'convoy', 'fundraising')
         and r.status = 'approved'
         and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date)
       limit 5
    ) q
    join public.employees e on e.id = q.employee_id;


  -- صياغة النص التنفيذي المنمق الموجه للإدارة العليا
  v_text :=
    '🌟 *موجز العمليات اليومي — مؤسسة أحلى شباب*' || E'\n' ||
    '📅 *اليوم:* ' || v_day_name || ' ' || to_char(v_date, 'YYYY/MM/DD') || E'\n' ||
    '⏰ *التحديث:* ' || to_char((now() at time zone 'Africa/Cairo'), 'HH12:MI AM') || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '👥 *مؤشرات القوة العاملة والانضباط:*' || E'\n' ||
    '• إجمالي القوة الملزمة: ' || v_total_active || ' موظف' || E'\n' ||
    '• الحضور الفعلي المسجل: ' || v_present || ' زميل ✅' || E'\n' ||
    '• الميدان والقوافل: ' || (v_missions + v_convoys + v_fandy) || ' زميل 🚚' || E'\n' ||
    '• الإجازات المعتمدة: ' || v_leaves || ' زميل 🏖️' || E'\n' ||
    '• نسبة الانضباط العام: ' || round(((v_present + v_missions + v_convoys + v_fandy)::numeric / nullif(v_total_active, 0)) * 100, 1) || '%' || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '💰 *الموقف المالي وصندوق الزمالة والتكافل:*' || E'\n' ||
    '• غرامات التأخير الصادرة: ' || v_penalties_issued || ' (' || v_penalties_issued_amount || ' ج.م)' || E'\n' ||
    '• المحصل والمودع بالصندوق: ' || v_penalties_paid || ' (' || v_penalties_paid_amount || ' ج.م) 🪙' || E'\n' ||
    '• الرصيد الإجمالي التراكمي للصندوق: ' || v_fund_balance || ' ج.م 🏦' || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    case when v_missions_list is not null and v_missions_list <> '' then
      '📍 *الفرق الميدانية في القوافل والمأموريات:*' || E'\n' || v_missions_list || E'\n' || '━━━━━━━━━━━━━━━━━━━━' || E'\n'
    else '' end ||
    '✨ *دمتم ذخراً لشباب الخير وعمار الأرض* 🌿';

  return jsonb_build_object(
    'date', v_date,
    'dayName', v_day_name,
    'totalActive', v_total_active,
    'present', v_present,
    'fieldMissions', (v_missions + v_convoys + v_fandy),
    'leaves', v_leaves,
    'absent', v_absent,
    'penaltiesIssued', v_penalties_issued,
    'penaltiesIssuedAmount', v_penalties_issued_amount,
    'penaltiesPaid', v_penalties_paid,
    'penaltiesPaidAmount', v_penalties_paid_amount,
    'fundBalance', v_fund_balance,
    'digestText', v_text
  );
end;
$$;

grant execute on function public.generate_executive_daily_digest(date) to authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────
-- 6) دالة فرسان الانضباط الشهرية (Gamification)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_punctuality_champions(p_month date default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_start_date date := date_trunc('month', coalesce(p_month, current_date))::date;
  v_end_date date := (date_trunc('month', coalesce(p_month, current_date)) + interval '1 month - 1 day')::date;
  v_champions jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'employeeId', q.employee_id,
      'fullName', q.full_name_ar,
      'employeeCode', q.employee_code,
      'photoUrl', q.photo_url,
      'daysAttended', q.days_attended,
      'totalLateMinutes', q.total_late_minutes,
      'rank', q.rank
    )
  ), '[]'::jsonb)
  into v_champions
  from (
    select e.id as employee_id,
           e.full_name_ar,
           e.employee_code,
           e.photo_url,
           count(distinct ae.event_at::date) as days_attended,
           coalesce(sum(ae.late_minutes), 0) as total_late_minutes,
           row_number() over (order by count(distinct ae.event_at::date) desc, coalesce(sum(ae.late_minutes), 0) asc) as rank
      from public.employees e
      join public.attendance_events ae on ae.employee_id = e.id
     where e.status = 'active'
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_attendance_exempt(e.id)
       and ae.event_type = 'CHECK_IN'
       and ae.event_at::date between v_start_date and v_end_date
       and not exists (
         select 1 from public.instant_attendance_penalties p
          where p.employee_id = e.id
            and p.work_date between v_start_date and v_end_date
            and p.status in ('pending_payment', 'doubled', 'paid')
       )
     group by e.id, e.full_name_ar, e.employee_code, e.photo_url
    having coalesce(sum(ae.late_minutes), 0) = 0
     order by count(distinct ae.event_at::date) desc
     limit 10
  ) q;



  return jsonb_build_object(
    'month', to_char(v_start_date, 'YYYY-MM'),
    'startDate', v_start_date,
    'endDate', v_end_date,
    'champions', v_champions
  );
end;
$$;

grant execute on function public.get_punctuality_champions(date) to authenticated, anon;

commit;
