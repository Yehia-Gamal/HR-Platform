-- =====================================================================
-- 0556: إصلاح النص العربي التالف (mojibake) في 12 دالة وفي الإشعارات
--
-- العَرَض: عناوين الإشعارات تظهر هكذا «Ø¬.Ù…» بدل «ج.م» في الويب والهاتف
-- (58 إشعار «مضاعفة غرامة تأخير» صباح 2026-09-25 + 30 إشعار قرار طلب).
--
-- السبب: نشر دوال عبر Management API دون إرسال النص بايتات UTF-8 — فُسِّر
-- كل حرف عربي كحرفين من cp1252 (النمط الموثّق في CLAUDE.md، وهو غير الـ ???
-- الذي كان فحص ما بعد النشر يلتقطه وحده). ملفات المصدر نفسها سليمة.
--
-- الإصلاح:
--   1) إعادة إنشاء كنونية لكل دالة من أحدث migration نظيفة تعرّفها (بلا
--      رقعة regex على pg_get_functiondef). تحقّقنا قبل الكتابة أن جسم كل دالة
--      في الإنتاج — بعد عكس التلف — يطابق المصدر حرفاً بحرف: لا تغيير سلوكي.
--      CREATE OR REPLACE يُبقي المنح والمالك كما هي.
--   2) إصلاح الصفوف المتأثرة: فقط «سلاسل التلف» داخل النص تُعاد ترميزاً؛
--      أسماء الموظفين العربية السليمة في نفس الصف لا تُمس. أي سلسلة لا
--      تُفكّ إلى UTF-8 صحيح تبقى كما هي.
--
-- لم تُعدَّل audit_events (109 صفاً متأثراً) عمداً: سجل تدقيق — القرار لصاحبه.
-- بعد النشر: select proname from pg_proc where prosrc ~ '(Ø|Ù|ðŸ|â€)' → فارغ.
-- =====================================================================

begin;

-- ─── auto_escalate_instant_penalties — المصدر النظيف: 0550_escalation_doubling_auto_suspension_manual.sql
create or replace function public.auto_escalate_instant_penalties()
returns integer
language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := ((now() at time zone 'Africa/Cairo')::date);
  v_rec record;
  v_escalated integer := 0;
  v_emp_name text;
  v_exempt jsonb;
  v_pending integer := 0;
  -- 0550: التعليق يكتب employees.status و profiles.status؛ حارساهما (0004 و 0289)
  -- يسمحان بذلك لـ full-access، أو لمن يملك update_sensitive و profiles.manage معاً.
  -- نطابق شرطهما حرفياً حتى لا تصطدم الدالة بهما أبداً.
  v_can_suspend boolean := public.current_is_full_access()
                           or (public.has_permission('people.employee.update_sensitive')
                               and public.has_permission('profiles.manage'));
