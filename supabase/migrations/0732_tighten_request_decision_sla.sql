-- Migration 0732: Tighten request decision SLA to realistic business hours
-- تقليص مهلة البت للمدير المباشر من 48 ساعة عمل (أكثر من 5 أيام) إلى 12 ساعة عمل (~يوم عمل وثلث)
-- وضبط مهلة التصعيد إلى 24 ساعة عمل لمنع تعطل مصالح الموظفين والعمليات

begin;

-- 1) تحديث التريجر / الإجراء الخاص بضبط مهل الطلبات الجديدة
create or replace function public.tg_set_request_decision_due_at()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.decision_due_at is null then
    -- 12 ساعة عمل رسمية للمدير المباشر (Africa/Cairo)
    new.decision_due_at := public.calculate_business_deadline(coalesce(new.created_at, now()), 12);
  end if;
  if new.escalation_deadline is null then
    -- 24 ساعة عمل رسمية للتصعيد التلقائي
    new.escalation_deadline := public.calculate_business_deadline(coalesce(new.created_at, now()), 24);
  end if;
  return new;
end;
$$;

-- 2) تحديث دالة submit_request لضمان ضبط المهل المنطقية (12 و24 ساعة عمل)
create or replace function public.submit_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb,
  p_client_id uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_mgr uuid;
  v_rec public.requests;
  v_due timestamptz;
  v_esc timestamptz;
  v_created_at timestamptz := now();
  v_wf_def_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- حساب مهلة البت (12 ساعة عمل رسمية) ومهلة التصعيد (24 ساعة عمل)
  v_due := public.calculate_business_deadline(v_created_at, 12);
  v_esc := public.calculate_business_deadline(v_created_at, 24);

  -- جلب المدير المباشر
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = v_me
    and relation_type = 'primary'
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc nulls last
  limit 1;

  insert into public.requests (
    request_type,
    employee_id,
    manager_employee_id,
    status,
    workflow_status,
    title,
    reason,
    decision_due_at,
    escalation_deadline,
    payload,
    created_at,
    updated_at
  ) values (
    p_request_type,
    v_me,
    v_mgr,
    'pending',
    'submitted',
    p_title,
    p_reason,
    v_due,
    v_esc,
    p_payload,
    v_created_at,
    v_created_at
  )
  returning * into v_rec;

  return v_rec;
end;
$$;

-- 3) تحديث المهل للطلبات المعلقة الحالية لتطابق 12 و24 ساعة عمل
update public.requests r
set decision_due_at = public.calculate_business_deadline(r.created_at, 12),
    escalation_deadline = public.calculate_business_deadline(r.created_at, 24)
where r.status = 'pending';

-- تحديث خطوات الطلبات المعلقة المتأثرة
update public.request_steps s
set due_at = public.calculate_business_deadline(s.created_at, 12),
    escalation_deadline = public.calculate_business_deadline(s.created_at, 24)
from public.requests r
where s.request_id = r.id
  and r.status = 'pending'
  and s.status in ('active', 'pending');

commit;
