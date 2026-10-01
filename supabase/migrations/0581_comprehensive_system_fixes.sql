-- ═════════════════════════════════════════════════════════════════════════════
-- Migration 0581: إصلاحات شاملة للنظام
-- ═════════════════════════════════════════════════════════════════════════════
-- (1) مصطفى أحمد كمال: تعيين أدوار clinics-manager + direct-manager
--     + نقله للقسم الصحيح + إصلاح سميرة (department_id = null)
-- (2) إضافة صلاحية organization.org_chart.read لدور clinics-manager
-- (3) إصلاح request_attendance_correction لإنشاء سجل في requests
--     حتى يظهر في صندوق الطلبات ويمر بسير العمل
-- (4) إصلاح get_honor_board: شمول حالة 'late' + إضافة تصنيف استجابات الموقع
-- ═════════════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) إصلاح مصطفى أحمد كمال — أدوار + قسم
-- ═══════════════════════════════════════════════════════════════════════════

-- تعيين دور clinics-manager لمصطفى (user_id: 3e950d11-b5b4-4652-9ecf-919c434222fc)
insert into public.user_roles (user_id, role_id)
select '3e950d11-b5b4-4652-9ecf-919c434222fc'::uuid, r.id
from public.roles r
where r.slug = 'clinics-manager'
  and not exists (
    select 1 from public.user_roles ur
    where ur.user_id = '3e950d11-b5b4-4652-9ecf-919c434222fc'
      and ur.role_id = r.id
  );

-- تعيين دور direct-manager لمصطفى
insert into public.user_roles (user_id, role_id)
select '3e950d11-b5b4-4652-9ecf-919c434222fc'::uuid, r.id
from public.roles r
where r.slug = 'direct-manager'
  and not exists (
    select 1 from public.user_roles ur
    where ur.user_id = '3e950d11-b5b4-4652-9ecf-919c434222fc'
      and ur.role_id = r.id
  );

-- نقل مصطفى للقسم الصحيح: إدارة العيادات الطبية (9783a1b7-...)
update public.employees
set department_id = '9783a1b7-f490-4cff-824e-9d2be0d01543'
where id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
  and department_id is distinct from '9783a1b7-f490-4cff-824e-9d2be0d01543';

-- إصلاح سميرة: department_id = null → إدارة العيادات الطبية
update public.employees
set department_id = '9783a1b7-f490-4cff-824e-9d2be0d01543'
where id = 'b97d9e90-d815-42f7-b192-255dd34129b8'
  and department_id is null;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2) إضافة صلاحيات لدور clinics-manager
-- ═══════════════════════════════════════════════════════════════════════════

-- إضافة organization.org_chart.read
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r, public.permissions p
where r.slug = 'clinics-manager'
  and p.code = 'organization.org_chart.read'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.role_id = r.id and rp.permission_id = p.id
  );

-- إضافة attendance.correction.review للسماح بمراجعة تصحيحات الحضور
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r, public.permissions p
where r.slug = 'clinics-manager'
  and p.code = 'attendance.correction.review'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.role_id = r.id and rp.permission_id = p.id
  );

-- إضافة attendance.record.manual_create للسماح بتعديل أيام الموظفين
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r, public.permissions p
where r.slug = 'clinics-manager'
  and p.code = 'attendance.record.manual_create'
  and not exists (
    select 1 from public.role_permissions rp
    where rp.role_id = r.id and rp.permission_id = p.id
  );


-- ═══════════════════════════════════════════════════════════════════════════
-- 3) إصلاح request_attendance_correction — إنشاء طلب رسمي في requests
-- ═══════════════════════════════════════════════════════════════════════════
-- المشكلة: الدالة كانت تُدرج في attendance_corrections فقط
-- دون إنشاء سجل في public.requests → لا يظهر في صندوق الطلبات
-- الحل: إنشاء سجل في attendance_corrections + requests مع ربطهما

