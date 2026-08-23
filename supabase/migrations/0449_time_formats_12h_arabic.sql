-- ============================================================================
-- 0449: صيغة الوقت 12 ساعة (ص/م) في كل النصوص المولّدة من الخادم
-- ============================================================================
-- طلب المستخدم: كل الأوقات المعروضة بنظام 12 ساعة مع صباحاً/مساءً بدل 24.
--
-- الويب سليم أصلاً (ar-EG يعرض "٩:٠٥ م" افتراضياً)، والموبايل يستخدم
-- DateFormat('h:mm a','ar') في أغلب الشاشات (الباقي أُصلح في كود التطبيق).
-- تبقى النصوص المركّبة داخل دوال قاعدة البيانات — تُعاد كتابتها هنا بصيغة
-- hh12:mi مع لاحقة ص (قبل الظهر) / م (بعد الظهر):
--   1) tg_attendance_daily_notify_manager — وقت الدخول/الانصراف في إشعارات
--      الحضور («وصل فلان للعمل بالمجمع… خرج الساعة ٥:٠٥ م»).
--   2) generate_punch_reminders — أوقت بداية/نهاية الوردة في تذكيرات البصمة.
--   3) schedule_dispute_session_v2 — موعد جلسة المشكلة في إشعار اللجنة.
--
-- استثناء مقصود — _build_attendance_statement_v287: حقلا checkIn/checkOut
-- فيهما عقدٌ آلي تعيد دوال 0362/0430/0432/0434 والغلاف 0398 تحليلهما بـ::time؛
-- صيغة العرض 12 ساعة متاحة أصلاً عبر checkIn12/checkOut12 (_fmt_time_12h)
-- وتنسيق الواجهات يتم في العميل.
--
-- ملاحظة: أرقام المراجع (DEC-/RST-/OFF-/CASE-) ومفاتيح الفرز والدمج الداخلية
-- تبقى HH24 عمداً — ليست نصوص عرض للمستخدم.
-- القاعدة: hh12 يعرض منتصف الليل 12:00 ص والظهر 12:00 م (العرف العربي).
-- ============================================================================

begin;

