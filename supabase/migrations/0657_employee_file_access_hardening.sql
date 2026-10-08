-- ═══════════════════════════════════════════════════════════════
-- 0657: ملف الموظف وكشفه الشهري — المتابعة لمن فوقه، والتعديل للموارد البشرية فقط
--
-- شكوى المالك (2026-10-07): «يستطيع أي موظف الدخول لملف موظف آخر تحت منه أو
-- زميله، والدخول إلى كشفه الشهري والتعديل عليه أو طلب إجازة أو تعديل حالة يوم».
--
-- ما وُجد في الإنتاج:
--   (1) التعديل الإداري ليوم حضور موظف آخر — set/clear_employee_attendance_day_admin
--       و submit_employee_day_mark وعلامة canEditDays في الكشف — مسموح لكل من يحمل
--       attendance.correction.review بنطاق «المرؤوسين المباشرين»: كل مدير مباشر (10)
--       ومدير العيادات. و«الإجازة» من هذا المسار تُعتمد فوراً وتُخصم من الرصيد بلا
--       سير عمل، و«الغياب» يُسجَّل بلا راتب.
--       → صلاحية مستقلة attendance.day.override بنطاق المؤسسة لمدير ومسؤول الموارد
--         البشرية فقط (+ الوصول الكامل كما كان). المدير المباشر يبقى يرى كشف فريقه
--         ويعتمد طلباتهم وتصحيحاتهم عبر سير العمل (attendance.correction.review باقية
--         لذلك — لم تُمس decide_attendance_correction ولا صناديق التصحيح).
--   (2) submit_employee_day_mark لم تستثنِ الذات: can_access_employee تعيد true للموظف
--       نفسه قبل أي فحص صلاحية، فكان أي موظف يسجّل ليومه «إجازة بدون راتب» أو مأمورية
--       متجاوزاً قواعد التقديم الذاتي (0652). → كالتعديل الإداري: لا ذات إلا للوصول الكامل.
--   (3) الملف الكامل والكشف الشهري بنطاق «نفس الإدارة/الفريق/الفرع» يفتحان للزميل ملف
--       زميله. → can_supervise_employee: نطاقات can_access_employee نفسها، لكن الإدارة/
--       الفريق/الفرع تعني من يرأس الموظف (رئيس إدارته، قائد فريقه، أو من فوقه في سلسلة
--       الإدارة) لا زميله. تُضيّق ولا تُوسّع أبداً؛ ولا أحد يفقد اليوم وصولاً مشروعاً
--       (مديرا التشغيل يرأسان إداراتهما ولا زملاء معهم فيها).
--   (4) دوال بلا أي فحص هوية ينفّذها أي موظف مسجّل:
--       • admin_activate_employee_after_password_set — تعيد تفعيل أي موظف حتى الموقوف
--         (مسارها الوحيد Edge Function admin-set-password بمفتاح service_role).
--       • apply_leave_ledger_entry — يضيف بها الموظف رصيد إجازات لنفسه (سُحبت في 0387
--         ثم عادت مع إعادة إنشاء الدالة؛ اختبار 0387 يتوقع سحبها).
--       • auto_notify_late_attendance (كرون) و backfill_request_managers (صيانة).
--       → سحب EXECUTE من public/anon/authenticated؛ الكرون والدوال الداخلية (SECURITY
--         DEFINER بصلاحية المالك) و service_role كما هي.
--   (5) get_penalty_disputes تعيد طعون الغرامات لكل الموظفين بالأسماء والمبالغ لأي موظف
--       (والتطبيق يعرضها كأنها «طعوني»). → الموظف يرى طعونه فقط؛ الوصول الكامل والموارد
--       البشرية والإدارة التنفيذية يرون الكل.
--       generate_executive_daily_digest (الغرامات ورصيد الصندوق والمأموريات) → للإدارة فقط.
--
-- كل الدوال المعدَّلة استبدال كنوني من تعريفها المنشور حرفياً؛ التغيير هو أسطر الحراسة فقط.
-- ═══════════════════════════════════════════════════════════════

begin;

-- ─── (1) صلاحية التعديل الإداري لأيام الحضور ───
insert into public.permissions (code, module, resource, action, description, risk_level, is_sensitive, name_ar)
values ('attendance.day.override', 'attendance', 'day', 'override',
        'تعديل يوم حضور موظف آخر إدارياً: نوع اليوم والساعات، وإجازة أو مأمورية تُعتمد فوراً',
        'sensitive', true, 'تعديل أيام الحضور إدارياً')
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id, scope)
select r.id, p.id, 'organization'
  from public.roles r
  join public.permissions p on p.code = 'attendance.day.override'
 where r.slug in ('hr-manager', 'hr-specialist')
on conflict (role_id, permission_id, scope) do nothing;

-- ─── (3) المتابعة من موقع إشرافي لا من الزمالة ───
create or replace function public.can_supervise_employee(p_employee_id uuid, p_codes text[])
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
-- 0657: منطق can_access_employee(uuid,text) ونطاقاته حرفياً، لعدة رموز، مع فرق واحد
-- مقصود: نطاقات «الإدارة/الفريق/الفرع» تمنح من يرأس الموظف — رئيس إدارته، أو قائد
-- فريقه، أو من فوقه في سلسلة الإدارة داخلها — لا زميله فيها. كل فرع هنا مجموعة جزئية
-- من فرعه في can_access_employee، فلا تمنح أبداً أكثر منها.
declare
  v_me uuid;
  v_scope text;
  v_ovr jsonb;
  v_target_dept uuid;
  v_target_branch uuid;
  v_target_team uuid;
  v_allowed boolean := false;
