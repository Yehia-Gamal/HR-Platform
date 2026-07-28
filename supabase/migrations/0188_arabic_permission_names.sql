-- =====================================================================================
-- 0188: Arabic permission names + fix full-access role display in admin catalog
-- =====================================================================================
-- 1) يُضيف عمود name_ar إلى جدول permissions ويملأه بالترجمات العربية (~189 صلاحية).
-- 2) يُصلح get_access_admin_catalog: أدوار is_full_access كانت تُظهر 0 صلاحية
--    لأن الاستعلام يبحث فقط في role_permissions (لا صفوف لها).
--    الحل: CASE — إذا is_full_access → كل الصلاحيات من الكتالوج.
-- 3) يُرجع nameAr و moduleAr ضمن بيانات الصلاحيات.
-- =====================================================================================

begin;

-- 1) إضافة عمود name_ar
alter table public.permissions add column if not exists name_ar text;

-- 2) تعبئة الترجمات العربية لجميع الصلاحيات
update public.permissions set name_ar = case code
  -- ═══════════ شؤون الموظفين (people) ═══════════
  when 'people.employee.read'               then 'عرض بيانات الموظف'
  when 'people.employee.create'             then 'إنشاء موظف'
  when 'people.employee.update_basic'       then 'تعديل البيانات الأساسية'
  when 'people.employee.update_sensitive'   then 'تعديل البيانات الحساسة'
  when 'people.employee.archive'            then 'أرشفة موظف'
  when 'people.employee.terminate'          then 'إنهاء خدمة موظف'
  when 'people.employee.restore'            then 'استعادة موظف'
  when 'people.employee.import'             then 'استيراد موظفين'
  when 'people.employee.export'             then 'تصدير بيانات الموظفين'
  when 'people.employee.assign_manager'     then 'تعيين المدير المباشر'
  when 'people.employee.transfer'           then 'نقل موظف'
  when 'people.employee.promote'            then 'ترقية موظف'
  when 'people.employee.change_status'      then 'تغيير حالة الموظف'
  when 'people.employee.view_identity'      then 'عرض بيانات الهوية'
  when 'people.employee.view_contact'       then 'عرض بيانات التواصل'
  when 'people.employee.view_compensation'  then 'عرض بيانات التعويضات'
  when 'people.employee.view_history'       then 'عرض السجل الوظيفي'
  when 'people.employee.view_audit'         then 'عرض سجل التدقيق'
  when 'people.employee.upload_avatar'      then 'رفع الصورة الشخصية'
  when 'people.employee.manage_documents'   then 'إدارة مستندات الموظف'

  -- ═══════════ الهيكل التنظيمي (organization) ═══════════
  when 'organization.entity.read'           then 'عرض الكيانات القانونية'
  when 'organization.entity.manage'         then 'إدارة الكيانات القانونية'
  when 'organization.branch.manage'         then 'إدارة الفروع'
  when 'organization.department.manage'     then 'إدارة الأقسام'
  when 'organization.unit.manage'           then 'إدارة الوحدات'
  when 'organization.position.manage'       then 'إدارة المناصب'
  when 'organization.job_title.manage'      then 'إدارة المسميات الوظيفية'
  when 'organization.grade.manage'          then 'إدارة الدرجات الوظيفية'
  when 'organization.org_chart.read'        then 'عرض الهيكل التنظيمي'

  -- ═══════════ إدارة الوصول (access) ═══════════
  when 'access.account.read'                then 'عرض الحسابات'
  when 'access.account.create'              then 'إنشاء حساب'
  when 'access.account.update'              then 'تعديل حساب'
  when 'access.account.clone'               then 'نسخ حساب'
  when 'access.account.assign'              then 'إسناد حساب'
  when 'access.account.remove'              then 'حذف حساب'
  when 'access.account.approve_sensitive_change' then 'اعتماد تغيير حساس'
  when 'access.account.preview'             then 'معاينة حساب'
  when 'access.role.read'                   then 'عرض الأدوار'
  when 'access.role.create'                 then 'إنشاء دور'
  when 'access.role.update'                 then 'تعديل دور'
  when 'access.role.clone'                  then 'نسخ دور'
  when 'access.role.assign'                 then 'إسناد دور'
  when 'access.role.remove'                 then 'حذف دور'
  when 'access.role.approve_sensitive_change' then 'اعتماد تغيير حساس للدور'
  when 'access.role.preview'                then 'معاينة دور'
  when 'access.audit.read'                  then 'عرض سجل تدقيق الوصول'
  when 'access.break_glass.activate'        then 'تفعيل الوصول الطارئ'

  -- ═══════════ الحضور والانصراف (attendance) ═══════════
  when 'attendance.punch.check_in'          then 'تسجيل حضور'
  when 'attendance.punch.check_out'         then 'تسجيل انصراف'
  when 'attendance.record.read'             then 'عرض سجلات الحضور'
  when 'attendance.record.read_location'    then 'عرض موقع التسجيل'
  when 'attendance.record.read_identity_check' then 'عرض التحقق من الهوية'
  when 'attendance.record.read_risk'        then 'عرض مخاطر الحضور'
  when 'attendance.record.export'           then 'تصدير سجلات الحضور'
  when 'attendance.record.manual_create'    then 'إنشاء سجل حضور يدوي'
  when 'attendance.record.void'             then 'إلغاء سجل حضور'
  when 'attendance.correction.create'       then 'إنشاء طلب تصحيح'
  when 'attendance.correction.review'       then 'مراجعة طلب تصحيح'
  when 'attendance.correction.approve'      then 'اعتماد طلب تصحيح'
  when 'attendance.correction.reject'       then 'رفض طلب تصحيح'
  when 'attendance.risk.review'             then 'مراجعة المخاطر'
  when 'attendance.risk.resolve'            then 'حل المخاطر'
  when 'attendance.shift.read'              then 'عرض الورديات'
  when 'attendance.shift.manage'            then 'إدارة الورديات'
  when 'attendance.shift.assign'            then 'تعيين الورديات'
  when 'attendance.calendar.manage'         then 'إدارة تقويم العمل'
  when 'attendance.geofence.manage'         then 'إدارة النطاق الجغرافي'
  when 'attendance.policy.manage'           then 'إدارة سياسة الحضور'
  when 'attendance.period.close'            then 'إغلاق فترة الحضور'
  when 'attendance.period.unlock'           then 'فتح فترة مغلقة'

  -- ═══════════ الموقع المباشر (live_location) ═══════════
  when 'live_location.request'              then 'طلب الموقع المباشر'
  when 'live_location.request_group'        then 'طلب موقع جماعي'
  when 'live_location.cancel'               then 'إلغاء طلب الموقع'
  when 'live_location.view_response'        then 'عرض استجابة الموقع'
  when 'live_location.view_history'         then 'عرض سجل المواقع'
  when 'live_location.export'               then 'تصدير بيانات المواقع'
  when 'live_location.manage_policy'        then 'إدارة سياسة الموقع'
  when 'live_location.manage_retention'     then 'إدارة الاحتفاظ بالبيانات'
  when 'live_location.read_access_log'      then 'عرض سجل الوصول للمواقع'

  -- ═══════════ الطلبات (requests) ═══════════
  when 'requests.request.read'              then 'عرض الطلبات'
  when 'requests.request.create'            then 'إنشاء طلب'
  when 'requests.request.update_draft'      then 'تعديل مسودة الطلب'
  when 'requests.request.submit'            then 'تقديم طلب'
  when 'requests.request.withdraw'          then 'سحب طلب'
  when 'requests.request.cancel_approved'   then 'إلغاء طلب معتمد'
  when 'requests.request.return_for_correction' then 'إرجاع للتصحيح'
  when 'requests.request.approve'           then 'اعتماد طلب'
  when 'requests.request.reject'            then 'رفض طلب'
  when 'requests.request.delegate'          then 'تفويض طلب'
  when 'requests.request.escalate'          then 'تصعيد طلب'
  when 'requests.request.override'          then 'تجاوز القرار'
  when 'requests.approve'                   then 'الموافقة على الطلبات'
  when 'requests.read'                      then 'قراءة الطلبات'
  when 'requests.workflow.read'             then 'عرض سير العمل'
  when 'requests.workflow.manage'           then 'إدارة سير العمل'
  when 'requests.workflow.publish_version'  then 'نشر نسخة سير العمل'
  when 'requests.workflow.view_audit'       then 'عرض تدقيق سير العمل'
  when 'requests.leave.balance.read'        then 'عرض رصيد الإجازات'
  when 'requests.leave.balance.adjust'      then 'تعديل رصيد الإجازات'
  when 'requests.leave.policy.manage'       then 'إدارة سياسة الإجازات'
  when 'requests.leave.execute_casual'      then 'تنفيذ إجازة عارضة'

  -- ═══════════ العمليات (operations) ═══════════
  when 'operations.task.read'               then 'عرض المهام'
  when 'operations.task.create'             then 'إنشاء مهمة'
  when 'operations.task.update'             then 'تعديل مهمة'
  when 'operations.task.assign'             then 'تعيين مهمة'
  when 'operations.task.complete'           then 'إتمام مهمة'
  when 'operations.task.cancel'             then 'إلغاء مهمة'
  when 'operations.incident.manage'         then 'إدارة الحوادث'
  when 'operations.convoy.manage'           then 'إدارة القوافل'
  when 'operations.mission.manage'          then 'إدارة المأموريات'
  when 'operations.shift_handover.create'   then 'إنشاء تسليم وردية'
  when 'operations.shift_handover.read'     then 'عرض تسليم الورديات'

  -- ═══════════ التكليفات (assignments) ═══════════
  when 'assignments.mission.manage'         then 'إدارة تكليف المأموريات'
  when 'assignments.convoy.manage'          then 'إدارة تكليف القوافل'
  when 'assignments.fundraising.manage'     then 'إدارة تكليف جمع التبرعات'
  when 'assignments.report.review'          then 'مراجعة تقارير التكليفات'

  -- ═══════════ الأداء (performance) ═══════════
  when 'performance.kpi.read'               then 'عرض مؤشرات الأداء'
  when 'performance.kpi.self_assess'        then 'التقييم الذاتي'
  when 'performance.kpi.manager_assess'     then 'تقييم المدير'
  when 'performance.kpi.hr_review'          then 'مراجعة الموارد البشرية'
  when 'performance.kpi.secretary_review'   then 'مراجعة السكرتير'
  when 'performance.kpi.executive_review'   then 'مراجعة المدير التنفيذي'
  when 'performance.kpi.finalize'           then 'اعتماد التقييم النهائي'
  when 'performance.kpi.reopen_amendment'   then 'إعادة فتح للتعديل'
  when 'performance.kpi.view_reviewer_notes' then 'عرض ملاحظات المراجعين'
  when 'performance.kpi.view_sensitive_scores' then 'عرض الدرجات الحساسة'
  when 'performance.kpi.export'             then 'تصدير بيانات الأداء'
  when 'performance.template.manage'        then 'إدارة قوالب التقييم'
  when 'performance.cycle.manage'           then 'إدارة دورات الأداء'
  when 'performance.calibration.manage'     then 'إدارة المعايرة'
  when 'performance.pip.manage'             then 'إدارة خطط تحسين الأداء'
  when 'performance.goal.manage_self'       then 'إدارة الأهداف الشخصية'
  when 'performance.goal.manage_team'       then 'إدارة أهداف الفريق'

  -- ═══════════ المستندات (documents) ═══════════
  when 'documents.employee.read'            then 'عرض مستندات الموظف'
  when 'documents.employee.create'          then 'إنشاء مستند موظف'
  when 'documents.employee.update'          then 'تعديل مستند موظف'
  when 'documents.employee.delete'          then 'حذف مستند موظف'
  when 'documents.employee.export'          then 'تصدير مستندات الموظف'
  when 'documents.contract.read'            then 'عرض العقود'
  when 'documents.contract.create'          then 'إنشاء عقد'
  when 'documents.contract.update'          then 'تعديل عقد'
  when 'documents.contract.delete'          then 'حذف عقد'
  when 'documents.contract.export'          then 'تصدير العقود'
  when 'documents.policy.publish'           then 'نشر سياسة'
  when 'documents.policy.acknowledge'       then 'الإقرار بسياسة'
  when 'documents.expiry.manage'            then 'إدارة صلاحية المستندات'

  -- ═══════════ علاقات الموظفين (relations) ═══════════
  when 'relations.case.read'                then 'عرض القضايا'
  when 'relations.case.create'              then 'إنشاء قضية'
  when 'relations.case.update'              then 'تعديل قضية'
  when 'relations.case.assign'              then 'إسناد قضية'
  when 'relations.case.resolve'             then 'حل قضية'
  when 'relations.case.close'               then 'إغلاق قضية'
  when 'relations.case.export'              then 'تصدير القضايا'
  when 'relations.committee.manage_templates' then 'إدارة قوالب اللجان'
  when 'relations.committee.manage_members' then 'إدارة أعضاء اللجان'
  when 'relations.discipline.create'        then 'إنشاء إجراء تأديبي'
  when 'relations.discipline.approve'       then 'اعتماد إجراء تأديبي'

  -- ═══════════ الاتصالات (communications) ═══════════
  when 'communications.announcement.create' then 'إنشاء إعلان'
  when 'communications.announcement.publish' then 'نشر إعلان'
  when 'communications.announcement.manage_targets' then 'إدارة مستهدفي الإعلان'
  when 'communications.decision.create'     then 'إنشاء قرار'
  when 'communications.decision.publish'    then 'نشر قرار'
  when 'communications.decision.acknowledge' then 'الإقرار بقرار'
  when 'communications.decision.read_receipts' then 'عرض إيصالات الاستلام'
  when 'communications.notification.send'   then 'إرسال إشعار'
  when 'communications.notification.send_bulk' then 'إرسال إشعارات جماعية'
  when 'communications.survey.manage'       then 'إدارة الاستبيانات'

  -- ═══════════ التقارير (reports) ═══════════
  when 'reports.attendance.read'            then 'تقارير الحضور'
  when 'reports.people.read'                then 'تقارير الموظفين'
  when 'reports.requests.read'              then 'تقارير الطلبات'
  when 'reports.performance.read'           then 'تقارير الأداء'
  when 'reports.operations.read'            then 'تقارير العمليات'
  when 'reports.report.export'              then 'تصدير التقارير'
  when 'reports.report.schedule'            then 'جدولة التقارير'
  when 'reports.builder.use'                then 'استخدام منشئ التقارير'
  when 'reports.builder.manage_catalog'     then 'إدارة كتالوج التقارير'

  -- ═══════════ النظام (system) ═══════════
  when 'system.settings.read'              then 'عرض الإعدادات'
  when 'system.settings.update_general'    then 'تعديل الإعدادات العامة'
  when 'system.settings.update_security'   then 'تعديل إعدادات الأمان'
  when 'system.feature_flags.manage'       then 'إدارة ميزات النظام'
  when 'system.integrations.manage'        then 'إدارة التكاملات'
  when 'system.jobs.read'                  then 'عرض المهام الخلفية'
  when 'system.jobs.retry'                 then 'إعادة تشغيل مهمة'
  when 'system.audit.read'                 then 'عرض سجل تدقيق النظام'
  when 'system.security_events.read'       then 'عرض أحداث الأمان'
  when 'system.security_events.resolve'    then 'حل أحداث الأمان'
  when 'system.backup.read_status'         then 'عرض حالة النسخ الاحتياطي'
  when 'system.backup.run'                 then 'تشغيل نسخ احتياطي'
  when 'system.restore.execute'            then 'تنفيذ استعادة النظام'

  else name_ar  -- أي صلاحية غير مدرجة تبقى كما هي
