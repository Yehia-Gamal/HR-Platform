/* 0537_penalty_disputes.sql — نظام الطعن على الغرامات الفورية
   - جدول penalty_disputes (طلب اعتراض → مراجعة HR → قرار)
   - RPCs: submit_penalty_dispute, review_penalty_dispute, get_penalty_disputes
   - إشعارات تلقائية عند الإرسال والقرار
*/
begin;

-- ─── الجدول ────────────────────────────────────────────────────────────────────
create table if not exists public.penalty_disputes (
  id             uuid primary key default gen_random_uuid(),
  penalty_id     uuid not null references public.instant_attendance_penalties(id) on delete cascade,
  employee_id    uuid not null references public.employees(id) on delete cascade,
  reason         text not null,
  status         text not null default 'pending'
                   check (status in ('pending','approved','rejected')),
  reviewed_by    uuid references public.employees(id),
  review_note    text,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table  public.penalty_disputes is 'طلبات الطعن على الغرامات الفورية';
comment on column public.penalty_disputes.status is 'pending → approved/rejected';

alter table public.penalty_disputes enable row level security;

do $$ begin
  create policy "الموظفون يقرأون طعونهم" on public.penalty_disputes
    for select using (employee_id = public.current_employee_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "الموظفون يرسلون طعوناً" on public.penalty_disputes
    for insert with check (employee_id = public.current_employee_id());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "HR يراجع الطعون" on public.penalty_disputes
    for update using (public.current_is_full_access());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "HR يقرأ كل الطعون" on public.penalty_disputes
    for select using (public.current_is_full_access());
exception when duplicate_object then null; end $$;

create index if not exists idx_penalty_disputes_penalty_id on public.penalty_disputes(penalty_id);
create index if not exists idx_penalty_disputes_status on public.penalty_disputes(status);
create index if not exists idx_penalty_disputes_employee_id on public.penalty_disputes(employee_id);

-- ─── RPC: إرسال طعن ──────────────────────────────────────────────────────────
create or replace function public.submit_penalty_dispute(
  p_penalty_id uuid,
  p_reason     text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee_id uuid;
  v_existing    int;
  v_id          uuid;
  v_penalty_status text;
  v_manager_id  uuid;
begin
  v_employee_id := public.current_employee_id();
  if v_employee_id is null then
    raise exception 'غير مصرح';
  end if;

  select status into v_penalty_status
  from public.instant_attendance_penalties
  where id = p_penalty_id;

  if v_penalty_status is null then
    raise exception 'الغرامة غير موجودة';
  end if;

  if v_penalty_status in ('paid','cancelled') then
    raise exception 'لا يمكن الطعن على غرامة %', case v_penalty_status when 'paid' then 'مدفوعة' else 'ملغاة' end;
  end if;

  select count(*) into v_existing
  from public.penalty_disputes
  where penalty_id = p_penalty_id and status = 'pending';

  if v_existing > 0 then
    raise exception 'يوجد طعن معلق بالفعل على هذه الغرامة';
  end if;

  insert into public.penalty_disputes (penalty_id, employee_id, reason)
  values (p_penalty_id, v_employee_id, p_reason)
  returning id into v_id;

  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select u.id,
         'تم إرسال طعنك',
         'تم استلام طعنك على الغرامة. سيتم مراجعته من قِبَل الموارد البشرية.',
         'system', 'normal',
         'penalty_dispute', v_id,
         '/me/penalties',
         jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
  from public.employees e
  join auth.users u on u.id = e.user_id
  where e.id = v_employee_id;

  select e2.id into v_manager_id
  from public.employees e1
  left join public.employees e2 on e2.id = e1.direct_manager_id
  where e1.id = v_employee_id;

  if v_manager_id is not null then
    insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
    select u.id,
           'طعن جديد على غرامة',
           'أرسل موظف طعناً على غرامة حضور. راجع التفاصيل.',
           'system', 'high',
           'penalty_dispute', v_id,
           '/admin/finance?tab=instant-penalties',
           jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
    from public.employees e
    join auth.users u on u.id = e.user_id
    where e.id = v_manager_id;
  end if;

  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select u.id,
         'طعن جديد على غرامة',
         'أرسل موظف طعناً على غرامة حضور. يرجى المراجعة.',
         'system', 'high',
         'penalty_dispute', v_id,
         '/admin/finance?tab=instant-penalties',
         jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
  from public.employees e
  join auth.users u on u.id = e.user_id
  where public.user_has_permission(u.id, 'payroll.run.manage');

  return v_id;
end;
$$;

-- ─── RPC: مراجعة الطعن ──────────────────────────────────────────────────────
create or replace function public.review_penalty_dispute(
  p_dispute_id  uuid,
  p_status      text,
  p_review_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dispute record;
begin
  if not public.current_is_full_access() then
    raise exception 'غير مصرح — يتطلب صلاحيات كاملة';
  end if;

  if p_status not in ('approved','rejected') then
    raise exception 'الحالة غير صحيحة';
  end if;

  select d.*, e.user_id as employee_user_id, ip.status as penalty_status
  into v_dispute
  from public.penalty_disputes d
  join public.employees e on e.id = d.employee_id
  join public.instant_attendance_penalties ip on ip.id = d.penalty_id
  where d.id = p_dispute_id;

  if v_dispute is null then
    raise exception 'الطعن غير موجود';
  end if;

  if v_dispute.status != 'pending' then
    raise exception 'تم مراجعة هذا الطعن بالفعل';
  end if;

  update public.penalty_disputes
  set status      = p_status,
      reviewed_by = (select id from public.employees where user_id = auth.uid() limit 1),
      review_note = p_review_note,
      reviewed_at = now(),
      updated_at  = now()
  where id = p_dispute_id;

  if p_status = 'approved' then
    update public.instant_attendance_penalties
    set status      = 'cancelled',
        updated_at  = now(),
        cancelled_reason = 'قُبل الطعن: ' || coalesce(p_review_note, 'بدون ملاحظات')
    where id = v_dispute.penalty_id;
  end if;

  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select v_dispute.employee_user_id,
         case p_status when 'approved' then 'طعنك مقبول' else 'طعنك مرفوض' end,
         case p_status
           when 'approved' then 'تم قبول طعنك وإلغاء الغرامة.'
           else 'تم رفض طعنك. ' || coalesce(p_review_note, '')
         end,
         'system',
         case p_status when 'approved' then 'high' else 'normal' end,
         'penalty_dispute', p_dispute_id,
         '/me/penalties',
         jsonb_build_object('penalty_id', v_dispute.penalty_id, 'dispute_id', p_dispute_id, 'action', 'reviewed', 'result', p_status)
  from auth.users u
  where u.id = v_dispute.employee_user_id;
end;
$$;

-- ─── RPC: جلب الطعون ──────────────────────────────────────────────────────────
create or replace function public.get_penalty_disputes(
  p_status text default null
)
returns table (
  id             uuid,
  penalty_id     uuid,
  employee_id    uuid,
  employee_name  text,
  department     text,
  penalty_date   date,
  penalty_amount numeric,
  reason         text,
  status         text,
  reviewed_by    uuid,
  reviewer_name  text,
  review_note    text,
  reviewed_at    timestamptz,
  created_at     timestamptz
)
language sql
security definer
set search_path = ''
stable
as $$
  select
    d.id, d.penalty_id, d.employee_id,
    e.full_name_ar, dep.name, ip.work_date, ip.current_amount,
    d.reason, d.status, d.reviewed_by, re.full_name_ar,
    d.review_note, d.reviewed_at, d.created_at
  from public.penalty_disputes d
  join public.employees e on e.id = d.employee_id
  left join public.departments dep on dep.id = e.department_id
  join public.instant_attendance_penalties ip on ip.id = d.penalty_id
  left join public.employees re on re.id = d.reviewed_by
  where (p_status is null or d.status = p_status)
  order by
    case d.status when 'pending' then 0 when 'approved' then 1 else 2 end,
    d.created_at desc;
$$;

grant execute on function public.submit_penalty_dispute(uuid, text) to authenticated;
grant execute on function public.review_penalty_dispute(uuid, text, text) to authenticated;
grant execute on function public.get_penalty_disputes(text) to authenticated;

commit;
