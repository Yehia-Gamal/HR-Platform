-- ═══════════════════════════════════════════════════════════════════════
-- Migration 0515: صندوق الزمالة والتكافل + توريد غرامات التأخير تلقائياً
-- ═══════════════════════════════════════════════════════════════════════

-- 1) جدول حركات صندوق الزمالة والتكافل (Fellowship & Solidarity Fund)
create table if not exists public.fellowship_fund_transactions (
  id                      uuid primary key default gen_random_uuid(),
  transaction_type        text not null check (transaction_type in ('inflow', 'outflow')),
  amount                  numeric(12,2) not null check (amount > 0),
  source_type             text not null default 'instant_penalty'
                            check (source_type in ('instant_penalty', 'manual_deposit', 'donation', 'withdrawal', 'adjustment')),
  instant_penalty_id      uuid references public.instant_attendance_penalties(id) on delete set null,
  employee_id             uuid references public.employees(id) on delete set null,
  employee_name           text not null,
  performed_by            uuid references public.employees(id) on delete set null,
  performer_name          text,
  category                text not null default 'غرامة تأخير حضور',
  reason                  text not null,
  balance_after           numeric(12,2) not null check (balance_after >= 0),
  notes                   text,
  created_at              timestamptz not null default now()
);

comment on table public.fellowship_fund_transactions is
  'سجل الحركات الشفاف لصندوق الزمالة والتكافل: إيداعات غرامات الحضور والانصراف، المساهمات، وسحوبات المساعدات مع توثيق السبب والرصيد المتبقي بعلم الفريق كله.';

-- الفهارس
create index if not exists idx_fellowship_fund_created_at on public.fellowship_fund_transactions(created_at desc);
create index if not exists idx_fellowship_fund_type on public.fellowship_fund_transactions(transaction_type);
create index if not exists idx_fellowship_fund_emp on public.fellowship_fund_transactions(employee_id);
create index if not exists idx_fellowship_fund_penalty on public.fellowship_fund_transactions(instant_penalty_id);

-- RLS: القراءة متاحة لجميع الموظفين النشطين (شفافية كاملة)، والإدخال والتعديل عبر الدوال المعتمدة فقط
alter table public.fellowship_fund_transactions enable row level security;

drop policy if exists p_fellowship_fund_select on public.fellowship_fund_transactions;
create policy p_fellowship_fund_select on public.fellowship_fund_transactions
  for select to authenticated
  using (true);

drop policy if exists p_fellowship_fund_insert on public.fellowship_fund_transactions;
create policy p_fellowship_fund_insert on public.fellowship_fund_transactions
  for insert to authenticated
  with check (
    public.current_is_full_access()
    or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage'])
  );

