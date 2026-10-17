-- ===========================================================================
-- 0690: منع تكرار الإشعارات تماماً وتخصيص عناوين الموظف المتأخر بالاسم الثنائي
-- ===========================================================================
-- 1) إضافة حماية منع التكرار الجذري في دالة notify_employee:
--    عدم إدراج أي إشعار مكرر لنفس الموظف ونفس الكيان أو المحتوى خلال 60 ثانية.
--
-- 2) معالجة تكرار إشعار الوصول للمدير التنفيذي:
--    عندما يكون المدير المباشر هو نفسه المدير التنفيذي (مثل الشيخ محمد يوسف)،
--    كان يتم إرسال الإشعار مرتين (مرة كمدير مباشر ومرة كمدير تنفيذي).
--    تم استثناء المدير المباشر من حلقة تكرار المديرين التنفيذيين.
--
-- 3) تخصيص عنوان إشعار الموظف المتأخر بالاسم الثنائي:
--    «موظف متأخر: بلال محمد» و«موظف متأخر: يحيى جمال» بدلاً من الاسم الرباعي الطويل
--    الذي يسبب اقتطاع العنوان وظهور نقاط (...).
--
-- 4) تنظيف الإشعارات المكررة الموجودة حالياً بأثر رجعي.
-- ===========================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث notify_employee مع فحص منع التكرار
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.notify_employee(
  p_employee_id uuid,
  p_title text,
  p_body text,
  p_category text default 'request'::text,
  p_priority text default 'normal'::text,
  p_entity_type text default null::text,
  p_entity_id uuid default null::uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_user uuid;
  v_id uuid;
begin
  if p_employee_id is null then
    return null;
  end if;

  select p.id into v_user from public.profiles p where p.employee_id = p_employee_id;
  if v_user is null then
    return null;
  end if;

  -- فحص منع التكرار: إذا أُرسل إشعار مطابق لنفس الموظف ونفس العنوان والكيان خلال آخر 60 ثانية، نتفادى التكرار فوراً
  select n.id into v_id
  from public.notifications n
  where n.recipient_employee_id = p_employee_id
    and n.title = p_title
    and (
      (p_entity_id is not null and n.entity_id = p_entity_id)
      or (p_entity_id is null and n.body = p_body)
    )
    and n.created_at >= (now() - interval '60 seconds')
  order by n.created_at desc
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.notifications(
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    entity_type,
    entity_id,
    metadata,
    created_by
  ) values (
    v_user,
    p_employee_id,
    p_title,
    p_body,
    p_category,
    p_priority,
    p_entity_type,
    p_entity_id,
    coalesce(p_metadata, '{}'::jsonb),
    auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.notify_employee(uuid,text,text,text,text,text,uuid,jsonb) from public;
grant execute on function public.notify_employee(uuid,text,text,text,text,text,uuid,jsonb) to authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث tg_attendance_notify_manager لمنع إرسال إشعارين للمدير التنفيذي
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.tg_attendance_notify_manager()
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
  v_two_names text;
  v_exec_emp uuid;
  v_title text;
  v_body text;
  v_has_actual_punch boolean := false;

  -- متغيرات التعويض والغرامة
  v_target_out timestamptz;
  v_target_out_str text;
  v_penalty numeric(12,2) := 0;
  v_self_title text;
  v_self_body text;
  v_priority text := 'normal';
begin
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  -- حماية المأموريات: التحقق من وجود بصمة حضور فعلية بالمقر اليوم
  if v_event = 'attendance_check_in' then
    select exists (
      select 1 from public.attendance_events ae
      where ae.employee_id = new.employee_id
        and (ae.event_at at time zone 'Africa/Cairo')::date = new.work_date
        and ae.event_type = 'CHECK_IN'
        and ae.status in ('accepted', 'adjusted')
        and ae.source not in ('mission_auto')
    ) into v_has_actual_punch;

    if not v_has_actual_punch then
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;
  
  -- استخراج الاسم الثنائي (أول كلمتين)
  v_two_names := trim(split_part(coalesce(v_emp_ar, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_ar, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_ar, ''), 'موظف');
  end if;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'FMHH12:MI'
  ) || case when extract(hour from (
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end;

  if v_event = 'attendance_check_in' then
    v_target_out := new.first_check_in + interval '8 hours';
    v_target_out_str := to_char(v_target_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                        case when (v_target_out at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;

    if coalesce(new.late_minutes, 0) > 15 then
      v_penalty := public.calc_instant_penalty_amount(least(120, new.late_minutes));
      v_self_title := '⏰ تسجيل حضور متأخر — فرصة تعويض الغرامة';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة — خصم مقرر ' || v_penalty || ' ج.م).' || chr(10) ||
                      '💡 اقتراح ذكي: إذا استكملت 8 ساعات عمل حتى الساعة ' || v_target_out_str || ' وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!';
      v_priority   := 'high';
    elsif coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '⏰ تسجيل حضور (فترة السماح الرسمية)';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة ضمن فترة السماح 15 دقيقة — بدون أي غرامة).' || chr(10) ||
                      '💡 موعد إتمام 8 ساعات عمل هو الساعة ' || v_target_out_str || ' وسجل انصرافك حينها.';
      v_priority   := 'normal';
    else
      v_self_title := '✅ تم تسجيل حضورك بنجاح';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' بموعدك المنضبط.' || chr(10) ||
                      '💡 موعد نهاية الـ 8 ساعات هو الساعة ' || v_target_out_str || '.';
      v_priority   := 'normal';
    end if;

    -- الاسم ثنائي واضح
    v_title := format('وصل %s للعمل بالمجمع', v_two_names);
    v_body  := format(
      'دخل الساعة %s%s',
      v_time,
      case when coalesce(new.late_minutes, 0) > 0 then format(' (تأخير %s دقيقة)', new.late_minutes) else '' end
    );
  else
    -- checkout
    if coalesce(new.work_minutes, 0) >= 480 and coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '🎉 تم تسجيل انصرافك وإسقاط غرامة التأخير';
      v_self_body  := 'سُجّل انصرافك في تمام الساعة ' || v_time || '. لقد استوفيت 8 ساعات عمل كاملة بنجاح، وتم إلغاء غرامة التأخير الصباحي وإسقاط الخصم بالكامل!';
      v_priority   := 'high';
    else
      v_self_title := 'تم تسجيل انصرافك';
      v_self_body  := format('تم تسجيل انصرافك الساعة %s', v_time);
      v_priority   := 'normal';
    end if;

    -- الاسم ثنائي واضح
    v_title := format('خرج %s من المجمع', v_two_names);
    v_body  := format(
      'انصرف الساعة %s (إجمالي العمل: %s دقيقة%s)',
      v_time,
      coalesce(new.work_minutes, 0),
      case when coalesce(new.overtime_minutes, 0) > 0 then format(' — إضافي: +%s د', new.overtime_minutes) else '' end
    );
  end if;

  -- 1) إشعار الموظف نفسه
  perform public.notify_employee(
    new.employee_id,
    v_self_title,
    v_self_body,
    'attendance', v_priority, 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time,
      'lateMinutes', new.late_minutes,
      'workMinutes', new.work_minutes,
      'overtimeMinutes', new.overtime_minutes,
      'targetCheckoutTime', v_target_out_str,
      'penaltyAmount', v_penalty,
      'deepLink', 'ahlashabab://action/attendance'
    )
  );

  -- 2) إشعار المدير المباشر
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null and v_manager <> new.employee_id then
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

  -- 3) إشعار المدير التنفيذي:
  --    استثناء من تم إشعاره بالفعل كمدير مباشر (e.id <> v_manager) منعاً لتكرار الإشعار!
  for v_exec_emp in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug in ('executive-director', 'executive')
      and e.is_active = true
      and e.id <> new.employee_id
      and e.id <> coalesce(v_manager, '00000000-0000-0000-0000-000000000000'::uuid)
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to is null or ur.effective_to > now())
  loop
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
  end loop;

  return new;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث tg_notify_manager_late_arrival (اعتماد الاسم الثنائي وحماية المأموريات)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.tg_notify_manager_late_arrival()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee    record;
  v_manager     record;
  v_notif_id    uuid;
  v_late_text   text;
  v_two_names   text;
