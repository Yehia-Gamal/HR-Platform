-- 0628: تحسينات شاملة لتصنيف الفاندي وصور الموظفين وإزالة رمز الدولة
-- 1. تحديث check_employee_penalty_exemption_v2 لتصنيف الفاندي كيوم ترفيهي للموظفين وليس جمع تبرعات
-- 2. إضافة employeePhotoUrl إلى دوال get_team_attendance_corrections و get_attendance_correction_detail
-- 3. إضافة employeePhotoUrl إلى get_request_inbox و get_mobile_request_detail

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0) جدول استثناءات الحضور — كانت الدالة تشير إليه دون أن يُنشأ في أي migration
--    (أُثبت في prod أن الجدول غير موجود) — الأعمدة مطابقة تماماً لاستخدام الدالة.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.attendance_exemptions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  exemption_type text not null default 'permanent_exemption',
  reason text,
  is_active boolean not null default true,
  start_date date not null default current_date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid
);
create index if not exists ix_attendance_exemptions_employee
  on public.attendance_exemptions (employee_id) where is_active;
alter table public.attendance_exemptions enable row level security;
drop policy if exists attendance_exemptions_full_access on public.attendance_exemptions;
create policy attendance_exemptions_full_access on public.attendance_exemptions
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());
drop trigger if exists trg_attendance_exemptions_updated_at on public.attendance_exemptions;
create trigger trg_attendance_exemptions_updated_at
  before update on public.attendance_exemptions
  for each row execute function public.set_updated_at();