CREATE OR REPLACE FUNCTION public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
  v_first text;
  v_exec_emp uuid;
  v_title text;
  v_body text;
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  -- الاسم الأول للعنوان الشخصي (وصل مصطفى…) مع احتياط عند غياب الاسم
  v_first := coalesce(nullif(split_part(coalesce(v_emp_ar, ''), ' ', 1), ''), 'موظف');

  -- 0449: الوقت بنظام 12 ساعة مع ص/م بدل HH24
  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'hh12:mi'
  ) || case when extract(hour from (
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end;

  -- 0446: عنوان شخصي باسم الموظف بدل الصيغة العامة
  v_title := case when v_event = 'attendance_check_in'
              then format('وصل %s للعمل بالمجمع', v_first)
              else format('خرج %s من المجمع', v_first) end;
  v_body := format(
    '%s الساعة %s',
    case when v_event = 'attendance_check_in' then 'دخل' else 'انصرف' end,
    v_time
  );

  -- إشعار الموظف نفسه (تأكيد تسجيل الحضور/الانصراف)
  perform public.notify_employee(
    new.employee_id,
    case when v_event = 'attendance_check_in' then 'تم تسجيل حضورك'
         else 'تم تسجيل انصرافك' end,
    format(
      'تم تسجيل %s الساعة %s',
      case when v_event = 'attendance_check_in' then 'حضورك' else 'انصرافك' end,
      v_time
    ),
    'attendance', 'normal', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time
    )
  );

  -- إشعار المدير المباشر (أولوية منخفضة — عنوان شخصي 0446)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
    perform public.notify_employee(
      v_manager,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- 0446: إشعار المدير التنفيذي بإشعار «عادي» (لا عاجل ولا full-screen)
  -- حتى لا تغرق إشعارات الحضور الروتينية قسم «تنبيهات عاجلة»؛ تبقى في
  -- قائمة الإشعارات العامة. لا يُشعر التنفيذي عن حضور/انصراف نفسه.
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null and v_exec_emp <> new.employee_id then
    perform public.notify_employee(
      v_exec_emp,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'normal', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'time', v_time
      )
    );
  end if;

  return new;
end;
$$;

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
  -- مسموح فقط لعملية خادمية (service_role) أو مالك صلاحية إرسال الإشعارات.
  if not (public.current_is_full_access()
          or public.has_permission('comms.notification.send')
          or auth.uid() is null) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- الجمعة فقط عطلة (يوم العمل: السبت=6 والأحد=7 والإثنين..الخميس=1..4).
  if v_dow = 5 then
    return 0;
  end if;

  -- الوردية الرسمية الحالية: النشطة الأحدث تحديثًا (تبديل رمضان يدوي).
  select * into v_shift
  from public.shifts
  where is_active = true
  order by updated_at desc nulls last, created_at desc
  limit 1;

  if v_shift.id is null then
    return 0;
  end if;

  for v_emp in
    select e.id as employee_id, e.user_id
    from public.employees e
    where e.is_active = true
      and e.is_deleted = false
      and e.status = 'active'
      and e.user_id is not null
      -- V17 §7: استثناء المدير التنفيذي من تذكيرات الحضور
      and not exists (
        select 1 from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = e.user_id
          and r.slug in ('executive', 'executive-director')
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
  loop
    -- سجل اليوم (إن وُجد) للموظف: مصدر الحقيقة لبصمة الدخول/الخروج.
    select * into v_daily
    from public.attendance_daily
    where employee_id = v_emp.employee_id
      and work_date = v_today;

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

    -- منع التكرار: نفس (المستخدم/اليوم/النوع) مرة واحدة.
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
$function$

;

CREATE OR REPLACE FUNCTION public.schedule_dispute_session_v2(p_case_id uuid, p_type text, p_scheduled_at timestamp with time zone, p_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_location text DEFAULT NULL::text, p_modality text DEFAULT 'in_person'::text, p_participants jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid; v_item jsonb; v_emp uuid; v_role text; v_status text;
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.session.manage') or exists(select 1 from public.committee_members where case_id=p_case_id and employee_id=public.current_employee_id() and role_in_committee in ('chair','secretary') and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_scheduled_at<=now() or (p_ends_at is not null and p_ends_at<=p_scheduled_at) or p_modality not in ('in_person','remote','hybrid') then raise exception 'INVALID_SESSION'; end if;
 if jsonb_array_length(coalesce(p_participants,'[]'::jsonb))>200 then raise exception 'ERR_BATCH_TOO_LARGE' using errcode='22023'; end if;
 select status into strict v_status from public.dispute_cases where id=p_case_id for update;
 insert into public.dispute_sessions(case_id,session_type,scheduled_at,ends_at,location,modality,status,created_by)
 values(p_case_id,p_type,p_scheduled_at,p_ends_at,nullif(trim(p_location),''),p_modality,'scheduled',auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(coalesce(p_participants,'[]'::jsonb)) loop
  v_emp=(v_item->>'employeeId')::uuid; v_role=coalesce(v_item->>'role','guest');
  if not exists(select 1 from public.employees where id=v_emp and status='active' and is_active and not is_deleted) then raise exception 'INVALID_SESSION_PARTICIPANT'; end if;
  insert into public.dispute_session_participants(session_id,employee_id,participant_role,created_by) values(v_id,v_emp,v_role,auth.uid()) on conflict do nothing;
  perform public.enqueue_dispute_notification(p_case_id,v_emp,'session:'||v_id::text,'تم تحديد جلسة للمشكلة','موعد الجلسة: '||(to_char(p_scheduled_at at time zone 'Africa/Cairo','YYYY-MM-DD hh12:mi') || case when extract(hour from (p_scheduled_at at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end),'high');
 end loop;
 update public.dispute_cases set status='session_scheduled',updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,'session_scheduled',v_status,'session_scheduled',public.current_employee_id(),auth.uid(),jsonb_build_object('sessionId',v_id,'scheduledAt',p_scheduled_at));
 perform public.log_audit_event('dispute.session_scheduled','workflow','notice','dispute_sessions',v_id,'تحديد جلسة للمشكلة',null,jsonb_build_object('caseId',p_case_id));
 return v_id;
end $function$

;


commit;

notify pgrst, 'reload schema';
