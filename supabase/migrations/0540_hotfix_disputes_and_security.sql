/* 0540_hotfix_disputes_and_security.sql — إصلاحات حرجة بعد المراجعة الشاملة
   C1: إضافة عمود cancelled_reason
   C2: إصلاح user_has_permission → استبدال بال查询 المباشر
   H1: إزالة perm من anon على الدوال التنفيذية
   H2: إضافة updated_at trigger على penalty_disputes
   M1: إضافة error codes في 0537
*/
begin;

-- ─── C1: إضافة عمود cancelled_reason ────────────────────────────────────────
ALTER TABLE public.instant_attendance_penalties
  ADD COLUMN IF NOT EXISTS cancelled_reason text;

-- ─── H1: إزالة perm من anon ─────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.generate_executive_daily_digest(date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_punctuality_champions(date) FROM anon;

-- ─── H2: updated_at trigger على penalty_disputes ────────────────────────────
DO $$ BEGIN
  CREATE TRIGGER trg_penalty_disputes_updated_at
    BEFORE UPDATE ON public.penalty_disputes
    FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── C2 + M1: إعادة بناء submit_penalty_dispute مع إصلاح الدوال ────────────
CREATE OR REPLACE FUNCTION public.submit_penalty_dispute(
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
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  select status into v_penalty_status
  from public.instant_attendance_penalties
  where id = p_penalty_id;

  if v_penalty_status is null then
    raise exception 'الغرامة غير موجودة' using errcode = 'P0002';
  end if;

  if v_penalty_status in ('paid','cancelled') then
    raise exception 'لا يمكن الطعن على غرامة %', case v_penalty_status when 'paid' then 'مدفوعة' else 'ملغاة' end
      using errcode = '22023';
  end if;

  select count(*) into v_existing
  from public.penalty_disputes
  where penalty_id = p_penalty_id and status = 'pending';

  if v_existing > 0 then
    raise exception 'يوجد طعن معلق بالفعل على هذه الغرامة' using errcode = '22023';
  end if;

  insert into public.penalty_disputes (penalty_id, employee_id, reason)
  values (p_penalty_id, v_employee_id, p_reason)
  returning id into v_id;

  -- إشعار الموظف
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

  -- إشعار المدير المباشر
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

  -- إشعار HR (بدالة user_has_permission → استعلام مباشر)
  insert into public.notifications (recipient_user_id, title, body, category, priority, entity_type, entity_id, action_url, metadata)
  select u.id,
         'طعن جديد على غرامة',
         'أرسل موظف طعناً على غرامة حضور. يرجى المراجعة.',
         'system', 'high',
         'penalty_dispute', v_id,
         '/admin/finance?tab=instant-penalties',
         jsonb_build_object('penalty_id', p_penalty_id, 'dispute_id', v_id, 'action', 'submitted')
  from auth.users u
  where exists (
    select 1 from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = u.id and p.code = 'payroll.run.manage'
  );

  return v_id;
end;
$$;

-- ─── review_penalty_dispute مع إصلاح cancelled_reason ───────────────────────
CREATE OR REPLACE FUNCTION public.review_penalty_dispute(
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
    raise exception 'غير مصرح — يتطلب صلاحيات كاملة' using errcode = '42501';
  end if;

  if p_status not in ('approved','rejected') then
    raise exception 'الحالة غير صحيحة — يجب أن تكون approved أو rejected' using errcode = '22023';
  end if;

  select d.*, e.user_id as employee_user_id, ip.status as penalty_status
  into v_dispute
  from public.penalty_disputes d
  join public.employees e on e.id = d.employee_id
  join public.instant_attendance_penalties ip on ip.id = d.penalty_id
  where d.id = p_dispute_id;

  if v_dispute is null then
    raise exception 'الطعن غير موجود' using errcode = 'P0002';
  end if;

  if v_dispute.status != 'pending' then
    raise exception 'تم مراجعة هذا الطعن بالفعل' using errcode = '22023';
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

-- ─── إصلاح bulk operations: تسجيل الأخطاء بدلاً من البتهم ──────────────────
CREATE OR REPLACE FUNCTION public.bulk_confirm_penalty_payments(
  p_penalty_ids uuid[],
  p_notes text default null
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  foreach v_id in array p_penalty_ids loop
    begin
      perform public.confirm_instant_penalty_payment(v_id, p_notes);
      v_count := v_count + 1;
    exception when others then
      raise notice 'bulk confirm failed for %: %', v_id, SQLERRM;
    end;
  end loop;

  return v_count;
end;
$$;

CREATE OR REPLACE FUNCTION public.bulk_cancel_penalties(
  p_penalty_ids uuid[],
  p_reason text
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int := 0;
  v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  foreach v_id in array p_penalty_ids loop
    begin
      perform public.cancel_instant_penalty(v_id, p_reason);
      v_count := v_count + 1;
    exception when others then
      raise notice 'bulk cancel failed for %: %', v_id, SQLERRM;
    end;
  end loop;

  return v_count;
end;
$$;

-- ─── M3: إصلاح query key في useInstantPenalties (يُنشر من الويب) ──────────

commit;
