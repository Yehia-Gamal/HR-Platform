-- Migration 0669: إلغاء غرامة التأخير تلقائياً عند استيفاء الموظف 8 ساعات عمل كاملة
-- ==============================================================================
-- قاعدة العمل:
-- إذا تأخر الموظف عن موعد الحضور الرسمي وسُجلت عليه غرامة تأخير فورية، ثم بقي في
-- العمل حتى أتمّ 8 ساعات عمل مقررة (من وقت دخوله حتى وقت خروجه، مثلاً من 10:23 ص حتى 6:23 م)،
-- يتم تلقائياً إلغاء الغرامة والخصم الذي وقع عليه وإشعار الموظف والمدير والإدارة بذلك في التطبيق.
-- وإذا غادر قبل إتمام 8 ساعات عمل، تظل الغرامة مستحقة السداد ويلزمه دفعها.
-- ==============================================================================

begin;

-- ─── 1) دالة إلغاء الغرامة التلقائية لاستيفاء 8 ساعات عمل ───────────────────────
create or replace function public.auto_waive_penalty_if_completed_eight_hours(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_att record;
  v_pen record;
  v_work_minutes integer;
  v_emp_name text;
  v_mgr_id uuid;
  v_in_str text;
  v_out_str text;
  v_hours integer;
  v_mins integer;
begin
  if p_employee_id is null or p_work_date is null then
    return jsonb_build_object('waived', false, 'reason', 'invalid_params');
  end if;

  -- 1. استعلام سجل الحضور اليومي
  select ad.id, ad.first_check_in, ad.last_check_out, ad.work_minutes
    into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if not found or v_att.first_check_in is null or v_att.last_check_out is null then
    return jsonb_build_object('waived', false, 'reason', 'no_checkout');
  end if;

  -- 2. حساب إجمالي دقائق العمل الفعلية
  v_work_minutes := greatest(
    coalesce(v_att.work_minutes, 0),
    floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
  );

  -- 3. فحص الغرامة الفورية المسجلة لذلك اليوم (إن وُجدت)
  select p.id, p.current_amount, p.original_amount, p.status, p.escalation_level, p.notes
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if not found then
    return jsonb_build_object(
      'waived', false,
      'workMinutes', v_work_minutes,
      'reason', 'no_active_penalty'
    );
  end if;

  -- إذا لم يكتمل وقت العمل (أقل من 8 ساعات = 480 دقيقة)
  if v_work_minutes < 480 then
    return jsonb_build_object(
      'waived', false,
      'penaltyRemaining', true,
      'penaltyId', v_pen.id,
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'remainingMinutes', (480 - v_work_minutes),
      'message', 'الغرامة مستحقة للمغادرة قبل إتمام 8 ساعات عمل'
    );
  end if;

  -- 4. الموظف أتمّ 8 ساعات عمل كاملة (480 دقيقة أو أكثر) → إلغاء الغرامة فوراً
  select e.full_name_ar into v_emp_name
    from public.employees e
   where e.id = p_employee_id;

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_out_str := to_char(v_att.last_check_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (v_att.last_check_out at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_hours := v_work_minutes / 60;
  v_mins := v_work_minutes % 60;

  -- تحديث حالة الغرامة إلى ملغاة مع توثيق الساعات والدقائق
  update public.instant_attendance_penalties
     set status = 'cancelled',
         cancelled_reason = 'إلغاء تلقائي: استيفاء 8 ساعات عمل كاملة (تعويض التأخير)',
         notes = coalesce(notes || ' | ', '') ||
                 'تم إلغاء الخصم لاستيفاء وقت العمل المقرر (8 ساعات كاملة) — الدخول: ' ||
                 v_in_str || '، الخروج: ' || v_out_str ||
                 ' (إجمالي العمل: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة)',
         updated_at = now()
   where id = v_pen.id;

  -- رفع التعليق إن كان موقوفاً بسبب هذه الغرامة ولا توجد غرامة أخرى مضاعفة
  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = p_employee_id
       and status in ('doubled', 'suspended')
       and id <> v_pen.id
  ) then
    update public.employees set is_active = true, status = 'active' where id = p_employee_id;
    update public.profiles set status = 'active' where employee_id = p_employee_id;
  end if;

  -- 5. إرسال الإشعارات الشفافة في التطبيق
  -- أ) إشعار الموظف نفسه
  perform public.notify_employee(
    p_employee_id,
    '🎉 إلغاء غرامة التأخير — استيفاء 8 ساعات عمل',
    'تم إلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) عنك يا ' || coalesce(v_emp_name, '') || ' لاستيفائك وقت العمل المقرر كاملاً (8 ساعات). وقت الحضور: ' || v_in_str || ' — وقت الانصراف: ' || v_out_str || ' (إجمالي العمل: ' || v_hours || ' ساعة و' || v_mins || ' دقيقة).',
    'system',
    'high',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'waived', true,
      'reason', 'eight_hours_completed',
      'amount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
    )
  );

  -- ب) إشعار المدير المباشر باسم الموظف الصريح
  select mr.manager_employee_id into v_mgr_id
    from public.manager_relations mr
    join public.employees m on m.id = mr.manager_employee_id
   where mr.employee_id = p_employee_id
     and mr.effective_from <= current_date
     and (mr.effective_to is null or mr.effective_to >= current_date)
     and m.is_active = true
   order by case mr.relation_type when 'primary' then 1 when 'functional' then 2 else 3 end
   limit 1;

  if v_mgr_id is not null and v_mgr_id <> p_employee_id then
    perform public.notify_employee(
      v_mgr_id,
      '🎉 إلغاء غرامة تأخير — ' || coalesce(v_emp_name, 'موظف'),
      'تم إلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) عن الموظف ' || coalesce(v_emp_name, 'الموظف') || ' لاستيفائه وقت العمل المقرر كاملاً (8 ساعات). وقت الحضور: ' || v_in_str || ' — وقت الانصراف: ' || v_out_str || ' (إجمالي العمل: ' || v_hours || ' س و' || v_mins || ' د).',
      'attendance',
      'normal',
      'instant_penalty',
      v_pen.id,
      jsonb_build_object(
        'penaltyId', v_pen.id,
        'employeeId', p_employee_id,
        'employeeName', v_emp_name,
        'waived', true,
        'amount', v_pen.current_amount,
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );
  end if;

  -- ج) إشعار الإدارة والموارد البشرية (payroll.run.manage)
  perform public.notify_employees_with_permission(
    'payroll.run.manage',
    '🎉 إلغاء غرامة تأخير — ' || coalesce(v_emp_name, 'موظف'),
    'تم إلغاء غرامة التأخير (' || v_pen.current_amount || ' ج.م) عن ' || coalesce(v_emp_name, 'الموظف') || ' لاستيفائه 8 ساعات عمل كاملة (الدخول: ' || v_in_str || ' — الخروج: ' || v_out_str || ').',
    'attendance',
    'normal',
    'instant_penalty',
    v_pen.id,
    jsonb_build_object(
      'penaltyId', v_pen.id,
      'employeeId', p_employee_id,
      'employeeName', v_emp_name,
      'waived', true
    ),
    p_employee_id
  );

  -- د) تسجيل حدث التدقيق
  perform public.log_audit_event(
    'instant_penalty.waived_eight_hours',
    'finance',
    'info',
    'instant_attendance_penalties',
    v_pen.id,
    'إلغاء تلقائي لغرامة التأخير لاستيفاء 8 ساعات عمل للموظف ' || coalesce(v_emp_name, ''),
    null,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'employeeName', v_emp_name,
      'workDate', p_work_date,
      'workMinutes', v_work_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'waivedAmount', v_pen.current_amount
    )
  );

  return jsonb_build_object(
    'waived', true,
    'penaltyId', v_pen.id,
    'employeeName', v_emp_name,
    'amount', v_pen.current_amount,
    'workMinutes', v_work_minutes,
    'checkIn', v_in_str,
    'checkOut', v_out_str,
    'message', 'تم إلغاء غرامة التأخير لاستيفاء 8 ساعات عمل كاملة'
  );
