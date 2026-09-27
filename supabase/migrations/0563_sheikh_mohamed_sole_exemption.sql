-- ============================================================================
-- Migration 0563: حصر الإعفاء من الحضور والجزاءات على الشيخ محمد فقط
-- وإلغاء أي إعفاءات أخرى بما فيها حساب يحيى جمال
-- ============================================================================

BEGIN;

-- 1. تحديث تريجر حماية الأدمن بحيث لا يفرض أي إعفاء من الحضور أو الجزاءات على يحيى جمال
CREATE OR REPLACE FUNCTION public.tg_admin_immunity_employees_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     OR NEW.phone_e164 IN ('+201154869616', '01154869616')
     OR NEW.employee_code IN ('+201154869616', '01154869616')
     OR NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960' THEN
    NEW.status := 'active';
    NEW.is_active := true;
    -- يحيى جمال موظف عادي ملزم بالبصمة والجزاءات (غير معفى)
    NEW.is_attendance_exempt := false;
    NEW.is_penalty_exempt := false;
  END IF;
  RETURN NEW;
END;
$$;

-- 2. تحديث تريجر منع الجزاءات: يستثني فقط المعفيين فعلياً (الشيخ محمد)
CREATE OR REPLACE FUNCTION public.tg_prevent_admin_penalty_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.is_employee_penalty_exempt(NEW.employee_id) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- 3. تحديث دالة فحص الإعفاء من الحضور: الشخص الوحيد المعفى هو الشيخ محمد يوسف
CREATE OR REPLACE FUNCTION public.is_employee_attendance_exempt(p_employee_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec record;
BEGIN
  IF p_employee_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT id, employee_code, phone_e164, full_name_ar, is_attendance_exempt, user_id INTO v_rec
    FROM public.employees
   WHERE id = p_employee_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- الشخص الوحيد المعفى هو الشيخ محمد يوسف
  IF p_employee_id IN (
    '7b0740fa-66ba-4616-8674-3dbd8e14109e', -- الشيخ محمد يوسف
    '886f4942-c469-4a03-8f02-659fd02c4a02'  -- الشيخ محمد يوسف (أرشيف)
  ) OR v_rec.employee_code = '+201121622820'
    OR v_rec.full_name_ar ILIKE '%الشيخ محمد يوسف%'
    OR v_rec.full_name_ar ILIKE '%ألشيخ محمد يوسف%' THEN
    RETURN true;
  END IF;

  -- فحص العمود في جدول الموظفين (مع التحقق الحصري أنه الشيخ محمد)
  IF COALESCE(v_rec.is_attendance_exempt, false) = true AND (
    p_employee_id IN ('7b0740fa-66ba-4616-8674-3dbd8e14109e', '886f4942-c469-4a03-8f02-659fd02c4a02')
    OR v_rec.full_name_ar ILIKE '%الشيخ محمد%'
    OR v_rec.full_name_ar ILIKE '%ألشيخ محمد%'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- 4. تحديث دالة فحص الإعفاء من الجزاءات: الشخص الوحيد المعفى هو الشيخ محمد يوسف
CREATE OR REPLACE FUNCTION public.is_employee_penalty_exempt(p_employee_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec record;
BEGIN
  IF p_employee_id IS NULL THEN
    RETURN false;
  END IF;

  -- أي موظف معفى من الحضور فهو معفى من الجزاءات
  IF public.is_employee_attendance_exempt(p_employee_id) THEN
    RETURN true;
  END IF;

  SELECT id, employee_code, phone_e164, full_name_ar, is_penalty_exempt, user_id INTO v_rec
    FROM public.employees
   WHERE id = p_employee_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF COALESCE(v_rec.is_penalty_exempt, false) = true AND (
    p_employee_id IN ('7b0740fa-66ba-4616-8674-3dbd8e14109e', '886f4942-c469-4a03-8f02-659fd02c4a02')
    OR v_rec.full_name_ar ILIKE '%الشيخ محمد%'
    OR v_rec.full_name_ar ILIKE '%ألشيخ محمد%'
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- 5. تحديث get_my_access_context() لضبط سياسة الحضور بدقة
CREATE OR REPLACE FUNCTION public.get_my_access_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path to 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
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
  v_is_suspended boolean := false;
  v_suspension_reason text := null;
  v_suspension_message text := null;
  v_suspension_amount numeric := null;
  v_is_immune_admin boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يلزم تسجيل الدخول أولاً' USING errcode = '28000';
  END IF;

  SELECT p.employee_id, COALESCE(e.full_name_ar, 'مستخدم النظام'), e.employee_code, e.photo_url,
         p.status, e.status
    INTO v_employee_id, v_display_name, v_employee_code, v_photo_url,
         v_profile_status, v_employee_status
  FROM public.profiles p
  LEFT JOIN public.employees e ON e.id = p.employee_id
  WHERE p.id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد ملف موظف نشط' USING errcode = '42501';
  END IF;

  -- الأدمن الرئيسي: منع قفل حسابه الإداري فقط
  IF v_user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     OR v_employee_code IN ('+201154869616', '01154869616')
     OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id = v_employee_id AND (e.phone_e164 IN ('+201154869616', '01154869616') OR e.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960')) THEN
    v_is_immune_admin := true;
    v_profile_status := 'active';
    v_employee_status := 'active';
  END IF;

  -- فحص إيقاف الموظف عن العمل (يستثنى منه الأدمن من حظر لوحة التحكم)
  IF NOT v_is_immune_admin AND (COALESCE(v_profile_status, '') = 'suspended' OR COALESCE(v_employee_status, '') = 'suspended') THEN
    v_is_suspended := true;

    SELECT p.current_amount INTO v_suspension_amount
    FROM public.instant_attendance_penalties p
    WHERE p.employee_id = v_employee_id
      AND p.status = 'suspended'
    ORDER BY p.created_at DESC
    LIMIT 1;

    IF FOUND THEN
      v_suspension_reason := 'penalty_unpaid';
      v_suspension_amount := COALESCE(v_suspension_amount, 500.00);
      v_suspension_message := 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    ELSE
      v_suspension_reason := 'administrative';
      v_suspension_message := 'تم إيقاف حسابك عن العمل مؤقتاً. يرجى مراجعة إدارة الموارد البشرية (HR).';
    END IF;

    RETURN jsonb_build_object(
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
  END IF;

  IF v_profile_status NOT IN ('active', 'pending') THEN
    RAISE EXCEPTION 'حساب المستخدم غير نشط' USING errcode = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT r.slug ORDER BY r.slug), '{}'::text[])
    INTO v_roles
  FROM public.user_roles ur
  JOIN public.roles r ON r.id = ur.role_id
  WHERE ur.user_id = v_user_id
    AND ur.effective_from <= now()
    AND (ur.effective_to IS NULL OR ur.effective_to > now());

  v_is_full := public.current_is_full_access() OR v_is_immune_admin;
  IF v_is_full THEN
    v_permissions := array['*']::text[];
  ELSE
    SELECT COALESCE(array_agg(DISTINCT p.code ORDER BY p.code), '{}'::text[])
      INTO v_permissions
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role_id = ur.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE ur.user_id = v_user_id
      AND ur.effective_from <= now()
      AND (ur.effective_to IS NULL OR ur.effective_to > now())
      AND (rp.effective_from IS NULL OR rp.effective_from <= now())
      AND (rp.effective_to IS NULL OR rp.effective_to > now());
  END IF;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations OR v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full OR v_is_immune_admin OR v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- مساحات العمل
  IF v_employee_id IS NOT NULL AND NOT v_is_executive THEN
    v_workspaces := array_append(v_workspaces, 'employee');
  END IF;
  IF v_is_manager AND NOT v_is_executive THEN
    v_workspaces := array_append(v_workspaces, 'manager');
  END IF;
  IF v_is_operations AND NOT v_is_executive THEN
    v_workspaces := array_append(v_workspaces, 'field_operations');
  END IF;
  IF v_is_executive THEN v_workspaces := array_append(v_workspaces, 'executive'); END IF;
  IF v_is_hr OR v_is_main_admin THEN v_workspaces := array_append(v_workspaces, 'hr'); END IF;
  IF v_is_main_admin THEN v_workspaces := array_append(v_workspaces, 'main_admin'); END IF;
  IF v_is_committee AND NOT v_is_hr AND NOT v_is_main_admin THEN
    v_workspaces := array_append(v_workspaces, 'committee');
  END IF;

  -- المساحة الافتراضية
  IF v_is_main_admin THEN
    v_default_workspace := 'main_admin';
  ELSIF v_is_executive THEN
    v_default_workspace := 'executive';
  ELSIF v_is_hr THEN
    v_default_workspace := 'hr';
  ELSIF v_is_operations THEN
    v_default_workspace := 'field_operations';
  ELSIF v_is_manager THEN
    v_default_workspace := 'manager';
  ELSIF v_employee_id IS NOT NULL THEN
    v_default_workspace := 'employee';
  ELSE
    RAISE EXCEPTION 'لا توجد مساحة عمل معينة' USING errcode = '42501';
  END IF;

  -- سياسة الحضور: الشيخ محمد فقط هو المعفى (v_is_executive أو is_employee_attendance_exempt)
  RETURN jsonb_build_object(
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
      'attendanceRequired', NOT v_is_executive AND NOT public.is_employee_attendance_exempt(v_employee_id) AND v_employee_id IS NOT NULL,
      'selfPunchEnabled', true,
      'liveLocationResponseEnabled', NOT v_is_executive AND NOT public.is_employee_attendance_exempt(v_employee_id) AND v_employee_id IS NOT NULL
    )
  );
END;
$function$;

-- 6. إلغاء الإعفاء عن كل الموظفين وحصره فقط على الشيخ محمد يوسف
UPDATE public.employees
   SET is_attendance_exempt = false,
       is_penalty_exempt = false,
       updated_at = now()
 WHERE id NOT IN (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e',
   '886f4942-c469-4a03-8f02-659fd02c4a02'
 );

-- ضمان إعفاء الشيخ محمد يوسف فقط
UPDATE public.employees
   SET is_attendance_exempt = true,
       is_penalty_exempt = true,
       updated_at = now()
 WHERE id IN (
   '7b0740fa-66ba-4616-8674-3dbd8e14109e',
   '886f4942-c469-4a03-8f02-659fd02c4a02'
 );

COMMIT;