begin
  if p_employee_id is null or p_codes is null then return false; end if;
  if public.current_is_full_access() then return true; end if;
  v_me := public.current_employee_id();
  if v_me is null then return false; end if;
  if v_me = p_employee_id then return true; end if;
  select e.department_id, e.branch_id, e.team_id into v_target_dept, v_target_branch, v_target_team
    from public.employees e where e.id = p_employee_id;
  if not found then return false; end if;
  for v_scope, v_ovr in
    select rp.scope, coalesce(ur.scope_override, '{}'::jsonb)
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid() and p.code = any(p_codes)
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now()) and (rp.effective_to is null or rp.effective_to > now())
  loop
    case v_scope
      when 'organization' then v_allowed := true; exit;
      when 'direct_reports' then
        if exists (select 1 from public.manager_relations mr where mr.manager_employee_id = v_me and mr.employee_id = p_employee_id and mr.effective_from <= now() and (mr.effective_to is null or mr.effective_to > now())) then v_allowed := true; exit; end if;
      when 'management_descendants' then if public.is_management_descendant(v_me, p_employee_id) then v_allowed := true; exit; end if;
      when 'department' then
        if v_target_dept is not null then
          -- رئيس الإدارة على إدارته
          if exists (select 1 from public.departments d where d.id = v_target_dept and d.manager_id = v_me) then v_allowed := true; exit; end if;
          -- داخل إدارتي: من تحتي في سلسلة الإدارة فقط — لا زميل الإدارة
          if (select e.department_id from public.employees e where e.id = v_me) = v_target_dept
             and public.is_management_descendant(v_me, p_employee_id) then v_allowed := true; exit; end if;
        end if;
      when 'branch' then
        if v_target_branch is not null and v_target_branch = (select e.branch_id from public.employees e where e.id = v_me)
           and public.is_management_descendant(v_me, p_employee_id) then v_allowed := true; exit; end if;
      when 'team' then
        if v_target_team is not null and v_target_team = (select e.team_id from public.employees e where e.id = v_me)
           and (exists (select 1 from public.teams t where t.id = v_target_team and t.lead_id = v_me)
                or public.is_management_descendant(v_me, p_employee_id)) then v_allowed := true; exit; end if;
      when 'selected_departments' then if v_target_dept is not null and coalesce(v_ovr->'department_ids','[]'::jsonb) ? v_target_dept::text then v_allowed := true; exit; end if;
      when 'selected_branches' then if v_target_branch is not null and coalesce(v_ovr->'branch_ids','[]'::jsonb) ? v_target_branch::text then v_allowed := true; exit; end if;
      when 'selected_employees' then if coalesce(v_ovr->'employee_ids','[]'::jsonb) ? p_employee_id::text then v_allowed := true; exit; end if;
      else null;
    end case;
  end loop;

  if v_allowed and public.is_employee_isolated(p_employee_id) and not public.can_view_isolated_employee(p_employee_id) then
    return false;
  end if;

  return v_allowed;
end;
$function$;

revoke all on function public.can_supervise_employee(uuid, text[]) from public, anon, authenticated;
grant execute on function public.can_supervise_employee(uuid, text[]) to service_role;