-- ═══════════════════════════════════════════════════════════════════════
-- 2) دالة مساعدة: بث إشعار فوري لكامل أعضاء الفريق
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public._broadcast_team_notification(
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_emp record;
  v_count integer := 0;
begin
  for v_emp in
    select id
      from public.employees
     where is_deleted = false
       and is_active = true
  loop
    perform public.notify_employee(
      v_emp.id,
      p_title,
      p_body,
      'system',
      'urgent',
      p_entity_type,
      p_entity_id,
      p_metadata
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 3) RPC: جلب ملخص ورصيد صندوق الزمالة وتفنيط المبالغ
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.get_fellowship_fund_summary()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_total_inflow numeric(12,2) := 0.00;
  v_total_outflow numeric(12,2) := 0.00;
  v_current_balance numeric(12,2) := 0.00;
  v_inflow_count integer := 0;
  v_outflow_count integer := 0;
  v_month_start timestamptz := date_trunc('month', now() at time zone 'Africa/Cairo');
  v_monthly_inflow numeric(12,2) := 0.00;
  v_monthly_outflow numeric(12,2) := 0.00;
  v_category_breakdown jsonb;
  v_recent_transactions jsonb;
begin
  -- حساب الإجماليات
  select
    coalesce(sum(case when transaction_type = 'inflow' then amount else 0 end), 0),
    coalesce(sum(case when transaction_type = 'outflow' then amount else 0 end), 0),
    count(case when transaction_type = 'inflow' then 1 end),
    count(case when transaction_type = 'outflow' then 1 end),
    coalesce(sum(case when transaction_type = 'inflow' and created_at >= v_month_start then amount else 0 end), 0),
    coalesce(sum(case when transaction_type = 'outflow' and created_at >= v_month_start then amount else 0 end), 0)
  into
    v_total_inflow,
    v_total_outflow,
    v_inflow_count,
    v_outflow_count,
    v_monthly_inflow,
    v_monthly_outflow
  from public.fellowship_fund_transactions;

  v_current_balance := v_total_inflow - v_total_outflow;

  -- تفنيط المبالغ بحسب الفئة
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', cat.category,
    'type', cat.transaction_type,
    'totalAmount', cat.total_amount,
    'count', cat.tx_count
  )), '[]'::jsonb)
  into v_category_breakdown
  from (
    select
      category,
      transaction_type,
      sum(amount) as total_amount,
      count(*) as tx_count
    from public.fellowship_fund_transactions
    group by category, transaction_type
    order by sum(amount) desc
  ) cat;

  -- آخر 5 حركات
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'transactionType', t.transaction_type,
    'amount', t.amount,
    'sourceType', t.source_type,
    'category', t.category,
    'reason', t.reason,
    'employeeName', t.employee_name,
    'performerName', t.performer_name,
    'balanceAfter', t.balance_after,
    'createdAt', t.created_at
  ) order by t.created_at desc), '[]'::jsonb)
  into v_recent_transactions
  from (
    select * from public.fellowship_fund_transactions
    order by created_at desc
    limit 5
  ) t;

  return jsonb_build_object(
    'currentBalance', v_current_balance,
    'totalInflows', v_total_inflow,
    'totalOutflows', v_total_outflow,
    'inflowsCount', v_inflow_count,
    'outflowsCount', v_outflow_count,
    'monthlyInflows', v_monthly_inflow,
    'monthlyOutflows', v_monthly_outflow,
    'categoryBreakdown', v_category_breakdown,
    'recentTransactions', v_recent_transactions
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 4) RPC: جلب سجل حركات صندوق الزمالة بالتفصيل مع الفلترة
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.get_fellowship_fund_transactions(
  p_limit integer default 50,
  p_offset integer default 0,
  p_type text default null,
  p_search text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', t.id,
      'transactionType', t.transaction_type,
      'amount', t.amount,
      'sourceType', t.source_type,
      'instantPenaltyId', t.instant_penalty_id,
      'employeeId', t.employee_id,
      'employeeName', t.employee_name,
      'performedBy', t.performed_by,
      'performerName', t.performer_name,
      'category', t.category,
      'reason', t.reason,
      'balanceAfter', t.balance_after,
      'notes', t.notes,
      'createdAt', t.created_at
    ) order by t.created_at desc)
    from public.fellowship_fund_transactions t
    where (p_type is null or p_type = 'all' or t.transaction_type = p_type)
      and (
        p_search is null
        or p_search = ''
        or t.employee_name ilike '%' || p_search || '%'
        or t.reason ilike '%' || p_search || '%'
        or t.category ilike '%' || p_search || '%'
        or coalesce(t.performer_name, '') ilike '%' || p_search || '%'
      )
    limit greatest(1, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 5) RPC: تأكيد استلام الغرامة الفورية وإيداعها في صندوق الزمالة
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.confirm_instant_penalty_payment(
  p_penalty_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_my_name text;
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_was_suspended boolean;
  v_current_balance numeric(12,2) := 0.00;
  v_new_balance numeric(12,2) := 0.00;
  v_tx_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  if not (public.current_is_full_access()
          or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات والرواتب' using errcode = '42501';
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

  -- 2) رفع التعليق فوراً إن كان الموظف معلقاً وإعادة تفعيل حسابه
  if v_was_suspended then
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

  -- 3) حساب الرصيد الحالي وإيداع المبلغ في صندوق الزمالة والتكافل
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0)
    into v_current_balance
    from public.fellowship_fund_transactions;

  v_new_balance := v_current_balance + v_row.current_amount;

  insert into public.fellowship_fund_transactions (
    transaction_type,
    amount,
    source_type,
    instant_penalty_id,
    employee_id,
    employee_name,
    performed_by,
    performer_name,
    category,
    reason,
    balance_after,
    notes
  ) values (
    'inflow',
    v_row.current_amount,
    'instant_penalty',
    v_row.id,
    v_row.employee_id,
    coalesce(v_emp_name, 'موظف'),
    v_me,
    coalesce(v_my_name, 'مسؤول النظام'),
    'غرامة تأخير حضور',
    'غرامة تأخير حضور وانصراف ليوم ' || to_char(v_row.work_date, 'YYYY-MM-DD') || ' (' || v_row.late_minutes || ' دقيقة)',
    v_new_balance,
    p_notes
  ) returning id into v_tx_id;

  -- 4) سجل التدقيق
  perform public.log_audit_event(
    'fellowship_fund.deposit', 'financial', 'info',
    'fellowship_fund_transactions', v_tx_id,
    'تم استلام غرامة تأخير من ' || coalesce(v_emp_name, 'موظف') || ' بقيمة ' || v_row.current_amount || ' ج.م وإيداعها في صندوق الزمالة (الرصيد: ' || v_new_balance || ' ج.م)' ||
      case when v_was_suspended then ' — تم رفع التعليق وفتح السيستم وعودته لمباشرة العمل' else '' end,
    null,
    jsonb_build_object(
      'employeeId', v_row.employee_id,
      'penaltyId', v_row.id,
      'amount', v_row.current_amount,
      'newBalance', v_new_balance,
      'wasSuspended', v_was_suspended
    )
  );

  -- 5) إشعار الموظف نفسه والمدير والـ HR
  perform public._notify_instant_penalty_stakeholders(
    v_row.employee_id,
    '✅ تم استلام الغرامة وإيداعها بصندوق الزمالة',
    'تم استلام مبلغ ' || v_row.current_amount || ' ج.م من ' || coalesce(v_emp_name, 'الموظف') || ' وإيداعه في صندوق الزمالة والتكافل' ||
      case when v_was_suspended then ' — تم فتح السيستم ورفع التعليق وعودته لمباشرة العمل.' else '.' end,
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'penaltyId', v_row.id::text,
      'amount', v_row.current_amount,
      'fundBalance', v_new_balance,
      'channel', 'fellowship_fund_deposit'
    )
  );

  -- 6) إرسال إشعار فوري لكامل الفريق بالشفافية المطلوبة (بعلم الفريق كله)
  perform public._broadcast_team_notification(
    '💰 إيداع جديد في صندوق الزمالة والتكافل',
    'تم استلام مبلغ ' || v_row.current_amount || ' ج.م من الزميل ' || coalesce(v_emp_name, 'أحد الزملاء') || ' وإيداعه في صندوق الزمالة (غرامة تأخير حضور). رصيد الصندوق الحالي: ' || v_new_balance || ' ج.م.',
    'fellowship_fund',
    v_tx_id,
    jsonb_build_object(
      'employeeId', v_row.employee_id::text,
      'amount', v_row.current_amount,
      'newBalance', v_new_balance,
      'channel', 'fellowship_fund_deposit',
      'deepLink', 'ahlashabab://action/fellowship-fund'
    )
  );

  return jsonb_build_object(
    'success', true,
    'penaltyId', v_row.id,
    'employeeId', v_row.employee_id,
    'employeeName', v_emp_name,
    'amount', v_row.current_amount,
    'fundBalanceAfter', v_new_balance,
    'wasSuspended', v_was_suspended,
    'transactionId', v_tx_id,
    'message', 'تم استلام المبلغ بنجاح وإيداعه في صندوق الزمالة والتكافل وإشعار الفريق'
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 6) RPC: سحب مبلغ من صندوق الزمالة (للأدمن فقط) مع إشعار الفريق كله
-- ═══════════════════════════════════════════════════════════════════════