end;
$$;

revoke all on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) from public, anon;
grant execute on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) to authenticated, service_role;
comment on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) is
  '0669: إلغاء غرامة التأخير تلقائياً للموظف الذي أتم 8 ساعات عمل كاملة في اليوم وإرسال إشعارات التوثيق.';


-- ─── 2) دالة فحص حالة غرامة الانصراف للتغذية الراجعة الفورية للموبايل ───────────
create or replace function public.get_checkout_penalty_status(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_att record;
  v_pen record;
  v_work_minutes integer;
  v_in_str text;
  v_out_str text;
begin
  select ad.first_check_in, ad.last_check_out, ad.work_minutes
    into v_att
    from public.attendance_daily ad
   where ad.employee_id = p_employee_id
     and ad.work_date = p_work_date;

  if not found or v_att.first_check_in is null or v_att.last_check_out is null then
    return null;
  end if;

  v_work_minutes := greatest(
    coalesce(v_att.work_minutes, 0),
    floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer
  );

  v_in_str := to_char(v_att.first_check_in at time zone 'Africa/Cairo', 'FMHH12:MI') ||
              case when (v_att.first_check_in at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;
  v_out_str := to_char(v_att.last_check_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
               case when (v_att.last_check_out at time zone 'Africa/Cairo')::time < '12:00'::time then ' ص' else ' م' end;

  -- فحص الغرامة الملغاة حديثاً لاستيفاء 8 ساعات
  select p.id, p.current_amount, p.cancelled_reason
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status = 'cancelled'
     and p.cancelled_reason like '%8 ساعات%';

  if found then
    return jsonb_build_object(
      'penaltyWaived', true,
      'waivedAmount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'message', 'تم استيفاء 8 ساعات عمل كاملة — تم إلغاء خصم غرامة التأخير (' || v_pen.current_amount || ' ج.م) بنجاح 🎉'
    );
  end if;

  -- فحص الغرامة المتبقية إن غادر قبل إتمام 8 ساعات
  select p.id, p.current_amount
    into v_pen
    from public.instant_attendance_penalties p
   where p.employee_id = p_employee_id
     and p.work_date = p_work_date
     and p.status in ('pending_payment', 'doubled', 'suspended');

  if found and v_work_minutes < 480 then
    return jsonb_build_object(
      'penaltyRemaining', true,
      'penaltyAmount', v_pen.current_amount,
      'workMinutes', v_work_minutes,
      'remainingMinutes', (480 - v_work_minutes),
      'checkIn', v_in_str,
      'checkOut', v_out_str,
      'message', 'تنبيه: انصراف قبل إتمام 8 ساعات عمل (متبقي ' || (480 - v_work_minutes) || ' دقيقة) — غرامة التأخير (' || v_pen.current_amount || ' ج.م) تظل مستحقة السداد.'
    );
  end if;

  return null;
end;
$$;

revoke all on function public.get_checkout_penalty_status(uuid, date) from public, anon;
grant execute on function public.get_checkout_penalty_status(uuid, date) to authenticated, service_role;


-- ─── 3) تريجر تلقائي على جدول الحضور اليومي (attendance_daily) ─────────────────
create or replace function public.tg_auto_waive_penalty_on_eight_hours()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.last_check_out is not null and new.first_check_in is not null then
    perform public.auto_waive_penalty_if_completed_eight_hours(new.employee_id, new.work_date);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_waive_penalty_eight_hours on public.attendance_daily;
create trigger trg_auto_waive_penalty_eight_hours
  after insert or update of last_check_out, work_minutes
  on public.attendance_daily
  for each row
  execute function public.tg_auto_waive_penalty_on_eight_hours();


-- ─── 4) تحديث تسجيل الحضور المحلي البيومتري لإرجاع تفاصيل الإلغاء ──────────────
create or replace function public.punch_attendance_local_biometric_v1(
  p_operation_id uuid,
  p_event_type text,
  p_installation_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_hash text;
  v_managed public.managed_devices;
  v_employee_device public.employee_devices;
  v_operation public.local_attendance_operations;
  v_event_id uuid;
  v_event public.attendance_events;
  v_result jsonb;
  v_error text;
  v_verification_method text;
  v_waive_status jsonb;
  v_work_date date;
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required','invalid_attendance_location'
  ];
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode='42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode='22023';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if length(trim(coalesce(p_installation_id,'')))<12 then
    raise exception 'invalid_installation_id' using errcode='22023';
  end if;
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode='42501';
  end if;

  v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'managed_device_not_active',
      'replayed', false
    );
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'employee_device_not_active',
      'replayed', false
    );
  end if;

  v_verification_method := case
    when v_managed.biometric_available then 'local_biometric'
    else 'device_lock'
  end;

  insert into public.local_attendance_operations(
    operation_id,user_id,employee_id,event_type,credential_id
  ) values (p_operation_id,auth.uid(),v_employee_id,p_event_type,v_hash)
  on conflict (operation_id) do nothing;
  select * into v_operation from public.local_attendance_operations
  where operation_id=p_operation_id for update;
  if v_operation.user_id<>auth.uid()
     or v_operation.employee_id<>v_employee_id
     or v_operation.event_type<>p_event_type
     or v_operation.credential_id<>v_hash then
    raise exception 'attendance_idempotency_conflict' using errcode='22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result,'{}'::jsonb)
      || jsonb_build_object('replayed',true);
  end if;

  begin
    v_event_id := public.record_attendance_local_biometric(
      v_employee_id,p_event_type,p_latitude,p_longitude,
      p_accuracy_meters,p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error=any(v_known_errors) then
      v_result := jsonb_build_object('ok',false,'error',v_error,'replayed',false);
      update public.local_attendance_operations
      set status='rejected',result=v_result,completed_at=now()
      where operation_id=p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  update public.employee_devices set last_used_at=now()
  where id=v_employee_device.id;
  update public.managed_devices set last_seen_at=now()
  where id=v_managed.id;
  select * into v_event from public.attendance_events where id=v_event_id;

  v_work_date := (v_event.event_at at time zone 'Africa/Cairo')::date;

  -- عند الانصراف: جلب حالة الإلغاء لاستيفاء 8 ساعات إن وُجدت
  if p_event_type = 'CHECK_OUT' then
    v_waive_status := public.get_checkout_penalty_status(v_employee_id, v_work_date);
  end if;

  v_result := jsonb_build_object(
    'ok',true,'verified',true,
    'verificationMethod',v_verification_method,
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );

  if v_waive_status is not null then
    v_result := v_result || v_waive_status;
  end if;

  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;
  return v_result;
end;
$$;


-- ─── 5) تحديث auto_generate_instant_penalties لدعم استيفاء 8 ساعات ──────────
create or replace function public.auto_generate_instant_penalties()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  v_flex_start time;
  v_flex_grace integer;
  v_start time;
  v_grace integer;
  v_start_label text;
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

  -- 3. خطوة التنظيف التلقائي:
  -- أ) إلغاء الغرامات لمن لديهم إعفاء معتمد
  -- ب) إلغاء الغرامات لمن استوفوا 8 ساعات عمل كاملة في ذلك اليوم (0669)
  for v_pen in
    select p.id, p.employee_id, p.work_date, e.full_name_ar
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
     where p.status in ('pending_payment', 'doubled', 'suspended')
       and p.work_date >= v_today - 3
  loop
    -- فحص استيفاء 8 ساعات عمل أولاً
    perform public.auto_waive_penalty_if_completed_eight_hours(v_pen.employee_id, v_pen.work_date);

    -- فحص الإعفاءات الرسمية
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_pen.employee_id, v_pen.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي: ' || coalesce(v_exempt->>'reason', 'عذر معتمد'),
             updated_at = now()
       where id = v_pen.id;

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

  -- 4. الدوام الأساسي المعتمد هو المعيار العام (10:00 ص مع 15 دقيقة سماح حتى 10:15 ص)
  select s.start_time, coalesce(s.grace_in_minutes, 15)
    into v_flex_start, v_flex_grace
    from public.shifts s
   where s.is_active and s.code = 'OFFICIAL'
   limit 1;
  if v_flex_start is null then
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_flex_start, v_flex_grace
      from public.shifts s
     where s.id = public.default_shift_id();
  end if;
  v_flex_start := coalesce(v_flex_start, '10:00'::time);
  v_flex_grace := coalesce(v_flex_grace, 15);

  -- 5. فحص الموظفين
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
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_emp.employee_id, v_today);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      continue;
    end if;

    v_att := null;
    select ad.id, ad.status, ad.late_minutes, ad.first_check_in, ad.last_check_out, ad.work_minutes
      into v_att
      from public.attendance_daily ad
     where ad.employee_id = v_emp.employee_id
       and ad.work_date = v_today
     limit 1;

    if v_att.status in ('on_leave', 'mission', 'excused', 'holiday', 'weekend') then
      continue;
    end if;

    -- 0669: إذا كان الموظف قد أتم 8 ساعات عمل بالفعل (480 دقيقة) لا تُسجل عليه أي غرامة
    if v_att.id is not null and v_att.first_check_in is not null and v_att.last_check_out is not null then
      if greatest(coalesce(v_att.work_minutes, 0), floor(extract(epoch from (date_trunc('minute', v_att.last_check_out) - date_trunc('minute', v_att.first_check_in))) / 60)::integer) >= 480 then
        continue;
      end if;
    end if;

    -- الحالة أ: الموظف بصم حضوراً ولديه تأخير فعلي أكثر من فترة السماح
    if v_att.id is not null and v_att.first_check_in is not null then
      if coalesce(v_att.late_minutes, 0) > 15 then
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

    -- الحالة ب: لم يسجل بصمة حضور بعد
    if v_emp.is_active = false or v_emp.emp_status is distinct from 'active' then
      continue;
    end if;

    v_start := null;
    v_grace := null;
    select s.start_time, coalesce(s.grace_in_minutes, 15)
      into v_start, v_grace
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_emp.employee_id
       and sa.is_active
       and sa.effective_from <= v_today
       and (sa.effective_to is null or sa.effective_to >= v_today)
     order by sa.effective_from desc
     limit 1;

    if v_start is null then
      select s.start_time, coalesce(s.grace_in_minutes, 15)
        into v_start, v_grace
        from public.roster_days rd
        join public.shifts s on s.id = rd.shift_id
        join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
       where rd.employee_id = v_emp.employee_id
         and rd.work_date = v_today
         and rd.day_status = 'scheduled'
       order by wr.published_at desc nulls last
       limit 1;
    end if;

    v_start := coalesce(v_start, v_flex_start);
    v_grace := coalesce(v_grace, v_flex_grace);

    v_elapsed_mins := floor(extract(epoch from (v_time_cairo - v_start)) / 60)::integer;
    if v_elapsed_mins <= v_grace then
      continue;
    end if;

    v_start_label := to_char(v_start, 'FMHH12:MI') || case when v_start < '12:00'::time then ' ص' else ' م' end;
    v_penalty_minutes := least(120, v_elapsed_mins);
    v_notes := case
      when v_elapsed_mins >= 120 then
        'تأخير عن بداية الوردية (' || v_start_label || ') — حُصر عند الحد الأقصى ساعتان (120 دقيقة) لعدم تسجيل البصمة حتى الآن'
      else
        'تأخير عن بداية الوردية (' || v_start_label || ') — لم يسجل بصمة الحضور حتى الآن (' || to_char(v_now_cairo, 'HH12:MI AM') || ')'
      end;

    perform public.generate_instant_penalty(v_emp.employee_id, v_today, v_penalty_minutes, v_notes);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

comment on function public.auto_generate_instant_penalties() is
  '0669: توليد غرامات التأخير التلقائية مع استثناء وتخطي كل من أتم 8 ساعات عمل كاملة في اليوم.';

-- ─── 6) تشغيل الفحص على البيانات الحالية لليوم ───────────────────────────────
select public.auto_generate_instant_penalties();

commit;