-- ─── (1)(2) التعديل الإداري لأيام الحضور: الموارد البشرية والوصول الكامل ───
CREATE OR REPLACE FUNCTION public.set_employee_attendance_day_admin(p_employee_id uuid, p_work_date date, p_day_type text, p_check_in time without time zone DEFAULT NULL::time without time zone, p_check_out time without time zone DEFAULT NULL::time without time zone, p_clear_check_in boolean DEFAULT false, p_clear_check_out boolean DEFAULT false, p_reason text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_leave_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_manager uuid;
  v_req public.requests;
  v_leave_type_id uuid;
  v_affects boolean;
  v_leave_type text;
  v_reason text;
  v_payload jsonb;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;

  -- تطبيع نوع اليوم
  p_day_type := lower(trim(coalesce(p_day_type, 'work')));
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;

  -- سبب التعديل: إن كان فارغاً أو قصيراً، يُعتمد سبب افتراضي موثوق لمنع كسر العملية
  v_reason := btrim(coalesce(p_reason, ''));
  if length(v_reason) < 3 then
    v_reason := case
      when p_day_type = 'work' then 'تعديل ساعات وحضور معتمد'
      when p_day_type = 'leave' then 'إجازة معتمدة إدارياً'
      when p_day_type = 'mission' then 'مأمورية عمل معتمدة'
      when p_day_type = 'convoy' then 'قافلة عمل معتمدة'
      when p_day_type = 'fundraising' then 'فاندي معتمد'
      when p_day_type = 'holiday' then 'عطلة رسمية معتمدة'
      when p_day_type = 'rest' then 'راحة أسبوعية معتمدة'
      when p_day_type = 'absent' then 'تأكيد غياب إداري'
      else 'تعديل إداري معتمد'
    end;
  end if;

  if p_clear_check_in and p_check_in is not null then
    p_check_in := null;
  end if;
  if p_clear_check_out and p_check_out is not null then
    p_check_out := null;
  end if;

  if not (
    auth.role() = 'service_role'
    or public.current_is_full_access()
    -- 0657: الموارد البشرية فقط (attendance.day.override) — لا المدير المباشر
    or (p_employee_id is distinct from public.current_employee_id()
        and public.can_access_employee(p_employee_id, 'attendance.day.override'))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- ── حارس التواريخ: يسمح بجدولة الإجازات والمأموريات والعطل مستقبلاً ──────────
  if auth.role() <> 'service_role' then
    if p_day_type = 'work' and p_work_date > v_today then
      -- ليوم العمل: يسمح لليوم الحالي وما قبله
      raise exception 'INVALID_DATE: cannot record physical work presence for a future date' using errcode = '22023';
    end if;
    if p_work_date < (v_today - interval '180 days')::date then
      raise exception 'BACKDATING_LIMIT: cannot modify attendance older than 180 days (date: %, limit: %)',
        p_work_date, (v_today - interval '180 days')::date;
    end if;
  end if;

  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- تطبيع نوع الإجازة قبل التخزين في attendance_day_overrides.leave_type.
  v_leave_type := nullif(trim(coalesce(p_leave_type, '')), '');
  if p_day_type in ('leave','absent') then
    v_leave_type := coalesce(v_leave_type, case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      v_leave_type := 'annual';
    end if;
  else
    v_leave_type := null;
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type, leave_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type, v_leave_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    v_reason, nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    leave_type = excluded.leave_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning id into v_id;

  -- إنشاء طلب معتمد إن تطلب الأمر (إجازات ومأموريات)
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    if p_day_type in ('leave','absent') then
      select id, affects_balance into v_leave_type_id, v_affects
      from public.leave_types where code = v_leave_type and is_active = true limit 1;

      if v_leave_type_id is not null and not exists (
        select 1
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
         where lr.employee_id = p_employee_id
           and p_work_date between lr.start_date and lr.end_date
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true);

        v_req := public._submit_request_for(
          p_employee_id,
          'leave',
          null,
          v_manager,
          'تحديد يوم إداري — ' || (case when p_day_type = 'absent' then 'غياب' else 'إجازة' end),
          v_reason,
          v_payload);

        insert into public.leave_requests(
          request_id, employee_id, leave_type_id, start_date, end_date,
          days_count, duration_unit, created_by)
        values(
          v_req.id, p_employee_id, v_leave_type_id, p_work_date, p_work_date,
          1, 'day', auth.uid());

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    else
      if not exists (
        select 1
          from public.requests r
         where r.employee_id = p_employee_id
           and r.request_type = p_day_type
           and r.status = 'approved'
           and p_work_date between (r.payload->>'startDate')::date
                               and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true,
          'location', coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'تحديد إداري'));

        v_req := public._submit_request_for(
          p_employee_id,
          p_day_type,
          null,
          v_manager,
          'تحديد يوم إداري — ' || public.request_type_label(p_day_type),
          v_reason,
          v_payload);

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    end if;
  end if;

  perform public.log_audit_event(
    'attendance.day.override.saved', 'workflow', 'warning',
    'attendance_day_overrides', v_id,
    'تعديل إداري ليوم حضور', v_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'previous', v_previous,
      'dayType', p_day_type,
      'leaveType', v_leave_type,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'clearCheckIn', coalesce(p_clear_check_in, false),
      'clearCheckOut', coalesce(p_clear_check_out, false)
    )
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'employeeId', p_employee_id,
    'workDate', p_work_date,
    'dayType', p_day_type,
    'leaveType', v_leave_type
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.clear_employee_attendance_day_admin(p_employee_id uuid, p_work_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_month date := date_trunc('month', p_work_date)::date;
  v_override_id uuid;
  v_previous jsonb;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;

  if not (
    auth.role() = 'service_role'
    or public.current_is_full_access()
    -- 0657: الموارد البشرية فقط (attendance.day.override) — لا المدير المباشر
    or (p_employee_id is distinct from public.current_employee_id()
        and public.can_access_employee(p_employee_id, 'attendance.day.override'))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  select id, to_jsonb(o) into v_override_id, v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  if v_override_id is not null then
    delete from public.attendance_day_overrides
    where employee_id = p_employee_id and work_date = p_work_date;

    perform public.log_audit_event(
      'attendance.day.override.reverted', 'workflow', 'info',
      'attendance_day_overrides', v_override_id,
      'إلغاء التعديل الإداري والعودة لاحتساب النظام', 'تم إلغاء التعديل الإداري لليوم',
      jsonb_build_object(
        'employeeId', p_employee_id,
        'workDate', p_work_date,
        'previous', v_previous
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'employeeId', p_employee_id,
    'workDate', p_work_date,
    'cleared', (v_override_id is not null)
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.submit_employee_day_mark(p_employee_id uuid, p_request_type text, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_start_date date;
  v_end_date date;
  v_manager uuid;
  v_leave_type text;
  v_leave_type_id uuid;
  v_days numeric := 1;
  v_substitute uuid;
  v_row public.requests;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'الموظف مطلوب' using errcode = '22023';
  end if;

  -- الصلاحية: نفس صلاحية التعديل الإداري لليوم (0266) — 0657: الموارد البشرية فقط،
  -- ولا تحديد ذاتي (can_access_employee تعيد true للموظف نفسه قبل فحص الصلاحية).
  if not (
    public.current_is_full_access()
    or (p_employee_id is distinct from v_me
        and public.can_access_employee(p_employee_id, 'attendance.day.override'))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- منع التعديل على شهر مغلق
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month_start
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- النوع: إجازة أو توجيه تشغيلي فقط
  if p_request_type not in ('leave','mission','convoy','fundraising') then
    raise exception 'ترميز اليوم يدعم الإجازة والمأمورية والقافلة والفاندي فقط' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  v_start_date := nullif(v_payload->>'startDate', '')::date;
  v_end_date := nullif(v_payload->>'endDate', '')::date;
  if v_start_date is null or v_end_date is null then
    raise exception 'day mark requires a date' using errcode = '22023';
  end if;
  if v_end_date <> v_start_date then
    raise exception 'day marks are single-day only' using errcode = '22023';
  end if;
  if v_start_date < v_month_start then
    raise exception 'day marks are allowed within the current month only' using errcode = '22023';
  end if;
  if v_start_date > v_today then
    raise exception 'future days cannot be marked' using errcode = '22023';
  end if;

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  if p_request_type = 'leave' then
    v_leave_type := v_payload->>'leaveType';
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
    end if;
    select id into v_leave_type_id
    from public.leave_types where code = v_leave_type and is_active = true;
    if v_leave_type_id is null then
      raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
    end if;
    v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
    v_payload := v_payload || jsonb_build_object(
      'leaveType', v_leave_type,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'days', v_days,
      'immediate', (v_leave_type = 'casual'),
      'dayMark', true);
  else
    if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
      raise exception 'assignment location is required' using errcode = '22023';
    end if;
    v_payload := v_payload || jsonb_build_object(
      'startDate', v_start_date,
      'endDate', v_end_date,
      'location', trim(v_payload->>'location'),
      'days', v_days,
      'dayMark', true);
  end if;

  v_row := public._submit_request_for(
    p_employee_id,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- صف تفصيل الإجازة + تنفيذ فوري للعارضة (نفس مسار submit_my_request)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, p_employee_id, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
    end if;
  end if;

  return v_row;
end;
$function$;


CREATE OR REPLACE FUNCTION public._admin_approve_request_immediately(p_request_id uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.requests;
  v_me uuid := public.current_employee_id();
begin
  if p_request_id is null then
    raise exception 'REQUEST_REQUIRED' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    -- 0657: مسارها الوحيد set_employee_attendance_day_admin — بنفس صلاحيتها
    or public.has_any_permission(array['attendance.day.override'])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_row from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'REQUEST_NOT_PENDING' using errcode = '22023';
  end if;

  update public.requests
    set status = 'approved',
        workflow_status = 'completed',
        decided_at = now(),
        decided_by = v_me,
        updated_at = now()
    where id = v_row.id
    returning * into v_row;

  update public.request_steps
    set status = 'skipped', acted_at = now(), acted_by = v_me,
        comment = 'اعتماد إداري مباشر من تصحيح يوم الحضور', updated_at = now()
    where request_id = v_row.id and status in ('active','pending');

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = v_row.id and status = 'running';

  insert into public.request_actions(
    request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
  values(
    v_row.id, v_me, 'system', 'pending', 'approved',
    'اعتماد إداري مباشر من تصحيح يوم الحضور',
    jsonb_build_object('source', 'attendance_day_editor'), auth.uid());

  perform public.log_audit_event(
    'attendance.day.request.approved', 'workflow', 'warning', 'requests', v_row.id,
    'اعتماد إداري مباشر لطلب يوم حضور',
    v_row.title,
    jsonb_build_object('requestType', v_row.request_type, 'employeeId', v_row.employee_id));

  return v_row;
end;
$function$;


CREATE OR REPLACE FUNCTION public._build_attendance_statement_v287(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_type text;
  v_check_in time;
  v_check_out time;
  v_work_minutes integer;
  v_required_minutes integer;
  v_scheduled boolean;
  v_present boolean;
  v_covered boolean;
  v_is_future boolean;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_covered_days integer := 0;
  v_total_work_minutes integer := 0;
  v_month_required_minutes integer := 0;
  v_month_deficit_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_open_shift_days integer := 0;
  v_completed_days integer := 0;
  v_absent_days integer := 0;
  v_upcoming_days integer := 0;
  v_leave_days integer := 0;
  v_mission_days integer := 0;
  v_convoy_days integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  v_due_days integer := 0;
  v_is_due boolean;
  v_is_open boolean;
  v_matched public.shifts%rowtype;
begin
  v_result := public._build_attendance_statement_v266(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_override := null;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    v_type := coalesce(v_override.day_type, '');
    v_check_in := nullif(v_day_obj->>'checkIn', '')::time;
    v_check_out := nullif(v_day_obj->>'checkOut', '')::time;

    if v_override.id is not null then
      if v_override.clear_check_in then v_check_in := null;
      elsif v_override.check_in_override is not null then v_check_in := v_override.check_in_override;
      end if;
      if v_override.clear_check_out then v_check_out := null;
      elsif v_override.check_out_override is not null then v_check_out := v_override.check_out_override;
      end if;
    end if;

    -- الجمعة والعطل الرسمية ليست أيام عمل شهرية
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_type not in ('holiday','rest');
    v_is_future := v_scheduled and v_day > (now() at time zone 'Africa/Cairo')::date;

    if v_type in ('leave','mission','convoy','fundraising','holiday','rest','absent') then
      v_check_in := null;
      v_check_out := null;
    end if;

    -- 0590: الوردية المجزأة (0588) — تجميع فترات العمل من البصمات واستبعاد الراحة؛
    -- عند تعديل إداري للأوقات أو غياب أزواج البصمات يُحسب من البصمتين كما كان.
    v_work_minutes := 0;
    if v_check_in is not null and v_check_out is not null then
      if v_override.id is null then
        v_work_minutes := coalesce(public.calculate_paired_work_minutes(
          p_employee_id,
          (v_day::text || ' 00:00:00 Africa/Cairo')::timestamptz,
          (v_day::text || ' 23:59:59 Africa/Cairo')::timestamptz), 0);
      end if;
      if v_work_minutes = 0 then
        v_work_minutes := greatest(0, (extract(epoch from (
          (v_day + v_check_out + case when v_check_out <= v_check_in then interval '1 day' else interval '0' end)
          - (v_day + v_check_in)
        )) / 60)::integer);
      end if;
    end if;

    -- 0590: الورديات المرنة (0588) — من لا وردية مسندة له تُطابَق ورديته بوقت حضوره
    -- (نفس مطابقة حساب التأخير)، فيظهر اسم الوردية وبدايتها ونهايتها الصحيحة ويُحسب
    -- الخروج المبكر من نهايتها (كان 18:00 للجميع فيُعدّ من انصرف 5م بوردية 9–5 مبكراً).
    v_matched := null;
    if v_check_in is not null and v_scheduled and not exists (
      select 1 from public.shift_assignments sa
      where sa.employee_id = p_employee_id and sa.is_active
        and sa.effective_from <= v_day and (sa.effective_to is null or sa.effective_to >= v_day)
    ) then
      select s.* into v_matched from public.shifts s
      where s.id = public.match_flexible_shift(((v_day + v_check_in)::timestamp at time zone 'Africa/Cairo'));
    end if;

    v_required_minutes := case when v_scheduled
      then greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60)::integer)
      else 0 end;
    if v_scheduled and v_required_minutes = 0 then v_required_minutes := 480; end if;

    v_present := v_scheduled and v_check_in is not null;
    v_covered := v_scheduled and (
      v_present
      or v_type in ('leave','mission','convoy','fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    v_is_open := v_check_in is not null and v_check_out is null and not v_is_future;
    v_is_due := v_scheduled and not v_is_future and not v_is_open and not (
      v_type in ('leave', 'mission', 'convoy', 'fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    if v_scheduled then
      v_scheduled_days := v_scheduled_days + 1;
      v_month_required_minutes := v_month_required_minutes + v_required_minutes;
      if v_present then v_present_days := v_present_days + 1; end if;
      if v_is_due then v_due_days := v_due_days + 1; end if;
      if v_covered then v_covered_days := v_covered_days + 1; end if;
      if v_is_future then v_upcoming_days := v_upcoming_days + 1; end if;
      if not v_is_future and not v_covered and v_type <> 'leave' then
        v_absent_days := v_absent_days + 1;
      end if;
    end if;

    if v_check_in is not null and v_check_out is null and not v_is_future then
      v_open_shift_days := v_open_shift_days + 1;
    end if;
    if v_check_in is not null and v_check_out is not null then
      v_completed_days := v_completed_days + 1;
      v_total_work_minutes := v_total_work_minutes + v_work_minutes;
      v_month_deficit_minutes := v_month_deficit_minutes + greatest(0, v_required_minutes - v_work_minutes);
      v_total_overtime_minutes := v_total_overtime_minutes + greatest(0, v_work_minutes - v_required_minutes);
    end if;

    if v_type = 'leave' or (v_override.id is null and coalesce((v_day_obj->>'hasLeave')::boolean, false)) then
      v_leave_days := v_leave_days + 1;
    end if;
    if v_type = 'mission' or (v_override.id is null and coalesce((v_day_obj->>'hasMission')::boolean, false)) then
      v_mission_days := v_mission_days + 1;
    end if;
    if v_type in ('convoy','fundraising') or (v_override.id is null and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then
      v_convoy_days := v_convoy_days + 1;
    end if;
    if not v_scheduled then
      if extract(isodow from v_day) = 5 or v_type = 'rest' then v_rest_days := v_rest_days + 1;
      else v_holiday_days := v_holiday_days + 1;
      end if;
    end if;

    if v_scheduled then
      v_total_late_minutes := v_total_late_minutes + 0;
      v_total_early_minutes := v_total_early_minutes + 0;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn', case when v_check_in is null then null else to_char(v_check_in, 'HH24:MI') end,
      'shiftName', case when v_matched.id is not null then v_matched.name else null end,
      'shiftStart', case when v_matched.id is not null then v_matched.start_time::text else null end,
      'shiftEnd', case when v_matched.id is not null then v_matched.end_time::text else null end,
      'checkOut', case when v_check_out is null then null else to_char(v_check_out, 'HH24:MI') end,
      'workHours', round(v_work_minutes / 60.0, 2),
      'requiredHours', round(v_required_minutes / 60.0, 2),
      'lateMinutes', 0,
      'earlyLeaveMinutes', 0,
      'overtimeMinutes', greatest(0, v_work_minutes - v_required_minutes),
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', (v_check_in is not null and v_check_out is not null),
      'isAbsent', (v_scheduled and not v_is_future and not v_covered),
      'hasLeave', case when v_override.id is null then coalesce((v_day_obj->>'hasLeave')::boolean, false) else v_type = 'leave' end,
      'hasMission', case when v_override.id is null then coalesce((v_day_obj->>'hasMission')::boolean, false) else v_type = 'mission' end,
      'hasConvoyFundi', case when v_override.id is null then coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) else v_type in ('convoy','fundraising') end,
      'hasCorrection', (v_override.id is not null) or coalesce((v_day_obj->>'hasCorrection')::boolean, false),
      'correctionNote', coalesce(v_override.notes, v_override.reason, v_day_obj->>'correctionNote'),
      'adminOverride', case when v_override.id is null then null else jsonb_build_object(
        'id', v_override.id,
        'dayType', v_override.day_type,
        'leaveType', v_override.leave_type,
        'reason', v_override.reason,
        'notes', v_override.notes,
        'updatedAt', v_override.updated_at
      ) end,
      'status', case
        when extract(isodow from v_day) = 5 then 'راحة أسبوعية'
        when v_type = 'holiday' then 'عطلة رسمية'
        when v_type = 'rest' then 'راحة أسبوعية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasMission')::boolean, false) then 'مأمورية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
             and v_day_obj->>'status' = 'فاندي' then 'فاندي'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) then 'قافلة'
        when v_type = 'leave' then 'إجازة معتمدة'
        when v_type = 'mission' then 'مأمورية'
        when v_type = 'convoy' then 'قافلة'
        when v_type = 'fundraising' then 'فاندي'
        when v_type = 'absent' then 'غائب دون إذن'
        when v_override.id is null
             and (coalesce((v_day_obj->>'hasLeave')::boolean, false)
                  or coalesce((v_day_obj->>'hasMission')::boolean, false)
                  or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then v_day_obj->>'status'
        when v_is_future then 'يوم قادم'
        when v_check_in is not null and v_check_out is null then 'حاضر — بانتظار الانصراف'
        when v_check_in is not null and v_check_out is not null then 'حاضر'
        when not v_scheduled then v_day_obj->>'status'
        else 'غائب دون إذن'
      end
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'capabilities', jsonb_build_object(
      -- 0657: التعديل الإداري للموارد البشرية والوصول الكامل فقط
      'canEditDays', public.current_is_full_access()
        or (p_employee_id is distinct from public.current_employee_id()
            and public.can_access_employee(p_employee_id, 'attendance.day.override'))
    ),
    'summary', (v_result->'summary') || jsonb_build_object(
      'scheduledDays', v_scheduled_days,
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_days,
      'leaveDays', v_leave_days,
      'missionDays', v_mission_days,
      'convoyFundiDays', v_convoy_days,
      'holidayDays', v_holiday_days,
      'restDays', v_rest_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_month_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_days > 0 then round(v_total_work_minutes / 60.0 / v_completed_days, 2) else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'totalDeficitMinutes', v_month_deficit_minutes,
      'attendanceRate', case when v_due_days > 0
        then round((v_present_days - v_open_shift_days) * 100.0 / v_due_days, 2)
        else 0 end,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', (v_present_days - v_open_shift_days),
        'dueDays', v_due_days,
        'presentDays', v_present_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_shift_days,
        'upcomingDays', v_upcoming_days
      ),
      'coverageRate', case when v_scheduled_days > 0 then round(v_covered_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'coverageDays', v_covered_days,
      'hoursComplianceAvailable', (v_month_required_minutes > 0),
      'hoursComplianceRate', case when v_month_required_minutes > 0
        then least(100, round(v_total_work_minutes * 100.0 / v_month_required_minutes, 2)) else 0 end,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_total_work_minutes,
        'requiredMinutes', v_month_required_minutes,
        'scheduledDays', v_scheduled_days,
        'deficitMinutes', v_month_deficit_minutes,
        'overtimeMinutes', v_total_overtime_minutes
      ),
      'compliantWorkMinutes', v_total_work_minutes,
      'requiredMinutes', v_month_required_minutes
    )
  );

  return v_result;
end;
$function$;


-- ─── (3) الكشف الشهري والملف الكامل: صاحبه ومن فوقه والموارد البشرية والإدارة ───
CREATE OR REPLACE FUNCTION public.get_employee_monthly_attendance_statement(p_employee_id uuid, p_year integer DEFAULT (EXTRACT(year FROM (now() AT TIME ZONE 'Africa/Cairo'::text)))::integer, p_month integer DEFAULT (EXTRACT(month FROM (now() AT TIME ZONE 'Africa/Cairo'::text)))::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_month < 1 or p_month > 12 then raise exception 'INVALID_MONTH' using errcode = '22023'; end if;
  -- الصلاحية: full-access أو وصول نطاقي فعلي (المدير المباشر/رئيس الإدارة/HR/التنفيذي)
  -- بصلاحية قراءة الحضور أو التقارير — بنطاق self لا يمر (لا يُرى سوى الموظف نفسه).
  -- 0657: من موقع إشرافي لا من الزمالة (نفس الإدارة/الفريق لا تكفي).
  if not (
    public.current_is_full_access()
    or public.can_supervise_employee(p_employee_id, array['attendance.record.read', 'reports.attendance.read'])
  ) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية كشف هذا الموظف' using errcode = '42501';
  end if;
  return public._build_attendance_statement(p_employee_id, p_year, p_month);
end $function$;


CREATE OR REPLACE FUNCTION public.get_employee_360(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_full boolean;
  v_basic jsonb;
  v_details jsonb;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  -- الحفاظ على عزل الإدارة الطبية / فتيات العيادات للمصرح لهم فقط
  if public.is_employee_isolated(p_employee_id) and not public.can_view_isolated_employee(p_employee_id) then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  -- من يملك قراءة ملف هذا الموظف (نفس نطاقات الصلاحيات): هو نفسه، مديره
  -- المباشر، الإدارة التنفيذية، الموارد البشرية، مديرو التشغيل في نطاقهم،
  -- والوصول الكامل. غيرهم يرى الملف الأساسي وحالته اليومية الواضحة فقط.
  -- 0657: من موقع إشرافي لا من الزمالة (نفس الإدارة/الفريق لا تكفي).
  v_full := public.can_supervise_employee(p_employee_id, array['people.employee.read']);

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'jobTitle', jt.name,
    'position', pos.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerId', mgr.id,
    'managerName', mgr.full_name_ar,
    'manager', case when mgr.id is not null then jsonb_build_object(
      'id', mgr.id,
      'fullNameAr', mgr.full_name_ar,
      'jobTitle', mgr_jt.name,
      'photoUrl', mgr.photo_url
    ) end,
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', coalesce(tm.member_count, 0),
    'teamMembers', coalesce(tm.members, '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id = ed.department_id
      where ed.employee_id = e.id
        and (ed.start_date is null or ed.start_date <= v_today)
        and (ed.end_date is null or ed.end_date >= v_today)
    ), '[]'::jsonb),
    'todayStatus', public._employee_today_status(e.id, v_full),
    'viewerScope', case when v_full then 'full' else 'basic' end,
    -- حقول التفاصيل حاضرة بقيمة فارغة للملف الأساسي (عقد web employee360Schema)
    'phoneE164', null,
    'hireDate', null,
    'contractEnd', null,
    'probationEnd', null,
    'grade', null,
    'accountStatus', null,
    'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
  )
  into v_basic
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions pos on pos.id = e.position_id
  left join public.departments dept on dept.id = e.department_id
  left join public.teams team on team.id = e.team_id
  left join public.branches branch on branch.id = e.branch_id
  left join public.work_sites site on site.id = e.work_site_id
  left join public.employees mgr on mgr.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
    order by (mr.effective_to is null) desc, mr.created_at desc
    limit 1
  )
  left join public.job_titles mgr_jt on mgr_jt.id = mgr.job_title_id
  -- فريقه المباشر: الأعضاء النشطون (مع احترام عزل العيادات) وحالة كل منهم اليوم
  left join lateral (
    select count(*) as member_count,
           jsonb_agg(
             jsonb_build_object(
               'id', m.id,
               'fullNameAr', m.full_name_ar,
               'jobTitle', m_jt.name,
               'photoUrl', m.photo_url
             )
             || (public._employee_today_status(m.id, public.can_supervise_employee(m.id, array['people.employee.read']))
                 - 'requestStatus' - 'lateMinutes' - 'checkInAt' - 'checkOutAt' - 'workMinutes' - 'dueTime')
             order by m.full_name_ar
           ) as members
    from (
      select distinct mr.employee_id
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    ) rel
    join public.employees m on m.id = rel.employee_id and m.is_active and not m.is_deleted
    left join public.job_titles m_jt on m_jt.id = m.job_title_id
    where not public.is_employee_isolated(m.id) or public.can_view_isolated_employee(m.id)
  ) tm on true
  where e.id = p_employee_id;

  if v_basic is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if not v_full then
    return v_basic;
  end if;

  select jsonb_build_object(
    'email', au.email,
    'phoneE164', e.phone_e164,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'grade', grade.name,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    -- نفس مصدر كشف الحضور الشهري (attendance_day_facts): أيام المأموريات
    -- والقوافل حضور، ويوم نسيان الانصراف حضور، والغياب = يوم عمل مستحق بلا حضور،
    -- والتأخير وفق اللائحة. الساعات من الأيام المكتملة فقط (حضور + انصراف).
    'attendance30', (
      select jsonb_build_object(
        'present', count(*) filter (where f.attended),
        'lateDays', count(*) filter (where f.late_minutes > 0),
        'absent', count(*) filter (where f.absent),
        'offsiteDays', count(*) filter (where f.offsite),
        'workMinutes', coalesce((
          select sum(a.work_minutes)
          from public.attendance_daily a
          where a.employee_id = e.id
            and a.work_date between v_today - 29 and v_today
            and a.first_check_in is not null
            and a.last_check_out is not null
            and a.last_check_out > a.first_check_in
        ), 0),
        'missingCheckout', (
          select count(*)
          from public.attendance_daily a
          where a.employee_id = e.id
            and a.work_date between v_today - 29 and v_today - 1
            and a.first_check_in is not null
            and a.last_check_out is null
        )
      )
      from public.attendance_day_facts_scoped(v_today - 29, v_today, e.id) f
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
      'approved', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'rejected')
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < v_today then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id = e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id = aa.asset_id
      where aa.employee_id = e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id = e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id = e.id order by created_at desc limit 10
      ) t
    ), '[]'::jsonb)
  )
  into v_details
  from public.employees e
  left join public.job_grades grade on grade.id = e.grade_id
  left join public.profiles profile on profile.employee_id = e.id
  left join auth.users au on au.id = profile.id
  where e.id = p_employee_id;

  return v_basic || coalesce(v_details, '{}'::jsonb);
end;
$function$;


-- ─── (5) طعون الغرامات وموجز الإدارة ───
CREATE OR REPLACE FUNCTION public.get_penalty_disputes(p_status text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, penalty_id uuid, employee_id uuid, employee_name text, department text, penalty_date date, penalty_amount numeric, reason text, status text, reviewed_by uuid, reviewer_name text, review_note text, reviewed_at timestamp with time zone, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    d.id, d.penalty_id, d.employee_id,
    e.full_name_ar, dep.name, ip.work_date, ip.current_amount,
    d.reason, d.status, d.reviewed_by, re.full_name_ar,
    d.review_note, d.reviewed_at, d.created_at
  from public.penalty_disputes d
  join public.employees e on e.id = d.employee_id
  left join public.departments dep on dep.id = e.department_id
  join public.instant_attendance_penalties ip on ip.id = d.penalty_id
  left join public.employees re on re.id = d.reviewed_by
  where (p_status is null or d.status = p_status)
    -- 0657: الموظف يرى طعونه فقط؛ الكل للوصول الكامل والموارد البشرية والإدارة التنفيذية
    and (public.current_is_full_access()
         or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive', 'executive-director'])
         or d.employee_id = public.current_employee_id())
  order by
    case d.status when 'pending' then 0 when 'approved' then 1 else 2 end,
    d.created_at desc;
$function$;


CREATE OR REPLACE FUNCTION public.generate_executive_daily_digest(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_day_name text;
  v_total_active int := 0;
  v_present int := 0;
  v_missions int := 0;
  v_convoys int := 0;
  v_fandy int := 0;
  v_leaves int := 0;
  v_absent int := 0;
  v_penalties_issued int := 0;
  v_penalties_issued_amount numeric(12,2) := 0.00;
  v_penalties_paid int := 0;
  v_penalties_paid_amount numeric(12,2) := 0.00;
  v_fund_balance numeric(12,2) := 0.00;
  v_missions_list text := '';
  v_text text;
begin
  -- 0657: موجز الإدارة (الغرامات ورصيد الصندوق والمأموريات بالأسماء) — لا لأي موظف
  if not (auth.role() = 'service_role'
          or public.current_is_full_access()
          or public.current_has_active_role(array['executive', 'executive-director', 'hr-manager', 'hr-specialist'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- أسماء الأيام بالعربية
  v_day_name := case extract(isodow from v_date)
    when 1 then 'الاثنين'
    when 2 then 'الثلاثاء'
    when 3 then 'الأربعاء'
    when 4 then 'الخميس'
    when 5 then 'الجمعة'
    when 6 then 'السبت'
    when 7 then 'الأحد'
  end;
  -- 0587: من حقائق يوم الحضور. كان المقام يشمل من في إجازة معتمدة (فيُخفض
  -- الانضباط)، ومن بصم في يوم مأمورية يُعدّ مرتين (قد تتجاوز النسبة 100%)، والجمعة
  -- والعطلات تُظهر نسبة قرب الصفر. «القوة الملزمة» = من عليه دوام اليوم بعد الإجازات
  -- (بمن فيهم من لم يحضر بعد)، و«الانضباط» = من حضر أو في الميدان منهم.
  select
    count(*) filter (where f.is_workday and not f.leave_like),
    count(*) filter (where f.checked_in),
    count(*) filter (where f.offsite and not f.checked_in),
    count(*) filter (where f.is_workday and f.leave_like)
  into v_total_active, v_present, v_missions, v_leaves
  from public.attendance_day_facts(v_date, v_date) f
  where not f.is_exempt;
  v_convoys := 0;
  v_fandy := 0;
  v_absent := greatest(0, v_total_active - v_present - v_missions);
  -- الغرامات الصادرة والمدفوعة لهذا اليوم
  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_issued, v_penalties_issued_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status in ('pending_payment', 'doubled', 'paid');
  select count(*), coalesce(sum(current_amount), 0.00)
    into v_penalties_paid, v_penalties_paid_amount
    from public.instant_attendance_penalties
   where work_date = v_date and status = 'paid';
  -- رصيد صندوق الزمالة الحالي
  select coalesce(sum(case when transaction_type = 'inflow' then amount else -amount end), 0.00)
    into v_fund_balance
    from public.fellowship_fund_transactions;
  -- تجميع أسماء أبرز المتواجدين في مهام ميدانية
  select string_agg('• ' || e.full_name_ar || ' (' || coalesce(q.request_type, 'مهمة') || ')', E'\n')
    into v_missions_list
    from (
      select distinct r.employee_id, r.request_type
        from public.requests r
       where r.request_type in ('mission', 'convoy', 'fundraising')
         and r.status = 'approved'
         and v_date between coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date)
                        and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date)
       limit 5
    ) q
    join public.employees e on e.id = q.employee_id;
  -- صياغة النص التنفيذي المنمق الموجه للإدارة العليا
  v_text :=
    '🌟 *موجز العمليات اليومي — مؤسسة أحلى شباب*' || E'\n' ||
    '📅 *اليوم:* ' || v_day_name || ' ' || to_char(v_date, 'YYYY/MM/DD') || E'\n' ||
    '⏰ *التحديث:* ' || to_char((now() at time zone 'Africa/Cairo'), 'HH12:MI AM') || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '👥 *مؤشرات القوة العاملة والانضباط:*' || E'\n' ||
    '• إجمالي القوة الملزمة: ' || v_total_active || ' موظف' || E'\n' ||
    '• الحضور الفعلي المسجل: ' || v_present || ' زميل ✅' || E'\n' ||
    '• الميدان والقوافل: ' || (v_missions + v_convoys + v_fandy) || ' زميل 🚚' || E'\n' ||
    '• الإجازات المعتمدة: ' || v_leaves || ' زميل 🏖️' || E'\n' ||
    '• نسبة الانضباط العام: ' || coalesce(round(((v_present + v_missions + v_convoys + v_fandy)::numeric / nullif(v_total_active, 0)) * 100, 1)::text || '%', 'لا دوام اليوم (عطلة)') || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    '💰 *الموقف المالي وصندوق الزمالة والتكافل:*' || E'\n' ||
    '• غرامات التأخير الصادرة: ' || v_penalties_issued || ' (' || v_penalties_issued_amount || ' ج.م)' || E'\n' ||
    '• المحصل والمودع بالصندوق: ' || v_penalties_paid || ' (' || v_penalties_paid_amount || ' ج.م) 🪙' || E'\n' ||
    '• الرصيد الإجمالي التراكمي للصندوق: ' || v_fund_balance || ' ج.م 🏦' || E'\n' ||
    '━━━━━━━━━━━━━━━━━━━━' || E'\n' ||
    case when v_missions_list is not null and v_missions_list <> '' then
      '📍 *الفرق الميدانية في القوافل والمأموريات:*' || E'\n' || v_missions_list || E'\n' || '━━━━━━━━━━━━━━━━━━━━' || E'\n'
    else '' end ||
    '✨ *دمتم ذخراً لشباب الخير وعمار الأرض* 🌿';
  return jsonb_build_object(
    'date', v_date,
    'dayName', v_day_name,
    'totalActive', v_total_active,
    'present', v_present,
    'fieldMissions', (v_missions + v_convoys + v_fandy),
    'leaves', v_leaves,
    'absent', v_absent,
    'penaltiesIssued', v_penalties_issued,
    'penaltiesIssuedAmount', v_penalties_issued_amount,
    'penaltiesPaid', v_penalties_paid,
    'penaltiesPaidAmount', v_penalties_paid_amount,
    'fundBalance', v_fund_balance,
    'digestText', v_text
  );
end;
$function$;


-- ─── (4) دوال بلا فحص هوية: لا ينفذها الموظفون ───
revoke execute on function public.admin_activate_employee_after_password_set(uuid) from public, anon, authenticated;
grant execute on function public.admin_activate_employee_after_password_set(uuid) to service_role;

revoke execute on function public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.apply_leave_ledger_entry(uuid, uuid, integer, text, numeric, text, uuid, text, jsonb) to service_role;

revoke execute on function public.auto_notify_late_attendance() from public, anon, authenticated;
grant execute on function public.auto_notify_late_attendance() to service_role;

revoke execute on function public.backfill_request_managers() from public, anon, authenticated;
grant execute on function public.backfill_request_managers() to service_role;

notify pgrst, 'reload schema';

commit;
