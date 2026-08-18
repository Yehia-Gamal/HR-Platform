-- 0436: مهلة موحدة ساعتان لكل الطلبات + إشعار ذاتي عند تسجيل الحضور/الانصراف
-- ══════════════════════════════════════════════════════════════════════
-- المطلوب:
--   (1) كل طلب (إجازة/مأمورية/قافلة/فاندي/أذونات/...) له مهلة إجمالية ساعتان:
--       الخطوة 1 (المدير المباشر) = ساعتان، وبعدها إشعار للأوبريشن
--       (operations-manager-1) وتصعيد الخطوة إليه بمهلة ساعتين أيضاً.
--       المدير المباشر يبقى مخوّلاً بالقبول/الرفض في أي وقت (كما هو في
--       decide_request — v_is_direct_mgr دائماً صالح).
--   (2) عدّاد "متبقي" المعروض (decision_due_at) = ساعتان كحد أقصى لأي طلب.
--   (3) عند تسجيل حضور/انصراف موظف: إشعار للموظف نفسه (تأكيد داخل
--       التطبيق + push) إضافةً لإشعار المدير المباشر والمدير التنفيذي.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ═════════════════════════════════════════════════════════════════════
-- 1) خطوة الأوبريشن في كل التعريفات: مهلة ساعتين بدل 4
-- ═════════════════════════════════════════════════════════════════════
update public.workflow_steps
  set sla_hours = 2,
      escalate_after_hours = 2,
      updated_at = now()
where is_active = true
  and step_type = 'approval'
  and approver_role_slug = 'operations-manager-1'
  and sla_hours = 4;

-- ═════════════════════════════════════════════════════════════════════
-- 2) التعريفات: default_due_hours = 2 (العدّاد العام للطلب) + tierHours=2/2
-- ═════════════════════════════════════════════════════════════════════
update public.workflow_definitions
  set default_due_hours = 2,
      config = config || jsonb_build_object(
        'tierHours', jsonb_build_object('manager', 2, 'operations', 2)
      ),
      updated_at = now()
where is_active = true;

-- ═════════════════════════════════════════════════════════════════════
-- 3) process_request_sla: تفعيل خطوة الأوبريشن بمهلة ساعتين بدل 4
-- ═════════════════════════════════════════════════════════════════════
create or replace function public.process_request_sla(
  p_limit integer default 200
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_target   uuid;
  v_role     text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(p_limit, 2000))
    for update of rs skip locked
  loop
    -- ── الخطوة النهائية (أبو عمار، أو أي مرحلة >= 2): لا تصعيد أبعد ──
    --    فقط تذكير دوري لأبو عمار وإعادة ضبط المهلة (24 ساعة).
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        -- أعد توجيه الخطوة إلى أبو عمار إن لم تكن له (طلبات قديمة 3-tier)
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
          where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبَتّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير).
المدير المباشر لم يبتّ والطلب محوّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;
      -- صفّر deadline لمنع تكرار التذكير الفوري (24 ساعة من الآن)
      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (أبو عمار) ──
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    -- وسّم الخطوة الحالية كـ escalated
    update public.request_steps
      set status = 'escalated', escalated_at = now(), updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      -- فعّل الخطوة التالية (أبو عمار) — مهلة ساعتين
      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      -- إشعار أبو عمار (الخطوة 2)
      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير التنفيذي (كامل الشاشة) عند كل تصعيد
      perform public.notify_executive_fullscreen(
        'تصعيد طلب — للمتابعة',
        coalesce(v_row.title, ''),
        'request',
        'request', v_row.request_id,
        '/requests/' || v_row.request_id,
        jsonb_build_object(
          'escalation', 'executive_notify',
          'tier', v_next.step_order
        )
      );
    else
      -- لا توجد خطوة تالية (طلب قديم بلا بنية): تصعيد عام
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  -- سجل صحة الـ cron
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('process_request_sla', 0, 'error', sqlerrm);
  raise;
end;
$$;
comment on function public.process_request_sla(integer) is
  '0436: تصعيد من مستويين — مدير(2س)→أبو عمار(operations-manager-1) بمهلة 2س. بدون HR؛ الخطوة الأخيرة لها تذكير دوري.';
revoke all on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

-- ═════════════════════════════════════════════════════════════════════
-- 4) الطلبات المعلقة حالياً: تقليص المهلات إلى ساعتين من الآن (قاعدة
--    موحدة: أي طلب معلق → متبقي 2 ساعة كحد أقصى)
-- ═════════════════════════════════════════════════════════════════════
update public.requests
  set decision_due_at = least(decision_due_at, now() + interval '2 hours'),
      updated_at = now()
where status = 'pending'
  and decision_due_at is not null;

update public.request_steps
  set due_at = case
        when due_at is not null then least(due_at, now() + interval '2 hours')
        else null end,
      escalation_deadline = case
        when escalation_deadline is not null
          then least(escalation_deadline, now() + interval '2 hours')
        else null end,
      updated_at = now()
where status in ('active', 'escalated');

-- ═════════════════════════════════════════════════════════════════════
-- 5) تريجر الحضور: إشعار ذاتي للموظف عند تسجيل حضوره/انصرافه
--    (تأكيد داخل التطبيق + push) — يضاف إلى إشعارَي المدير المباشر
--    والمدير التنفيذي الحاليين.
-- ═════════════════════════════════════════════════════════════════════
create or replace function public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'HH24:MI'
  );

  -- إشعار الموظف نفسه (تأكيد تسجيل الحضور/الانصراف)
  perform public.notify_employee(
    new.employee_id,
    case when v_event = 'attendance_check_in' then 'تم تسجيل حضورك'
         else 'تم تسجيل انصرافك' end,
    format(
      'تم تسجيل %s الساعة %s',
      case when v_event = 'attendance_check_in' then 'حضورك' else 'انصرافك' end,
      v_time
    ),
    'attendance', 'normal', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time
    )
  );

  -- إشعار المدير المباشر (يبقى كما هو — أولوية منخفضة)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
    perform public.notify_employee(
      v_manager,
      case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
           else 'انصراف موظف — تسجيل خروج' end,
      format(
        '%s — %s (%s)',
        coalesce(v_emp_ar, 'موظف'),
        case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
        v_time
      ),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- إشعار المدير التنفيذي (كامل الشاشة) عند كل دخول/انصراف
  perform public.notify_executive_fullscreen(
    case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
         else 'انصراف موظف — تسجيل خروج' end,
    format(
      '%s — %s (%s)',
      coalesce(v_emp_ar, 'موظف'),
      case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
      v_time
    ),
    'attendance',
    'attendance_daily', new.id,
    null,
    jsonb_build_object(
      'event', v_event,
      'employeeId', new.employee_id,
      'workDate', new.work_date,
      'time', v_time
    ),
    false  -- لا nudge على كثافة أحداث الحضور؛ يعتمد على جدولة الـ dispatcher
  );

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  '0436: يُشعر الموظف نفسه (تأكيد) والمدير المباشر (low) والمدير التنفيذي (كامل الشاشة) بدخول/انصراف أي موظف.';

drop trigger if exists trg_attendance_daily_notify_manager on public.attendance_daily;
create trigger trg_attendance_daily_notify_manager
  after insert or update of first_check_in, last_check_out on public.attendance_daily
  for each row execute function public.tg_attendance_daily_notify_manager();

notify pgrst, 'reload schema';

commit;