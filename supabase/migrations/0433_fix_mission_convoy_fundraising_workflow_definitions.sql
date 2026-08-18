-- 0433: استعادة تعريفات سير الاعتماد المفقودة + إصلاح الطلبات المعلقة
--
-- التشخيص: تعريفات workflow_definitions الخاصة بـ mission/convoy/fundraising
-- (و late_permit/early_permit) مفقودة في الإنتاج (تعريفات three-tier من 0366
-- حُذفت من قاعدة الإنتاج)، وبما أن _submit_request_for لا ينشئ خطوات إلا عند
-- وجود تعريف، تُنشأ الطلبات بـ status='pending' و workflow_status='submitted'
-- بلا request_steps ولا workflow_instances — فتعلق للأبد ولا يتم تسجيل/اعتماد
-- المأمورية، ويعرض الواجهات مؤقّت مهلة (decision_due_at) "متبقي Xس Yد" دون
-- أي تقدم.
--
-- الإصلاح:
--   1) إنشاء تعريفات three-tier-{mission,convoy,fundraising,late_permit,early_permit}
--      إن لم توجد، بنفس نسق التعريفات الناجية (two-tier: مدير مباشر ثم مشرف
--      عمليات 1).
--   2) ربط الطلبات المعلقة بلا خطوات بالتعريف الجديد وإنشاء خطواتها ومثيل
--      السير، مع تجديد decision_due_at/escalation_deadline لتبدأ مهلة جديدة
--      (ساعات الخطوة الأولى).

begin;

do $$
declare
  v_type text;
  v_def  uuid;
  v_steps integer;
begin
  foreach v_type in array array['mission','convoy','fundraising','late_permit','early_permit'] loop
    -- التعريف النشط الافتراضي للفئة
    select id into v_def
    from public.workflow_definitions
    where request_type = v_type and is_default = true and is_active = true
    order by version desc limit 1;

    if v_def is null then
      insert into public.workflow_definitions (
        code, name_ar, description, request_type, version,
        is_active, is_default, auto_escalate, default_due_hours, config
      ) values (
        'three-tier-' || v_type,
        case v_type
          when 'mission'     then 'سير اعتماد المأمورية — مدير مباشر ثم مشرف عمليات 1'
          when 'convoy'      then 'سير اعتماد القافلة — مدير مباشر ثم مشرف عمليات 1'
          when 'fundraising' then 'سير اعتماد الفاندي — مدير مباشر ثم مشرف عمليات 1'
          when 'late_permit' then 'سير اعتماد إذن الحضور — مدير مباشر ثم مشرف عمليات 1'
          else                    'سير اعتماد إذن الانصراف — مدير مباشر ثم مشرف عمليات 1'
        end,
        'سير عمل ثنائي المراحل: موافقة المدير المباشر ثم موافقة مشرف العمليات 1. لا تشمل موافقة HR.',
        v_type, 1, true, true, true, 48,
        jsonb_build_object(
          'tierHours', jsonb_build_object('manager', 2, 'operations', 4),
          'concurrentActors', jsonb_build_array('direct_manager','operations','executive')
        )
      )
      returning id into v_def;
    end if;

    -- خطوات التعريف (فقط عند غيابها — لا نمسح خطوات قائمة)
    select count(*) into v_steps
    from public.workflow_steps
    where definition_id = v_def and is_active = true;

    if v_steps = 0 then
      insert into public.workflow_steps (
        definition_id, step_order, name_ar, name_en, step_type,
        approver_type, approver_employee_id, approver_role_slug,
        approver_permission, is_optional, allow_delegate,
        sla_hours, escalate_after_hours, config, is_active
      ) values
        (v_def, 1, 'موافقة المدير المباشر', 'Manager approval', 'approval',
         'direct_manager', null, null, null, false, true, 2, 2, '{}'::jsonb, true),
        (v_def, 2, 'موافقة مشرف العمليات 1', 'Operations supervisor 1 approval', 'approval',
         'operator', null, 'operations-manager-1', null, false, true, 4, 4, '{}'::jsonb, true);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- إصلاح الطلبات المعلقة (mission/convoy/fundraising/late_permit/early_permit)