begin
  -- الكرون (auth.uid() is null) مسموح. استدعاء يدوي يتطلب صلاحية.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('payroll.run.manage')) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  -- ═══ المرحلة 1: مضاعفة الغرامات المتأخرة (pending_payment من أمس فأقدم) ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'pending_payment'
       and p.escalation_level = 'initial'
       and p.work_date < v_today
  loop
    -- فحص الإعفاء قبل المضاعفة
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص المضاعفة: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;
      continue;
    end if;

    update public.instant_attendance_penalties
       set status = 'doubled',
           escalation_level = 'doubled',
           current_amount = 500.00,
           updated_at = now()
     where id = v_rec.id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.doubled', 'financial', 'high',
      'instant_attendance_penalties', v_rec.id,
      'مضاعفة غرامة فورية: ' || coalesce(v_emp_name, 'موظف') || ' — 500 ج.م',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'originalAmount', v_rec.original_amount)
    );

    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🔴 مضاعفة غرامة تأخير — 500 ج.م',
      coalesce(v_emp_name, 'الموظف') || ' لم يسدد غرامة التأخير في الموعد. تمت مضاعفة الغرامة إلى 500 ج.م. يجب السداد فوراً وإلا سيتم تعليقه عن العمل.',
      'instant_penalty_doubled',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'originalAmount', v_rec.original_amount,
        'newAmount', 500,
        'channel', 'instant_penalty_doubled',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    v_escalated := v_escalated + 1;
  end loop;

  -- ═══ المرحلة 2: اليوم الثالث — غلق السيستم وإيقاف الموظف عن العمل وإشعار كامل الفريق ═══
  for v_rec in
    select p.*
      from public.instant_attendance_penalties p
     where p.status = 'doubled'
       and p.escalation_level = 'doubled'
       and p.work_date < v_today - 1
  loop
    -- فحص الإعفاء قبل التعليق
    v_exempt := public.is_employee_exempt_from_instant_penalty(v_rec.employee_id, v_rec.work_date);
    if coalesce((v_exempt->>'isExempt')::boolean, false) = true then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             notes = coalesce(notes || ' | ', '') || 'إلغاء تلقائي عند فحص الإيقاف: ' || (v_exempt->>'reason'),
             updated_at = now()
       where id = v_rec.id;

      -- رفع أي تعليق إن وجد
      update public.employees set is_active = true where id = v_rec.employee_id;
      continue;
    end if;

    -- 0550: التعليق قرار بشري. في الكرون (بلا JWT) أو لمن لا يملك تغيير الحالة
    -- كان حارسا employees/profiles يرفضان التحديث، فيلتقط `when others` الخطأ
    -- ويُلغي الدورة كاملة — بما فيها المضاعفات — ويُرجع 0 بصمت.
    -- الآن: نسجّل الاستحقاق ونترك الصف `doubled` حتى يقرر إنسان مخوَّل.
    if not v_can_suspend then
      perform public.log_audit_event(
        'instant_penalty.suspension_pending', 'operations', 'warning',
        'instant_attendance_penalties', v_rec.id,
        'موظف مستحق للتعليق — بانتظار قرار بشري',
        null,
        jsonb_build_object('employeeId', v_rec.employee_id,
                           'amount', v_rec.current_amount,
                           'workDate', v_rec.work_date)
      );
      v_pending := v_pending + 1;
      continue;
    end if;

    -- 1) تحديث سجل الغرامة
    update public.instant_attendance_penalties
       set status = 'suspended',
           escalation_level = 'suspended',
           suspended_at = now(),
           updated_at = now()
     where id = v_rec.id;

    -- 2) غلق السيستم على الموظف وإيقافه عن العمل
    update public.employees
       set status = 'suspended',
           is_active = false,
           updated_at = now()
     where id = v_rec.employee_id;

    update public.profiles
       set status = 'suspended',
           updated_at = now()
     where employee_id = v_rec.employee_id;

    select full_name_ar into v_emp_name
      from public.employees where id = v_rec.employee_id;

    perform public.log_audit_event(
      'instant_penalty.suspended', 'security', 'critical',
      'instant_attendance_penalties', v_rec.id,
      'غلق السيستم وتعليق موظف عن العمل: ' || coalesce(v_emp_name, 'موظف') || ' — لعدم سداد غرامة 500 ج.م في اليوم الثاني',
      null,
      jsonb_build_object('employeeId', v_rec.employee_id, 'amount', v_rec.current_amount)
    );

    -- 3) إشعار الموظف والمديرين
    perform public._notify_instant_penalty_stakeholders(
      v_rec.employee_id,
      '🚫 إيقاف عن العمل وغلق الحساب',
      'تم إيقافك عن العمل وغلق حسابك على السيستم لعدم سداد غرامة الـ 500 ج.م. يجب التوجه للـ HR وسداد المبلغ لإعادة فتح الحساب ومباشرة العمل.',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'amount', v_rec.current_amount,
        'channel', 'instant_penalty_suspended',
        'deepLink', 'ahlashabab://action/finance?tab=instant-penalties'
      )
    );

    -- 4) إرسال إشعار فوري لكامل الفريق (كل الموظفين النشطين بالشركة)
    perform public.notify_employee(
      e.id,
      '🚫 إشعار إيقاف موظف عن العمل',
      'إشعار للفريق: تم إيقاف ' || coalesce(v_emp_name, 'أحد الموظفين') || ' عن العمل مؤقتاً وغلق حسابه على السيستم لعدم سداد غرامة التأخير (500 ج.م) حتى يتم السداد للـ HR وإزالة الغرامة وعودته لمباشرة العمل.',
      'system',
      'urgent',
      'instant_penalty_suspended',
      v_rec.id,
      jsonb_build_object(
        'employeeId', v_rec.employee_id::text,
        'suspendedEmployeeName', v_emp_name,
        'amount', 500,
        'channel', 'team_suspension_broadcast'
      )
    )
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and e.id <> v_rec.employee_id;

    v_escalated := v_escalated + 1;
  end loop;

  return v_escalated;
exception
  when others then
    perform public.log_audit_event(
      'instant_penalty.escalation_failed', 'operations', 'error',
      'instant_attendance_penalties', null,
      'فشل التصعيد التلقائي للغرامات الفورية', null,
      jsonb_build_object('error', sqlerrm)
    );
    return 0;
end;
$function$;

-- ─── decide_request — المصدر النظيف: 0545_fix_mission_approval_check_constraint.sql
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

-- ─── get_attendance_correction_detail — المصدر النظيف: 0544_attendance_corrections_team_review.sql
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

  IF NOT FOUND THEN
    RAISE EXCEPTION 'طلب التصحيح غير موجود' USING errcode = 'P0002';
  END IF;

  -- فحص الصلاحية: صاحب الطلب أو المدير أو من يملك صلاحية المراجعة أو وصول كامل
  IF NOT (
    v_rec."employeeId" = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.can_access_employee(v_rec."employeeId", 'attendance.correction.review')
    OR EXISTS (
      SELECT 1 FROM public.manager_relations mr
      WHERE mr.employee_id = v_rec."employeeId"
        AND mr.manager_employee_id = public.current_employee_id()
        AND mr.relation_type = 'primary'
        AND mr.effective_from <= current_date
        AND (mr.effective_to IS NULL OR mr.effective_to >= current_date)
    )
    OR public.has_any_permission(ARRAY['attendance.read', 'attendance.review', 'attendance.manage', 'requests.read'])
  ) THEN
    RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode = '42501';
  END IF;

  RETURN to_jsonb(v_rec);
END;
$$;