create or replace function public.withdraw_from_fellowship_fund(
  p_amount numeric,
  p_category text,
  p_reason text,
  p_beneficiary_employee_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_my_name text;
  v_beneficiary_name text;
  v_current_balance numeric(12,2) := 0.00;
  v_new_balance numeric(12,2) := 0.00;
  v_tx_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بالمستخدم الحالي' using errcode = '42501';
  end if;

  -- الصلاحية: للأدمن والـ HR فقط
  if not (public.current_is_full_access()
          or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'finance.manage'])) then
    raise exception 'غير مسموح: صلاحية الإدارة مطلوبة للسحب من صندوق الزمالة' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'مبلغ السحب يجب أن يكون أكبر من صفر' using errcode = '22023';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'يجب ذكر سبب السحب بالتفصيل لضمان الشفافية' using errcode = '22023';
  end if;

  -- حساب الرصيد المتاح حالياً
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0)
    into v_current_balance
    from public.fellowship_fund_transactions;

  if p_amount > v_current_balance then
    raise exception 'الرصيد المتاح في صندوق الزمالة (% ج.م) لا يكفي لسحب % ج.م', v_current_balance, p_amount using errcode = '22023';
  end if;

  v_new_balance := v_current_balance - p_amount;

  select full_name_ar into v_my_name
    from public.employees where id = v_me;

  if p_beneficiary_employee_id is not null then
    select full_name_ar into v_beneficiary_name
      from public.employees where id = p_beneficiary_employee_id;
  end if;

  -- 1) تسجيل حركة السحب
  insert into public.fellowship_fund_transactions (
    transaction_type,
    amount,
    source_type,
    employee_id,
    employee_name,
    performed_by,
    performer_name,
    category,
    reason,
    balance_after,
    notes
  ) values (
    'outflow',
    p_amount,
    'withdrawal',
    p_beneficiary_employee_id,
    coalesce(v_beneficiary_name, 'صرف عام / دعم مؤسسي'),
    v_me,
    coalesce(v_my_name, 'مسؤول النظام'),
    coalesce(p_category, 'مساعدة زميل'),
    trim(p_reason),
    v_new_balance,
    p_notes
  ) returning id into v_tx_id;

  -- 2) سجل التدقيق
  perform public.log_audit_event(
    'fellowship_fund.withdraw', 'financial', 'warning',
    'fellowship_fund_transactions', v_tx_id,
    'سحب من صندوق الزمالة: تم سحب ' || p_amount || ' ج.م لسبب: ' || p_reason || ' (الرصيد الباقي: ' || v_new_balance || ' ج.م)',
    null,
    jsonb_build_object(
      'amount', p_amount,
      'category', p_category,
      'reason', p_reason,
      'beneficiary', v_beneficiary_name,
      'newBalance', v_new_balance
    )
  );

  -- 3) إشعار فوري لكامل الفريق بعلم الجميع
  perform public._broadcast_team_notification(
    '📢 سحب من صندوق الزمالة والتكافل',
    'إشعار للفريق: تم سحب مبلغ ' || p_amount || ' ج.م من صندوق الزمالة لسبب: (' || trim(p_reason) || '). الرصيد المتبقي في الصندوق الآن: ' || v_new_balance || ' ج.م.',
    'fellowship_fund',
    v_tx_id,
    jsonb_build_object(
      'amount', p_amount,
      'category', p_category,
      'reason', p_reason,
      'newBalance', v_new_balance,
      'channel', 'fellowship_fund_withdrawal',
      'deepLink', 'ahlashabab://action/fellowship-fund'
    )
  );

  return jsonb_build_object(
    'success', true,
    'transactionId', v_tx_id,
    'amount', p_amount,
    'category', p_category,
    'reason', p_reason,
    'balanceAfter', v_new_balance,
    'message', 'تم سحب المبلغ وتوثيق العملية وإشعار كامل الفريق بنجاح'
  );
end;
$$;
