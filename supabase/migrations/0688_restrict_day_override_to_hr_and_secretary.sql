-- Migration 0688: Restrict attendance day editing and rest grant to HR and Executive Secretary
-- تعديل حالة اليوم والدوام ومنح الراحات مقتصر على الموارد البشرية والسكرتير التنفيذي وليس للمدير التنفيذي

-- 1) منح صلاحية attendance.day.override للسكرتير التنفيذي
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.slug = 'executive-secretary'
  and p.code = 'attendance.day.override'
on conflict do nothing;

-- 2) تحديث دالة set_employee_attendance_day_admin لاستبعاد المدير التنفيذي صراحة
CREATE OR REPLACE FUNCTION public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time without time zone DEFAULT NULL::time without time zone,
  p_check_out time without time zone DEFAULT NULL::time without time zone,
  p_clear_check_in boolean DEFAULT false,
  p_clear_check_out boolean DEFAULT false,
  p_reason text DEFAULT NULL::text,
  p_notes text DEFAULT NULL::text,
  p_leave_type text DEFAULT NULL::text
)
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
  v_is_exec boolean;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;

  -- التحقق من استبعاد المدير التنفيذي صراحة بحسب توجيه الإدارة
  v_is_exec := public.current_has_active_role(array['executive', 'executive-director']);
  if v_is_exec and auth.role() <> 'service_role' then
    raise exception 'التعديل الإداري اليومي مقتصر على الموارد البشرية والسكرتير التنفيذي فقط وليس للمدير التنفيذي' using errcode = '42501';
  end if;

  -- التحقق من صلاحية الموارد البشرية أو السكرتير التنفيذي أو الأدمن التقني
  if not (
    auth.role() = 'service_role'
    or public.current_has_active_role(array['hr-manager', 'hr-specialist', 'executive-secretary', 'admin', 'super-admin'])
    or public.has_permission('attendance.day.override')
    or (p_employee_id is distinct from public.current_employee_id()
        and public.can_access_employee(p_employee_id, 'attendance.day.override'))
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
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

  -- ── حارس التواريخ: يسمح بجدولة الإجازات والمأموريات والعطل مستقبلاً ──────────
  if auth.role() <> 'service_role' then
    if p_day_type = 'work' and p_work_date > v_today then
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

  -- حفظ الحالة السابقة
  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  -- الإدراج أو التحديث في attendance_day_overrides
  insert into public.attendance_day_overrides (
    employee_id, work_date, day_type, leave_type,
    check_in, check_out, reason, notes,
    override_by, updated_at
  ) values (
    p_employee_id, p_work_date, p_day_type, v_leave_type,
    p_check_in, p_check_out, v_reason, p_notes,
    auth.uid(), now()
  )
  on conflict (employee_id, work_date) do update set
    day_type = excluded.day_type,
    leave_type = excluded.leave_type,
    check_in = excluded.check_in,
    check_out = excluded.check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    override_by = excluded.override_by,
    updated_at = now()
  returning id into v_id;

  -- إعادة احتساب اليوم وسجل الحضور اليومي
  perform public.recompute_employee_attendance_day(p_employee_id, p_work_date);

  -- تسجيل الحدث في سجل التدقيق
  perform public.log_audit_event(
    'attendance_day_override',
    'attendance_day_overrides',
    v_id,
    v_previous,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'work_date', p_work_date,
      'day_type', p_day_type,
      'leave_type', v_leave_type,
      'check_in', p_check_in,
      'check_out', p_check_out,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'success', true,
    'id', v_id,
    'employee_id', p_employee_id,
    'work_date', p_work_date,
    'day_type', p_day_type,
    'leave_type', v_leave_type
  );
end;
$function$;
