-- ============================================================================
-- 0304 — إعادة تطبيع الهاتف في update_employee_admin
-- ════════════════════════════════════════════════════════════════════════════
-- المشكلة: المايقريشن 0281 أضاف تطبيع phoneE164 إلى E.164، لكن المايقريشن
-- 0302 (تبسيط تعديل الموظف) أعاد تعريف update_employee_admin بالكامل من
-- نسخة 0191 الأصلية **بدون** تطبيع الهاتف، فأسقط الإصلاح.
--
-- النتيجة: الإداري يكتب هاتف الموظف بصيغة محلية '01XXXXXXXXX' فيُخزَّن كما
-- هو، ثم يفشل دخول الموظف لأن identifier-sign-in يبحث عن '+20XXXXXXXXX'.
--
-- الحل: نُعيد تعريف الدالة مع تطبيع الهاتف فقط — دون تغيير أي منطق آخر.
-- نأخذ آخر نسخة (من 0302: سبب اختياري + email في 360) ونضيف عليها فقط
-- استدعاء normalize_phone_e164 للحقل phoneE164.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- ─── دالة تطبيع الهاتف (CREATE OR REPLACE كافية، لا حاجة لـ DO block) ───
-- إن وُجدت من 0281 تُستبدل، وإن لم تُوجد تُنشأ. CREATE OR REPLACE idempotent.
create or replace function public.normalize_phone_e164(p_raw text)
returns text
language plpgsql
immutable
strict
as $$
begin
  if p_raw ~ '^01[0-9]{9}$' then
    return '+20' || substring(p_raw from 2);
  end if;
  return p_raw;
end;
$$;

comment on function public.normalize_phone_e164(text) is
  'يُطبّع رقم الهاتف إلى E.164 — المحلي المصري 01XXXXXXXXX ← +20XXXXXXXXX.';

