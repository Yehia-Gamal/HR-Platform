-- 0410: إصلاح الجداء الديكارتي في get_mobile_operations_center
--
-- 0408 قرأ المهام/المهمات/القوافل من جدول employees بثلاثة LEFT JOIN ثم
-- jsonb_agg واحد → أي موظف لديه مهمتان وثلاث مهمات ينتج 2×3 صفوف، فتتضخم
-- العدادات وتتكرر العناصر. الويب (useOperationsCenter) يقرأ كل جدول باستعلام
-- مستقل — نعيد كتابة الـ RPC بنفس الطريقة مع نفس قواعد الوصول لكل جدول:
--   tasks:      المسند إليه / المنشئ / has_permission('tasks.read')
--   missions:   full-access / requests.read / صاحب الطلب / can_access_employee
--   convoys:    full-access / requests.read / صاحب الطلب / can_access_employee
-- كما عُدّل الحارس ليطابق بوابة الويب /operations: reports.read أو
-- operations.mission.manage أو operations.convoy.manage — وأُزيل tasks.read
-- من البوابة (متاحة لكل الأدوار فلا تُفتح بها ميزة إدارية).

create or replace function public.get_mobile_operations_center()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tasks    jsonb;
  v_missions jsonb;
  v_convoys  jsonb;
  v_summary  jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.read')
    or public.has_permission('operations.mission.manage')
    or public.has_permission('operations.convoy.manage')
  ) then
    raise exception 'operations center permission required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_tasks
  from (
    select jsonb_build_object(
      'id', t.id,
      'title', t.title,
      'description', t.description,
      'assigneeId', t.assignee_employee_id,
      'assigneeName', coalesce(a.full_name_ar, 'غير معيّن'),
      'priority', t.priority,
      'dueDate', t.due_date,
      'status', t.status
    ) as j
    from public.tasks t
    left join public.employees a on a.id = t.assignee_employee_id
    where (
      public.current_is_full_access()
      or t.assignee_employee_id = public.current_employee_id()
      or t.created_by_employee_id = public.current_employee_id()
      or public.has_permission('tasks.read')
    )
    order by t.created_at desc
    limit 200
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_missions
  from (
    select jsonb_build_object(
      'id', m.id,
      'employeeName', coalesce(me.full_name_ar, 'موظف'),
      'destination', m.destination,
      'purpose', m.purpose,
      'startAt', m.start_at,
      'endAt', m.end_at,
      'status', coalesce(mr.status, 'pending'),
      'transportMode', m.transport_mode
    ) as j
    from public.missions m
    left join public.employees me on me.id = m.employee_id
    left join public.requests mr on mr.id = m.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or m.employee_id = public.current_employee_id()
      or public.can_access_employee(m.employee_id)
    )
    order by m.start_at desc
    limit 100
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_convoys
  from (
    select jsonb_build_object(
      'id', c.id,
      'employeeName', coalesce(ce.full_name_ar, 'موظف'),
      'name', c.convoy_name,
      'origin', c.origin,
      'destination', c.destination,
      'departureAt', c.departure_at,
      'returnAt', c.return_at,
      'passengers', c.passengers_count,
      'vehicles', c.vehicles_count,
      'status', coalesce(cr.status, 'pending')
    ) as j
    from public.convoy_requests c
    left join public.employees ce on ce.id = c.employee_id
    left join public.requests cr on cr.id = c.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or c.employee_id = public.current_employee_id()
      or public.can_access_employee(c.employee_id)
    )
    order by c.departure_at desc
    limit 100
  ) s;

  select jsonb_build_object(
    'openTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'status' not in ('done', 'cancelled')),
    'urgentTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'priority' = 'urgent'
         and x->>'status' not in ('done', 'cancelled')),
    'missions', jsonb_array_length(v_missions),
    'convoys', jsonb_array_length(v_convoys)
  )
  into v_summary;

  return jsonb_build_object(
    'summary', v_summary,
    'tasks', v_tasks,
    'missions', v_missions,
    'convoys', v_convoys,
    'lastUpdatedAt', now()
  );
end;
$$;

revoke all on function public.get_mobile_operations_center() from public, anon;
grant execute on function public.get_mobile_operations_center() to authenticated;
