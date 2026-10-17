// ترتيب الموظفين حسب الهيكل الإداري — مطابق لمنطق shared-contracts/hierarchySort.ts
// الترتيب: المدير التنفيذي (الشيخ محمد يوسف) → السكرتير التنفيذي (يحيى السبع) → أوبريشن 1 (أبو عمار) → أوبريشن 2 (ياسر) → باقي المديرين → باقي الموظفين → تيم البنات بتوع الطاقم الطبي

import 'package:ahla_shabab_management_os/shared/access_context.dart';

/// منطق ترتيب الهيكل الإداري — يُعيّن رقماً ترتيبياً لكل موظف:
/// 1 — الشيخ محمد يوسف (على رأس الهيكل الإداري)
/// 2 — يحيى السبع (السكرتير التنفيذي)
/// 3 — أبو عمار (محمد عبدالباسط - مدير تشغيل / أوبريشن 1)
/// 4 — ياسر (ياسر فتحي نور الدين - مدير تشغيل / أوبريشن 2)
/// 5 — باقي المديرين (بما فيهم مديرا العيادات مصطفى أحمد ويوسف رسمي)
/// 6 — باقي الموظفين
/// 7 — تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
int getHierarchyRank({
  String? name,
  String? jobTitle,
  String? department,
}) {
  final n = (name ?? '').trim();
  final t = (jobTitle ?? '').trim().toLowerCase();
  final d = (department ?? '').trim().toLowerCase();

  // 1 — الشيخ محمد يوسف (على رأس الهيكل الإداري)
  final isSheikhMohamed = n.contains('الشيخ محمد') ||
      n.contains('ألشيخ محمد') ||
      n == 'محمد يوسف' ||
      n.startsWith('محمد يوسف ') ||
      t.contains('مدير تنفيذي') ||
      (t.contains('مدير') && t.contains('تنفيذي')) ||
      t == 'ceo' ||
      t.contains('chief executive');
  if (isSheikhMohamed) {
    return 1;
  }

  // 2 — يحيى السبع (السكرتير التنفيذي)
  if (n.contains('يحيى') ||
      n.contains('يحيي') ||
      n.contains('السبع') ||
      t.contains('سكرتير') ||
      t.contains('المساعد التنفيذي') ||
      t.contains('executive secretary') ||
      t.contains('executive assistant')) {
    return 2;
  }

  // 3 — أبو عمار (محمد عبدالباسط - مدير تشغيل / أوبريشن 1)
  final isAbuAmmar = n.contains('ابو عمار') ||
      n.contains('أبو عمار') ||
      n.startsWith('محمد عبدالباسط') ||
      n.startsWith('محمد عبد الباسط') ||
      ((t.contains('أوبريشن') || t.contains('تشغيل') || t.contains('operations')) &&
          (t.contains('1') || t.contains('أول') || t.contains('رئيسي')));
  if (isAbuAmmar) {
    return 3;
  }

  // 4 — ياسر (ياسر فتحي نور الدين - مدير تشغيل / أوبريشن 2)
  if (n.contains('ياسر') ||
      ((t.contains('أوبريشن') || t.contains('تشغيل') || t.contains('operations')) &&
          (t.contains('2') || t.contains('ثاني') || t.contains('مساعد')))) {
    return 4;
  }

  // هل هو من مديري العيادات (مصطفى أحمد كمال الدين، يوسف رسمي شعبان)؟
  final isMedicalManager = n.contains('مصطفي أحمد') ||
      n.contains('مصطفى أحمد') ||
      n.contains('يوسف رسمي') ||
      t.contains('مدير مجمع') ||
      (d.contains('عياد') && t.contains('مدير'));

  // 7 — تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
  if (!isMedicalManager) {
    if (d.contains('عياد') ||
        t.contains('تمريض') ||
        t.contains('معمل') ||
        t.contains('دكتورة المعمل') ||
        t.contains('استقبال') ||
        n.contains('رحاب مجدي') ||
        n.contains('ساميه') ||
        n.contains('سامية') ||
        n.contains('سمر احمد') ||
        n.contains('سمر أحمد') ||
        n.contains('سميرة سعيد') ||
        n.contains('سميره سعيد') ||
        n.contains('شروق عبد العليم') ||
        n.contains('شروق عبدالعليم')) {
      return 7;
    }
  }

  // 5 — باقي المديرين (يشمل مديري العيادات مصطفى أحمد ويوسف رسمي، وباقي مديري الجمعية)
  if (t.contains('مدير') ||
      t.contains('manager') ||
      t.contains('head') ||
      t.contains('lead') ||
      t.contains('director') ||
      t.contains('رئيس') ||
      t.contains('نائب') ||
      t.contains('وكيل') ||
      isMedicalManager) {
    return 5;
  }

  // 6 — باقي الموظفين
  return 6;
}

