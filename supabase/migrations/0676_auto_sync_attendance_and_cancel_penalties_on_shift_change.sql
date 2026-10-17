-- ==============================================================================
-- Migration 0676: Auto-Sync Attendance and Auto-Cancel Penalties on Shift Change
-- ==============================================================================
-- المشكلة:
-- عند تغيير وردية عمل موظف (سواء عبر طلب تغيير وردية معتمد، أو التثبيت الفوري للوردية
-- adopt_my_work_shift، أو التعيين الإداري المباشر)، إذا كان الموظف قد سجل حضوره بالفعل
-- لليوم قبل اعتماد الوردية، كان النظام يحتفظ بدقائق التأخير والغرامة الفورية المحسوبة
-- استناداً للوردية القديمة، رغم أن الموظف حضر في موعد الوردية الجديدة المعتمدة أو قبلها.
--
-- الحل:
-- 1) إنشاء Trigger موحد على جدول shift_assignments عند إسناد أو تفعيل وردية جديدة:
--    - يعيد احتساب دقائق التأخير attendance_policy_late_minutes بناءً على الوردية الجديدة.
--    - يحدّث سجل attendance_daily لليوم (shift_id, late_minutes, status).
--    - يحدّث أحداث الحضور attendance_events (late_minutes).
--    - في حال أصبح التأخير 0 (أو أقل من حد الغرامة):
--      يُلغي فوراً الغرامة المسجلة في instant_attendance_penalties بحالة 'cancelled'
--      مع توثيق سبب الإلغاء، وإرسال إشعار فوري للموظف.
-- ==============================================================================

create or replace function public.sync_attendance_on_shift_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_rec record;
  v_new_late integer;
  v_shift public.shifts%rowtype;
begin
  -- يعمل عند تفعيل تعيين وردية نشط
  if NEW.is_active = true and NEW.shift_id is not null then
    select * into v_shift from public.shifts where id = NEW.shift_id;
    if v_shift.id is not null then
      -- فحص سجلات الحضور اليومي الواقعة ضمن فترة سريان الوردية (خلال الأيام الأخيرة واليوم الحالي)
      for v_rec in (
        select ad.*
        from public.attendance_daily ad
        where ad.employee_id = NEW.employee_id
          and ad.work_date >= greatest(NEW.effective_from, v_today - interval '7 days')
          and (NEW.effective_to is null or ad.work_date <= NEW.effective_to)
          and ad.work_date <= v_today
          and ad.first_check_in is not null
      ) loop
        -- 1) إعادة احتساب دقائق التأخير بناءً على الوردية الجديدة وسياسات التأخير
        begin
          v_new_late := public.attendance_policy_late_minutes(
            v_rec.employee_id,
            v_rec.work_date,
            v_rec.first_check_in,
            NEW.shift_id
          );
        exception when others then
          v_new_late := 0;
        end;

        -- 2) تحديث سجل attendance_daily
        update public.attendance_daily
        set shift_id = NEW.shift_id,
            late_minutes = v_new_late,
            status = case 
              when v_rec.work_minutes >= 480 then 'present'
              when v_new_late > 0 then 'late' 
              else 'present' 
            end,
            updated_at = now()
        where id = v_rec.id;

        -- 3) تحديث حدث بصمة الحضور في attendance_events
        update public.attendance_events
        set late_minutes = v_new_late
        where employee_id = v_rec.employee_id
          and event_at >= (v_rec.work_date::timestamp at time zone 'Africa/Cairo')
          and event_at < ((v_rec.work_date + 1)::timestamp at time zone 'Africa/Cairo')
          and event_type = 'CHECK_IN';

        -- 4) إذا انتفى التأخير، إسقاط الغرامة الفورية تلقائياً
        if v_new_late = 0 then
          update public.instant_attendance_penalties
          set status = 'cancelled',
              cancelled_reason = 'إلغاء تلقائي: اعتماد وردية عمل جديدة (' || coalesce(v_shift.name, '') || ') والحضور في الموعد المحدد',
              updated_at = now()
          where employee_id = v_rec.employee_id
            and work_date = v_rec.work_date
            and status in ('pending_payment', 'doubled');

          -- إشعار الموظف بإلغاء الغرامة
          begin
            perform public.notify_employee(
              v_rec.employee_id,
              'إلغاء غرامة التأخير',
              'تم إلغاء غرامة التأخير تلقائياً لتاريخ ' || to_char(v_rec.work_date, 'YYYY-MM-DD') || ' لاعتماد وردية العمل (' || coalesce(v_shift.name, '') || ') وحضورك في الموعد.',
              'attendance', 'normal', 'attendance', null,
              jsonb_build_object('type', 'penalty_cancelled_shift_change', 'workDate', v_rec.work_date, 'shiftId', NEW.shift_id)
            );
          exception when others then
            -- عدم تعطيل المعاملة في حال حدوث أي خطأ في الإشعار
            null;
          end;
        end if;
      end loop;
    end if;
  end if;

  return NEW;
end;
$$;

-- إسقاط التريجر إن وجد مسبقاً ثم إنشاؤه
drop trigger if exists trg_sync_attendance_on_shift_assignment on public.shift_assignments;
create trigger trg_sync_attendance_on_shift_assignment
  after insert or update of shift_id, is_active, effective_from, effective_to
  on public.shift_assignments
  for each row
  execute function public.sync_attendance_on_shift_assignment_change();

comment on function public.sync_attendance_on_shift_assignment_change() is
  '0676: إعادة احتساب التأخير وإسقاط الغرامات تلقائياً عند اعتماد أو تغيير وردية العمل للموظف.';
