-- =====================================================================
-- 0576: حصر احتساب دقائق التأخير عند ساعتين كحد أقصى (120 دقيقة)
--       وإلغاء أي استثناء من الغرامات للجميع بما فيهم يحيى
--       مع الحماية المطلقة لحساب يحيى من أي وقف للعمل أو غلق للنظام
-- =====================================================================
-- 1) حصر احتساب دقائق التأخير عند ساعتين كحد أقصى (120 دقيقة):
--    - الشريحة القصوى للتأخير تقف عند ساعتين (120 دقيقة = 150 ج.م).
--    - بعد ساعتين يدخل الموظف في إجراءات الغياب/خصم نصف يوم وفق اللائحة،
--      ولكن في احتساب الغرامة الفورية يتوقف العد قطعياً عند 120 دقيقة (ساعتان)
--      ولا يُسجل في النظام 9 ساعات أو 6 ساعات نهائياً.
--    - تصحيح السجلات السابقة التي تجاوزت 120 دقيقة لتصبح 120 دقيقة (ساعتان).
--
-- 2) دورة التصعيد الثلاثية:
--    - اليوم الأول (يوم المخالفة): تسجيل الغرامة الأصلية حسب مدة التأخير (بحد أقصى 150 ج.م).
--    - اليوم الثاني (غداً): في حال عدم السداد تتضاعف الغرامة تلقائياً إلى 500 ج.م.
--    - اليوم الثالث: في حال عدم السداد لليوم الثالث يتم توقيع وقف العمل وغرامة 500 ج.م.
--
-- 3) تراكم الجزاءات اليومية المتتالية بلا استثناء:
--    - إذا تأخر الموظف في اليوم الثاني أو الثالث، تُسجل عليه غرامة تأخير جديدة لليوم الحالي،
--      ولا يُعفى من غرامة اليوم لمجرد وجود غرامة سابقة أو مضاعفة عليه.
--
-- 4) إلغاء أي استثناء من الغرامات لأي شخص (بما في ذلك يحيى جمال والقيادات):
--    - لا يوجد أي موظف معفى من الغرامة إذا تأخر دون إذن رسمي أو إجازة أو مأمورية أو عطلة معتمدة.
--    - إلغاء تريجر tg_prevent_admin_penalty.
--
-- 5) الحصانة المطلقة لحساب يحيى جمال السبع:
--    - لا يُوقف حساب يحيى عن العمل ولا يُغلق حسابه على النظام نهائياً تحت أي ظرف.
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة حساب شريحة الغرامة الفورية مع حصر المدة عند 120 دقيقة كحد أقصى
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.calc_instant_penalty_amount(p_late_minutes integer)
returns numeric(12,2)
language sql immutable strict
set search_path = public, extensions, pg_temp
as $$
  select case
    when p_late_minutes is null or p_late_minutes <= 15 then 0.00   -- فترة سماح 15 دقيقة (10:00 - 10:15) بدون أي خصم
    when p_late_minutes <= 30                           then 20.00  -- تمام تأخير 30 دقيقة (16-30 دقيقة) = 20 ج.م
    when p_late_minutes < 120                           then 50.00  -- تمام تأخير 1 ساعة وحتى أقل من ساعتين (31-119 دقيقة) = 50 ج.م
    else 150.00                                                     -- تمام التأخر ساعتين فأكثر (محصورة عند 120 دقيقة كحد أقصى) = 150 ج.م
  end;
$$;

revoke all on function public.calc_instant_penalty_amount(integer) from public, anon;
grant execute on function public.calc_instant_penalty_amount(integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) إلغاء أي استثناء دائم من الغرامات (is_employee_penalty_exempt)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  -- لا يوجد أي استثناء دائم من الغرامات لأي شخص كائناً من كان
  select false;
$$;

revoke all on function public.is_employee_penalty_exempt(uuid) from public, anon;
grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, service_role;

-- تصفير أي أعلام إعفاء سابقة من الغرامات في جدول الموظفين
update public.employees
   set is_penalty_exempt = false
 where is_penalty_exempt = true;