-- ─── get_instant_penalties — المصدر النظيف: 0542_fix_instant_penalties_anon_leak_and_pagination.sql
create or replace function public.get_instant_penalties(
  p_employee_id uuid default null::uuid,
  p_status text default null::text,
  p_date_from date default null::date,
  p_date_to date default null::date,
  p_limit integer default null::integer,   -- null = بلا تقييد (سلوك اليوم)
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- تتطلب جلسة مستخدم. لا استثناء لـ«غياب الجلسة»:
  --   • لا يستدعيها أي عامل خادمي — الويب فقط (useInstantPenalties.ts).
  --   • و current_user داخل SECURITY DEFINER يساوي *مالك الدالة* لا المستدعي،
  --     فلا يصلح للتمييز بين anon و service_role (وثّق ذلك مؤلف 0483 نفسه).
  --     أي فحص على current_user هنا لا يُطلق أبداً — لذا نرفض غياب الجلسة مباشرة.
  if auth.uid() is null then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'payroll.run.manage', 'payroll.run.approve', 'people.employee.read', 'attendance.record.read'
    ])
    or (p_employee_id is not null and p_employee_id = public.current_employee_id())
    or (p_employee_id is not null and exists (
      select 1 from public.profiles where id = auth.uid() and employee_id = p_employee_id
    ))
  ) then
    raise exception 'غير مسموح' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',                     t.id,
        'employeeId',             t.employee_id,
        'employeeName',           t.employee_name,
        'employeeCode',           t.employee_code,
        'departmentName',         t.department_name,
        'workDate',               t.work_date,
        'lateMinutes',            t.late_minutes,
        'originalAmount',         t.original_amount,
        'currentAmount',          t.current_amount,
        'currency',               t.currency,
        'status',                 t.status,
        'escalationLevel',        t.escalation_level,
        'paidAt',                 t.paid_at,
        'confirmedBy',            t.confirmed_by,
        'suspendedAt',            t.suspended_at,
        'suspensionLiftedAt',     t.suspension_lifted_at,
        'notes',                  t.notes,
        'createdAt',              t.created_at,
        'excuseStatus',           t.excuse_status,
        'excuseText',             t.excuse_text,
        'excuseAttachmentUrl',    t.excuse_attachment_url,
        'excuseSubmittedAt',      t.excuse_submitted_at,
        'excuseReviewedAt',       t.excuse_reviewed_at,
        'excuseNotes',            t.excuse_notes,
        'paymentMethod',          t.payment_method,
        'receiptAttachmentUrl',   t.receipt_attachment_url,
        'receiptSubmittedAt',     t.receipt_submitted_at,
        'receiptReferenceNumber', t.receipt_reference_number
      )
      order by t.work_date desc, t.created_at desc
    )
    -- الترقيم داخل استعلام فرعي: limit/offset على استعلام تجميعي بلا أثر.
    from (
      select
        p.id,
        p.employee_id,
        e.full_name_ar                        as employee_name,
        e.employee_code,
        d.name                                as department_name,
        p.work_date,
        p.late_minutes,
        p.original_amount,
        p.current_amount,
        p.currency,
        p.status,
        p.escalation_level,
        p.paid_at,
        p.confirmed_by,
        p.suspended_at,
        p.suspension_lifted_at,
        p.notes,
        p.created_at,
        coalesce(p.excuse_status, 'none')     as excuse_status,
        p.excuse_text,
        p.excuse_attachment_url,
        p.excuse_submitted_at,
        p.excuse_reviewed_at,
        p.excuse_notes,
        coalesce(p.payment_method, 'cash')    as payment_method,
        p.receipt_attachment_url,
        p.receipt_submitted_at,
        p.receipt_reference_number
      from public.instant_attendance_penalties p
      join public.employees e on e.id = p.employee_id
      left join public.departments d on d.id = e.department_id
      where (p_employee_id is null or p.employee_id = p_employee_id)
        and (p_status is null or p.status = p_status)
        and (p_date_from is null or p.work_date >= p_date_from)
        and (p_date_to is null or p.work_date <= p_date_to)
      order by p.work_date desc, p.created_at desc
      -- LIMIT NULL في PostgreSQL = بلا تقييد. الاستدعاءات القائمة (الويب لا
      -- يمرّر p_limit) تبقى كما هي تماماً، ومن يمرّر قيمة يحصل على تقييد فعلي.
      limit case when p_limit is null then null else greatest(1, p_limit) end
      offset greatest(0, coalesce(p_offset, 0))
    ) t
  ), '[]'::jsonb);
end;
$$;

