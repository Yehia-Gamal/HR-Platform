-- migration: 0428
-- description: رصيد بدل الراحة الأسبوعية (weekly_rest_comp) عبر الـ ledger
-- -----------------------------------------------------------------------------
-- الهدف: منح الموظف رصيداً قابلاً للقياس مقابل عمله يوم الجمعة (بدل الراحة
-- الأسبوعي) ثم الحجز والاستهلاك عند تقديم طلب بدل الراحة واعتماده.
--
-- الآلية (دون تغيير affects_balance حتى لا تنكسر اختبارات 0105/0116):
--   1) نوع entry جديد 'credit' في leave_ledger_entries + معالجته في
--      apply_leave_ledger_entry (يُضاف إلى adjusted_units → يظهر في
--      get_my_leave_balances كرصيد متاح).
--   2) trigger على attendance_daily: عمل فعلي يوم الجمعة (isodow=5)
--      → credit +1 بـ source_key معرفي `weekly-rest:credit:<emp>:<date>`
--      (idempotent — لا يتضاعف الرصيد لو تكررت الكتابة/التحديث على نفس اليوم).
--   3) تقديم طلب weekly_rest_comp → reserve بـ source_key
--      `weekly-rest:reserve:<request_id>` (يرفع INSUFFICIENT_LEAVE_BALANCE
--      إن لم يتوفر رصيد مكتسب).
--   4) قرار الطلب:
--      approved    → consume `weekly-rest:consume:<request_id>`
--                    (توافق قديم: إن لم يوجد reserve — طلبات قُدّمت قبل
--                    0428 — لا نستهلك شيئاً حتى لا تنكسر الطلبات القديمة).
--      إلغاء بعد اعتماد → refund (مطابق لـ LEDGER-02 في 0055).
--      rejected/cancelled/withdrawn/expired → release.
--   5) لا backfill تاريخي: الرصيد يُمنح لعمل الجمعة اعتباراً من نشر 0428.
--
-- ملاحظة: طلب بدل راحة ليوم في سنة مختلفة عن سنة عمل الجمعة لا يجد رصيداً
-- في حساب سنة الطلب (يرفع INSUFFICIENT_LEAVE_BALANCE) — يظل HR قادراً على
-- التعديل يدوياً عبر adjust_leave_balance.

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) entry_type: إضافة 'credit' للقيد + دعمه في apply_leave_ledger_entry
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.leave_ledger_entries
  drop constraint if exists leave_ledger_entries_entry_type_check;

alter table public.leave_ledger_entries
  add constraint leave_ledger_entries_entry_type_check
  check (entry_type in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire','credit'
  ));

