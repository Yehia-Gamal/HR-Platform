-- ============================================================================
-- Migration 0582: استثناء الشيخ محمد وأبو عمار وطاقم العيادات فقط من الحضور والانصراف والغرامات
-- وإلغاء أي استثناءات أخرى في المنظومة
-- ============================================================================
-- بناءً على التوجيه الإداري الصريح:
-- 1. استثناء الشيخ محمد (ألشيخ محمد يوسف)
-- 2. استثناء أبو عمار (محمد عبدالباسط)
-- 3. استثناء طاقم عمل العيادات الطبية (فريق البنات: تمريض، معمل، استقبال)
-- 4. قصر الإعفاء حصرياً على هؤلاء وإلغاء أي إعفاء من الحضور أو الجزاءات لأي شخص آخر.
-- 5. منع إدراج أي غرامة أو جزاء عليهم نهائياً عبر التريجرات والدوال المعتمدة.
-- ============================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث دالة فحص طاقم العيادات is_clinic_staff_exempt
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
       -- استبعاد المديرين والمشرفين صراحةً
       and emp.id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c', -- مصطفي أحمد كمال الدين (مدير العيادات الطبية)
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', -- يوسف رسمي شعبان (مدير مجمع وعيادات منيل شيحة)
         '7d879f2d-b4d4-4da0-93d6-14e542e7fef3'  -- عبدالله رمضان أيوب (مشرف المجمع)
       )
       and emp.full_name_ar not ilike '%مصطفي%أحمد%كمال%'
       and emp.full_name_ar not ilike '%يوسف%رسمي%شعبان%'
       and emp.full_name_ar not ilike '%عبدالله%رمضان%عبدالله%'
       and coalesce(jt.name, '') not ilike '%مدير%'
       and coalesce(jt.name, '') not ilike '%مشرف%'
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


-- ─────────────────────────────────────────────────────────────────────────────
-- 2) دالة فحص الإعفاء من الحضور والانصراف is_employee_attendance_exempt
--    (مقصورة حصرياً على: الشيخ محمد، أبو عمار، وطاقم العيادات)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_attendance_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 1. الشيخ محمد يوسف
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02'  -- الشيخ محمد يوسف (أرشيف)
  ) or v_rec.employee_code = '+201121622820'
    or v_rec.full_name_ar ilike '%الشيخ محمد يوسف%'
    or v_rec.full_name_ar ilike '%ألشيخ محمد يوسف%' then
    return true;
  end if;

  -- 2. أبو عمار (محمد عبدالباسط)
  if p_employee_id = '767eae8e-e7be-458e-a6ca-879414e46b08'
    or v_rec.employee_code in ('+201150499996', '01150499996')
    or v_rec.phone_e164 in ('+201150499996', '01150499996')
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%أبو عمار%'
    or v_rec.full_name_ar ilike '%محمد عبدالباسط%' then
    return true;
  end if;

  -- 3. طاقم العيادات الطبية (فريق البنات)
  if public.is_clinic_staff_exempt(p_employee_id) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.is_employee_attendance_exempt(uuid) from public, anon;
grant execute on function public.is_employee_attendance_exempt(uuid) to authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3) دالة فحص الإعفاء من الغرامات والجزاءات is_employee_penalty_exempt
--    (مقصورة حصرياً على: الشيخ محمد، أبو عمار، وطاقم العيادات)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  -- المعفى من الحضور والانصراف معفى بالتبعية من غرامات الحضور
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_penalty_exempt into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 1. الشيخ محمد يوسف
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e',
    '886f4942-c469-4a03-8f02-659fd02c4a02'
  ) or v_rec.full_name_ar ilike '%الشيخ محمد%'
    or v_rec.full_name_ar ilike '%ألشيخ محمد%' then
    return true;
  end if;

  -- 2. أبو عمار
  if p_employee_id = '767eae8e-e7be-458e-a6ca-879414e46b08'
    or v_rec.full_name_ar ilike '%ابو عمار%'
    or v_rec.full_name_ar ilike '%أبو عمار%'
    or v_rec.full_name_ar ilike '%محمد عبدالباسط%' then
    return true;
  end if;

  -- 3. طاقم العيادات
  if public.is_clinic_staff_exempt(p_employee_id) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.is_employee_penalty_exempt(uuid) from public, anon;