-- ─────────────────────────────────────────────────────────────────────
-- 3) تحديث دالة فحص الإعفاء الشامل من الغرامة في تاريخ محدد
--    تقتصر حصراً على الأسباب التشغيلية المعتمدة رسمياً في ذلك اليوم:
--    (عطلة الجمعة، الأعياد الرسمية، الإجازة، إذن الحضور/التأخير، المأمورية/القافلة)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.is_employee_exempt_from_instant_penalty(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req record;
  v_wa record;
  v_att record;
  v_loc text;
begin
  -- ملاحظة هامة: تم إلغاء أي إعفاء إداري دائم للأشخاص (لا استثناء لأحد من الغرامة)
  -- الإعفاء يقتصر فقط على الظروف الرسمية المعتمدة لتاريخ العمل المحدد أدناه:

  -- 1) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- 2) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- 3) فحص الإجازات في جدول leave_requests (معتمدة أو قيد المراجعة / طلب مقدم)
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type, r.status into v_req
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    left join public.leave_types lt on lt.id = lr.leave_type_id
   where lr.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and p_work_date between lr.start_date and lr.end_date
   limit 1;

  if v_req.request_type is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_type, 'رسمية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- 4) فحص أذونات الحضور والتأخير (late_permit, early_permit, permit, permission)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         (r.payload->>'permitDate')::date,
         (r.payload->>'date')::date,
         (r.payload->>'startDate')::date,
         (r.payload->>'start_date')::date,
         (r.payload->>'workDate')::date,
         r.created_at::date
       ) = p_work_date
     order by r.created_at desc
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permit',
      'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
    );
  end loop;

  -- 5) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and (
         -- طلب إجازة
         (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
          and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- مأمورية عمل
         or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- قافلة ميدانية
         or (r.request_type in ('convoy', 'field_convoy')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فاندي / جمع تبرعات
         or (r.request_type in ('fundraising', 'fandy', 'fundi')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- فحص داخل payload للأنواع المدمجة
         or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         -- عمل عن بعد أو تعويض
         or (r.request_type in ('remote_work', 'compensation')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
       )
     order by r.created_at desc
     limit 1
  loop
    v_loc := case
      when v_req.request_type in ('convoy', 'field_convoy') or coalesce(v_req.payload->>'missionType', '') = 'convoy' then 'قافلة ميدانية'
      when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') = 'fundraising' then 'فاندي (جمع تبرعات)'
      when v_req.request_type in ('mission', 'external_mission', 'administrative_mission') then 'مأمورية عمل'
      when v_req.request_type = 'remote_work' then 'عمل عن بعد'
      when v_req.request_type = 'compensation' then 'يوم راحة تعويضي'
      else 'إجازة رسمية'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', v_req.request_type,
      'reason', v_loc || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end loop;

  -- 6) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.responsible_employee_id = p_employee_id
     and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
     and p_work_date between wa.start_at::date and wa.end_at::date
   limit 1;

  if v_wa.assignment_type is not null then
    v_loc := case
      when upper(v_wa.assignment_type) in ('CONVOY', 'FIELD_CONVOY') then 'قافلة ميدانية'
      when upper(v_wa.assignment_type) in ('FUNDRAISING', 'FANDY') then 'فاندي (جمع تبرعات)'
      when upper(v_wa.assignment_type) in ('MISSION', 'EXTERNAL') then 'مأمورية عمل'
      else 'مهمة عمل رسمية (' || coalesce(v_wa.title, v_wa.assignment_type) || ')'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', 'assignment',
      'reason', v_loc || ' مكلف بها رسمياً'
    );
  end if;

  -- 7) فحص حالة الحضور اليومي في attendance_daily
  select ad.status into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date
   limit 1;

  if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
    return jsonb_build_object(
      'isExempt', true,
      'category', v_att.status,
      'reason', case v_att.status
        when 'on_leave' then 'مسجل في عطلة/إجازة رسمية'
        when 'mission'  then 'مسجل في مأمورية عمل'
        when 'excused'  then 'معذور رسمياً في سجل الحضور'
        when 'holiday'  then 'عطلة رسمية'
        when 'weekend'  then 'راحة أسبوعية'
        else v_att.status
      end
    );
  end if;

  -- الموظف غير معفى
  return jsonb_build_object(
    'isExempt', false,
    'category', 'none',
    'reason', null
  );
end;
$$;

revoke all on function public.is_employee_exempt_from_instant_penalty(uuid, date) from public, anon;
grant execute on function public.is_employee_exempt_from_instant_penalty(uuid, date) to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4) حذف تريجر منع تسجيل الغرامات للأدمن (tg_prevent_admin_penalty)
--    ليتمكن النظام من تسجيل الغرامة على أي شخص بما فيهم يحيى في حال التأخير
-- ─────────────────────────────────────────────────────────────────────

