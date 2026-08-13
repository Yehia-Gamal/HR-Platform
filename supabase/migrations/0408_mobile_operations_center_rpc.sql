-- 0408: RPC get_mobile_operations_center — مركز العمليات للموبايل (إدارة التشغيل)
--
-- كان «إدارة التشغيل» محذوفاً من الجوال ويُعرض عبر صفحة "ويب فقط". هذا الـ RPC
-- يقدّم نفس بيانات مركز العمليات على الويب (المهام/المهمات/القوافل) لكن بصيغة
-- مضغوطة مناسبة للموبايل، مع نفس قيود الصلاحيات (tasks.read / operations.*).
-- الصلاحيات تُطبَّق داخل دالة security definer بدل الاعتماد على RLS الجدولي.

create or replace function public.get_mobile_operations_center()
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
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('tasks.read')
    or public.has_permission('operations.mission.manage')
    or public.has_permission('operations.convoy.manage')
  ) then
    raise exception 'operations center permission required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'openTasks',   count(*) filter (where t.id is not null and t.status not in ('done', 'cancelled')),
      'urgentTasks', count(*) filter (where t.id is not null and t.priority = 'urgent' and t.status not in ('done', 'cancelled')),
      'missions',    count(*) filter (where m.id is not null),
      'convoys',     count(*) filter (where c.id is not null)
    ),
    'tasks', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'description', t.description,
        'assigneeId', t.assignee_employee_id,
        'assigneeName', coalesce(a.full_name_ar, 'غير معيّن'),
        'priority', t.priority,
        'dueDate', t.due_date,
        'status', t.status
      )
    ) filter (where t.id is not null), '[]'::jsonb),
    'missions', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'employeeName', coalesce(me.full_name_ar, 'موظف'),
        'destination', m.destination,
        'purpose', m.purpose,
        'startAt', m.start_at,
        'endAt', m.end_at,
        'status', coalesce(mr.status, 'pending'),
        'transportMode', m.transport_mode
      )
    ) filter (where m.id is not null), '[]'::jsonb),
    'convoys', coalesce(jsonb_agg(
      jsonb_build_object(
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
      )
    ) filter (where c.id is not null), '[]'::jsonb),
    'lastUpdatedAt', now()
  )
  into v_result
  from public.employees e
  left join public.tasks t
    on t.assignee_employee_id = e.id
  left join public.employees a on a.id = t.assignee_employee_id
  left join public.missions m
    on m.employee_id = e.id
  left join public.requests mr on mr.id = m.request_id
  left join public.employees me on me.id = m.employee_id
  left join public.convoy_requests c
    on c.employee_id = e.id
  left join public.requests cr on cr.id = c.request_id
  left join public.employees ce on ce.id = c.employee_id
  where e.status = 'active'
    and e.is_deleted = false
    and (t.id is not null or m.id is not null or c.id is not null)
    and (
      public.current_is_full_access()
      or public.can_access_employee(e.id, 'tasks.read')
      or public.can_access_employee(e.id, 'operations.mission.manage')
      or public.can_access_employee(e.id, 'operations.convoy.manage')
    );

  return coalesce(v_result, jsonb_build_object(
    'summary', jsonb_build_object('openTasks', 0, 'urgentTasks', 0, 'missions', 0, 'convoys', 0),
    'tasks', '[]'::jsonb, 'missions', '[]'::jsonb, 'convoys', '[]'::jsonb,
    'lastUpdatedAt', now()
  ));
end;
$$;

revoke all on function public.get_mobile_operations_center() from public, anon;
grant execute on function public.get_mobile_operations_center() to authenticated;
