-- mig 0389: إشعار FCM تلقائي للمدير عند تأخر الموظف
-- يُطلق على كل حدث CHECK_IN بـ late_minutes > 0 ويبلغ المدير المباشر.

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
begin
  -- تنطبق فقط على CHECK_IN متأخر (late_minutes > 0)
  if new.event_type <> 'CHECK_IN' or coalesce(new.late_minutes, 0) <= 0 then
    return new;
  end if;

  -- جلب بيانات الموظف المتأخر
  select e.id, e.full_name_ar, e.user_id
    into v_employee
    from public.employees e
   where e.id = new.employee_id;

  if not found then return new; end if;

  -- جلب المدير المباشر (أول مدير في manager_relations)
  select e.id, e.user_id
    into v_manager
    from public.manager_relations mr
    join public.employees e on e.id = mr.manager_employee_id
   where mr.employee_id = new.employee_id
     and e.user_id is not null
     and e.is_active = true
   limit 1;

  if not found or v_manager.user_id is null then return new; end if;

  -- صياغة وقت التأخير
  v_late_text := case
    when new.late_minutes >= 60 then
      (new.late_minutes / 60)::text || ' ساعة ' || (new.late_minutes % 60)::text || ' دقيقة'
    else
      new.late_minutes::text || ' دقيقة'
  end;

  -- إدراج الإشعار — الـ trigger trg_notifications_queue_jobs يُضيف notification_jobs تلقائياً
  insert into public.notifications (
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    entity_type,
    entity_id,
    metadata
  ) values (
    v_manager.user_id,
    v_manager.id,
    'موظف متأخر: ' || coalesce(v_employee.full_name_ar, 'غير محدد'),
    'سجّل ' || coalesce(v_employee.full_name_ar, 'الموظف') || ' حضوره متأخراً بمقدار ' || v_late_text || '.',
    'system',
    'normal',
    'attendance_event',
    new.id,
    jsonb_build_object(
      'lateMinutes', new.late_minutes,
      'employeeId', new.employee_id::text
    )
  ) returning id into v_notif_id;

  return new;
exception
  when others then
    -- الإشعار اختياري — لا يعطّل تسجيل الحضور
    return new;
end;
$$;

drop trigger if exists trg_late_arrival_notify_manager on public.attendance_events;
create trigger trg_late_arrival_notify_manager
  after insert on public.attendance_events
  for each row
  execute function public.tg_notify_manager_late_arrival();