drop trigger if exists tg_prevent_admin_penalty on public.instant_attendance_penalties;
drop function if exists public.tg_prevent_admin_penalty_fn();

-- ─────────────────────────────────────────────────────────────────────
-- 5) تحديث تريجر الحصانة الدائمة لحساب يحيى جمال:
--    - حماية الحساب من أي وقف أو تعليق أو تعطيل (يبقى نشطاً دائماً)
--    - لا إعفاء من الغرامات (يُحاسب على التأخير كغيره)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.tg_admin_immunity_employees_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or NEW.phone_e164 in ('+201154869616', '01154869616')
     or NEW.employee_code in ('+201154869616', '01154869616')
     or NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.full_name_ar ilike '%يحيى%جمال%' then
    -- الحساب نشط دائماً ولا يُوقف عن العمل نهائياً
    NEW.status := 'active';
    NEW.is_active := true;
    -- غير معفى من الغرامات: ملزم بالانضباط والجزاءات
    NEW.is_penalty_exempt := false;
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_admin_immunity_employees on public.employees;
create trigger tg_admin_immunity_employees
before insert or update on public.employees
for each row
execute function public.tg_admin_immunity_employees_fn();

create or replace function public.tg_admin_immunity_profiles_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or exists (select 1 from public.employees e where e.id = NEW.employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    NEW.status := 'active';
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_admin_immunity_profiles on public.profiles;
create trigger tg_admin_immunity_profiles
before insert or update on public.profiles
for each row
execute function public.tg_admin_immunity_profiles_fn();

-- ─────────────────────────────────────────────────────────────────────
-- 6) تحديث دالة توليد الغرامة generate_instant_penalty
--    - حصر دقائق التأخير بحد أقصى 120 دقيقة (ساعتان فقط)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.generate_instant_penalty(
  p_employee_id uuid,
  p_work_date date,
  p_late_minutes integer,
  p_notes text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_effective_late_minutes integer;
  v_amount numeric(12,2);
  v_row public.instant_attendance_penalties;
  v_emp_name text;
  v_default_notes text;
  v_exempt jsonb;
begin
  -- التحقق من الصلاحيات (الكرون auth.uid() is null مسموح)
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح: تحتاج صلاحية إدارة الغرامات' using errcode = '42501';
  end if;

  -- 1. فحص الإعفاء الشامل المعتمد لذلك اليوم
  v_exempt := public.is_employee_exempt_from_instant_penalty(p_employee_id, p_work_date);
  if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isExempt', true,
      'amount', 0,
      'message', 'الموظف معفى من غرامات الحضور والانصراف: ' || (v_exempt->>'reason')
    );
  end if;

  -- 2. التحقق من وجود الموظف (دون اشتراط is_active للسماح بتسجيل غرامة من حضر متأخراً في اليوم 2 أو 3)
  select full_name_ar into v_emp_name
    from public.employees
   where id = p_employee_id and coalesce(is_deleted, false) = false;

  if v_emp_name is null then
    raise exception 'الموظف غير موجود' using errcode = 'P0002';
  end if;

  if p_late_minutes is null or p_late_minutes <= 0 then
    raise exception 'دقائق التأخير يجب أن تكون أكبر من صفر' using errcode = '22023';
  end if;

  -- 3. حصر دقائق التأخير عند 120 دقيقة كحد أقصى (ساعتان فقط)
  v_effective_late_minutes := least(120, greatest(1, p_late_minutes));
  v_amount := public.calc_instant_penalty_amount(v_effective_late_minutes);

  -- إذا كان التأخير ضمن فترة السماح (15 دقيقة الأولى: 10:00 - 10:15 = 0 ج.م)
  if v_amount <= 0.00 then
    return jsonb_build_object(
      'id', null,
      'alreadyExists', false,
      'isGracePeriod', true,
      'amount', 0,
      'message', 'التأخير ضمن فترة السماح الرسمية (15 دقيقة الأولى: 10:00 - 10:15) — لا توجد غرامة مستحقة'
    );
  end if;

  v_default_notes := coalesce(p_notes, case
    when v_effective_late_minutes >= 120 then 'تأخير بلغ ساعتين (حُصر عند الحد الأقصى 120 دقيقة)'
    else 'تأخير عن موعد العمل الرسمي (10:00 ص)'
  end);

  -- محاولة الإدخال
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes,
    original_amount, current_amount, currency,
    status, escalation_level, notes, created_by
  ) values (
    p_employee_id, p_work_date, v_effective_late_minutes,
    v_amount, v_amount, 'EGP',
    'pending_payment', 'initial', v_default_notes, auth.uid()
  )
  on conflict (employee_id, work_date) do nothing
  returning * into v_row;

  -- إذا كانت الغرامة مسجلة مسبقاً لهذا اليوم:
  if v_row.id is null then
    select * into v_row
      from public.instant_attendance_penalties
     where employee_id = p_employee_id and work_date = p_work_date;

    -- إذا كانت لا تزال قيد السداد وكان التأخير/المبلغ الجديد أكبر:
    if v_row.status = 'pending_payment' and (v_amount > v_row.current_amount or v_effective_late_minutes > coalesce(v_row.late_minutes, 0)) then
      update public.instant_attendance_penalties
         set late_minutes = v_effective_late_minutes,
             original_amount = v_amount,
             current_amount = v_amount,
             notes = v_default_notes,
             updated_at = now()
       where id = v_row.id
      returning * into v_row;

      perform public._notify_instant_penalty_stakeholders(
        p_employee_id,
        '⚠️ تصعيد غرامة تأخير الحضور',
        v_emp_name || ': تزايد التأخير إلى ' || case when v_effective_late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_effective_late_minutes || ' دقيقة' end || ' — تم تحديث الغرامة إلى ' || v_amount || ' ج.م.',
        'instant_penalty',
        v_row.id,
        jsonb_build_object(
          'employeeId', p_employee_id::text,
          'penaltyId', v_row.id::text,
          'lateMinutes', v_effective_late_minutes,
          'originalAmount', v_amount,
          'currentAmount', v_amount,
          'channel', 'instant_penalty',
          'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
        )
      );
    end if;

    return jsonb_build_object(
      'id', v_row.id,
      'alreadyExists', true,
      'amount', v_row.current_amount,
      'status', v_row.status,
      'lateMinutes', v_row.late_minutes,
      'message', 'توجد غرامة مسجلة مسبقاً لهذا اليوم'
    );
  end if;

  -- إشعار أصحاب الشأن
  perform public._notify_instant_penalty_stakeholders(
    p_employee_id,
    '⚠️ تسجيل غرامة تأخير حضور فورية',
    'تم تسجيل غرامة تأخير على ' || v_emp_name || ' بمبلغ ' || v_amount || ' ج.م (' || case when v_effective_late_minutes >= 120 then 'ساعتان — الحد الأقصى' else v_effective_late_minutes || ' دقيقة' end || ' تأخير). المهلة: نفس اليوم قبل المضاعفة إلى 500 ج.م غداً.',
    'instant_penalty',
    v_row.id,
    jsonb_build_object(
      'employeeId', p_employee_id::text,
      'penaltyId', v_row.id::text,
      'lateMinutes', v_effective_late_minutes,
      'originalAmount', v_amount,
      'currentAmount', v_amount,
      'channel', 'instant_penalty',
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'alreadyExists', false,
    'amount', v_amount,
    'status', 'pending_payment',
    'lateMinutes', v_effective_late_minutes,
    'message', 'تم تسجيل الغرامة الفورية بنجاح'
  );
end;
$$;

revoke all on function public.generate_instant_penalty(uuid, date, integer, text) from public, anon;
grant execute on function public.generate_instant_penalty(uuid, date, integer, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 7) تحديث الكرون التلقائي لتوليد الغرامات auto_generate_instant_penalties:
--    - حصر احتساب دقائق التأخير عند 120 دقيقة (ساعتان فقط) قطعياً
--    - فحص جميع الموظفين النشطين ومن حضر متأخراً دون استثناء لأحد
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_now_cairo timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_now_cairo::date;
  v_time_cairo time := v_now_cairo::time;
  v_isodow integer := extract(isodow from v_now_cairo)::integer;
  v_elapsed_mins integer;
  v_processed integer := 0;
  v_emp record;
  v_att record;
  v_penalty_minutes integer;
  v_notes text;
  v_exempt jsonb;
  v_pen record;
begin
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- 1. استثناء عطلة الجمعة
  if v_isodow = 5 then
    return 0;
  end if;

  -- 2. استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- 3. خطوة التنظيف التلقائي: إلغاء أي غرامات معلقة لموظفين لديهم إذن أو مأمورية أو إجازة معتمدة لذلك اليوم
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
       and p.work_date >= v_today - 3
  loop
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_pen.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             updated_at = now()
       where id = v_pen.id;

      -- رفع التعليق إن لم تكن هناك غرامات مضاعفة أخرى غير معفى منها
      if not exists (
        select 1 from public.instant_attendance_penalties
         where employee_id = v_pen.employee_id
           and status in ('doubled', 'suspended')
           and id != v_pen.id
      ) then
        update public.employees set is_active = true, status = 'active' where id = v_pen.employee_id;
        update public.profiles set status = 'active' where employee_id = v_pen.employee_id;
      end if;
    end if;
  end loop;

  -- 4. قبل انتهاء فترة السماح (10:15 ص): لا توجد غرامات
  if v_time_cairo <= '10:15:00'::time then
    return 0;
  end if;

  -- حساب الدقائق المنقضية منذ 10:00 ص
  v_elapsed_mins := floor(extract(epoch from (v_time_cairo - '10:00:00'::time)) / 60)::integer;
  if v_elapsed_mins <= 15 then
    return 0;
  end if;

  -- 5. فحص الموظفين: يشمل جميع الموظفين النشطين، وكذلك من حضر اليوم وسجل بصمة متأخرة
  for v_emp in
    select e.id as employee_id, e.full_name_ar, e.is_active, e.status as emp_status
      from public.employees e
     where coalesce(e.is_deleted, false) = false
       and (
         e.is_active = true
         or exists (
           select 1 from public.attendance_daily ad
            where ad.employee_id = e.id
              and ad.work_date = v_today
         )
       )
  loop
    -- فحص الإعفاء اليومي المعتمد (إذن حضور، إجازة، مأمورية، قافلة)
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    -- فحص سجل الحضور اليومي للموظف
    select ad.id, ad.status, ad.late_minutes, ad.first_check_in into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today
     limit 1;

    -- إذا كانت حالة السجل تشير إلى إجازة أو مأمورية أو عذر رسمي
    if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- الحالة أ: الموظف بصم حضوراً ولديه تأخير فعلي أكثر من فترة السماح
    if v_att.id is not null and v_att.first_check_in is not null then
      if coalesce(v_att.late_minutes, 0) > 15 then
        -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى)
        v_penalty_minutes := least(120, coalesce(v_att.late_minutes, 0));
        v_notes := case
          when coalesce(v_att.late_minutes, 0) >= 120 then
            'تأخير حضور فعلي تجاوز ساعتين (حُصر عند الحد الأقصى 120 دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
          else
            'تأخير حضور فعلي (' || v_penalty_minutes || ' دقيقة) — وقت البصمة: ' ||
            to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'HH12:MI AM')
        end;

        perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
        v_processed := v_processed + 1;
      end if;
      continue;
    end if;

    -- الحالة ب: الموظف لم يسجل بصمة حضور حتى الآن وتجاوزنا 10:15 ص
    -- إذا كان الموظف معلقاً من العمل ولم يحضر لا نحسب عليه تأخير غياب إضافي
    if v_emp.is_active = false or v_emp.emp_status = 'suspended' then
      continue;
    end if;

    -- حصر التأخير قطعياً عند ساعتين (120 دقيقة كحد أقصى) مهما تأخر الوقت في اليوم
    v_penalty_minutes := least(120, v_elapsed_mins);
    v_notes := case
      when v_elapsed_mins >= 120 then
        'تأخير عن موعد العمل (10:00 ص) — حُصر عند الحد الأقصى ساعتان (120 دقيقة) لعدم تسجيل البصمة حتى الآن'
      else
        'تأخير عن موعد العمل (10:00 ص) — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')'
    end;

    perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$$;