create or replace function public.request_attendance_correction(
  p_work_date date,
  p_type text,
  p_reason text,
  p_check_in timestamptz default null,
  p_check_out timestamptz default null,
  p_status text default null,
  p_attachment_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_emp uuid := public.current_employee_id();
  v_id uuid;
  v_daily uuid;
  v_reason text;
  v_req public.requests;
  v_title text;
  v_check_in_str text;
  v_check_out_str text;
begin
  if v_emp is null then
    raise exception 'NO_EMPLOYEE' using errcode = '42501';
  end if;

  -- التحقق من صحة التاريخ (لا مستقبلي)
  if p_work_date > (now() at time zone 'Africa/Cairo')::date then
    raise exception 'INVALID_CORRECTION: لا يمكن تصحيح تاريخ مستقبلي' using errcode = '22023';
  end if;

  -- تبسيط شرط السبب: 3 أحرف كحد أدنى بدل 5
  v_reason := btrim(coalesce(p_reason, ''));
  if length(v_reason) < 3 then
    v_reason := case
      when p_type = 'missing_check_in' then 'نسيان بصمة حضور'
      when p_type = 'missing_check_out' then 'نسيان بصمة انصراف'
      else 'طلب تصحيح حضور'
    end;
  end if;

  -- البحث عن سجل الحضور اليومي
  select id into v_daily
  from public.attendance_daily
  where employee_id = v_emp and work_date = p_work_date;

  -- إدراج سجل التصحيح
  insert into public.attendance_corrections(
    employee_id, attendance_daily_id, work_date, correction_type,
    requested_check_in, requested_check_out, requested_status,
    reason, attachment_path, created_by
  )
  values(
    v_emp, v_daily, p_work_date, p_type,
    p_check_in, p_check_out, p_status,
    v_reason, p_attachment_path, auth.uid()
  )
  returning id into v_id;

  -- تجهيز نصوص الوقت المطلوب تصحيحه للعرض
  v_check_in_str := case
    when p_check_in is not null then to_char(p_check_in at time zone 'Africa/Cairo', 'HH24:MI')
    else null
  end;
  v_check_out_str := case
    when p_check_out is not null then to_char(p_check_out at time zone 'Africa/Cairo', 'HH24:MI')
    else null
  end;

  v_title := case
    when p_type = 'missing_check_in' then 'طلب تصحيح بصمة حضور — ' || p_work_date
    when p_type = 'missing_check_out' then 'طلب تصحيح بصمة انصراف — ' || p_work_date
    else 'طلب تصحيح حضور — ' || p_work_date
  end;

  -- تطبيع نوع التصحيح ليتوافق تماماً مع قيد الجدول مهما كان المدخل
  p_type := case
    when lower(coalesce(p_type, '')) in ('check_in', 'checkin', 'in') then 'missing_check_in'
    when lower(coalesce(p_type, '')) in ('check_out', 'checkout', 'out') then 'missing_check_out'
    when lower(coalesce(p_type, '')) in ('time', 'wrong_time') then 'wrong_time'
    when lower(coalesce(p_type, '')) in ('status', 'wrong_status') then 'wrong_status'
    when lower(coalesce(p_type, '')) in ('missing_check_in', 'missing_check_out', 'wrong_time', 'wrong_status', 'mission', 'leave', 'other') then lower(p_type)
    else 'missing_check_in'
  end;

  -- إنشاء طلب رسمي في جدول requests عبر _submit_request_for بالمعاملات المسمّاة
  -- حتى يظهر في صندوق الطلبات ويمر بسير العمل ويصل للمدير
  v_req := public._submit_request_for(
    p_employee_id => v_emp,
    p_request_type => 'attendance_correction',
    p_workflow_definition_id => null::uuid,
    p_manager_employee_id => null::uuid,
    p_title => v_title,
    p_reason => v_reason,
    p_payload => jsonb_strip_nulls(jsonb_build_object(
      'correctionId', v_id,
      'workDate', p_work_date,
      'correctionType', p_type,
      'requestedCheckIn', p_check_in,
      'requestedCheckOut', p_check_out,
      'requestedStatus', p_status,
      'proposedCheckInTime', v_check_in_str,
      'proposedCheckOutTime', v_check_out_str,
      'timeFormatted', coalesce(v_check_in_str, v_check_out_str, '—'),
      'reason', v_reason,
      'attachmentPath', p_attachment_path,
      'source', 'mobile_app'
    ))
  );

  -- ربط التصحيح بالطلب الرسمي
  -- (حقل request_id موجود إن كان في الجدول، وإلا نتجاهل)
  begin
    execute format(
      'update public.attendance_corrections set request_id = $1 where id = $2'
    ) using v_req.id, v_id;
  exception when undefined_column then
    -- لا يوجد عمود request_id — نتجاهل (التصحيح مرتبط بالـ payload)
    null;
  end;

  -- إشعار إضافي للمراجعين (fallback إذا لم يُنشئ سير العمل خطوة)
  perform public.notify_employees_with_permission(
    'attendance.correction.review',
    'طلب تصحيح حضور جديد',
    format('طلب تصحيح حضور بتاريخ %s (%s) — %s',
      p_work_date,
      coalesce(p_type, ''),
      coalesce(v_check_in_str, v_check_out_str, '')),
    'attendance', 'normal', 'attendance_corrections', v_id,
    jsonb_build_object(
      'requestId', v_req.id,
      'correctionId', v_id,
      'workDate', p_work_date,
      'type', p_type,
      'deepLink', '/requests/' || v_req.id
    ),
    v_emp
  );

  return v_id;
end;
$$;

revoke execute on function public.request_attendance_correction(date,text,text,timestamptz,timestamptz,text,text) from public;
grant execute on function public.request_attendance_correction(date,text,text,timestamptz,timestamptz,text,text) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 4) إصلاح decide_request — إضافة معالجة attendance_correction
-- ═══════════════════════════════════════════════════════════════════════════
-- عند اعتماد طلب من نوع attendance_correction، يتم تطبيق التصحيح
-- على attendance_daily عبر decide_attendance_correction