-- ─── إعادة تعريف update_employee_admin مع تطبيع الهاتف ───────────────────
-- نأخذ نسخة 0302 حرفياً (سبب اختياري + نفس الحقول) ونُضيف سطر تطبيع الهاتف
-- فقط قبل منطق UPDATE. كل شيء آخر يبقى كما هو.
create or replace function public.update_employee_admin(
  p_employee_id uuid,
  p_changes jsonb,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_has_sensitive boolean;
  v_has_basic boolean;
  v_employee public.employees;
  v_basic_fields text[] := array['fullNameAr','fullNameEn','phoneE164','photoUrl'];
  v_sensitive_fields text[] := array[
    'departmentId','teamId','branchId','workSiteId',
    'jobTitleId','positionId','gradeId','employmentTypeId',
    'hireDate','contractEnd','probationEnd','status',
    'jobTitleName','gradeName'
  ];
  v_key text;
  v_has_sensitive_change boolean := false;
  v_old_snapshot jsonb;
  v_jt_name text;
  v_jt_id uuid;
  v_jt_code text;
  v_gr_name text;
  v_gr_id uuid;
  v_gr_code text;
begin
  if v_actor_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_changes is null or p_changes = '{}'::jsonb then
    raise exception 'no_changes_provided' using errcode = '22023';
  end if;

  -- سبب التعديل: اختياري — عند الفراغ نستخدم قيمة افتراضية للتدقيق.
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    p_reason := 'تعديل عبر لوحة التحكم';
  end if;

  v_has_sensitive := public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive');
  v_has_basic := v_has_sensitive
    or public.has_permission('people.employee.update_basic');

  if not v_has_basic then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;

  if not public.can_access_employee(p_employee_id, 'people.employee.update_basic')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_changes) loop
    if v_key = any(v_sensitive_fields) then
      v_has_sensitive_change := true;
    end if;
    if v_key <> all(v_basic_fields) and v_key <> all(v_sensitive_fields) then
      raise exception 'unknown field: %', v_key using errcode = '22023';
    end if;
  end loop;

  if v_has_sensitive_change and not v_has_sensitive then
    raise exception 'sensitive_field_requires_elevated_permission' using errcode = '42501';
  end if;

  -- P0-FIX: طبّع الهاتف إلى E.164 قبل أي منطق آخر يعتمد عليه (فحص تكرار /
  -- UPDATE). بدون هذه الخطوة يفشل identifier-sign-in عند محاولة الدخول لاحقاً
  -- لأنه يبحث بالصيغة المُطبّعة بينما المخزن بقي بصيغة محلية.
  if p_changes ? 'phoneE164' and nullif(trim(p_changes->>'phoneE164'), '') is not null then
    p_changes := jsonb_set(
      p_changes, '{phoneE164}',
      to_jsonb(public.normalize_phone_e164(trim(p_changes->>'phoneE164'))),
      true
    );
  end if;

  -- حل المسمى الوظيفي من النص إلى UUID
  if p_changes ? 'jobTitleName' then
    v_jt_name := nullif(trim(p_changes->>'jobTitleName'), '');
    if v_jt_name is not null then
      select id into v_jt_id
      from public.job_titles
      where lower(name) = lower(v_jt_name) and is_active = true
      limit 1;

      if v_jt_id is null then
        v_jt_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_titles (code, name, is_active, created_by)
        values (v_jt_code, v_jt_name, true, v_actor_id)
        on conflict ((lower(name))) where is_active = true
        do update set updated_at = now()
        returning id into v_jt_id;
      end if;

      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', v_jt_id);
      end if;
    else
      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', null);
      end if;
    end if;
    p_changes := p_changes - 'jobTitleName';
  end if;

  -- حل الدرجة الوظيفية من النص إلى UUID
  if p_changes ? 'gradeName' then
    v_gr_name := nullif(trim(p_changes->>'gradeName'), '');
    if v_gr_name is not null then
      select id into v_gr_id
      from public.job_grades
      where lower(name) = lower(v_gr_name) and is_active = true
      limit 1;

      if v_gr_id is null then
        v_gr_code := 'GR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_grades (code, name, level, is_active, created_by)
        values (v_gr_code, v_gr_name, 1, true, v_actor_id)
        returning id into v_gr_id;
      end if;

      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', v_gr_id);
      end if;
    else
      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', null);
      end if;
    end if;
    p_changes := p_changes - 'gradeName';
  end if;

  -- تحميل الموظف مع قفل
  select * into v_employee
  from public.employees
  where id = p_employee_id and is_deleted = false
  for update;

  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  v_old_snapshot := jsonb_build_object(
    'fullNameAr', v_employee.full_name_ar,
    'fullNameEn', v_employee.full_name_en,
    'phoneE164', v_employee.phone_e164,
    'photoUrl', v_employee.photo_url,
    'departmentId', v_employee.department_id,
    'teamId', v_employee.team_id,
    'branchId', v_employee.branch_id,
    'workSiteId', v_employee.work_site_id,
    'jobTitleId', v_employee.job_title_id,
    'positionId', v_employee.position_id,
    'gradeId', v_employee.grade_id,
    'employmentTypeId', v_employee.employment_type_id,
    'hireDate', v_employee.hire_date,
    'contractEnd', v_employee.contract_end,
    'probationEnd', v_employee.probation_end,
    'status', v_employee.status
  );

  update public.employees set
    full_name_ar = case when p_changes ? 'fullNameAr'
      then trim(p_changes->>'fullNameAr') else full_name_ar end,
    full_name_en = case when p_changes ? 'fullNameEn'
      then nullif(trim(p_changes->>'fullNameEn'), '') else full_name_en end,
    phone_e164 = case when p_changes ? 'phoneE164'
      then nullif(trim(p_changes->>'phoneE164'), '') else phone_e164 end,
    photo_url = case when p_changes ? 'photoUrl'
      then nullif(trim(p_changes->>'photoUrl'), '') else photo_url end,
    department_id = case when p_changes ? 'departmentId'
      then (p_changes->>'departmentId')::uuid else department_id end,
    team_id = case when p_changes ? 'teamId'
      then (p_changes->>'teamId')::uuid else team_id end,
    branch_id = case when p_changes ? 'branchId'
      then (p_changes->>'branchId')::uuid else branch_id end,
    work_site_id = case when p_changes ? 'workSiteId'
      then (p_changes->>'workSiteId')::uuid else work_site_id end,
    job_title_id = case when p_changes ? 'jobTitleId'
      then (p_changes->>'jobTitleId')::uuid else job_title_id end,
    position_id = case when p_changes ? 'positionId'
      then (p_changes->>'positionId')::uuid else position_id end,
    grade_id = case when p_changes ? 'gradeId'
      then (p_changes->>'gradeId')::uuid else grade_id end,
    employment_type_id = case when p_changes ? 'employmentTypeId'
      then (p_changes->>'employmentTypeId')::uuid else employment_type_id end,
    hire_date = case when p_changes ? 'hireDate'
      then (p_changes->>'hireDate')::date else hire_date end,
    contract_end = case when p_changes ? 'contractEnd'
      then (p_changes->>'contractEnd')::date else contract_end end,
    probation_end = case when p_changes ? 'probationEnd'
      then (p_changes->>'probationEnd')::date else probation_end end,
    status = case when p_changes ? 'status'
      then (p_changes->>'status') else status end,
    updated_at = now()
  where id = p_employee_id;

  -- فحص تكرار الهاتف بعد التحديث (يستخدم القيمة المُطبّعة المخزّنة حديثاً)
  if p_changes ? 'phoneE164' and (p_changes->>'phoneE164') is not null then
    if exists (
      select 1 from public.employees
      where phone_e164 = trim(p_changes->>'phoneE164')
        and id <> p_employee_id
        and is_active = true and is_deleted = false
    ) then
      raise exception 'phone number already belongs to an active employee' using errcode = '23505';
    end if;
  end if;

  -- التدقيق
  perform public.log_audit_event(
    'employee_updated', 'people', 'info', 'employees', p_employee_id,
    'تعديل بيانات الموظف',
    trim(p_reason),
    jsonb_build_object('before', v_old_snapshot, 'after', p_changes)
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'updatedFields', (select jsonb_agg(k) from jsonb_object_keys(p_changes) as k),
    'updatedAt', now()
  );
end;
$$;

-- نفس التوقيع، لا حاجة لإعادة REVOKE/GRANT
comment on function public.update_employee_admin(uuid, jsonb, text) is
  'تحديث موظف من لوحة الإدارة — يُطبّع phoneE164 إلى E.164 قبل الحفظ لمنع فشل identifier-sign-in. سبب التعديل اختياري.';

-- ─── تطبيع السجلات الموجودة مرة أخرى (قد تكون دخلت بعد 0281) ─────────────
do $$
declare
  v_row record;
  v_normalized text;
  v_fixed integer := 0;
begin
  for v_row in
    select id, phone_e164
    from public.employees
    where phone_e164 is not null
      and phone_e164 ~ '^01[0-9]{9}$'
      and is_active = true
      and is_deleted = false
  loop
    v_normalized := '+20' || substring(v_row.phone_e164 from 2);
    if not exists (
      select 1 from public.employees
      where phone_e164 = v_normalized
        and is_active = true and is_deleted = false
        and id <> v_row.id
    ) then
      update public.employees
      set    phone_e164 = v_normalized, updated_at = now()
      where  id = v_row.id;
      v_fixed := v_fixed + 1;
    end if;
  end loop;
  raise notice 'normalized % employee phone rows to E.164 (0304 backfill)', v_fixed;
end $$;

commit;