revoke all on function public.auto_generate_instant_penalties() from public, anon;
grant execute on function public.auto_generate_instant_penalties() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 8) دالة التصعيد التلقائي:
--    - اليوم الثاني (غداً): مضاعفة إلى 500 ج.م لجميع غير المسددين بلا استثناء
--    - اليوم الثالث: وقف العمل وغلق النظام لمن لم يسدد مع غرامة 500 ج.م
--    - حماية مطلقة لحساب يحيى جمال السبع من أي وقف أو تعليق
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'attendance.record.manage'])) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- ═══ المرحلة 1: عدم السداد في نفس اليوم -> مضاعفة الغرامة إلى 500 ج.م تدفع في اليوم الثاني ═══
  -- تنطبق على الجميع بلا استثناء (بما فيهم يحيى جمال والقيادات)
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    -- فحص الإعفاء المعتمد قبل المضاعفة
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص المضاعفة: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'warning',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م لعدم السداد في نفس اليوم',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount, 'currentAmount', 500.00)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم تسدد غرامة التأخير في نفس اليوم. تمت مضاعفة الغرامة إلى 500 ج.م تدفع اليوم (ثاني يوم). في حال عدم السداد لليوم الثالث، سيتم غلق الحساب ووقفك عن العمل تلقائياً.',
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

  -- ═══ المرحلة 2: عدم السداد حتى اليوم الثالث -> غلق الحساب ووقف الموظف عن العمل مع غرامة 500 ج.م ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status in ('doubled', 'pending_payment')
       and p.work_date < v_today - 1
  loop
    -- فحص الإعفاء المعتمد قبل التعليق
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;

      -- رفع أي تعليق إن وجد
      update public.employees set status = 'active', is_active = true where id = v_rec.employee_id;
      update public.profiles set status = 'active' where employee_id = v_rec.employee_id;
      continue;
    end if;

    -- استثناء الحساب الرئيسي والمسؤول العام للنظام (يحيى جمال السبع) من وقف العمل وغلق الحساب قطعياً
    -- الغرامة تظل قائمة ومضاعفة بـ 500 ج.م ولكن الحساب يظل نشطاً ومحمياً
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

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
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
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثالث',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', 500.00, 'workDate', v_rec.work_date)
    );

    -- 3) إشعار عاجل للموظف
    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 إيقاف عن العمل وغلق الحساب',
      'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م لليوم الثالث. توجه إلى قسم الـ HR لسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', 500.00,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    -- 4) إرسال إشعار لكامل الفريق
    perform public.notify_employee(
      e.id,
      '🚫 إشعار إيقاف موظف عن العمل',
      'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
      'system',
      'urgent',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'suspendedEmployeeName', v_emp_name,
        'amount', 500,
        'channel', 'team_suspension_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_rec.employee_id;

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────
-- 9) تصحيح جميع سجلات الغرامات السابقة التي تجاوزت 120 دقيقة (ساعتان)
-- ─────────────────────────────────────────────────────────────────────

update public.instant_attendance_penalties
   set late_minutes = 120,
       notes = case
         when notes ilike '%لم يسجل بصمة%' or notes ilike '%590%' or notes ilike '%9 ساعة%'
           then 'تأخير عن موعد العمل (10:00 ص) — حُصر عند الحد الأقصى ساعتان (120 دقيقة)'
         else notes
       end,
       updated_at = now()
 where late_minutes > 120;

commit;