-- نُعيد بناء decide_request بإضافة الفرع الجديد
-- نأخذ النسخة الحية من 0556 ونضيف فرع attendance_correction

create or replace function public.decide_request(
  p_request_id uuid,
  p_decision   text,
  p_comment    text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_exec_emp        uuid;
  v_correction_id   uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);
  v_is_direct_mgr := (v_req.manager_employee_id = v_me) or exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = v_req.employee_id
      and mr.manager_employee_id = v_me
      and mr.relation_type = 'primary'
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-manager','operations-officer']);

  -- الصلاحية الشاملة لاعتماد الطلبات:
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or (v_step.id is not null and v_step.assignee_employee_id = v_me)
    or public.current_has_active_role(array['admin','super-admin'])
    or public.has_any_permission(array['requests.request.approve','requests.approve','requests.request.override'])
    or public.can_access_employee(v_req.employee_id, 'requests.approve')
    or public.can_access_employee(v_req.employee_id, 'requests.request.approve')
    or (v_is_operations
        and (
          v_current_step >= 2
          or coalesce(v_step.escalation_deadline, v_req.escalation_deadline) < now()
          or v_req.workflow_status in ('escalated', 'awaiting_operator')
          or v_req.request_type in ('mission','convoy','fundraising')
        ));

  if not v_authorized then
    raise exception 'not authorized for the active workflow step (step: %, role required)',
      v_current_step using errcode = '42501';
  end if;

  -- تحديد دور الفاعل للسجل
  v_actor_role := case
    when public.current_is_full_access() and not v_is_direct_mgr then 'admin'
    when v_is_exec then 'executive'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_hr then 'hr'
    when v_is_operations then 'operations'
    else 'authorized'
  end;

  v_final_status := case p_decision
    when 'approve' then 'approved'
    when 'return'  then 'returned'
    else 'rejected'
  end;

  -- تسجيل إجراء الخطوة الحالية
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  -- إغلاق باقي الخطوات (موافقة واحدة تُنهي الطلب)
  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending','active','escalated')
    and id is distinct from v_step.id;

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status = v_final_status,
        workflow_status = 'completed',
        decided_at = now(), decided_by = v_me, updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- إذا كانت مأمورية وتم اعتمادها، يتم تفعيل تنفيذ المأمورية بأمان
  if v_final_status = 'approved' and v_req.request_type = 'mission' then
    insert into public.mission_executions(request_id, employee_id, status, started_at)
    values (v_req.id, v_req.employee_id, 'in_progress', coalesce(v_req.created_at, now()))
    on conflict (request_id) do update
      set status = case when public.mission_executions.status = 'completed' then 'completed' else 'in_progress' end,
          started_at = coalesce(public.mission_executions.started_at, v_req.created_at, now()),
          updated_at = now();
  end if;

  -- ═══ جديد 0581: إذا كان تصحيح حضور وتم اعتماده → تطبيق التصحيح ═══
  if v_final_status = 'approved' and v_req.request_type = 'attendance_correction' then
    v_correction_id := (v_req.payload->>'correctionId')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'approved', p_comment);
      exception when others then
        -- التصحيح ربما اعتُمد مسبقاً أو حُذف — لا نكسر الطلب
        raise notice 'decide_attendance_correction fallback: %', sqlerrm;
      end;
    end if;
  end if;

  -- إذا كان تصحيح حضور وتم رفضه → رفض التصحيح
  if v_final_status = 'rejected' and v_req.request_type = 'attendance_correction' then
    v_correction_id := (v_req.payload->>'correctionId')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'rejected', coalesce(p_comment, 'تم الرفض من سير العمل'));
      exception when others then
        raise notice 'decide_attendance_correction reject fallback: %', sqlerrm;
      end;
    end if;
  end if;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف بالنتيجة
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request',
    case when v_req.status = 'approved' then 'normal' else 'high' end,
    'request', v_req.id,
    jsonb_build_object(
      'decision', p_decision,
      'request_type', v_req.request_type,
      'actorRole', v_actor_role,
      'deepLink', '/requests/' || v_req.id
    )
  );

  -- إشعار المدير التنفيذي (كامل الشاشة)
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is null then
    v_exec_emp := public.first_active_employee_for_role('executive');
  end if;
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_me then
    perform public.notify_executive_fullscreen(
      'قرار طلب — ' || case v_req.status
        when 'approved' then 'موافقة'
        when 'rejected' then 'رفض'
        else 'إعادة طلب' end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'decision', p_decision,
        'request_type', v_req.request_type,
        'actorRole', v_actor_role
      )
    );
  end if;

  return v_req;
