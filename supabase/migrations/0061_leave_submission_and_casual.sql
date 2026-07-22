-- =====================================================================
-- 0061: ربط تقديم الإجازة بالدفتر + تنفيذ العارضة مباشرة + توجيه المدير
-- =====================================================================
-- المرجع: المواصفة الرسمية (البنود 2،3،4،7 + ملاحظة العارضة الفورية).
-- المشاكل المُعالَجة (من الفحص العميق):
--   1) submit_my_request كان يخزّن الإجازة كنص في payload فقط ولا ينشئ صف
--      leave_requests، فلا يعمل تريغر حجز الرصيد (0026) إطلاقًا → الرصيد معطّل.
--   2) العارضة/الطارئة يجب أن تُنفَّذ مباشرة دون موافقة المدير المباشر.
--   3) لا يجوز أن يعتمد المدير طلبه الشخصي؛ يُوجَّه لمديره الأعلى تلقائيًا.
-- الحل: نعيد كتابة submit_my_request لتُنشئ صف leave_requests فعليًا (يُفعّل
--   الحجز)، وتعتمد العارضة فورًا عبر مسار القرار القائم (يُفعّل الخصم)، وتحدد
--   المدير المباشر من manager_relations مع صعود تلقائي لو كان المُقدِّم مديرًا.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) مُحدِّد المدير المسؤول عن طلب موظف معيّن.
--    القاعدة: المدير المباشر (primary) للمُقدِّم. إن كان المُقدِّم نفسه هو
--    ذلك المدير (لا يعتمد المدير طلبه)، نصعد لمدير المدير. يُرجع NULL إن لم
--    يوجد (يُترك للمخوّلين/التصعيد لاحقًا).
-- ---------------------------------------------------------------------
create or replace function public.resolve_request_approver(
  p_employee_id uuid,
  p_as_of date default (now() at time zone 'Africa/Cairo')::date
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_mgr uuid;
begin
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_from <= p_as_of
    and (effective_to is null or effective_to >= p_as_of)
  order by effective_from desc
  limit 1;

  -- منع الموافقة الذاتية: لو صار المدير هو المُقدِّم نفسه، اصعد لمديره.
  if v_mgr is not null and v_mgr = p_employee_id then
    select manager_employee_id into v_mgr
    from public.manager_relations
    where employee_id = p_employee_id
      and relation_type = 'primary'
      and manager_employee_id <> p_employee_id
      and effective_from <= p_as_of
      and (effective_to is null or effective_to >= p_as_of)
    order by effective_from desc
    limit 1;
  end if;

  return v_mgr;
end $$;

comment on function public.resolve_request_approver(uuid, date) is
  'يحدد المدير المسؤول عن طلب الموظف من الهيكل الإداري (primary) مع منع الموافقة الذاتية.';

revoke execute on function public.resolve_request_approver(uuid, date) from public;
grant execute on function public.resolve_request_approver(uuid, date) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2) إعادة كتابة submit_my_request:
--    * الإجازة: تحلّ leave_type_id، تحسب days_count، تُنشئ صف leave_requests
--      (يُفعّل حجز الرصيد)، وتحدد المدير المباشر تلقائيًا.
--    * العارضة (casual): تُعتمَد فورًا عبر مسار القرار (system) → خصم مباشر.
--    * mission/convoy: تبقى كما هي (لا خصم رصيد) للتوافق الخلفي؛ الوحدة
--      الجديدة لتكليفات العمل في 0063.
-- ملاحظة توافق: payload القديم قد يرسل 'emergency' — نخرّطها إلى 'casual'.
-- ---------------------------------------------------------------------
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_start_date date;
  v_end_date date;
  v_permit_date date;
  v_minutes integer;
  v_leave_type text;
  v_permit_kind text;
  v_leave_type_id uuid;
  v_affects boolean;
  v_days numeric;
  v_substitute uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_request_type not in ('leave','mission','convoy','attendance_permit','generic') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 5 then
    raise exception 'title and reason are required' using errcode = '22023';
  end if;

  begin
    case p_request_type
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- توافق خلفي: emergency → casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid') then
          raise exception 'unsupported leave type' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        -- النوع يجب أن يكون نشطًا (الوضع/رعاية الطفل معطّلان بالسياسة).
        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      when 'mission', 'convoy' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        if v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1);

      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive attendance permits are not allowed' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'unsupported permit kind' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes);
      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'invalid request dates or numeric values' using errcode = '22023';
  end;

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية).
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public.submit_request(
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026).
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    -- العارضة/الطارئة: تُنفَّذ مباشرة دون موافقة المدير المباشر.
    -- نعتمد الطلب فورًا عبر تحديث الحالة (يُفعّل تريغر الخصم/التسوية 0055).
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
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  return v_row;
end $$;

revoke execute on function public.submit_my_request(text,text,text,jsonb) from public;
grant execute on function public.submit_my_request(text,text,text,jsonb) to authenticated;

-- =====================================================================
-- نهاية Migration 0061
-- =====================================================================
