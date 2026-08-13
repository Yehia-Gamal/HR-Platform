-- 0404: منح صلاحيات طلبات الموافقات لدور operations-officer (طبقة التصعيد 2)
-- ══════════════════════════════════════════════════════════════════════
-- 0396 بنى تصعيداً ثلاثي الطبقات:
--       الخطوة 1 (0–2س): المدير المباشر + full_access فقط
--       الخطوة 2 (2–6س): المدير + الأوبريشن + full_access
--       الخطوة 3 (6س+): المدير + الأوبريشن + HR + full_access
-- process_request_sla يكلّف step 2 إلى أول موظف فعّال بدور
-- 'operations-officer' (first_active_employee_for_role) ويُشعره
-- «طلب محوّل إليك — يمكنك البت فيه الآن».
--
-- لكن operations-officer لم يكن يملك أصلاً requests.read/requests.approve
-- (0317 منحها لـ hr-manager/hr-specialist/direct-manager فقط؛ والنموذج
-- القديم 0062 كان يجعل الأوبريشن manager_employee_id فيصبح مفوّضاً بصفته
-- مديراً مباشراً). فكانت طبقة الأوبريشن عمياء (RLS على requests يحجبها)
-- وعاجزة عن البت (decide_request يطلب can_access_employee(…, 'requests.approve')).
--
-- الإصلاح: منح operations-officer نفس صلاحيات HR بنطاق organization،
-- لأن هدف التصعيد موظف واحد يُستقى من كامل المؤسسة وقد يكون الطلب
-- من أي إدارة؛ ونطاق department لن يغطي الحالات العابرة للإدارات.
-- الأكواد الأربعة مطابقة لمنح 0317 لـ hr-manager: approve/read
-- بالإضافة إلى مفاتيح request-scoped التي يستخدمها
-- get_mobile_request_detail للسماح بالاطلاع والبت.
-- ══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[];
begin
  v_codes := array[
    'requests.approve','requests.read',
    'requests.request.approve','requests.request.read'
  ];
  select id into v_role_id from public.roles where slug = 'operations-officer';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;
end $$;

commit;