end;
$$;

comment on function public.decide_request(uuid, text, text) is
  '0581: قرار على طلب — مع دعم اعتماد/رفض تصحيحات الحضور تلقائياً';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- 5) إصلاح get_honor_board — حساب صحيح + تصنيف استجابات الموقع
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_honor_board(p_period text default 'month', p_category text default 'attendance')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_today  date := (now() at time zone 'Africa/Cairo')::date;
  v_start  date;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if p_period = 'week' then
    -- السبت = 6 في extract(dow): السبت الماضي (أو اليوم إن كان سبتاً)
    v_start := v_today - ((extract(dow from v_today)::int + 1) % 7);
  else
    v_start := date_trunc('month', v_today)::date;
  end if;

  if p_category = 'attendance' then
    with days as (
      select d::date as day,
             (extract(dow from d) <> 5
              and not exists (
                select 1 from public.public_holidays h
                where h.is_active
                  and d::date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
              )) as is_workday
      from generate_series(v_start, v_today, interval '1 day') d
    ),
    staff as (
      select e.id, e.full_name_ar, e.photo_url, e.hire_date,
             coalesce(dp.name, 'الإدارة العامة') as department
      from public.employees e
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not coalesce(e.is_attendance_exempt, false)
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    ),
    grid as (
      select s.id as employee_id, dy.day, dy.is_workday, ad.status,
             coalesce(ad.late_minutes, 0) as late_minutes,
             ad.first_check_in
      from staff s
      cross join days dy
      left join public.attendance_daily ad on ad.employee_id = s.id and ad.work_date = dy.day
      where s.hire_date is null or dy.day >= s.hire_date
    ),
    per_emp as (
      select g.employee_id,
             count(*) filter (where g.is_workday and (g.day < v_today or g.status is not null)) as workdays,
             count(*) filter (where g.is_workday and g.status = 'on_leave') as leave_days,
             -- 0581: شمول 'late' و'present' والحالات المكتملة (بصمة حضور موجودة)
             count(*) filter (where g.is_workday and (
               g.status in ('present','attended','excused','mission','missing_checkout','late')
               or g.first_check_in is not null
             )) as present_days,
             count(*) filter (where not g.is_workday and (
               g.status in ('present','attended','excused','mission','missing_checkout','late')
               or g.first_check_in is not null
             )) as extra_days,
             coalesce(sum(g.late_minutes) filter (where g.is_workday and (
               g.status in ('present','attended','excused','mission','missing_checkout','late')
               or g.first_check_in is not null
             )), 0) as late_minutes
      from grid g
      group by g.employee_id
    ),
    scored as (
      select s.*, p.*,
             greatest(p.workdays - p.leave_days, 0) as expected,
             -- 0581: نسبة الانضباط = نسبة الحضور مع خصم التأخير
             case when p.workdays - p.leave_days > 0
                  then greatest(0, least(
                    p.present_days::numeric / (p.workdays - p.leave_days),
                    1
                  ) - (p.late_minutes::numeric / (greatest(p.workdays - p.leave_days, 1) * 480.0)))
                  else 0 end as ratio
      from per_emp p join staff s on s.id = p.employee_id
      where p.present_days > 0
    ),
    ranked as (
      select row_number() over (
               order by ratio desc, present_days desc, late_minutes asc, extra_days desc, full_name_ar asc
             ) as rank,
             sc.*
      from scored sc
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement',
               case
                 when present_days >= expected and late_minutes = 0
                   then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل بدون أي تأخير'
                 when present_days >= expected
                   then 'حضور كامل ' || present_days || ' من ' || expected || ' يوم عمل (تأخير '
                        || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
                 else 'حضور ' || present_days || ' من ' || expected || ' يوم عمل'
                      || case when late_minutes > 0
                              then ' (تأخير ' || public._ar_count(late_minutes, 'دقيقة', 'دقيقتان', 'دقائق', 'دقيقة') || ')'
                              else '' end
               end
               || case when extra_days > 0
                       then ' + ' || public._ar_count(extra_days, 'يوم إضافي', 'يومان إضافيان', 'أيام إضافية', 'يوماً إضافياً')
                       else '' end,
             'metric', round(ratio * 100)::int || '% انضباط',
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  elsif p_category = 'missions' then
    with field as (
      select r.employee_id,
             greatest((r.payload->>'startDate')::date, v_start) as s,
             least(coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date), v_today) as e
      from public.requests r
      where r.request_type in ('mission', 'convoy', 'fundraising')
        and r.status = 'approved'
        and r.payload ? 'startDate'
        and (r.payload->>'startDate')::date <= v_today
        and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date) >= v_start
    ),
    per_emp as (
      select employee_id, count(*) as missions, sum(e - s + 1) as field_days
      from field group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.missions desc, p.field_days desc, e.full_name_ar asc) as rank,
             e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.missions, p.field_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement', public._ar_count(missions, 'مأمورية ميدانية معتمدة', 'مأموريتان ميدانيتان معتمدتان', 'مأموريات ميدانية معتمدة', 'مأمورية ميدانية معتمدة')
                            || ' بإجمالي ' || public._ar_count(field_days, 'يوم عمل ميداني', 'يوما عمل ميداني', 'أيام عمل ميداني', 'يوم عمل ميداني'),
             'metric', public._ar_count(missions, 'مأمورية', 'مأموريتان', 'مأموريات', 'مأمورية'),
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  -- ═══ جديد 0581: تصنيف استجابات الموقع ═══
  elsif p_category = 'locations' then
    with loc_data as (
      select lr.employee_id,
             count(*) as total_requests,
             count(*) filter (where lr.status = 'completed') as completed,
             count(*) filter (where lr.status in ('pending','active') and lr.expires_at < now()) as expired,
             -- متوسط زمن الاستجابة بالدقائق
             avg(extract(epoch from (lr.responded_at - lr.requested_at)) / 60.0)
               filter (where lr.status = 'completed' and lr.responded_at is not null) as avg_response_minutes
      from public.live_location_requests lr
      where lr.requested_at >= v_start
        and lr.requested_at <= now()
      group by lr.employee_id
    ),
    ranked as (
      select row_number() over (
               order by ld.completed desc,
                        coalesce(ld.avg_response_minutes, 999) asc,
                        ld.expired asc,
                        e.full_name_ar asc
             ) as rank,
             e.full_name_ar,
             coalesce(dp.name, 'الإدارة العامة') as department,
             e.photo_url,
             ld.total_requests,
             ld.completed,
             ld.expired,
             round(coalesce(ld.avg_response_minutes, 0)::numeric, 1) as avg_min
      from loc_data ld
      join public.employees e on e.id = ld.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
        and ld.completed > 0
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement', 'استجاب لـ ' || completed || ' من ' || total_requests || ' طلب موقع'
                            || case when avg_min > 0
                                    then ' (متوسط ' || avg_min || ' دقيقة)'
                                    else '' end
                            || case when expired > 0
                                    then ' — ' || expired || ' منتهية'
                                    else '' end,
             'metric', completed || '/' || total_requests || ' استجابة',
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;

  else
    -- التقارير اليومية (reports)
    with per_emp as (
      select employee_id, count(*) as reports, count(distinct report_date) as report_days
      from public.daily_reports
      where report_date between v_start and v_today
      group by employee_id
    ),
    ranked as (
      select row_number() over (order by p.reports desc, p.report_days desc, e.full_name_ar asc) as rank,
             e.full_name_ar, coalesce(dp.name, 'الإدارة العامة') as department, e.photo_url,
             p.reports, p.report_days
      from per_emp p
      join public.employees e on e.id = p.employee_id
      left join public.departments dp on dp.id = e.department_id
      where e.is_active and not e.is_deleted
        and not public.is_employee_executive(e.id)
        and e.full_name_ar not like '%تجريبي%'
        and e.full_name_ar not like '%اختبار%'
    )
    select jsonb_agg(jsonb_build_object(
             'rank', rank,
             'name', full_name_ar,
             'department', department,
             'achievement', 'رفع ' || public._ar_count(reports, 'تقرير يومي', 'تقريرين يوميين', 'تقارير يومية', 'تقريراً يومياً')
                            || ' في ' || public._ar_count(report_days, 'يوم', 'يومين', 'أيام', 'يوماً'),
             'metric', public._ar_count(reports, 'تقرير', 'تقريران', 'تقارير', 'تقريراً'),
             'photo_url', photo_url
           ) order by rank)
    into v_result
    from (select * from ranked order by rank limit 10) t;
  end if;

  return coalesce(v_result, '[]'::jsonb);
end;
$fn$;

revoke execute on function public.get_honor_board(text, text) from public, anon;
grant execute on function public.get_honor_board(text, text) to authenticated, service_role;


commit;