begin
  -- تنطبق فقط على CHECK_IN متأخر (late_minutes > 0) وبصمة فعلية
  if new.event_type <> 'CHECK_IN' or coalesce(new.late_minutes, 0) <= 0 then
    return new;
  end if;

  if coalesce(new.source, '') = 'mission_auto' then
    return new;
  end if;

  -- جلب بيانات الموظف المتأخر
  select e.id, e.full_name_ar, e.user_id
    into v_employee
    from public.employees e
   where e.id = new.employee_id;

  if not found then return new; end if;

  -- جلب المدير المباشر
  select e.id, e.user_id
    into v_manager
    from public.manager_relations mr
    join public.employees e on e.id = mr.manager_employee_id
   where mr.employee_id = new.employee_id
     and e.user_id is not null
     and e.is_active = true
   limit 1;

  if not found or v_manager.user_id is null then return new; end if;

  -- استخراج الاسم الثنائي
  v_two_names := trim(split_part(coalesce(v_employee.full_name_ar, ''), ' ', 1) || ' ' || split_part(coalesce(v_employee.full_name_ar, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(v_employee.full_name_ar, 'غير محدد');
  end if;

  -- صياغة وقت التأخير
  v_late_text := case
    when new.late_minutes >= 60 then
      (new.late_minutes / 60)::text || ' ساعة و' || (new.late_minutes % 60)::text || ' دقيقة'
    else
      new.late_minutes::text || ' دقيقة'
  end;

  -- إدراج الإشعار باستخدام notify_employee للاستفادة من فحص منع التكرار التلقائي
  perform public.notify_employee(
    v_manager.id,
    'موظف متأخر: ' || v_two_names,
    'سجّل ' || coalesce(v_employee.full_name_ar, 'الموظف') || ' حضوره متأخراً بمقدار ' || v_late_text || '.',
    'system',
    'normal',
    'attendance_event',
    new.id,
    jsonb_build_object(
      'lateMinutes', new.late_minutes,
      'employeeId', new.employee_id::text
    )
  );

  return new;
exception
  when others then
    return new;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث بأثر رجعي وتنظيف الإشعارات المكررة
-- ─────────────────────────────────────────────────────────────────────────────

-- أ) تحديث عناوين إشعارات التأخر القديمة لتكون بالاسم الثنائي الأنيق
update public.notifications
set title = 'موظف متأخر: ' || trim(split_part(substring(title from 'موظف متأخر: (.*)'), ' ', 1) || ' ' || split_part(substring(title from 'موظف متأخر: (.*)'), ' ', 2))
where title like 'موظف متأخر: %'
  and length(title) > 20;

-- ب) حذف الإشعارات المكررة القديمة لنفس الموظف ونفس الحدث بفارق زمني أقل من دقيقة
delete from public.notifications
where id in (
  select n2.id
  from public.notifications n1
  join public.notifications n2
    on n1.recipient_employee_id = n2.recipient_employee_id
   and n1.title = n2.title
   and (
     (n1.entity_id is not null and n1.entity_id = n2.entity_id)
     or (n1.body = n2.body)
   )
   and n1.id < n2.id
   and abs(extract(epoch from (n1.created_at - n2.created_at))) <= 60
);

commit;