comment on table public.attendance_exemptions is
  'استثناءات من خصومات الحضور — تُدار من الإدارة العليا فقط (full-access)، وتُقرأ عبر دوال SECURITY DEFINER.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث check_employee_penalty_exemption_v2
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.check_employee_penalty_exemption_v2(
  p_employee_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
  v_emp record;
  v_req record;
  v_wa record;
  v_att record;
  v_loc text;
begin
  -- 1) فحص وجود الموظف وحالته الأساسية
  select e.id, e.status, e.is_active, e.department_id, e.branch_id,
         d.name as department_name, b.name as branch_name
    into v_emp
    from public.employees e
    left join public.departments d on d.id = e.department_id
    left join public.branches b on b.id = e.branch_id
   where e.id = p_employee_id;

  if v_emp.id is null then
    return jsonb_build_object('isExempt', false, 'category', 'unknown_employee', 'reason', 'الموظف غير موجود');
  end if;

  -- 2) فحص الحالات المستثناة دائماً (استقالة، إنهاء خدمة، إيقاف، إلخ)
  if v_emp.status in ('resigned', 'terminated', 'suspended') or not coalesce(v_emp.is_active, true) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'inactive_status',
      'reason', 'الموظف غير نشط حالياً (' || coalesce(v_emp.status, 'معطل') || ')'
    );
  end if;

  -- 3) فحص الاستثناءات الدائمة في جدول attendance_exemptions
  for v_rec in
    select ae.reason, ae.exemption_type
      from public.attendance_exemptions ae
     where ae.employee_id = p_employee_id
       and ae.is_active = true
       and p_work_date between ae.start_date and coalesce(ae.end_date, '2099-12-31'::date)
     limit 1
  loop
    return jsonb_build_object(
      'isExempt', true,
      'category', coalesce(v_rec.exemption_type, 'permanent_exemption'),
      'reason', coalesce(v_rec.reason, 'إعفاء رسمي مسجل في النظام')
    );
  end loop;

  -- 4) فحص استثناءات VIP والقيادات من جدول profile_attendance_policies / roles
  if exists (
    select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
     where ur.user_id = p_employee_id
       and r.code in ('super-admin', 'general-manager', 'executive', 'executive-director', 'board-member')
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'vip_role',
      'reason', 'إعفاء خاص بالقيادات والإدارة العليا'
    );
  end if;

  -- 5) فحص طاقم العيادة والمستوصف
  if coalesce(v_emp.department_name, '') like '%عياد%'
     or coalesce(v_emp.branch_name, '') like '%عياد%'
     or coalesce(v_emp.department_name, '') like '%مستوصف%' then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'clinic_staff',
      'reason', 'طاقم العيادة الطبية معفى من الخصومات اللحظية'
    );
  end if;

  -- 6) فحص العطلات الرسمية والراحات الأسبوعية
  if extract(isodow from p_work_date) = 5 then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'weekly_rest',
      'reason', 'عطلة نهاية الأسبوع (الجمعة)'
    );
  end if;

  if exists (
    -- الجدول الفعلي public_holidays (holiday_date..end_date) — لا يوجد جدول holidays
    select 1 from public.public_holidays h
     where h.is_active
       and p_work_date between h.holiday_date and coalesce(h.end_date, h.holiday_date)
  ) then
    return jsonb_build_object(
      'isExempt', true,
      'category', 'official_holiday',
      'reason', 'عطلة رسمية عامة'
    );
  end if;

  -- 7) فحص الطلبات المعتمدة أو قيد المراجعة: مأموريات، قوافل، فاندي (يوم ترفيهي)، إجازات
  for v_req in
    select r.id, r.request_type, r.status, r.payload
      from public.requests r
     where r.employee_id = p_employee_id
       and r.status in ('approved', 'pending')
       and (
          -- إجازات
          (r.request_type = 'leave'
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- مأموريات
          or (r.request_type in ('mission', 'external_mission', 'administrative_mission')
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- قوافل
          or (r.request_type in ('convoy', 'field_convoy')
              and p_work_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                                  and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date))
          -- فاندي (يوم ترفيهي للموظفين)
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
      when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') = 'fundraising' then 'يوم ترفيهي للموظفين (فاندي)'
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

  -- 8) فحص جدول مهام العمل والمأموريات والقوافل work_assignments
  select wa.assignment_type, wa.title into v_wa
    from public.work_assignments wa
   where wa.responsible_employee_id = p_employee_id
     and wa.status in ('APPROVED', 'IN_PROGRESS', 'PENDING')
     and p_work_date between wa.start_at::date and wa.end_at::date
   limit 1;

  if v_wa.assignment_type is not null then
    v_loc := case
      when upper(v_wa.assignment_type) in ('CONVOY', 'FIELD_CONVOY') then 'قافلة ميدانية'
      when upper(v_wa.assignment_type) in ('FUNDRAISING', 'FANDY') then 'يوم ترفيهي للموظفين (فاندي)'
      when upper(v_wa.assignment_type) in ('MISSION', 'EXTERNAL') then 'مأمورية عمل'
      else 'مهمة عمل رسمية (' || coalesce(v_wa.title, v_wa.assignment_type) || ')'
    end;

    return jsonb_build_object(
      'isExempt', true,
      'category', 'assignment',
      'reason', v_loc || ' مكلف بها رسمياً'
    );
  end if;

  -- 9) فحص حالة الحضور اليومي في attendance_daily
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) إضافة employeePhotoUrl إلى get_team_attendance_corrections
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_team_attendance_corrections(
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', e.full_name_ar,
        'employeeCode', e.employee_code,
        'employeePhotoUrl', e.photo_url,
        'jobTitle', jt.name,
        'workDate', c.work_date,
        'type', c.correction_type,
        'requestedCheckIn', c.requested_check_in,
        'requestedCheckOut', c.requested_check_out,
        'requestedStatus', c.requested_status,
        'reason', c.reason,
        'attachmentPath', c.attachment_path,
        'status', c.status,
        'reviewedBy', c.reviewed_by,
        'reviewedAt', c.reviewed_at,
        'reviewNote', c.review_note,
        'createdAt', c.created_at,
        'canDecide', (
          c.status = 'pending'
          AND (
            public.current_is_full_access()
            OR public.current_has_active_role(ARRAY['admin', 'super-admin', 'general-manager', 'hr-manager'])
            OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
            OR EXISTS (
              SELECT 1 FROM public.manager_relations mr
              WHERE mr.employee_id = c.employee_id
                AND mr.manager_employee_id = public.current_employee_id()
                AND mr.relation_type = 'primary'
                AND mr.effective_from <= current_date
                AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
            )
          )
        )
      ) ORDER BY c.created_at DESC
    )
    FROM public.attendance_corrections c
    JOIN public.employees e ON e.id = c.employee_id
    LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
    WHERE (p_status IS NULL OR p_status = 'all' OR c.status = p_status)
      AND (
        public.current_is_full_access()
        OR public.current_has_active_role(ARRAY['admin', 'super-admin', 'general-manager', 'hr-manager'])
        OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
        OR EXISTS (
          SELECT 1 FROM public.manager_relations mr
          WHERE mr.employee_id = c.employee_id
            AND mr.manager_employee_id = public.current_employee_id()
            AND mr.relation_type = 'primary'
            AND mr.effective_from <= current_date
            AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
        )
      )
    LIMIT p_limit
  ), '[]'::jsonb);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) إضافة employeePhotoUrl إلى get_attendance_correction_detail
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_attendance_correction_detail(p_correction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec record;
BEGIN
  SELECT
    c.id,
    c.employee_id AS "employeeId",
    e.full_name_ar AS "employeeName",
    e.employee_code AS "employeeCode",
    e.photo_url AS "employeePhotoUrl",
    jt.name AS "jobTitle",
    e.branch_id AS "branchId",
    c.work_date AS "workDate",
    c.correction_type AS "type",
    c.requested_check_in AS "requestedCheckIn",
    c.requested_check_out AS "requestedCheckOut",
    c.requested_status AS "requestedStatus",
    c.reason,
    c.attachment_path AS "attachmentPath",
    c.status,
    c.reviewed_by AS "reviewedBy",
    rev.full_name_ar AS "reviewerName",
    c.reviewed_at AS "reviewedAt",
    c.review_note AS "reviewNote",
    c.created_at AS "createdAt",
    (
      c.status = 'pending'
      AND (
        public.current_is_full_access()
        OR public.can_access_employee(c.employee_id, 'attendance.correction.review')
        OR EXISTS (
          SELECT 1 FROM public.manager_relations mr
          WHERE mr.employee_id = c.employee_id
            AND mr.manager_employee_id = public.current_employee_id()
            AND mr.relation_type = 'primary'
            AND mr.effective_from <= current_date
            AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
        )
      )
    ) AS "canDecide"
  INTO v_rec
  FROM public.attendance_corrections c
  JOIN public.employees e ON e.id = c.employee_id
  LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
  LEFT JOIN public.employees rev ON rev.id = c.reviewed_by
  WHERE c.id = p_correction_id;

  IF v_rec.id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN to_jsonb(v_rec);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) إضافة employeePhotoUrl إلى get_request_inbox
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select coalesce(jsonb_agg(item order by item->>'createdAt' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', r.id,
      'requestNumber', r.request_number,
      'requestType', r.request_type,
      'employeeId', r.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'employeePhotoUrl', e.photo_url,
      'title', r.title,
      'reason', r.reason,
      'status', r.status,
      'workflowStatus', r.workflow_status,
      'currentStepOrder', r.current_step_order,
      'activeStepName', active_step.name_ar,
      'decisionDueAt', r.decision_due_at,
      'createdAt', r.created_at,
      'payload', r.payload,
      'missionExecution', case when r.request_type in ('mission','convoy','fundraising') then (
        select to_jsonb(me) from (
          select me.id, me.status,
                 me.started_at as "startedAt",
                 me.ended_at as "endedAt",
                 me.actual_minutes as "actualMinutes",
                 me.report, me.outcome
          from public.mission_executions me
          where me.request_id = r.id
        ) me
      ) else null end
    ) as item
    from public.requests r
    join public.employees e on e.id = r.employee_id
    left join lateral (
      select rs.name_ar from public.request_steps rs
      where rs.request_id = r.id and rs.status in ('active','escalated')
      order by rs.step_order limit 1
    ) active_step on true
    where (
      -- طلباتي الشخصية
      r.employee_id = public.current_employee_id()
      -- طلبات المرؤوسين المباشرين (عبر العلاقة الإدارية)
      or exists (
        select 1 from public.manager_relations mr
        where mr.employee_id = r.employee_id
          and mr.manager_employee_id = public.current_employee_id()
          and mr.relation_type = 'primary'
          and mr.effective_from <= current_date
          and (mr.effective_to is null or mr.effective_to >= current_date)
      )
      -- صلاحيات مدير النظام / HR
      or public.current_is_full_access()
      or public.can_access_employee(r.employee_id, 'requests.request.approve')
      or public.can_access_employee(r.employee_id, 'requests.request.read')
      or public.can_access_employee(r.employee_id, 'requests.read')
      or public.can_access_employee(r.employee_id, 'requests.approve')
      or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    )
    limit p_limit
  ) sub;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) إضافة employeePhotoUrl إلى get_mobile_request_detail
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_request public.requests;
  v_employee public.employees;
  v_steps jsonb;
  v_attachments jsonb;
  v_can_decide boolean;
  v_can_cancel boolean;
  v_is_direct_mgr boolean;
  v_decision_actor text;
  v_decision_mode text;
  v_decision_on_behalf boolean;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  v_is_direct_mgr := exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = v_request.employee_id
      and mr.manager_employee_id = public.current_employee_id()
      and mr.relation_type = 'primary'
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );

  if not (
    v_request.employee_id = public.current_employee_id()
    or v_is_direct_mgr
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  v_can_cancel := v_request.status = 'pending' and v_request.employee_id = public.current_employee_id();

  v_can_decide := v_request.status = 'pending' and (
    public.current_is_full_access()
    or v_is_direct_mgr
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.has_permission('requests.request.approve')
    or public.has_permission('requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'order', s.step_order, 'name', s.name_ar, 'status', s.status,
    'decision', case when s.status in ('approved','rejected') then s.status else null end,
    'comment', s.comment, 'decidedAt', s.acted_at, 'dueAt', s.due_at,
    'actorName', actor.full_name_ar
  ) order by s.step_order), '[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id = s.acted_by
  where s.request_id = p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
  ) order by a.created_at), '[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type = 'request' and a.entity_id = p_request_id;

  select e.full_name_ar, a.metadata->>'decisionMode', coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
  into v_decision_actor, v_decision_mode, v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id = a.actor_employee_id
  where a.request_id = p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  if v_request.request_type in ('mission','convoy','fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
      from public.mission_executions me
      where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'employeePhotoUrl', v_employee.photo_url,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'canDecide', v_can_decide,
    'canCancel', v_can_cancel,
    'steps', v_steps,
    'attachments', v_attachments,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$function$;

COMMIT;