-- بلا خطوات سير
-- ---------------------------------------------------------------------------
do $$
declare
  v_req   record;
  v_def   uuid;
  v_step1 public.workflow_steps%rowtype;
  v_step2 public.workflow_steps%rowtype;
  v_due   timestamptz;
  v_user  uuid;
begin
  for v_req in
    select r.id, r.request_type, r.manager_employee_id, r.employee_id, r.decision_due_at
    from public.requests r
    where r.request_type in ('mission','convoy','fundraising','late_permit','early_permit')
      and r.status = 'pending'
      and r.workflow_status = 'submitted'
      and not exists (
        select 1 from public.request_steps s where s.request_id = r.id
      )
  loop
    -- created_by يشير إلى auth.users وليس employees
    select user_id into v_user from public.employees where id = v_req.employee_id;

    select id into v_def
    from public.workflow_definitions
    where request_type = v_req.request_type and is_default = true and is_active = true
    order by version desc limit 1;

    if v_def is null then
      continue;
    end if;

    -- الخطوة 1: نشطة بموعد جديد (ساعتان من الآن) — نعطي مهلة نظيفة بدل الماضي
    select * into v_step1
    from public.workflow_steps
    where definition_id = v_def and step_order = 1 and is_active = true;

    select * into v_step2
    from public.workflow_steps
    where definition_id = v_def and step_order = 2 and is_active = true;

    if v_step1.id is null then
      continue;
    end if;

    v_due := now() + make_interval(hours => coalesce(v_step1.sla_hours, 2));

    -- تحديث مرجع التعريف + تجديد المهلة على الطلب
    update public.requests
       set workflow_definition_id = v_def,
           decision_due_at        = v_due,
           escalation_deadline    = case when exists (
               select 1 from public.workflow_definitions d
               where d.id = v_def and d.auto_escalate
             ) then v_due else escalation_deadline end,
           updated_at = now()
     where id = v_req.id;

    -- إنشاء الخطوتين
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    ) values
      (v_req.id, v_step1.id, 1, v_step1.name_ar, v_step1.step_type,
       v_req.manager_employee_id, v_step1.approver_role_slug, 'active',
       v_step1.sla_hours, v_due,
       case when v_step1.escalate_after_hours is not null
            then now() + make_interval(hours => v_step1.escalate_after_hours) end,
       v_user),
      (v_req.id, v_step2.id, 2, v_step2.name_ar, v_step2.step_type,
       null, v_step2.approver_role_slug, 'pending',
       v_step2.sla_hours, null, null, v_user);

    -- مثيل السير
    insert into public.workflow_instances (
      definition_id, request_id, status, current_step_order, created_by
    ) values (
      v_def, v_req.id, 'running', 1, v_user
    );

    -- سجل إعادة التفعيل
    insert into public.request_actions (
      request_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      v_req.id, null, 'system', 'pending', 'pending',
      'أُعيد ربط الطلب بسير الاعتماد بعد إصلاح التعريفات المفقودة (0433)', v_user
    );

    -- إشعار المسؤول الأول (المدير المباشر) لتفعيل الخطوة
    if v_req.manager_employee_id is not null
       and v_req.manager_employee_id <> v_req.employee_id then
      perform public.notify_employee(
        v_req.manager_employee_id,
        'طلب معلق بانتظار موافقتك',
        format('%s — أعيد ربطه بسير الاعتماد بعد إصلاح التعريفات.',
               coalesce((select title from public.requests where id = v_req.id), 'طلب')),
        'request', 'high', 'request', v_req.id,
        jsonb_build_object(
          'requestType', v_req.request_type,
          'workflowStatus', 'submitted',
          'deepLink', '/requests/' || v_req.id
        )
      );
    end if;
  end loop;
end $$;

commit;