grant execute on function public.is_employee_penalty_exempt(uuid) to authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث دالة فحص الإعفاء الشامل من الغرامة is_employee_exempt_from_instant_penalty
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
  -- 0) استثناء الشيخ محمد وأبو عمار وطاقم العيادات بقرار الإدارة
  if public.is_employee_penalty_exempt(p_employee_id)
     or public.is_employee_attendance_exempt(p_employee_id) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'management_exemption',
      'reason', 'معفى من الحضور والانصراف والغرامات بقرار الإدارة'
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
      'reason', 'إذن حضور معتمد (' || case v_req.request_type
        when 'late_permit' then 'إذن تأخير'
        when 'early_permit' then 'إذن انصراف مبكر'
        when 'errand' then 'مأمورية سريعة'
        else 'تصريح رسمي'
      end || case when v_req.status = 'pending' then ' — قيد المراجعة)' else ' — معتمد)' end
    );
  end loop;

  -- 5) فحص طلبات المأموريات، القوافل، الفاندي، والإجازات في جدول requests
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status not in ('rejected', 'cancelled')
       and (
         (r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave')
          and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         or (r.request_type in ('convoy', 'field_convoy')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         or (r.request_type in ('fundraising', 'fandy', 'fundi')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
         or (coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission')
             and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                 and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
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
-- 5) تريجر منع تسجيل أي غرامة في قواعد البيانات على المعفيين
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.tg_prevent_admin_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_employee_penalty_exempt(NEW.employee_id)
     or public.is_employee_attendance_exempt(NEW.employee_id) then
    return null; -- إلغاء إدراج الغرامة فوراً
  end if;
  return NEW;
end;
$$;

drop trigger if exists tg_prevent_admin_penalty_instant on public.instant_attendance_penalties;
create trigger tg_prevent_admin_penalty_instant
before insert or update on public.instant_attendance_penalties
for each row
execute function public.tg_prevent_admin_penalty_fn();

drop trigger if exists tg_prevent_admin_penalty_regular on public.employee_penalties;
create trigger tg_prevent_admin_penalty_regular
before insert or update on public.employee_penalties
for each row
execute function public.tg_prevent_admin_penalty_fn();


-- ─────────────────────────────────────────────────────────────────────────────
-- 6) تحديث دالة تنبيهات التأخر auto_notify_late_attendance
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
      -- استبعاد المعفيين بقرار الإدارة (الشيخ محمد، أبو عمار، وطاقم العيادات)
      and not public.is_clinic_staff_exempt(ad.employee_id)
      and not public.is_employee_attendance_exempt(ad.employee_id)
      and not public.is_employee_penalty_exempt(ad.employee_id)
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
-- 7) تحديث جدول الموظفين: قصر أعلام الإعفاء على الشيخ محمد، أبو عمار، وطاقم العيادات
--    وإلغاء الإعفاء عن أي شخص آخر
-- ─────────────────────────────────────────────────────────────────────────────

-- تصفير الإعفاء للجميع أولاً
update public.employees
   set is_attendance_exempt = false,
       is_penalty_exempt = false;

-- تفعيل الإعفاء حصرياً للشيخ محمد، أبو عمار، وطاقم العيادات المعفى
update public.employees
   set is_attendance_exempt = true,
       is_penalty_exempt = true
 where id in (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف (نشط)
   '886f4942-c469-4a03-8f02-659fd02c4a02', -- الشيخ محمد يوسف (أرشيف)
   '767eae8e-e7be-458e-a6ca-879414e46b08'  -- أبو عمار (محمد عبدالباسط)
 )
 or public.is_clinic_staff_exempt(id);


-- ─────────────────────────────────────────────────────────────────────────────
-- 8) إلغاء وتصفير أي غرامات معلقة سابقة للمستثنين
-- ─────────────────────────────────────────────────────────────────────────────

update public.instant_attendance_penalties
   set status = 'cancelled',
       notes = coalesce(notes, '') || ' — أُلغيت لاستثناء الموظف بقرار الإدارة'
 where (
   employee_id in (
     '7b0740fa-66ba-4616-8674-3dbd8e14109e',
     '767eae8e-e7be-458e-a6ca-879414e46b08'
   )
   or public.is_clinic_staff_exempt(employee_id)
 )
 and status not in ('cancelled', 'paid', 'waived');

update public.employee_penalties
   set status = 'waived',
       waive_reason = 'استثناء معتمد بقرار الإدارة'
 where (
   employee_id in (
     '7b0740fa-66ba-4616-8674-3dbd8e14109e',
     '767eae8e-e7be-458e-a6ca-879414e46b08'
   )
   or public.is_clinic_staff_exempt(employee_id)
 )
 and status not in ('cancelled', 'paid', 'waived');

-- ─────────────────────────────────────────────────────────────────────────────
-- 9) تسجيل المايجريشن
-- ─────────────────────────────────────────────────────────────────────────────

insert into supabase_migrations.schema_migrations (version)
values ('0582')
on conflict (version) do nothing;

commit;
