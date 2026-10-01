-- =====================================================================
-- 0585: سياسة الإعفاء النهائية (بقرار الإدارة 2026-09-30)
--
--  • معفى من البصمة والحضور والانصراف والغرامات: الشيخ محمد وأبو عمار فقط.
--  • معفى من الغرامات فقط (ملزم بالبصمة والحضور والانصراف): طاقم العيادات
--    الطبية — التمريض والاستقبال والمعمل — دون مديريهم ومشرفيهم.
--  • لا إعفاء لأي شخص آخر.
--
-- ما صحّحته عن 0582:
--  1) طاقم العيادات كان معفى من البصمة أيضاً → الآن من الغرامات فقط، فيظهر في
--     الكشوف والنسب ولوحة الشرف وتصله تذكيرات البصمة.
--  2) المطابقة بالأسماء (ilike '%محمد عبدالباسط%'، '%الشيخ محمد%') كانت تعفي أي
--     موظف يحمل اسماً مشابهاً (ثغرة سبق إغلاقها في 0548) → بالمعرّفات فقط.
--  3) «طاقم العيادات» كان كل من في قسم اسمه يحوي «عياد» → الدور clinic-staff أو
--     مسمى التمريض/الاستقبال/المعمل، مع استبعاد المديرين والمشرفين.
--  4) generate_punch_reminders كان يستثني بالدور (operations-manager-1) مدير
--     تشغيل آخر غير معفى، ويستثني المعفى من الغرامات → المعفى من البصمة فقط.
--  5) أعلام employees.is_attendance_exempt/is_penalty_exempt متسقة مع السياسة
--     (تقرؤها لوحة الشرف وغيرها)، وموظفة العيادات بلا مسمى سُجّلت «تمريض».
-- =====================================================================

begin;

-- ─── 1) المعفى من البصمة والحضور والانصراف (والغرامات بالتبعية) ─────────
create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  -- الشيخ محمد (والسجل المؤرشف له) وأبو عمار — بالمعرّف فقط
  select coalesce(p_employee_id in ('7b0740fa-66ba-4616-8674-3dbd8e14109e', '886f4942-c469-4a03-8f02-659fd02c4a02', '767eae8e-e7be-458e-a6ca-879414e46b08'), false);
$fn$;

-- ─── 2) طاقم العيادات: معفى من الغرامات فقط ─────────────────────────────
create or replace function public.is_clinic_staff_exempt(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select exists (
    select 1
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    where e.id = p_employee_id
      and not e.is_deleted
      -- المديرون والمشرفون غير معفيين (مدير العيادات، مدير المجمع، مشرف المجمع)
      and e.id not in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c', 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', '7d879f2d-b4d4-4da0-93d6-14e542e7fef3')
      and coalesce(jt.name, '') not like '%مدير%'
      and coalesce(jt.name, '') not like '%مشرف%'
      and (
        coalesce(jt.name, '') in ('تمريض', 'موظف استقبال', 'دكتورة المعمل')
        or exists (
          select 1 from public.user_roles ur
          join public.roles r on r.id = ur.role_id
          where ur.user_id = e.user_id
            and r.slug = 'clinic-staff'
            and (ur.effective_to is null or ur.effective_to > now())
        )
      )
  );
$fn$;

-- ─── 3) المعفى من الغرامات = المعفى من البصمة + طاقم العيادات ──────────
create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.is_employee_attendance_exempt(p_employee_id)
      or public.is_clinic_staff_exempt(p_employee_id);
$fn$;

-- ─── 4) البيانات: مسمى موظفة العيادات + أعلام الإعفاء المتسقة ────────────
update public.employees
   set job_title_id = '1fa53fd1-fc65-4fd3-abe1-eba0bd8fb366'
 where id = '9ab2509b-4000-4933-8610-d67dbdcc4737' and job_title_id is null;

update public.employees e
   set is_attendance_exempt = public.is_employee_attendance_exempt(e.id),
       is_penalty_exempt    = public.is_employee_penalty_exempt(e.id)
 where e.is_attendance_exempt is distinct from public.is_employee_attendance_exempt(e.id)
    or e.is_penalty_exempt    is distinct from public.is_employee_penalty_exempt(e.id);

-- ─── 5) تذكيرات البصمة: المعفى من البصمة فقط لا يُذكَّر ─────────────────
CREATE OR REPLACE FUNCTION public.generate_punch_reminders(p_lead_minutes integer DEFAULT 15)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_created integer := 0;
  v_now_cairo timestamptz := now();
  v_local timestamp := (now() at time zone 'Africa/Cairo');
  v_today date := v_local::date;
  v_now_time time := v_local::time;
  v_dow integer := extract(isodow from v_local)::integer;  -- 1=إثنين .. 7=أحد
  v_lead integer := greatest(coalesce(p_lead_minutes, 15), 1);
  v_shift record;
  v_emp record;
  v_daily public.attendance_daily;
  v_kind text;
  v_title text;
  v_body text;