/// هل هذا الموظف من تيم البنات بتوع الطاقم الطبي؟
bool isClinicGirl({
  String? name,
  String? jobTitle,
  String? department,
}) {
  return getHierarchyRank(
    name: name,
    jobTitle: jobTitle,
    department: department,
  ) == 7;
}

/// هل يحق للمستخدم الحالي رؤية تيم البنات بتوع الطاقم الطبي؟
/// القاعدة المعتمدة: "مش بيظهرو لي اي حد غير مديرهم مصطفي احمد ويوسف رسمي ويحيى والشيخ محمد وهكذه"
bool canViewClinicGirls(AccessContext? access) {
  if (access == null) return false;
  final name = access.displayName.trim();
  // 1. الشيخ محمد يوسف
  if (name.contains('محمد يوسف')) return true;
  // 2. يحيى السبع
  if (name.contains('يحيى') || name.contains('يحيي') || name.contains('السبع')) {
    return true;
  }
  // 3. مصطفى أحمد كمال الدين
  if (name.contains('مصطفى أحمد') ||
      name.contains('مصطفي أحمد') ||
      name.contains('كمال الدين') ||
      access.employeeId == '4120ce3a-8999-453e-8d9d-acd8f3b5f04c') {
    return true;
  }
  // 4. يوسف رسمي شعبان
  if (name.contains('يوسف رسمي') ||
      access.employeeId == 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6') {
    return true;
  }
  // 5. موظفة الطاقم الطبي نفسها (ترى زميلاتها)
  if (access.isClinicStaff) return true;

  // الأدوار القيادية والإدارية العليا
  const allowedRoles = {
    'admin',
    'system-admin',
    'executive-director',
    'executive-secretary',
    'executive',
    'clinics-manager',
    'hr-manager',
    'hr-specialist',
  };
  return access.roles.any(allowedRoles.contains);
}

/// تصفية القائمة واستبعاد تيم البنات إذا كان المستخدم غير مصرح له
List<T> filterVisibleEmployees<T>(
  List<T> items, {
  required AccessContext? access,
  required String Function(T) getName,
  String Function(T)? getJobTitle,
  String Function(T)? getDepartment,
}) {
  if (canViewClinicGirls(access)) return items;
  return items.where((item) {
    return !isClinicGirl(
      name: getName(item),
      jobTitle: getJobTitle?.call(item),
      department: getDepartment?.call(item),
    );
  }).toList();
}

/// مقارنة ترتيب حسب الهيكل الإداري — تُمرَّر إلى List.sort()
int hierarchyCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final nameA = (a['fullNameAr'] ?? a['name']) as String? ?? '';
  final nameB = (b['fullNameAr'] ?? b['name']) as String? ?? '';
  final titleA = (a['jobTitle'] ?? a['job_title']) as String?;
  final titleB = (b['jobTitle'] ?? b['job_title']) as String?;
  final deptA = (a['department'] ?? a['departmentName'] ?? a['department_name']) as String?;
  final deptB = (b['department'] ?? b['departmentName'] ?? b['department_name']) as String?;

  final ra = getHierarchyRank(name: nameA, jobTitle: titleA, department: deptA);
  final rb = getHierarchyRank(name: nameB, jobTitle: titleB, department: deptB);
  if (ra != rb) return ra - rb;
  // داخل نفس المستوى — ترتيب أبجدي عربي بالاسم
  return nameA.compareTo(nameB);
}

/// ترتيب مصفوفة موظفين حسب الهيكل الإداري (تُعيد مصفوفة جديدة)
List<T> sortByHierarchy<T>(
  List<T> items,
  String Function(T) getJobTitle,
  String Function(T) getName, {
  String Function(T)? getDepartment,
}) {
  return [...items]..sort((a, b) {
      final nameA = getName(a);
      final nameB = getName(b);
      final titleA = getJobTitle(a);
      final titleB = getJobTitle(b);
      final deptA = getDepartment != null ? getDepartment(a) : null;
      final deptB = getDepartment != null ? getDepartment(b) : null;

      final ra = getHierarchyRank(name: nameA, jobTitle: titleA, department: deptA);
      final rb = getHierarchyRank(name: nameB, jobTitle: titleB, department: deptB);
      if (ra != rb) return ra - rb;
      return nameA.compareTo(nameB);
    });
}

