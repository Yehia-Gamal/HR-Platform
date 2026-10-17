-- Migration 0687: Delegate request immediately to Abu Ammar (Operations Manager 1)
-- تسريع الطلب وتفويضه فوراً لأبو عمار (محمد عبدالباسط) دون انتظار اكتمال فترة الساعة

create or replace function public.delegate_request_to_abu_ammar(
  p_request_id uuid,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_abu_ammar       uuid := '767eae8e-e7be-458e-a6ca-879414e46b08'::uuid;
  v_authorized      boolean := false;
  v_is_exec         boolean;
  v_is_hr           boolean;
  v_is_admin        boolean;
  v_is_mgr          boolean;
  v_step_id         uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مسجل بحسابك' using errcode = '42501';
  end if;

  select * into v_req
  from public.requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'لا يمكن تفويض طلب غير معلّق (الحالة: %)', v_req.status using errcode = '22023';
  end if;

  -- التحقق من صلاحية القائم بالتفويض (المدير التنفيذي، مدير عام، HR، أو المدير المباشر الحالي للطلب)
  v_is_exec  := public.current_has_active_role(array['executive', 'executive-director', 'general-manager']);
  v_is_hr    := public.current_has_active_role(array['hr-manager', 'hr-specialist']);
  v_is_admin := public.current_is_full_access() or public.current_has_active_role(array['admin', 'super-admin']);
  v_is_mgr   := (v_req.manager_employee_id is not distinct from v_me)
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_authorized := v_is_exec or v_is_hr or v_is_admin or v_is_mgr;

  if not v_authorized then
    raise exception 'ليس لديك صلاحية لتفويض هذا الطلب' using errcode = '42501';
  end if;

  -- التحقق من معرف أبو عمار في النظام
  select id into v_abu_ammar
  from public.employees
  where id = '767eae8e-e7be-458e-a6ca-879414e46b08'
     or full_name_ar ilike '%ابو عمار%'
     or full_name_ar ilike '%أبو عمار%'
  order by (id = '767eae8e-e7be-458e-a6ca-879414e46b08') desc
  limit 1;

  if v_abu_ammar is null then
    v_abu_ammar := '767eae8e-e7be-458e-a6ca-879414e46b08'::uuid;
  end if;

  -- 1) تحديث الطلب: إسناده لأبو عمار فوراً وتصفير مهلة الساعة
  update public.requests
  set manager_employee_id = v_abu_ammar,
      workflow_status = 'awaiting_operator',
      escalated_at = now(),
      decision_due_at = now(),
      escalation_deadline = now(),
      payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object(
        'delegated_to', v_abu_ammar,
        'delegated_by', v_me,
        'delegated_at', now(),
        'escalation', jsonb_build_object(
          'mode', 'MANUAL_DELEGATION_TO_ABU_AMMAR',
          'escalatedToRole', 'operations-manager-1',
          'escalatedToEmployeeId', v_abu_ammar,
          'comment', coalesce(p_comment, 'تفويض وتسريع فوري لأبو عمار')
        )
      ),
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- 2) تحديث خطوات الطلب النشطة/المعلقة
  update public.request_steps
  set assignee_employee_id = v_abu_ammar,
      assignee_role_slug = 'operations-manager-1',
      status = 'escalated',
      escalated_at = now(),
      escalation_deadline = now(),
      due_at = now(),
      updated_at = now()
  where request_id = p_request_id
    and status in ('active', 'pending', 'escalated');

  -- 3) تسجيل الحدث في سجل الحركات
  insert into public.request_actions (
    request_id,
    actor_employee_id,
    action,
    from_status,
    to_status,
    comment,
    metadata
  ) values (
    p_request_id,
    v_me,
    'escalate',
    'pending',
    'pending',
    coalesce(nullif(trim(p_comment), ''), 'تفويض فوري وتسريع للطلب إلى مدير التشغيل (أبو عمار) دون انتظار مهلة الساعة'),
    jsonb_build_object(
      'delegated_to', v_abu_ammar,
      'delegated_by', v_me,
      'mode', 'MANUAL_DELEGATION_TO_ABU_AMMAR'
    )
  );

  -- 4) إرسال إشعار عاجل لأبو عمار
  perform public.notify_employee(
    v_abu_ammar,
    'طلب مُفوَّض بصفة عاجلة',
    format('تم تفويض طلب #%s (%s) إليك بصفة عاجلة للبت والاعتماد الفوري.', v_req.request_number, coalesce(v_req.title, v_req.request_type)),
    'request',
    'urgent',
    'requests',
    v_req.id,
    jsonb_build_object('delegated_by', v_me, 'requestId', v_req.id)
  );

  -- 5) تسجيل في سجل التدقيق
  perform public.log_audit_event(
    'request.delegated',
    'workflow',
    'notice',
    'requests',
    v_req.id,
    'تفويض وتسريع الطلب لأبو عمار',
    p_comment,
    jsonb_build_object('delegated_to', v_abu_ammar, 'delegated_by', v_me)
  );

  return v_req;
end;
$$;

revoke all on function public.delegate_request_to_abu_ammar(uuid, text) from public, anon;
grant execute on function public.delegate_request_to_abu_ammar(uuid, text) to authenticated, service_role;