create or replace function public.apply_leave_ledger_entry(
  p_employee_id   uuid,
  p_leave_type_id uuid,
  p_year          integer,
  p_entry_type    text,   -- opening|accrual|carryover|adjustment|reserve|release|consume|refund|expire|credit
  p_units         numeric,
  p_source_key    text,
  p_request_id    uuid default null,
  p_reason        text default null,
  p_metadata      jsonb default '{}'::jsonb
) returns public.leave_ledger_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_account   public.leave_balance_accounts;
  v_entry     public.leave_ledger_entries;
  v_available numeric;
  v_lock_id   bigint;
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire','credit'
  ) then raise exception 'INVALID_LEAVE_ENTRY_TYPE'; end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'LEAVE_SOURCE_KEY_REQUIRED';
  end if;

  -- ── advisory lock: serialize per (employee, leave_type) ──────────────────
  -- يمنع سباقات reserve/consume المتزامنة (0382).
  v_lock_id := hashtextextended(p_employee_id::text || ':' || p_leave_type_id::text, 0);
  perform pg_advisory_xact_lock(v_lock_id);

  v_account := public.ensure_leave_account(p_employee_id, p_leave_type_id, p_year);

  -- ── idempotency: skip if source_key already processed ────────────────────
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key;
  if found then
    return v_entry; -- already applied — idempotent return
  end if;

  if p_entry_type = 'opening' and v_account.opening_units <> 0 then
    select * into v_entry
    from public.leave_ledger_entries
    where account_id = v_account.id and entry_type = 'opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

  -- ── insert audit entry (unique(source_key) يمنع التكرار عند التزامن) ─────
  insert into public.leave_ledger_entries(
    account_id, employee_id, leave_type_id, request_id, entry_type, units,
    effective_date, reason, source_key, metadata, created_by
  ) values (
    v_account.id, p_employee_id, p_leave_type_id, p_request_id, p_entry_type, p_units,
    current_date, p_reason, p_source_key, coalesce(p_metadata, '{}'::jsonb), auth.uid()
  ) on conflict(source_key) do nothing returning * into v_entry;
  if not found then
    select * into strict v_entry from public.leave_ledger_entries
    where source_key = p_source_key;
    return v_entry;
  end if;

  -- ── apply entry by type على الأعمدة الحقيقية للرصيد ──────────────────────
  if p_entry_type = 'opening' then
    update public.leave_balance_accounts set opening_units = opening_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'accrual' then
    update public.leave_balance_accounts set accrued_units = accrued_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'carryover' then
    update public.leave_balance_accounts set carryover_units = carryover_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'adjustment' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'credit' then
    -- رصيد بدل راحة أسبوعي (0428): يُضاف إلى adjusted_units فيظهر ضمن الرصيد المتاح.
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'reserve' then
    select opening_units + accrued_units + adjusted_units + carryover_units - consumed_units - reserved_units
      into v_available from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'INSUFFICIENT_LEAVE_BALANCE: available=% requested=%', v_available, p_units;
    end if;
    update public.leave_balance_accounts set reserved_units = reserved_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'release' then
    update public.leave_balance_accounts set reserved_units = greatest(0, reserved_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'consume' then
    -- حارس 0382: لا يستهلك أكثر مما حُجز فعلياً
    select reserved_units into v_available
    from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'CONSUME_EXCEEDS_RESERVE: reserved=% requested=% (concurrent modification?)', v_available, p_units;
    end if;
    update public.leave_balance_accounts
      set reserved_units = greatest(0, reserved_units - abs(p_units)),
          consumed_units = consumed_units + abs(p_units),
          updated_at = now()
      where id = v_account.id;
  elsif p_entry_type = 'refund' then
    update public.leave_balance_accounts set consumed_units = greatest(0, consumed_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'expire' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units - abs(p_units), updated_at = now() where id = v_account.id;
  end if;

  return v_entry;
end;
$$;

revoke all on function public.apply_leave_ledger_entry(
  uuid, uuid, integer, text, numeric, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_leave_ledger_entry(
  uuid, uuid, integer, text, numeric, text, uuid, text, jsonb
) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) منح رصيد بدل الراحة: عمل فعلي يوم الجمعة → credit +1
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_weekly_rest_credit_on_attendance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type_id uuid;
  v_year    integer;
begin
  -- الجمعة فقط (isodow=5)
  if extract(isodow from new.work_date) <> 5 then
    return new;
  end if;

  -- عمل فعلي: بصمة دخول/خروج موجودة أو حالة تشير لحضور فعلي
  -- (المصمم أعلاه متطابق مع تعريف 0005+0169: present|late|partial|missing_checkout)
  if new.first_check_in is null
     and new.last_check_out is null
     and new.status not in ('present','late','partial','missing_checkout') then
    return new;
  end if;

  select id into v_type_id
  from public.leave_types
  where code = 'weekly_rest_comp';
  if v_type_id is null then
    return new; -- النوع غير معرّف (بيئة قديمة) — لا نقف ترقية.
  end if;

  v_year := extract(year from new.work_date)::integer;

  -- source_key معرفي لكل (موظف + يوم) → idempotent مهما تكررت التحديثات.
  perform public.apply_leave_ledger_entry(
    new.employee_id, v_type_id, v_year, 'credit', 1,
    'weekly-rest:credit:' || new.employee_id::text || ':' || new.work_date::text,
    null,
    'رصيد بدل راحة أسبوعي عن العمل يوم الجمعة ' || to_char(new.work_date, 'YYYY-MM-DD'),
    jsonb_build_object('workDate', new.work_date::text)
  );

  return new;
end;
$$;

drop trigger if exists trg_weekly_rest_credit on public.attendance_daily;
create trigger trg_weekly_rest_credit
  after insert or update of first_check_in, last_check_out, status
  on public.attendance_daily
  for each row execute function public.tg_weekly_rest_credit_on_attendance();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3) حجز رصيد بدل الراحة عند تقديم الطلب (trg_leave_reserve_on_detail)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_leave_reserve_on_detail()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lt public.leave_types; v_units numeric; v_year integer;
begin
  select * into v_lt from public.leave_types where id = new.leave_type_id;
  if not found then return new; end if;

  v_units := case when new.duration_unit='hour' then coalesce(new.hours_count,0) else coalesce(new.days_count,0) end;
  if v_units <= 0 then raise exception 'INVALID_LEAVE_DURATION'; end if;
  v_year := extract(year from new.start_date)::integer;

  -- بدل الراحة الأسبوعية (0428): حجز من الرصيد المكتسب عن عمل الجمعة.
  if v_lt.code = 'weekly_rest_comp' then
    perform public.apply_leave_ledger_entry(
      new.employee_id, new.leave_type_id, v_year, 'reserve', v_units,
      'weekly-rest:reserve:' || new.request_id, new.request_id,
      'حجز يوم بدل راحة — يتطلب رصيداً مكتسباً من العمل يوم الجمعة',
      jsonb_build_object('durationUnit', new.duration_unit)
    );
    return new;
  end if;

  if not coalesce(v_lt.affects_balance,false) then return new; end if;
  perform public.apply_leave_ledger_entry(new.employee_id,new.leave_type_id,v_year,'reserve',v_units,'leave:reserve:'||new.request_id,new.request_id,'حجز رصيد عند تقديم الطلب',jsonb_build_object('durationUnit',new.duration_unit));
  return new;
end $$;

drop trigger if exists trg_leave_reserve_on_detail on public.leave_requests;
create trigger trg_leave_reserve_on_detail after insert on public.leave_requests
for each row execute function public.tg_leave_reserve_on_detail();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4) تسوية قرار الطلب (tg_leave_settle_on_request_decision) — قاعدة 0055 (LEDGER-02)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_leave_settle_on_request_decision()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lr public.leave_requests; v_lt public.leave_types; v_units numeric; v_year integer; v_has_reserve boolean;
begin
  if new.request_type <> 'leave' or old.status = new.status then return new; end if;
  select * into v_lr from public.leave_requests where request_id=new.id;
  if not found then return new; end if;
  select * into v_lt from public.leave_types where id=v_lr.leave_type_id;
  if not found then return new; end if;

  v_units := case when v_lr.duration_unit='hour' then coalesce(v_lr.hours_count,0) else coalesce(v_lr.days_count,0) end;
  v_year := extract(year from v_lr.start_date)::integer;

  -- بدل الراحة الأسبوعية (0428): consume عند الاعتماد (إن وُجد حجز — توافق
  -- قديم للطلبات المقدمة قبل 0428)، refund عند إلغاء معتمد، release خلاف ذلك.
  if v_lt.code = 'weekly_rest_comp' then
    if new.status='approved' then
      select exists(
        select 1 from public.leave_ledger_entries
        where source_key = 'weekly-rest:reserve:' || new.id
      ) into v_has_reserve;
      if v_has_reserve then
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'consume', v_units,
          'weekly-rest:consume:' || new.id, new.id,
          'استهلاك رصيد بدل الراحة بعد الاعتماد'
        );
      end if;
    elsif new.status in ('rejected','cancelled','withdrawn','expired') then
      if old.status='approved' then
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'refund', v_units,
          'weekly-rest:refund:' || new.id || ':' || new.status, new.id,
          'استرداد رصيد بدل الراحة بعد إلغاء طلب معتمد (' || new.status || ')'
        );
      else
        perform public.apply_leave_ledger_entry(
          v_lr.employee_id, v_lr.leave_type_id, v_year, 'release', v_units,
          'weekly-rest:release:' || new.id || ':' || new.status, new.id,
          'تحرير حجز بدل الراحة بعد ' || new.status
        );
      end if;
    end if;
    return new;
  end if;

  if not coalesce(v_lt.affects_balance,false) then return new; end if;
  if new.status='approved' then
    perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'consume',v_units,'leave:consume:'||new.id,new.id,'خصم الرصيد بعد الاعتماد');
  elsif new.status in ('rejected','cancelled','withdrawn','expired') then
    -- LEDGER-02: إلغاء طلب معتمد → refund؛ إلغاء من حالة معلقة → release.
    if old.status='approved' then
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'refund',v_units,'leave:refund:'||new.id||':'||new.status,new.id,'استرداد الرصيد بعد إلغاء طلب معتمد ('||new.status||')');
    else
      perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'release',v_units,'leave:release:'||new.id||':'||new.status,new.id,'تحرير الحجز بعد '||new.status);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_leave_settle_on_request_decision on public.requests;
create trigger trg_leave_settle_on_request_decision after update of status on public.requests
for each row execute function public.tg_leave_settle_on_request_decision();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5) دالة مساعدة: رصيد بدل الراحة المكتسب لموظف في سنة معينة (للواجهات والاختبارات)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.weekly_rest_credit_available(
  p_employee_id uuid,
  p_year integer default extract(year from current_date)::integer
) returns numeric
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(round(sum(units), 2), 0)
  from public.leave_ledger_entries le
  join public.leave_balance_accounts a on a.id = le.account_id
  where a.employee_id = p_employee_id
    and a.balance_year = p_year
    and le.entry_type = 'credit'
$$;

revoke all on function public.weekly_rest_credit_available(uuid, integer) from public, anon;
grant execute on function public.weekly_rest_credit_available(uuid, integer) to authenticated, service_role;

commit;
