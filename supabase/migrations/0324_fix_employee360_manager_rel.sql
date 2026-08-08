-- ============================================================================
-- 0324 — إصلاح get_employee_360: managerId لا يُحلّ بعد تغيير 0305
-- ════════════════════════════════════════════════════════════════════════════
-- مشاكل في get_employee_360 تُفشل الدالة وقت التنفيذ على كل الموظفين
-- (تعطّل فتح ملف الموظف — صفحة EmployeeDetailPage):
--   1) 0305 غيّرت manager_rel من lateral join إلى left join على جدول
--      employees لكنها أبقَتَ 'managerId', manager_rel.manager_employee_id
--      (عمود غير موجود في employees).
--   2) شرط ed.is_active=true على employee_departments — عمود غير موجود
--      (الجدول يستخدم start_date/end_date للنطاق الفعّال).
-- الحل: إعادة تعريف الدالة كاملة — managerId كـ subquery ذاتي من
-- manager_relations، وفلترة الإدارات بالنطاق الفعّال بدل is_active.
-- ============================================================================

create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'email', au.email,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', (
      select mr.manager_employee_id
      from public.manager_relations mr
      where mr.employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      limit 1
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'latestKpi', (
      select jsonb_build_object(
        'id', ke.id,
        'periodMonth', kc.period_month,
        'currentStage', ke.current_stage,
        'finalScore', ke.final_score,
        'finalRating', ke.final_rating
      )
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id=ke.cycle_id
      where ke.employee_id=e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id=e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id=e.id order by created_at desc limit 10
      ) t
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id=ed.department_id
      where ed.employee_id=e.id
        and (ed.start_date is null or ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        and (ed.end_date is null or ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.employees manager_rel on manager_rel.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    limit 1
  )
  left join public.profiles profile on profile.employee_id=e.id
  left join auth.users au on au.id=profile.id
  where e.id=p_employee_id;

  if v_result is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

revoke all on function public.get_employee_360(uuid) from public;
grant execute on function public.get_employee_360(uuid) to authenticated;

comment on function public.get_employee_360(uuid) is
  'ملف الموظف 360° — يُصلح managerId (قراءة مباشرة من manager_relations بعد كسر 0305).';
