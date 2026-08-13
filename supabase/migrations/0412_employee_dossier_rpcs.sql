-- 0412: دوال ملف الموظف الشامل (Dossier) — إجازات/حضور/طلبات مواقع/مهام/KPI/تقارير.
-- سلسلة دوال قراءة آمنة (SECURITY DEFINER) لبيانات موظف واحد لصفحة الملف الشامل في الويب.
-- الحارس موحّد مع get_employee_360: people.employee.read أو can_access_employee (المدير المباشر).
-- التقارير اليومية عبر get_mobile_daily_reports (موجود)، والإجازات عبر get_leave_requests_admin،
-- والحضور عبر get_employee_monthly_attendance_statement، والكتالوج عبر get_report_scheduler_catalog.

-- ---------------------------------------------------------------------
-- 1) طلبات المواقع الخاصة بالموظف
-- ---------------------------------------------------------------------
create or replace function public.get_employee_location_requests(
  p_employee_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'requestedByName', rb.full_name_ar,
    'reason', l.reason,
    'status', l.status,
    'purpose', l.purpose,
    'requestedAt', l.requested_at,
    'respondedAt', l.responded_at,
    'startsAt', l.starts_at,
    'expiresAt', l.expires_at,
    'durationMinutes', l.duration_minutes
  ) order by l.requested_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.live_location_requests
    where employee_id = p_employee_id
    order by requested_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) l
  left join public.employees rb on rb.id = l.requested_by;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) مهام الموظف (كل المهام المسندة إليه)
-- ---------------------------------------------------------------------
create or replace function public.get_employee_tasks_admin(
  p_employee_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'title', t.title,
    'description', t.description,
    'priority', t.priority,
    'status', t.status,
    'dueDate', t.due_date,
    'createdAt', t.created_at,
    'createdByName', c.full_name_ar
  ) order by t.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.tasks
    where assignee_employee_id = p_employee_id
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  ) t
  left join public.employees c on c.id = t.created_by_employee_id;

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) تقييمات KPI الخاصة بالموظف عبر جميع الدورات
-- ---------------------------------------------------------------------
create or replace function public.get_employee_kpi_evaluations_admin(
  p_employee_id uuid,
  p_limit integer default 60
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ke.id,
    'periodMonth', kc.period_month,
    'currentStage', ke.current_stage,
    'workflowStatus', ke.workflow_status,
    'cycleStatus', kc.status,
    'finalScore', ke.final_score,
    'finalRating', ke.final_rating,
    'managerComment', ke.manager_comment,
    'hrComment', ke.hr_comment,
    'locked', ke.locked,
    'updatedAt', ke.updated_at
  ) order by kc.period_month desc), '[]'::jsonb)
  into v_result
  from public.kpi_evaluations ke
  join public.kpi_cycles kc on kc.id = ke.cycle_id
  where ke.employee_id = p_employee_id
  order by kc.period_month desc
  limit greatest(1, least(coalesce(p_limit, 60), 240));

  return v_result;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) القرارات المنشورة الموجهة للموظف (all أو في قائمة المستلمين)
-- ---------------------------------------------------------------------
create or replace function public.get_employee_published_decisions_admin(
  p_employee_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if not (
    public.has_permission('people.employee.read')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'ERR_FORBIDDEN' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'decisionNumber', d.decision_number,
    'title', d.title,
    'category', d.category,
    'effectiveDate', d.effective_date,
    'expiryDate', d.expiry_date,
    'publishedAt', d.published_at,
    'isRead', exists(
      select 1 from public.decision_reads dr
      where dr.decision_id = d.id and dr.employee_id = p_employee_id
    ),
    'acknowledged', coalesce((
      select dr.acknowledged from public.decision_reads dr
      where dr.decision_id = d.id and dr.employee_id = p_employee_id
      limit 1
    ), false)
  ) order by d.published_at desc nulls last), '[]'::jsonb)
  into v_result
  from (
    select * from public.administrative_decisions d
    where d.status = 'published'
      and (
        d.target_type = 'all'
        or exists (
          select 1 from public.decision_recipients r
          where r.decision_id = d.id and r.employee_id = p_employee_id
        )
      )
    order by d.published_at desc nulls last
    limit greatest(1, least(coalesce(p_limit, 100), 300))
  ) d;

  return v_result;
end;
$$;

-- الأذونات: متاحة للمصادق فقط
revoke execute on function public.get_employee_location_requests(uuid, integer) from public, anon;
grant execute on function public.get_employee_location_requests(uuid, integer) to authenticated;

revoke execute on function public.get_employee_tasks_admin(uuid, integer) from public, anon;
grant execute on function public.get_employee_tasks_admin(uuid, integer) to authenticated;

revoke execute on function public.get_employee_kpi_evaluations_admin(uuid, integer) from public, anon;
grant execute on function public.get_employee_kpi_evaluations_admin(uuid, integer) to authenticated;

revoke execute on function public.get_employee_published_decisions_admin(uuid, integer) from public, anon;
grant execute on function public.get_employee_published_decisions_admin(uuid, integer) to authenticated;
