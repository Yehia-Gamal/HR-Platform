-- ==============================================================================
-- Migration 0683: إصلاح تغيير واعتماد وردية العمل ومنع خطأ 42703 (تعذر تحميل البيانات)
-- ==============================================================================
-- المشكلة:
-- عند محاولة الموظف تغيير ورديته أو تثبيتها (adoptMyWorkShift)، كانت الدالة
-- adopt_my_work_shift تُرجع خطأ PostgreSQL:
-- `ERROR: 42703: record "v_shift" has no field "name_ar"`
-- بسبب محاولة الوصول إلى v_shift.name_ar في حين أن جدول shifts يحتوي على الحقل name.
-- هذا الخطأ (رمز 42703) كان يترجم في تطبيق الموبايل إلى:
-- «تعذر تحميل البيانات. تواصل مع مسؤول النظام.» مما يمنع الموظف من تغيير ورديته.
--
-- الحل:
-- 1) إضافة عمود مولد name_ar في جدول public.shifts كمرادف دائم لـ name (Generated Always as name).
-- 2) تحديث دالة public.adopt_my_work_shift لترجع coalesce(v_shift.name, v_shift.name_ar).
-- ==============================================================================

begin;

-- ─── 1) إضافة عمود name_ar لجدول shifts لضمان التوافق التام ─────────────────
alter table public.shifts
  add column if not exists name_ar text generated always as (name) stored;

-- ─── 2) تحديث دالة adopt_my_work_shift ───────────────────────────────────────
create or replace function public.adopt_my_work_shift(p_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_shift public.shifts%rowtype;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_shift from public.shifts where id = p_shift_id and is_active = true;
  if not found then
    raise exception 'فترة العمل المحددة غير موجودة أو غير مفعلة' using errcode = '22023';
  end if;

  -- 1) إنهاء أي تعيين وردية نشط سابق
  update public.shift_assignments
  set is_active = false,
      effective_to = least(coalesce(effective_to, v_today), v_today),
      updated_at = now()
  where employee_id = v_me and is_active = true;

  -- 2) إسناد الوردية المختارة فوراً للموظف
  insert into public.shift_assignments (
    employee_id, shift_id, effective_from, is_active, notes, created_by
  ) values (
    v_me, p_shift_id, v_today, true,
    'اعتماد وتثبيت فوري بطلب الموظف عند البصمة', auth.uid()
  );

  -- 3) تحديث سجل attendance_daily لليوم فوراً إن وجد
  update public.attendance_daily
  set shift_id = p_shift_id,
      updated_at = now()
  where employee_id = v_me and work_date = v_today;

  -- 4) اعتماد وإغلاق أي طلب تغيير وردية معلق للموظف
  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where employee_id = v_me
    and request_type = 'shift_change'
    and status = 'pending';

  return jsonb_build_object(
    'ok', true,
    'shiftId', v_shift.id,
    'shiftName', coalesce(v_shift.name, v_shift.name_ar, ''),
    'startTime', v_shift.start_time,
    'endTime', v_shift.end_time
  );
end;
$$;

revoke all on function public.adopt_my_work_shift(uuid) from public, anon;
grant execute on function public.adopt_my_work_shift(uuid) to authenticated, service_role;

comment on function public.adopt_my_work_shift(uuid) is
  '0683: تثبيت واعتماد فترة العمل للموظف فورياً مع تصحيح اسم حقل الوردية name/name_ar.';

commit;
