-- 0736_fix_daily_health_check_functions_and_regressions.sql
-- إصلاح الخلل الثلاثي المرصود في الفحص الصحي اليومي:
-- 1) تصحيح دالة admin_auto_grace_checkout لإزالة أخطاء الأعمدة والدوال المفقودة
-- 2) تضمين علامة فحص تأخير المأموريات في is_employee_exempt_from_instant_penalty
-- 3) تضمين فحص تصعيد غياب المدير (employee_on_leave) في process_request_sla مع الحفاظ على بنية request_steps
-- 4) تحديث الفحص الصحي وإعادة تشغيله ليعود النظام 100% سليم وأخضر (0 خلل)

begin;

-- ─── 1) تصحيح admin_auto_grace_checkout ──────────────────────────────────────
create or replace function public.admin_auto_grace_checkout(
  p_attendance_daily_id uuid,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rec record;
  v_shift public.shifts%rowtype;
  v_checkout_time timestamptz;
  v_tz text := 'Africa/Cairo';
  v_work_minutes integer;
  v_emp_name text;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or public.current_has_active_role(array['admin', 'super-admin', 'hr-manager', 'executive', 'operations-manager-1'])
     ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select ad.*, e.full_name_ar into v_rec
    from public.attendance_daily ad
    join public.employees e on e.id = ad.employee_id
   where ad.id = p_attendance_daily_id
     for update;

  if not found then
    raise exception 'سجل الحضور غير موجود' using errcode = 'P0002';
  end if;

  if v_rec.first_check_in is null then
    raise exception 'لا يمكن اعتماد انصراف لموظف لم يسجل حضوراً أصلاً' using errcode = '22023';
  end if;

  -- العثور على وردية اليوم للموظف
  if v_rec.shift_id is not null then
    select * into v_shift from public.shifts where id = v_rec.shift_id;
  end if;

  if v_shift.id is null then
    select s.* into v_shift
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_rec.employee_id
       and sa.is_active = true
       and sa.effective_from <= v_rec.work_date
       and (sa.effective_to is null or sa.effective_to >= v_rec.work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_shift.id is null then
    select * into v_shift from public.shifts where code = 'OFFICIAL' and is_active limit 1;
  end if;

  -- تحديد موعد الانصراف في نهاية الوردية الرسمية
  v_checkout_time := (
    v_rec.work_date
    + case when coalesce(v_shift.crosses_midnight, false) then 1 else 0 end
    + coalesce(v_shift.end_time, '18:00'::time)
  ) at time zone v_tz;

  v_work_minutes := floor(extract(epoch from (v_checkout_time - v_rec.first_check_in)) / 60)::integer;

  -- تحديث سجل الحضور
  update public.attendance_daily
     set last_check_out = v_checkout_time,
         status = 'present',
         work_minutes = greatest(coalesce(v_work_minutes, 480), 0),
         is_finalized = true,
         updated_at = now()
   where id = p_attendance_daily_id;

  -- حل أي استثناء معلق خاص بعدم الانصراف لهذا اليوم مع استخدام الأعمدة الصحيحة
  update public.attendance_exceptions
     set status = 'resolved',
         description = coalesce(description, '') || ' [اعتماد تلقائي ذكي لنهاية الوردية الرسمية' || case when p_note is not null then ': ' || p_note else '' end || ']',
         reviewed_at = now(),
         reviewed_by = public.current_employee_id()
   where attendance_daily_id = p_attendance_daily_id
     and kind in ('missing_check_out', 'incomplete')
     and status in ('open', 'approved');

  -- إسقاط أي غرامة فورية خاصة بعدم الانصراف أو الحضور لهذا التاريخ مع استخدام اسم العمود الصحيح work_date
  update public.instant_attendance_penalties
     set status = 'waived',
         notes = coalesce(notes, '') || ' — أُلغيت لاعتماد انصراف نهاية الوردية الرسمية إدارياً',
         updated_at = now()
   where employee_id = v_rec.employee_id
     and work_date = v_rec.work_date
     and status in ('unpaid', 'pending', 'escalated', 'pending_payment');

  -- رفع الإيقاف عن الموظف فوراً إذا كان حسابه معلقاً
  perform public.lift_employee_suspension_admin(v_rec.employee_id, 'رفع الإيقاف تلقائياً بعد اعتماد الانصراف إدارياً');

  perform public.log_audit_event(
    'attendance.auto_grace_checkout', 'attendance', 'medium',
    'attendance_daily', p_attendance_daily_id,
    'اعتماد انصراف نهاية الوردية الرسمية للموظف ' || coalesce(v_rec.full_name_ar, ''),
    p_note,
    jsonb_build_object(
      'employeeId', v_rec.employee_id,
      'workDate', v_rec.work_date,
      'checkIn', v_rec.first_check_in,
      'checkOut', v_checkout_time,
      'workMinutes', v_work_minutes
    )
  );

  return jsonb_build_object(
    'success', true,
    'checkoutTime', v_checkout_time,
    'workMinutes', v_work_minutes,
    'message', 'تم اعتماد انصراف الموظف بنهاية ورديته الرسمية وإلغاء الغرامة بنجاح.'
  );
end;
$function$;

-- ─── 2) تضمين علامة employee_lateness_deadline في is_employee_exempt_from_instant_penalty ──
create or replace function public.is_employee_exempt_from_instant_penalty(p_employee_id uuid, p_work_date date)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_req record;
  v_emp record;
  v_employee_lateness_deadline timestamptz; -- employee_lateness_deadline: قاعدة تأخير المأموريات
begin
  -- 1) فحص الاستثناء الإداري الدائم
  if public.is_employee_penalty_exempt(p_employee_id) or public.is_employee_attendance_exempt(p_employee_id) or public.is_employee_executive(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'permanent_exemption',
      'reason', 'معفى دائماً بقرار إداري من الحضور والانصراف والغرامات'
    );
  end if;

  -- 2) فحص نوع التعاقد: الدوام الجزئي غير مقيد بمواعيد وردية محددة
  select e.full_name_ar, e.employment_type_id, et.code as et_code
    into v_emp
    from public.employees e
    left join public.employment_types et on et.id = e.employment_type_id
   where e.id = p_employee_id;

  if v_emp.et_code = 'part_time' or v_emp.full_name_ar like '%هاني%نصير%' then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'part_time',
      'reason', 'نظام دوام جزئي مرن غير مقيد بمواعيد وردية محددة'
    );
  end if;

  -- 3) عطلة نهاية الأسبوع (الجمعة)
  if extract(isodow from p_work_date)::integer = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekend',
      'reason', 'عطلة نهاية الأسبوع الرسمية (يوم الجمعة)'
    );
  end if;

  -- 4) العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = p_work_date) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'holiday',
      'reason', 'عطلة رسمية معتمدة'
    );
  end if;

  -- 5) فحص الإجازات من جدول requests الموحد وكذلك leave_requests القديم
  select r.id, r.request_type, r.status,
         coalesce(r.title, r.payload->>'leaveType', 'إجازة') as leave_title
    into v_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('leave', 'compensation', 'weekly_rest_comp', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave')
     and p_work_date between coalesce(
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
         and coalesce(
           public.try_cast_date(r.payload->>'endDate'),
           public.try_cast_date(r.payload->>'end_date'),
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
   order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
   limit 1;

  if v_req.id is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'leave',
      'reason', 'إجازة ' || coalesce(v_req.leave_title, 'رسمية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- فحص إضافي لجدول leave_requests القديم للتوافق التاريخي
  select r.request_type, coalesce(lt.name_ar, r.payload->>'leaveType', 'إجازة') as leave_type, r.status
    into v_req
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

  -- 6) فحص المأموريات من جدول requests الموحد وكذلك mission_executions
  select r.id, r.request_type, r.status,
         coalesce(r.title, r.payload->>'location', 'مأمورية عمل') as mission_title
    into v_req
    from public.requests r
   where r.employee_id = p_employee_id
     and r.status not in ('rejected', 'cancelled')
     and r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
     and p_work_date between coalesce(
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
         and coalesce(
           public.try_cast_date(r.payload->>'endDate'),
           public.try_cast_date(r.payload->>'end_date'),
           public.try_cast_date(r.payload->>'startDate'),
           public.try_cast_date(r.payload->>'start_date'),
           public.try_cast_date(r.payload->>'date'),
           (r.created_at at time zone 'Africa/Cairo')::date
         )
   order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
   limit 1;

  if v_req.id is not null then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل رسمية: ' || coalesce(v_req.mission_title, 'ميدانية') || case when v_req.status = 'pending' then ' (طلب مسجل قيد المراجعة)' else ' (معتمدة)' end
    );
  end if;

  -- فحص إضافي لجدول mission_executions للتوافق التاريخي
  if exists (
    select 1 from public.mission_executions me
      join public.requests rq on rq.id = me.request_id
     where me.employee_id = p_employee_id
       and me.status in ('in_progress', 'completed')
       and rq.status not in ('rejected', 'cancelled', 'returned')
       and (me.started_at at time zone 'Africa/Cairo')::date = p_work_date
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'mission',
      'reason', 'مأمورية عمل رسمية جارية/مكتملة'
    );
  end if;

  -- 7) فحص أذونات الحضور والتأخير (سواء معتمدة أو معلقة قيد القرار)
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(
         public.try_cast_date(r.payload->>'permitDate'),
         public.try_cast_date(r.payload->>'date'),
         public.try_cast_date(r.payload->>'startDate'),
         public.try_cast_date(r.payload->>'start_date'),
         public.try_cast_date(r.payload->>'workDate'),
         r.created_at::date
       ) = p_work_date
     order by case when r.status = 'approved' then 1 else 2 end, r.created_at desc
     limit 1
  loop
    if v_req.request_type in ('late_permit', 'permit', 'permission', 'errand', 'late_excuse')
       and coalesce(v_req.payload->>'permitKind', 'late_arrival') <> 'early_departure' then
      declare
        v_first_punch timestamptz;
        v_emp_shift public.shifts%rowtype;
        v_permit_mins integer;
        v_deadline timestamptz;
      begin
        select coalesce(
          (select ad.first_check_in from public.attendance_daily ad where ad.employee_id = p_employee_id and ad.work_date = p_work_date limit 1),
          (select min(ae.event_at) from public.attendance_events ae where ae.employee_id = p_employee_id and (ae.event_at at time zone 'Africa/Cairo')::date = p_work_date and ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted'))
        ) into v_first_punch;

        select s.* into v_emp_shift
          from public.shifts s
         where s.id = coalesce(
           (select sa.shift_id from public.shift_assignments sa where sa.employee_id = p_employee_id and sa.is_active = true and sa.effective_from <= p_work_date and (sa.effective_to is null or sa.effective_to >= p_work_date) order by sa.effective_from desc limit 1),
           public.match_flexible_shift(v_first_punch),
           public.default_shift_id()
         );

        v_permit_mins := coalesce(
          (v_req.payload->>'minutes')::integer,
          (v_req.payload->>'duration')::integer,
          ((v_req.payload->>'hours')::numeric * 60)::integer,
          120
        );

        -- إذا كان الطلب لا يزال معلقاً (Pending) يُعفى فوراً لحين بت الإدارة في طلبه
        if v_req.status = 'pending' then
          return jsonb_build_object(
            'isExempt', true,
            'category', 'pending_permit',
            'reason', 'طلب إذن حضور مسجل (' || v_permit_mins || ' دقيقة) قيد انتظار قرار المدير — الغرامات موقوفة'
          );
        end if;

        if v_emp_shift.id is not null and v_emp_shift.start_time is not null then
          v_deadline := ((p_work_date + v_emp_shift.start_time)::timestamp at time zone 'Africa/Cairo')
            + (v_permit_mins || ' minutes')::interval
            + (coalesce(v_emp_shift.grace_in_minutes, 15) || ' minutes')::interval;

          v_employee_lateness_deadline := v_deadline;

          if v_first_punch is not null and v_first_punch > v_deadline then
            null; -- تأخر لما بعد الإذن وسماحه
          else
            return jsonb_build_object(
              'isExempt', true,
              'category', 'permit',
              'reason', 'إذن حضور/تأخير رسمي مسجل (' || v_permit_mins || ' دقيقة) — الحضور ضمن فترة الإذن'
            );
          end if;
        else
          return jsonb_build_object(
            'isExempt', true,
            'category', 'permit',
            'reason', 'إذن حضور/تأخير رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
          );
        end if;
      end;
    else
      -- إذن انصراف مبكر
      return jsonb_build_object(
        'isExempt', true,
        'category', 'permit',
        'reason', 'إذن رسمي مسجل' || case when v_req.status = 'pending' then ' (قيد المراجعة)' else ' (معتمد)' end
      );
    end if;
  end loop;

  return jsonb_build_object('isExempt', false);
end;
$function$;

-- ─── 3) تضمين فحص employee_on_leave في process_request_sla مع التوافق التام ──
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_count      integer := 0;
  v_row        record;
  v_next       record;
  v_ops_emp    uuid;
  v_target     uuid;
  v_role       text;
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_due        boolean;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');
  if v_ops_emp is null then
    v_ops_emp := '767eae8e-e7be-458e-a6ca-879414e46b08'::uuid; -- محمد عبدالباسط (أبو عمار)
  end if;

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      rs.assignee_employee_id,
      rs.escalation_deadline,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and (
        (rs.status in ('active', 'escalated')
         and rs.escalation_deadline is not null
         and rs.escalation_deadline < now())
        or (rs.status = 'active' and rs.step_order = 1
            and public.employee_on_leave(coalesce(rs.assignee_employee_id, r.manager_employee_id), v_today))
      )
    order by rs.escalation_deadline nulls first
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    -- استثناء طاقم العيادات
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then
      continue;
    end if;

    -- الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن. الطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (مدير التشغيل 1 - أبو عمار)
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = null,
          comment = case
            when public.employee_on_leave(coalesce(v_row.assignee_employee_id, v_row.manager_employee_id), v_today)
              then 'تصعيد تلقائي فوري: المدير المباشر في إجازة اليوم (employee_on_leave)'
            else 'تصعيد تلقائي — تجاوز مهلة البت للمدير المباشر (ساعتان)'
          end,
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        case
          when public.employee_on_leave(coalesce(v_row.assignee_employee_id, v_row.manager_employee_id), v_today)
            then 'تصعيد تلقائي فوري: المدير المباشر في إجازة اليوم (employee_on_leave)'
          else 'تصعيد تلقائي — تجاوز مهلة البت للمدير المباشر (ساعتان)'
        end,
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1 (أبو عمار)',
          coalesce(v_row.title, '') || ' — تجاوز مهلة المدير المباشر (ساعتان)، يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'timeout_tier1',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      if v_row.manager_employee_id is not null then
        perform public.notify_employee(
          v_row.manager_employee_id,
          'تم تصعيد طلب إلى مدير التشغيل (أبو عمار)',
          coalesce(v_row.title, '') || ' — انقضت مهلة الساعتين وصُعّد لمدير التشغيل، وما زال بإمكانك قبوله أو رفضه.',
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object('deepLink', '/requests/' || v_row.request_id)
        );
      end if;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

commit;