end
where name_ar is null or name_ar = '';

-- 3) إعادة إنشاء get_access_admin_catalog مع إصلاح full-access + أسماء عربية
create or replace function public.get_access_admin_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.role.update','access.role.assign'])) then
    raise exception 'access catalog denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', case
          -- ═══ أدوار الوصول الكامل: إرجاع كل الصلاحيات من الكتالوج ═══
          when r.is_full_access then
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.name_ar, p.description, p.code),
                'scope', 'organization',
                'requiresMfa', false,
                'requiresReason', false
              ) order by p.module, p.code)
              from public.permissions p
            ), '[]'::jsonb)
          -- ═══ أدوار عادية: فقط الصلاحيات المسندة عبر role_permissions ═══
          else
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.name_ar, p.description, p.code),
                'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
                'requiresReason', rp.requires_reason
              ) order by p.module, p.code)
              from public.role_permissions rp
              join public.permissions p on p.id = rp.permission_id
              where rp.role_id = r.id
            ), '[]'::jsonb)
        end,
        'assignments', (
          select count(*)
          from public.user_roles ur
          where ur.role_id = r.id
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action,
        'name', coalesce(p.name_ar, p.description, p.code),
        'nameAr', p.name_ar,
        'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'moduleAr', case p.module
          when 'access'         then 'إدارة الوصول'
          when 'assignments'    then 'التكليفات'
          when 'attendance'     then 'الحضور والانصراف'
          when 'communications' then 'الاتصالات'
          when 'documents'      then 'المستندات'
          when 'live_location'  then 'الموقع المباشر'
          when 'operations'     then 'العمليات'
          when 'organization'   then 'الهيكل التنظيمي'
          when 'people'         then 'شؤون الموظفين'
          when 'performance'    then 'الأداء'
          when 'relations'      then 'علاقات الموظفين'
          when 'reports'        then 'التقارير'
          when 'requests'       then 'الطلبات'
          when 'system'         then 'النظام'
          else p.module
        end,
        'allowedScopes', array[
          'self','direct_reports','management_descendants','selected_employees',
          'team','department','selected_departments','branch','selected_branches',
          'organization','assigned_cases','workflow_inbox',
          'records_created_by_user','archive_readonly'
        ]
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr left join public.employees e on e.id = pr.employee_id
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

-- الصلاحيات لم تتغير — نفس REVOKE/GRANT الأصلية
revoke execute on function public.get_access_admin_catalog() from public;
grant execute on function public.get_access_admin_catalog() to authenticated;

notify pgrst, 'reload schema';

commit;
