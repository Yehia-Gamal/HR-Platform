/* 0579_exempt_clinic_staff_girls_from_penalties.sql
   ─────────────────────────────────────────────────────────────────────────────
   استثناء طاقم عمل العيادات الطبية (فريق البنات) من خصومات وغرامات الحضور
   مع إبقاء المديرين (مصطفى أحمد كمال الدين، ويوسف رسمي شعبان) خاضعين للغرامات
   ─────────────────────────────────────────────────────────────────────────────
   بناءً على التوجيه الإداري الصريح:
   1. إعفاء فريق البنات وطاقم العيادات الطبية (تمريض، معمل، استقبال / دور clinic-staff)
      من أي خصومات أو غرامات فورية للحضور والانصراف.
   2. استثناء المديرين من هذا الإعفاء:
      - مصطفى أحمد كمال الدين (مدير العيادات الطبية)
      - يوسف رسمي شعبان (مدير مجمع وعيادات منيل شيحة)
      - وأي موظف بمسؤولية إدارية / مسمى مدير.
   3. تحديث دالة فحص الإعفاء is_employee_exempt_from_instant_penalty.
   4. تحديث تنبيه التأخر auto_notify_late_attendance لعدم إرسال تنبيهات لطاقم العيادات.
   5. إلغاء أي غرامات معلقة لطاقم العيادات المعفى.
*/

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) دالة مساعدة مركزية: هل الموظف من طاقم العيادات المعفى (وليس من المديرين)؟
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_clinic_staff_exempt(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.employees emp
      left join public.user_roles ur on ur.user_id = emp.user_id
      left join public.roles r on r.id = ur.role_id
      left join public.departments d on d.id = emp.department_id
      left join public.job_titles jt on jt.id = emp.job_title_id
     where emp.id = p_employee_id
       -- استثناء المديرين صراحةً (مصطفى كمال الدين، ويوسف رسمي، وأي وظيفة مدير)
       and emp.id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c', -- مصطفي أحمد كمال الدين (مدير العيادات الطبية)
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'  -- يوسف رسمي شعبان (مدير مجمع وعيادات منيل شيحة)
       )
       and emp.full_name_ar not ilike '%مصطفي%أحمد%كمال%'
       and emp.full_name_ar not ilike '%يوسف%رسمي%شعبان%'
       and coalesce(jt.name, '') not ilike '%مدير%'
       -- طاقم العيادات (فريق البنات: دور clinic-staff أو قسم العيادات أو مسميات التمريض والمعمل والاستقبال)
       and (
         r.slug = 'clinic-staff'
         or coalesce(d.name, '') ilike '%عياد%'
         or coalesce(jt.name, '') ilike '%عياد%'
         or coalesce(jt.name, '') in ('تمريض', 'دكتورة المعمل', 'موظف استقبال')
       )
  );
$$;

revoke all on function public.is_clinic_staff_exempt(uuid) from public, anon;
grant execute on function public.is_clinic_staff_exempt(uuid) to authenticated, service_role;

comment on function public.is_clinic_staff_exempt(uuid) is
  'فحص هل الموظف من طاقم عمل العيادات الطبية المعفى (مع استبعاد المديرين مصطفى ويوسف).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث دالة فحص الإعفاء الشامل is_employee_exempt_from_instant_penalty
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- 0) استثناء طاقم عمل العيادات الطبية (فريق البنات) وليس المديرين مصطفى ويوسف
  if public.is_clinic_staff_exempt(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'clinic_staff',
      'reason', 'طاقم عمل العيادات الطبية مستثنى من الخصومات وغرامات الحضور بقرار الإدارة'
    );
  end if;

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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث دالة التنبيه بالتأخر auto_notify_late_attendance
--    استبعاد طاقم العيادات المعفى من إرسال تنبيهات التأخر للمديرين
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.auto_notify_late_attendance()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=إثنين..5=جمعة..6=سبت..7=أحد
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- قفل استشاري لمنع سباق التشغيلات المتزامنة
  perform pg_advisory_xact_lock(hashtext('auto_notify_late_attendance'));

  -- الاستدعاء اليدوي يتطلب صلاحية؛ الكرون (auth.uid() is null) مسموح.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  -- عطلة نهاية الأسبوع: الجمعة فقط (isodow = 5)
  if v_isodow = 5 then
    return 0;
  end if;

  -- العطلات الرسمية
  if exists (select 1 from public.public_holidays where holiday_date = v_today) then
    return 0;
  end if;

  for v_rec in
    select
      ad.employee_id,
      least(120, coalesce(ad.late_minutes, 0)) as late_minutes,
      e.full_name_ar      as employee_name,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e   on e.id = ad.employee_id
    -- المدير المباشر الوحيد لكل موظف
    left join lateral (
      select m.user_id as manager_user_id, m.id as manager_employee_id
      from public.manager_relations mr
      join public.employees m on m.id = mr.manager_employee_id
      where mr.employee_id = ad.employee_id
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
        and m.is_active = true
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
      and not public.is_clinic_staff_exempt(ad.employee_id) -- استبعاد طاقم العيادات المعفى
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

revoke all on function public.auto_notify_late_attendance() from public, anon;
grant execute on function public.auto_notify_late_attendance() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تنظيف فوري: إلغاء أي غرامات معلقة لطاقم عمل العيادات الطبية المعفى
-- ─────────────────────────────────────────────────────────────────────────────

update public.instant_attendance_penalties p
   set status = 'cancelled',
       cancelled_reason = 'إلغاء بأمر الإدارة: استثناء طاقم عمل العيادات الطبية (فريق البنات) من الغرامات',
       notes = coalesce(notes || ' | ', '') || 'إلغاء بأمر الإدارة: استثناء طاقم عمل العيادات الطبية من الغرامات',
       updated_at = now()
 where public.is_clinic_staff_exempt(p.employee_id)
   and p.status in ('pending_payment', 'doubled', 'suspended');

-- رفع أي تعليق إن وُجد لأي موظفة من طاقم العيادات
update public.employees
   set status = 'active', is_active = true
 where public.is_clinic_staff_exempt(id)
   and status = 'suspended';

update public.profiles
   set status = 'active'
 where employee_id in (
   select id from public.employees where public.is_clinic_staff_exempt(id)
 )
 and status = 'suspended';
