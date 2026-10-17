-- ==============================================================================
-- Migration 0682: إصلاح اعتماد الطلبات وتصحيحات الحضور (عدم إخفاء الأزرار للمدير والإدارة)
-- ==============================================================================
-- المشاكل المعالجة:
-- 1) اختفاء أزرار الاعتماد والرفض لطلبات الإجازات والمأموريات بعد التصعيد التلقائي:
--    عند تصعيد الطلب بعد ساعتين لمدير التشغيل (أبو عمار)، كانت دالة request_decision_flags
--    تُرجع awaitingMe = false للمدير المباشر وللإدارة التنفيذية والإدارة العامة،
--    مما يؤدي في واجهات الويب وتطبيق الموبايل إلى إخفاء زر الاعتماد واعتبار الطلب
--    «ليس بانتظارك»، على الرغم من امتلاكهم الصلاحية الكاملة للبت فيه بأي وقت.
-- 2) تعطل اعتماد تصحيحات الحضور (خطأ 42883: function public.is_manager_of does not exist):
--    استدعاء الدالة في decide_attendance_correction دون تعريفها مسبقاً في قاعدة البيانات.
-- 3) حجب قائمة تصحيحات الحضور المعلقة عن الإدارة التنفيذية (الشيخ محمد يوسف):
--    إضافة أدواره ('executive' و 'executive-director') لدالة get_team_attendance_corrections.
-- ==============================================================================

begin;

-- ─── 1) إنشاء دالة التحقق من علاقة الإدارة المباشرة is_manager_of ───────────
create or replace function public.is_manager_of(
  p_manager_id  uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = p_employee_id
      and mr.manager_employee_id = p_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );
$$;

revoke all on function public.is_manager_of(uuid, uuid) from public, anon;
grant execute on function public.is_manager_of(uuid, uuid) to authenticated, service_role;

-- ─── 2) تحديث request_decision_flags لضمان ظهور awaitingMe للمديرين والإدارة ─
create or replace function public.request_decision_flags(
  p_req   public.requests,
  p_me    uuid,
  p_full  boolean,
  p_roles text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_roles         text[] := coalesce(p_roles, '{}'::text[]);
  v_step          public.request_steps;
  v_is_clinic_mgr boolean;
  v_is_mgr        boolean;
  v_is_ops        boolean;
  v_override      boolean;
  v_can           boolean;
  v_awaiting      boolean;
begin
  -- لا قرار على طلب غير معلّق ولا على طلب المستخدم نفسه
  if p_me is null or p_req.id is null or p_req.status <> 'pending'
     or p_req.employee_id = p_me then
    return jsonb_build_object('canDecide', false, 'awaitingMe', false);
  end if;

  -- نفس اختيار decide_request: الخطوة النشطة أولًا ثم أول escalated/pending
  select * into v_step
    from public.request_steps
   where request_id = p_req.id
     and status in ('active', 'escalated', 'pending')
   order by (status = 'active') desc, step_order
   limit 1;

  v_is_clinic_mgr := (
    p_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  v_is_mgr := p_req.manager_employee_id is not distinct from p_me
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(p_req.employee_id)
        or p_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = p_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_req.employee_id
         and mr.manager_employee_id = p_me
         and mr.relation_type = 'primary'
         and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_is_ops := 'operations-manager-1' = any(v_roles);
  v_override := coalesce(p_full, false)
    or v_roles && array['executive', 'executive-director', 'general-manager',
                        'hr-manager', 'hr-specialist', 'hr-officer',
                        'admin', 'super-admin'];

  v_can := v_override
    or v_is_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = p_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or (v_is_ops and (
          coalesce(v_step.step_order, 0) >= 2
       or coalesce(v_step.escalation_deadline, p_req.escalation_deadline) < now()
       or p_req.workflow_status in ('escalated', 'awaiting_operator')
       or p_req.request_type in ('mission', 'convoy', 'fundraising')));

  -- «دورك الآن»: الطلب بانتظار قرارك إذا كنت تملك صلاحية البت فيه
  -- سواء كنت المدير المباشر، أو الإدارة العليا/المفوضة، أو الخطوة الحالية مسندة إليك
  v_awaiting := v_can and (
       v_override
    or v_is_mgr
    or (v_step.id is not null and (
         v_step.assignee_employee_id = p_me
         or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
       ))
    or (v_step.id is not null and v_step.assignee_role_slug is not null
        and (v_step.assignee_role_slug = any(v_roles) or (v_is_clinic_mgr and v_step.assignee_role_slug = 'clinics-manager')))
    or (v_step.id is not null and v_step.assignee_employee_id is null
        and v_step.assignee_role_slug is null and v_is_mgr)
    or (v_step.id is null and (
          v_is_mgr
       or (v_is_ops and p_req.workflow_status in ('escalated', 'awaiting_operator')))));

  return jsonb_build_object('canDecide', v_can, 'awaitingMe', coalesce(v_awaiting, false));
end;
$$;

-- ─── 3) تحديث get_team_attendance_corrections لتشمل الإدارة التنفيذية والتشغيل ─
create or replace function public.get_team_attendance_corrections(
  p_status text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return coalesce((
    select jsonb_agg(
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
          and (
            public.current_is_full_access()
            or public.current_has_active_role(array['admin', 'super-admin', 'general-manager', 'hr-manager', 'executive', 'executive-director', 'operations-manager-1'])
            or public.can_access_employee(c.employee_id, 'attendance.correction.review')
            or exists (
              select 1 from public.manager_relations mr
              where mr.employee_id = c.employee_id
                and mr.manager_employee_id = public.current_employee_id()
                and mr.relation_type = 'primary'
                and mr.effective_from <= current_date
                and (mr.effective_to is null or mr.effective_to >= current_date)
            )
          )
        )
      ) order by c.created_at desc
    )
    from public.attendance_corrections c
    join public.employees e on e.id = c.employee_id
    left join public.job_titles jt on jt.id = e.job_title_id
    where (p_status is null or p_status = 'all' or c.status = p_status)
      and (
        public.current_is_full_access()
        or public.current_has_active_role(array['admin', 'super-admin', 'general-manager', 'hr-manager', 'executive', 'executive-director', 'operations-manager-1'])
        or public.can_access_employee(c.employee_id, 'attendance.correction.review')
        or exists (
          select 1 from public.manager_relations mr
          where mr.employee_id = c.employee_id
            and mr.manager_employee_id = public.current_employee_id()
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date)
        )
      )
    limit p_limit
  ), '[]'::jsonb);
end;
$$;

commit;