begin
  -- قفل استشاري يمنع تشغيلَين متزامنين للوظيفة
  perform pg_advisory_xact_lock(hashtext('generate_punch_reminders'));
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة فقط عطلة (السبت=6، الأحد=7، الإثنين..الخميس=1..4)
  if v_dow = 5 then
    return 0;
  end if;

  -- استثناء العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  -- الوردية الرسمية الحالية
  select * into v_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  if v_shift.id is null then
    return 0;
  end if;

  for v_emp in
    select e.id as employee_id, e.user_id, e.is_attendance_exempt, e.is_penalty_exempt
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
  loop
    -- 1. المعفى من البصمة وحده لا يُذكَّر (الشيخ محمد وأبو عمار — 0585). المعفى من
    --    الغرامات فقط (طاقم العيادات) ملزم بالبصمة فيُذكَّر، وكذلك بقية مديري التشغيل.
    if public.is_employee_attendance_exempt(v_emp.employee_id) then
      continue;
    end if;

    -- 2. استثناء الموظف المكلف بمهمة عمل أو قافلة رسمية اليوم
    if exists (
      select 1 from public.work_assignments wa
      where wa.responsible_employee_id = v_emp.employee_id
        and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
        and v_today between wa.start_at::date and wa.end_at::date
    ) then
      continue;
    end if;

    -- 3. استثناء الموظف إذا كان لديه طلب إجازة مسجل أو معتمد في leave_requests
    if exists (
      select 1 from public.leave_requests lr
      join public.requests r on r.id = lr.request_id
      where lr.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and v_today between lr.start_date and lr.end_date
    ) then
      continue;
    end if;

    -- 4. استثناء الموظف إذا كان لديه طلب (إجازة، مأمورية، قافلة، فاندي، عمل عن بعد، تعويض) في requests
    if exists (
      select 1 from public.requests r
      where r.employee_id = v_emp.employee_id
        and r.status not in ('rejected', 'cancelled')
        and (
          -- إجازة
          (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
           and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                           and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- مأمورية عمل
          or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- قافلة ميدانية
          or (r.request_type in ('convoy', 'field_convoy')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- فاندي / جمع تبرعات
          or (r.request_type in ('fundraising', 'fandy', 'fundi')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- داخل payload
          or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- عمل عن بعد أو تعويض
          or (r.request_type in ('remote_work', 'compensation')
              and v_today between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
        )
    ) then
      continue;
    end if;

    -- 5. سجل اليوم للموظف
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id
      and work_date = v_today;

    -- إذا كانت حالة الحضور اليومي معذورة بالفعل
    if v_daily.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- تحديد نوع التذكير حسب التوقيت
    v_kind := null;
    if v_now_time >= (v_shift.start_time - make_interval(mins := v_lead))
       and v_now_time < v_shift.start_time
       and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'before_in';
      v_title := 'تذكير بالحضور';
      v_body := 'اقترب وقت الحضور (' || (to_char(v_shift.start_time, 'hh12:mi') || case when extract(hour from v_shift.start_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل البصمة.';
    elsif v_now_time >= v_shift.start_time + make_interval(mins := v_shift.grace_in_minutes)
          and v_now_time < v_shift.start_time + make_interval(mins := v_shift.grace_in_minutes + v_lead)
          and (v_daily.id is null or v_daily.first_check_in is null) then
      v_kind := 'late_in';
      v_title := '⚠️ تأخير في الحضور';
      v_body := 'لم تُسجَّل بصمة حضورك حتى الآن. سجّل البصمة في أقرب وقت.';
    elsif v_now_time >= (v_shift.end_time - make_interval(mins := v_lead))
          and v_now_time < v_shift.end_time
          and v_daily.first_check_in is not null
          and v_daily.last_check_out is null then
      v_kind := 'before_out';
      v_title := 'تذكير بالانصراف';
      v_body := 'اقترب وقت الانصراف (' || (to_char(v_shift.end_time, 'hh12:mi') || case when extract(hour from v_shift.end_time) < 12 then ' ص' else ' م' end) || '). لا تنسَ تسجيل بصمة الانصراف.';
    end if;

    if v_kind is null then
      continue;
    end if;

    -- 6. فحص أذونات الحضور والانصراف:
    -- أ) في حالة تذكير الحضور أو تنبيه التأخر (before_in أو late_in):
    -- إذا كان الموظف قد طلب إذن حضور/تأخير (late_permit, permit, permission) لا نرسل له تذكيراً
    if v_kind in ('before_in', 'late_in') then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    -- ب) في حالة تذكير الانصراف (before_out):
    -- إذا كان الموظف لديه إذن انصراف مبكر (early_permit, permit) لا نرسل له تذكيراً
    if v_kind = 'before_out' then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_emp.employee_id
          and r.status not in ('rejected', 'cancelled')
          and r.request_type in ('early_permit', 'permit')
          and coalesce(
            (r.payload->>'permitDate')::date,
            (r.payload->>'date')::date,
            (r.payload->>'startDate')::date,
            (r.payload->>'start_date')::date,
            (r.payload->>'workDate')::date,
            r.created_at::date
          ) = v_today
      ) then
        continue;
      end if;
    end if;

    -- منع التكرار: نفس (المستخدم/اليوم/النوع) مرة واحدة
    if exists (
      select 1 from public.notifications n
      where n.recipient_user_id = v_emp.user_id
        and n.entity_type = 'punch_reminder'
        and n.metadata->>'kind' = v_kind
        and (n.metadata->>'workDate') = v_today::text
    ) then
      continue;
    end if;

    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body,
      category, priority, action_url, entity_type, entity_id, metadata
    ) values (
      v_emp.user_id, v_emp.employee_id, v_title, v_body,
      'system',
      case when v_kind = 'late_in' then 'high' else 'normal' end,
      '/attendance', 'punch_reminder', v_shift.id,
      jsonb_build_object('kind', v_kind, 'workDate', v_today::text, 'shiftId', v_shift.id)
    );
    v_created := v_created + 1;
  end loop;

  return v_created;
end;
$function$;

-- ─── 6) تنبيه تأخر الموظف للمدير: المعفى من البصمة فقط خارجه ─────────────
CREATE OR REPLACE FUNCTION public.auto_notify_late_attendance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=إثنين..5=جمعة..6=سبت..7=أحد
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- قفل استشاري لمنع التكرار
  perform pg_advisory_xact_lock(hashtext('auto_notify_late_attendance'));

  -- الجمعة (5 في isodow) عطلة أسبوعية رسمية
  if v_isodow = 5 then
    return 0;
  end if;

  if exists (
    select 1 from public.public_holidays
    where holiday_date = v_today and is_active = true
  ) then
    return 0;
  end if;

  for v_rec in
    select
      ad.id as attendance_id,
      ad.employee_id,
      ad.late_minutes,
      e.full_name_ar as employee_name,
      e.phone_e164,
      e.user_id as employee_user_id,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e on e.id = ad.employee_id
    left join lateral (
      select
        m.user_id as manager_user_id,
        m.id as manager_employee_id
      from public.manager_relations mr
      join public.employees m on m.id = mr.manager_employee_id
      where mr.employee_id = ad.employee_id
        and (mr.effective_from is null or mr.effective_from <= v_today)
        and (mr.effective_to is null or mr.effective_to >= v_today)
        and m.user_id is not null
      order by case mr.relation_type
                 when 'primary'    then 1
                 when 'functional' then 2
                 when 'dotted'     then 3
                 else 4
               end
      limit 1
    ) mgr on true
    where ad.work_date = v_today
      and ad.status    = 'late'
      and coalesce(ad.late_minutes, 0) > 15
      and e.is_active  = true
      and e.is_deleted = false
      and mgr.manager_user_id is not null
      -- المعفى من البصمة وحده خارج تنبيه التأخر (0585)؛ طاقم العيادات ملزم بالحضور
      and not public.is_employee_attendance_exempt(ad.employee_id)
      and not exists (
        select 1
        from public.notifications n
        where n.recipient_user_id = mgr.manager_user_id
          and n.entity_type = 'late_attendance_alert'
          and (n.metadata->>'employeeId') = ad.employee_id::text
          and (n.metadata->>'workDate')   = v_today::text
      )
    order by e.full_name_ar
  loop
    insert into public.notifications (
      recipient_user_id,
      recipient_employee_id,
      title,
      body,
      category,
      priority,
      action_url,
      entity_type,
      entity_id,
      metadata
    ) values (
      v_rec.manager_user_id,
      v_rec.manager_employee_id,
      'تنبيه تأخر موظف',
      coalesce(v_rec.employee_name, 'الموظف') || ' تأخر عن موعد الحضور الرسمي بمقدار ' ||
        case when v_rec.late_minutes >= 120 then 'ساعتين (الحد الأقصى)' else v_rec.late_minutes::text || ' دقيقة' end,
      'system',
      'urgent',
      '/attendance',
      'late_attendance_alert',
      v_rec.employee_id,
      jsonb_build_object(
        'workDate',     v_today::text,
        'lateMinutes',  v_rec.late_minutes,
        'employeeId',   v_rec.employee_id::text,
        'managerEmployeeId', v_rec.manager_employee_id::text,
        'channel', 'late_attendance',
        'deepLink', 'ahlashabab://action/attendance?date=' || to_char(v_today, 'YYYY-MM-DD')
      )
    ) returning id into v_notif_id;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
exception
  when others then
    perform public.log_audit_event(
      'attendance.late_alert_failed', 'operations', 'warning',
      'attendance_daily', null, 'فشل تنبيه التأخر التلقائي', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$function$;

commit;