-- ─── get_mobile_action_target — المصدر النظيف: 0549_support_all_mobile_action_targets.sql
CREATE OR REPLACE FUNCTION public.get_mobile_action_target(p_action_id text, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
BEGIN
  IF p_action_id IS NULL OR p_kind IS NULL THEN
    RETURN jsonb_build_object('kind', coalesce(p_kind, ''), 'recordId', '', 'mobileRoute', 'unsupported');
  END IF;

  IF position(v_prefix in lower(p_action_id)) = 1 THEN
    v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  ELSE
    v_raw_id := p_action_id;
  END IF;

  BEGIN
    v_uuid := v_raw_id::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('kind', lower(p_kind), 'recordId', coalesce(v_raw_id, ''), 'mobileRoute', 'unsupported');
  END;

  CASE lower(p_kind)
    WHEN 'request' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.requests r
        WHERE r.id = v_uuid
          AND (
            r.employee_id = public.current_employee_id()
            OR public.current_is_full_access()
            OR public.can_access_employee(r.employee_id, 'requests.request.approve')
            OR public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    WHEN 'kpi' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.kpi_evaluations k
        WHERE k.id = v_uuid
          AND (
            k.employee_id = public.current_employee_id()
            OR public.current_is_full_access()
            OR public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            OR public.has_any_permission(ARRAY[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    WHEN 'decision' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.administrative_decisions d
        WHERE d.id = v_uuid and d.status = 'published'
          AND (
            public.current_is_full_access()
            OR public.has_any_permission(ARRAY['comms.decision.read','comms.decision.manage'])
            OR EXISTS (
              SELECT 1 FROM public.decision_recipients dr
              WHERE dr.decision_id=d.id AND dr.employee_id=public.current_employee_id()
            )
          )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    WHEN 'attendance_correction', 'attendance_corrections' THEN
      SELECT (
        EXISTS(SELECT 1 FROM public.attendance_corrections c WHERE c.id = v_uuid AND c.employee_id = public.current_employee_id())
        OR public.current_is_full_access()
        OR EXISTS(
          SELECT 1 FROM public.attendance_corrections c
          WHERE c.id = v_uuid
            AND (
              public.can_access_employee(c.employee_id, 'attendance.correction.review')
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
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','attendance_correction','recordId',v_uuid,'mobileRoute','attendance_correction_detail');

    WHEN 'attendance' THEN
      IF EXISTS(SELECT 1 FROM public.attendance_corrections c WHERE c.id = v_uuid) THEN
        RETURN jsonb_build_object('kind','attendance_correction','recordId',v_uuid,'mobileRoute','attendance_correction_detail');
      END IF;

      SELECT (
        EXISTS(SELECT 1 FROM public.attendance_events e
               WHERE e.id = v_uuid AND e.employee_id = public.current_employee_id())
        OR EXISTS(SELECT 1 FROM public.attendance_punch_attempts pa
                  WHERE pa.attendance_event_id = v_uuid AND pa.employee_id = public.current_employee_id())
        OR public.current_is_full_access()
        OR public.has_any_permission(ARRAY[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) INTO v_allowed;
      IF NOT v_allowed THEN
        RETURN jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      END IF;
      RETURN jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    WHEN 'dispute' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.dispute_cases dc
        WHERE dc.id = v_uuid AND (
          dc.actor_employee_id = public.current_employee_id()
          OR dc.respondent_employee_id = public.current_employee_id()
          OR public.current_is_full_access()
          OR public.can_access_dispute(dc.id)
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    WHEN 'task' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.tasks t
        WHERE t.id = v_uuid AND (
          t.assignee_employee_id = public.current_employee_id()
          OR t.created_by = auth.uid()
          OR public.current_is_full_access()
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    WHEN 'announcement' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.announcements a
        WHERE a.id = v_uuid AND a.status = 'published'
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    WHEN 'recognition' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.recognitions r
        WHERE r.id = v_uuid AND (
          r.recipient_employee_id = public.current_employee_id()
          OR public.current_is_full_access()
        )
      ) INTO v_allowed;
      IF NOT v_allowed THEN RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode='42501'; END IF;
      RETURN jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    WHEN 'instant_penalty', 'penalty' THEN
      SELECT EXISTS(
        SELECT 1 FROM public.instant_attendance_penalties p
        WHERE p.id = v_uuid AND (
          p.employee_id = public.current_employee_id()
          OR public.current_is_full_access()
          OR public.has_any_permission(ARRAY['penalties.read', 'penalties.manage', 'penalties.admin'])
        )
      ) INTO v_allowed;
      RETURN jsonb_build_object('kind','instant_penalty','recordId',v_uuid,'mobileRoute','instant_penalty');

    WHEN 'daily_report', 'daily_reports' THEN
      RETURN jsonb_build_object('kind','daily_report','recordId',v_uuid,'mobileRoute','daily_report');

    WHEN 'device', 'devices', 'employee_device' THEN
      RETURN jsonb_build_object('kind','device','recordId',v_uuid,'mobileRoute','device');

    WHEN 'fellowship_fund', 'fellowship' THEN
      RETURN jsonb_build_object('kind','fellowship_fund','recordId',v_uuid,'mobileRoute','instant_penalty');

    ELSE
      RETURN jsonb_build_object('kind', lower(p_kind), 'recordId', v_uuid, 'mobileRoute', 'unsupported');
  END CASE;
END;
$function$;

-- ─── get_my_access_context — المصدر النظيف: 0547_admin_account_permanent_immunity.sql
create or replace function public.get_my_access_context()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'auth', 'pg_temp'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_profile_status text;
  v_employee_status text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  -- تعليق الموظف
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code, e.photo_url,
         p.status, e.status
    into v_employee_id, v_display_name, v_employee_code, v_photo_url,
         v_profile_status, v_employee_status
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id;

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  -- ═══ الحصانة المطلقة للأدمن الرئيسي (يحيى جمال السبع) ═══
  if v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or v_employee_code in ('+201154869616', '01154869616')
     or exists (select 1 from public.employees e where e.id = v_employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  end if;

  -- ═══ فحص إيقاف الموظف عن العمل (يستثنى منه الأدمن الرئيسي قطعياً) ═══
  if not v_is_immune_admin and (coalesce(v_profile_status, '') = 'suspended' or coalesce(v_employee_status, '') = 'suspended') then
    v_is_suspended := true;

    -- فحص الغرامة الفورية المتسببة في الإيقاف (500 ج.م)
    select p.current_amount into v_suspension_amount
    from public.instant_attendance_penalties p
    where p.employee_id = v_employee_id
      and p.status = 'suspended'
    order by p.created_at desc
    limit 1;

    if found then
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := coalesce(v_suspension_amount, 500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    else
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    end if;

    return jsonb_build_object(
      'userId', v_user_id,
      'employeeId', v_employee_id,
      'displayName', v_display_name,
      'employeeCode', v_employee_code,
      'photoUrl', v_photo_url,
      'roles', '[]'::jsonb,
      'permissions', '[]'::jsonb,
      'workspaces', '[]'::jsonb,
      'defaultWorkspace', 'employee',
      'isSuspended', true,
      'suspensionReason', v_suspension_reason,
      'suspensionMessage', v_suspension_message,
      'suspensionAmount', v_suspension_amount,
      'attendancePolicy', jsonb_build_object(
        'attendanceRequired', false,
        'selfPunchEnabled', false,
        'liveLocationResponseEnabled', false
      )
    );
  end if;

  if v_profile_status not in ('active', 'pending') then
    raise exception 'حساب المستخدم غير نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id
    and ur.effective_from <= now()
    and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access() or v_is_immune_admin;
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_is_immune_admin or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- ═══ مساحات العمل ═══
  if v_employee_id is not null and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'manager');
  end if;
  if v_is_operations and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'field_operations');
  end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  -- ═══ المساحة الافتراضية ═══
  if v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_hr then
    v_default_workspace := 'hr';
  elsif v_is_operations then
    v_default_workspace := 'field_operations';
  elsif v_is_manager then
    v_default_workspace := 'manager';
  elsif v_employee_id is not null then
    v_default_workspace := 'employee';
  else
    raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'isSuspended', false,
    'suspensionReason', null,
    'suspensionMessage', null,
    'suspensionAmount', null,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and not v_is_immune_admin and v_employee_id is not null,
      'selfPunchEnabled', true,
      'liveLocationResponseEnabled', not v_is_executive and not v_is_immune_admin and v_employee_id is not null
    )
  );
end;
$function$;

-- ─── is_employee_attendance_exempt — المصدر النظيف: 0548_block_self_exemption_and_name_based_immunity.sql
create or replace function public.is_employee_attendance_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  select id, employee_code, phone_e164, full_name_ar, is_attendance_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  -- 0. الحساب الرئيسي للنظام — بالمعرّف/الكود/الهاتف فقط، لا بالاسم
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' then
    return true;
  end if;

  -- 1. فحص العلم في جدول employees
  if coalesce(v_rec.is_attendance_exempt, false) = true then
    return true;
  end if;

  -- 2. شبكة أمان كبار المسؤولين
  if p_employee_id in (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- كبير مسؤولين
    '886f4942-c469-4a03-8f02-659fd02c4a02',
    '767eae8e-e7be-458e-a6ca-879414e46b08', -- كبير مسؤولين
    'fad7044c-fe47-4db3-b7bb-54856e7ba851', -- كبير مسؤولين
    'c61c2a26-19db-49fb-ad8b-ace2d8a765af'  -- كبير مسؤولين
  ) or v_rec.employee_code in ('+201121622820', 'EXE001', '+201226905602', '+201000867705', '+201016664229') then
    return true;
  end if;

  return false;
end;
$$;

-- ─── is_employee_penalty_exempt — المصدر النظيف: 0548_block_self_exemption_and_name_based_immunity.sql
create or replace function public.is_employee_penalty_exempt(p_employee_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_rec record;
begin
  if p_employee_id is null then
    return false;
  end if;

  -- 0. الحساب الرئيسي للنظام — بالمعرّف/الكود/الهاتف فقط، لا بالاسم
  if p_employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9' then
    return true;
  end if;

  -- 1. أي موظف معفى من الحضور فهو معفى حكماً من الغرامات
  if public.is_employee_attendance_exempt(p_employee_id) then
    return true;
  end if;

  -- 2. فحص السجل في جدول employees
  select id, employee_code, phone_e164, full_name_ar, is_penalty_exempt, user_id into v_rec
    from public.employees
   where id = p_employee_id;

  if not found then
    return false;
  end if;

  if v_rec.employee_code in ('+201154869616', '01154869616')
     or v_rec.phone_e164 in ('+201154869616', '01154869616')
     or v_rec.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' then
    return true;
  end if;

  if coalesce(v_rec.is_penalty_exempt, false) = true then
    return true;
  end if;

  -- 3. استثناء بالمعرّف/الكود
  if p_employee_id = '8e21d363-f87c-4c80-b06d-1b84a2dd3804'
     or v_rec.employee_code = '+201012141949' then
    return true;
  end if;

  return false;
end;
$$;

-- ─── resolve_mobile_action_target — المصدر النظيف: 0549_support_all_mobile_action_targets.sql
CREATE OR REPLACE FUNCTION public.resolve_mobile_action_target(p_action_id text, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
  v_resolved_kind text;
BEGIN
  v_resolved_kind := CASE v_kind
    WHEN 'location' THEN 'live_location_request'
    WHEN 'location_request' THEN 'live_location_request'
    WHEN 'live_location_request' THEN 'live_location_request'
    WHEN 'live_location' THEN 'live_location_request'
    WHEN 'live_location_requests' THEN 'live_location_request'
    WHEN 'attendance_alert' THEN 'attendance'
    WHEN 'punch_reminder' THEN 'attendance'
    WHEN 'attendance_daily' THEN 'attendance'
    WHEN 'attendance_event' THEN 'attendance'
    WHEN 'attendance_corrections' THEN 'attendance_correction'
    WHEN 'attendance_correction' THEN 'attendance_correction'
    WHEN 'attendance' THEN 'attendance'
    WHEN 'overtime_records' THEN 'attendance'
    WHEN 'work_rosters' THEN 'attendance'
    WHEN 'request' THEN 'request'
    WHEN 'requests' THEN 'request'
    WHEN 'request_decision' THEN 'request'
    WHEN 'kpi' THEN 'kpi'
    WHEN 'kpi_evaluation' THEN 'kpi'
    WHEN 'decision' THEN 'decision'
    WHEN 'dispute' THEN 'dispute'
    WHEN 'dispute_case' THEN 'dispute'
    WHEN 'task' THEN 'task'
    WHEN 'announcement' THEN 'announcement'
    WHEN 'recognition' THEN 'recognition'
    WHEN 'instant_penalty' THEN 'instant_penalty'
    WHEN 'instant_penalty_doubled' THEN 'instant_penalty'
    WHEN 'instant_penalty_suspended' THEN 'instant_penalty'
    WHEN 'instant_penalty_reinstated' THEN 'instant_penalty'
    WHEN 'instant_penalty_lifted' THEN 'instant_penalty'
    WHEN 'instant_penalty_paid' THEN 'instant_penalty'
    WHEN 'instant_penalty_cancelled' THEN 'instant_penalty'
    WHEN 'daily_report' THEN 'daily_report'
    WHEN 'daily_reports' THEN 'daily_report'
    WHEN 'device' THEN 'device'
    WHEN 'employee_device' THEN 'device'
    WHEN 'devices' THEN 'device'
    WHEN 'fellowship_fund' THEN 'fellowship_fund'
    WHEN 'fellowship' THEN 'fellowship_fund'
    ELSE NULL
  END;

  IF v_resolved_kind IS NULL THEN
    RETURN jsonb_build_object('kind', v_kind, 'recordId', coalesce(v_raw, ''), 'mobileRoute', 'unsupported');
  END IF;

  -- strip prefix إن وُجد (kind-uuid)
  IF position(v_resolved_kind || '-' in lower(v_raw)) = 1 THEN
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  END IF;

  BEGIN
    v_uuid := v_raw::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('kind', v_resolved_kind, 'recordId', coalesce(v_raw, ''), 'mobileRoute', 'unsupported');
  END;

  IF v_resolved_kind = 'live_location_request' THEN
    SELECT * INTO v_req FROM public.live_location_requests WHERE id = v_uuid;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('kind', v_resolved_kind, 'recordId', v_uuid, 'mobileRoute', 'unsupported');
    END IF;
    IF NOT (
      v_req.employee_id = public.current_employee_id()
      OR v_req.requested_by = public.current_employee_id()
      OR public.current_is_full_access()
      OR public.can_access_employee(v_req.employee_id, 'live_location.view_response')
    ) THEN
      RAISE EXCEPTION 'لا تملك صلاحية على هذا الموظف' USING errcode = '42501';
    END IF;

    RETURN jsonb_build_object(
      'kind', v_resolved_kind,
      'recordId', v_uuid,
      'mobileRoute', 'live_location_request'
    );
  END IF;

  RETURN public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
END;
$function$;

-- ─── tg_employees_protect_exemption_identity — المصدر النظيف: 0548_block_self_exemption_and_name_based_immunity.sql
create or replace function public.tg_employees_protect_exemption_identity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- مسارات موثوقة تمر:
  --   • auth.role() is null = لا JWT إطلاقاً = اتصال داخلي (pg_cron، migrations،
  --     اتصال قاعدة مباشر). لا يصل طلب PostgREST إلى تعديل employees بلا JWT:
  --     سياستا employees_insert/employees_update مقصورتان على `to authenticated`.
  --   • service_role (Edge Functions) — نفس نمط 0289.
  --   • full-access أو people.employee.update_sensitive.
  -- لا نستخدم current_user: داخل SECURITY DEFINER يساوي مالك الدالة دائماً.
  if auth.role() is null
     or auth.role() = 'service_role'
     or public.current_is_full_access()
     or public.has_permission('people.employee.update_sensitive') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.is_attendance_exempt or new.is_penalty_exempt then
      raise exception 'not authorized to set attendance/penalty exemption' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.is_attendance_exempt is distinct from old.is_attendance_exempt then
    raise exception 'not authorized to change is_attendance_exempt' using errcode = '42501';
  end if;
  if new.is_penalty_exempt is distinct from old.is_penalty_exempt then
    raise exception 'not authorized to change is_penalty_exempt' using errcode = '42501';
  end if;

  -- الهوية الذاتية: الاسم والهاتف يدخلان في مطابقة الإعفاء/الحصانة، وكانا
  -- قابلين للتعديل الذاتي عبر employees_update. يبقى تعديلهما متاحاً لمن يملك
  -- people.employee.update_basic (HR/المديرون) عبر update_employee_admin.
  if new.id = public.current_employee_id()
     and not public.has_permission('people.employee.update_basic') then
    if new.full_name_ar is distinct from old.full_name_ar then
      raise exception 'not authorized to change own full_name_ar' using errcode = '42501';
    end if;
    if new.phone_e164 is distinct from old.phone_e164 then
      raise exception 'not authorized to change own phone_e164' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- ─── tg_leave_attendance_on_approval — المصدر النظيف: 0545_fix_mission_approval_check_constraint.sql
create or replace function public.tg_leave_attendance_on_approval()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lr public.leave_requests;
  v_day date; v_end date; v_start date; v_emp uuid;
  v_start_ts timestamptz; v_end_ts timestamptz;
  v_type_id uuid; v_year integer;
  v_punch timestamptz;
  v_covered boolean;
  v_dep_ts timestamptz;
  v_ret_ts timestamptz;
begin
  if old.status = new.status then return new; end if;

  -- ── إجازة معتمدة: on_leave (مع حماية أيام العمل المعتمدة الأخرى) ──
  if new.request_type = 'leave' and new.status = 'approved' then
    select * into v_lr from public.leave_requests where request_id = new.id;
    if not found then return new; end if;
    v_day := v_lr.start_date;
    while v_day <= v_lr.end_date loop
      -- يوم مغطّى بمأمورية/قافلة/فاندي/تكليف معتمد = يوم عمل → لا يُعلَّم إجازة
      v_covered := exists (
        select 1 from public.requests r
        where r.employee_id = v_lr.employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and v_day between public._payload_date(r.payload, 'startDate')
                       and coalesce(public._payload_date(r.payload, 'endDate'), public._payload_date(r.payload, 'startDate'))
      ) or exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = v_lr.employee_id and wa.status = 'APPROVED'
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                       and (wa.end_at at time zone 'Africa/Cairo')::date
      );
      if not v_covered then
        insert into public.attendance_daily(employee_id, work_date, status)
        values(v_lr.employee_id, v_day, 'on_leave')
        on conflict on constraint attendance_daily_uq do update
          set status = 'on_leave', updated_at = now()
          where public.attendance_daily.is_finalized = false
            and public.attendance_daily.status <> 'on_leave';
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_lr.employee_id,
      'تم تعليم أيام الإجازة المعتمدة كـ on_leave في الحضور',
      format('من %s إلى %s', v_lr.start_date, v_lr.end_date),
      jsonb_build_object('requestId', new.id));
    return new;
  end if;

  -- ── مأمورية/قافلة/فاندي معتمدة: أيام عمل → present (بلا خصم من الرصيد) ──
  if new.request_type in ('mission','convoy','fundraising') and new.status = 'approved' then
    v_emp := new.employee_id;
    if v_emp is null then
      return new; -- لا بيانات مصدرية للطلب → لا تعليم
    end if;
    v_start := public._payload_date(new.payload, 'startDate');
    v_end := coalesce(public._payload_date(new.payload, 'endDate'), v_start);

    if v_start is null then
      -- بلا payload: قراءة التواريخ من الخانات الخاصة (طلبات قديمة / إنشاء مباشر)
      v_start_ts := null; v_end_ts := null;
      if new.request_type = 'mission' then
        select start_at, end_at into v_start_ts, v_end_ts
        from public.missions where request_id = new.id;
      elsif new.request_type = 'convoy' then
        select departure_at, coalesce(return_at, departure_at) into v_start_ts, v_end_ts
        from public.convoy_requests where request_id = new.id;
      end if;
      if v_start_ts is null then
        return new;
      end if;
      v_start := (v_start_ts at time zone 'Africa/Cairo')::date;
      v_end := (v_end_ts at time zone 'Africa/Cairo')::date;
    else
      -- ضبط الخانات الخاصة بالطلب من payload (متوافقة مع قراءة الكشف والتراجع)
      if new.request_type = 'mission'
         and not exists (select 1 from public.missions where request_id = new.id) then
        
        -- حساب start_at و end_at للمأمورية:
        -- المأمورية تبدأ من startTime أو T00:00:00
        -- وتنتهي في endTime أو نهاية اليوم T23:59:59 (لمنع انتهاك ck_missions_period)
        v_start_ts := (v_start::text || case when new.payload->>'startTime' is not null
                                             then 'T' || (new.payload->>'startTime') || ':00'
                                             else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo';
        v_end_ts   := (v_end::text   || case when new.payload->>'endTime' is not null
                                             then 'T' || (new.payload->>'endTime') || ':00'
                                             else 'T23:59:59' end)::timestamp at time zone 'Africa/Cairo';
        if v_end_ts < v_start_ts then
          v_end_ts := v_start_ts;
        end if;

        insert into public.missions (request_id, employee_id, destination, purpose, start_at, end_at, created_by)
        values (
          new.id, v_emp, coalesce(new.payload->>'location', ''), coalesce(new.title, ''),
          v_start_ts, v_end_ts, new.created_by
        );
      elsif new.request_type = 'convoy'
            and not exists (select 1 from public.convoy_requests where request_id = new.id) then
        v_dep_ts := (v_start::text || case when new.payload->>'startTime' is not null
                                           then 'T' || (new.payload->>'startTime') || ':00'
                                           else 'T00:00:00' end)::timestamp at time zone 'Africa/Cairo';
        v_ret_ts := case
                      when new.payload->>'endTime' is not null
                        then (v_end::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo'
                      when v_end > v_start
                        then (v_end::text || 'T23:59:59')::timestamp at time zone 'Africa/Cairo'
                      else null
                    end;
        if v_ret_ts is not null and v_ret_ts < v_dep_ts then
          v_ret_ts := v_dep_ts;
        end if;

        insert into public.convoy_requests (request_id, employee_id, convoy_name, origin, destination, departure_at, return_at, created_by)
        values (
          new.id, v_emp,
          coalesce(coalesce(new.payload->>'convoyName', new.title), ''),
          coalesce(new.payload->>'origin', ''), coalesce(new.payload->>'location', ''),
          v_dep_ts, v_ret_ts,
          new.created_by
        );
      end if;
    end if;

    v_day := v_start;
    while v_day <= v_end loop
      -- بصمة حضور في أول يوم (من وقت بدء المأمورية إن وُجد — بدون بصمة = حضور مُسجَّل)
      v_punch := null;
      if v_day = v_start and new.payload->>'startTime' is not null then
        v_punch := (v_day::text || 'T' || (new.payload->>'startTime') || ':00')::timestamp at time zone 'Africa/Cairo';
      end if;
      insert into public.attendance_daily(employee_id, work_date, status, first_check_in)
      values(v_emp, v_day, 'present', v_punch)
      on conflict on constraint attendance_daily_uq do update
        set status = 'present',
            first_check_in = coalesce(public.attendance_daily.first_check_in, excluded.first_check_in),
            updated_at = now()
        where public.attendance_daily.is_finalized = false
          and public.attendance_daily.status not in ('holiday','weekend');

      -- بصمة انصراف في آخر يوم (وقت نهاية المأمورية إن وُجد — يُسجَّل الانصراف عند الامتداد خارج العمل)
      if v_day = v_end and new.payload->>'endTime' is not null then
        update public.attendance_daily
        set last_check_out = (v_day::text || 'T' || (new.payload->>'endTime') || ':00')::timestamp at time zone 'Africa/Cairo',
            updated_at = now()
        where employee_id = v_emp and work_date = v_day
          and last_check_out is null and is_finalized = false;
      end if;

      -- بدل الراحة الأسبوعي: الجمعة خلال مأمورية/قافلة/فاندي
      if extract(isodow from v_day) = 5 then
        select id into v_type_id from public.leave_types where code = 'weekly_rest_comp';
        if v_type_id is not null then
          v_year := extract(year from v_day)::integer;
          perform public.apply_leave_ledger_entry(
            v_emp, v_type_id, v_year, 'credit', 1,
            'weekly-rest:credit:' || v_emp::text || ':' || v_day::text,
            null,
            'بدل راحة أسبوعي عن يوم عمل في ' || new.request_type || ' بتاريخ ' || to_char(v_day, 'YYYY-MM-DD'),
            jsonb_build_object('workDate', v_day::text, 'source', new.request_type, 'requestId', new.id)
          );
        end if;
      end if;
      v_day := v_day + 1;
    end loop;
    perform public.log_audit_event(
      'leave.attendance.marked', 'workflow', 'info', 'attendance_daily', v_emp,
      'تم تعليم أيام ' || new.request_type || ' المعتمدة كحضور عمل (present) بلا خصم',
      format('من %s إلى %s', v_start, v_end),
      jsonb_build_object('requestId', new.id, 'kind', new.request_type));
    return new;
  end if;

  return new;
end $function$;

-- ─── tg_prevent_admin_penalty_fn — المصدر النظيف: 0547_admin_account_permanent_immunity.sql
create or replace function public.tg_prevent_admin_penalty_fn()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or public.is_employee_penalty_exempt(NEW.employee_id)
     or exists (select 1 from public.employees e where e.id = NEW.employee_id and (e.phone_e164 in ('+201154869616', '01154869616') or e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) then
    -- إلغاء إنشاء الغرامة نهائياً وبلا استثناء
    return null;
  end if;
  return NEW;
end;
$$;


-- ─── إصلاح الصفوف ───
create or replace function pg_temp.fix_mojibake(p text)
returns text
language plpgsql
as $fx$
declare
  v_out text := '';
  v_run text := '';
  v_ch text;
  v_code int;
  i int;
  -- ما يولّده التلف: 0x80–0xFF + رموز cp1252 الموسّعة
  v_cp constant text := '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';

begin
  if p is null then return null; end if;
  for i in 1 .. char_length(p) + 1 loop
    v_ch := case when i <= char_length(p) then substr(p, i, 1) else null end;
    v_code := coalesce(ascii(v_ch), 0);
    if v_ch is not null and ((v_code between 128 and 255) or strpos(v_cp, v_ch) > 0) then
      v_run := v_run || v_ch;
    else
      if v_run <> '' then
        v_out := v_out || pg_temp.decode_run(v_run);
        v_run := '';
      end if;
      if v_ch is not null then v_out := v_out || v_ch; end if;
    end if;
  end loop;
  return v_out;
end;
$fx$;

create or replace function pg_temp.decode_run(p text)
returns text
language plpgsql
as $dr$
declare
  v_bytes bytea := ''::bytea;
  v_ch text;
  v_code int;
  i int;
begin
  for i in 1 .. char_length(p) loop
    v_ch := substr(p, i, 1);
    v_code := ascii(v_ch);
    if v_code < 256 then
      v_bytes := v_bytes || set_byte('\x00'::bytea, 0, v_code);
    else
      v_bytes := v_bytes || convert_to(v_ch, 'WIN1252');
    end if;
  end loop;
  return convert_from(v_bytes, 'UTF8');
exception when others then
  return p;  -- ليست سلسلة تلف (مثل «—» أصلية) — تُترك كما هي
end;
$dr$;

update public.notifications
   set title = pg_temp.fix_mojibake(title),
       body  = pg_temp.fix_mojibake(body)
 where title ~ '(Ø|Ù|ðŸ|â€)' or body ~ '(Ø|Ù|ðŸ|â€)';

update public.instant_attendance_penalties
   set cancelled_reason = pg_temp.fix_mojibake(cancelled_reason)
 where cancelled_reason ~ '(Ø|Ù|ðŸ|â€)';

notify pgrst, 'reload schema';

commit;
