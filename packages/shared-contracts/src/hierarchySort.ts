// ترتيب الموظفين حسب الهيكل الإداري — يُستخدم في ويب وموبايل
// الترتيب: المدير التنفيذي (الشيخ محمد يوسف) → السكرتير التنفيذي (يحيى السبع) → أوبريشن 1 (أبو عمار) → أوبريشن 2 (ياسر) → باقي المديرين → باقي الموظفين → تيم البنات بتوع الطاقم الطبي

export interface HierarchySortable {
  name?: string | null;
  fullNameAr?: string | null;
  jobTitle?: string | null;
  department?: string | null;
  departmentName?: string | null;
  employeeCode?: string | null;
}

/**
 * منطق ترتيب الهيكل الإداري — يُعيّن رقماً ترتيبياً لكل موظف:
 * 1 — الشيخ محمد يوسف (على رأس الهيكل الإداري)
 * 2 — يحيى السبع (السكرتير التنفيذي)
 * 3 — أبو عمار (محمد عبدالباسط - أوبريشن 1)
 * 4 — ياسر (ياسر فتحي نور الدين - أوبريشن 2)
 * 5 — باقي المديرين (بما فيهم مديرا العيادات مصطفى أحمد ويوسف رسمي)
 * 6 — باقي الموظفين
 * 7 — تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
 */
export function getHierarchyRank(item: HierarchySortable): number {
  const name = (item.fullNameAr || item.name || '').trim();
  const title = (item.jobTitle || '').trim().toLowerCase();
  const dept = (item.departmentName || item.department || '').trim().toLowerCase();

  // 1 — الشيخ محمد يوسف (على رأس الهيكل الإداري)
  const isSheikhMohamed =
    name.includes('الشيخ محمد') ||
    name.includes('ألشيخ محمد') ||
    name === 'محمد يوسف' ||
    name.startsWith('محمد يوسف ') ||
    title.includes('مدير تنفيذي') ||
    (title.includes('مدير') && title.includes('تنفيذي')) ||
    title === 'ceo' ||
    title.includes('chief executive');
  if (isSheikhMohamed) {
    return 1;
  }

  // 2 — يحيى السبع (السكرتير التنفيذي)
  if (
    name.includes('يحيى') ||
    name.includes('يحيي') ||
    name.includes('السبع') ||
    title.includes('سكرتير') ||
    title.includes('المساعد التنفيذي') ||
    title.includes('executive secretary') ||
    title.includes('executive assistant')
  ) {
    return 2;
  }

  // 3 — أبو عمار (محمد عبدالباسط - مدير تشغيل / أوبريشن 1)
  const isAbuAmmar =
    name.includes('ابو عمار') ||
    name.includes('أبو عمار') ||
    name.startsWith('محمد عبدالباسط') ||
    name.startsWith('محمد عبد الباسط') ||
    ((title.includes('أوبريشن') || title.includes('تشغيل') || title.includes('operations')) &&
      (title.includes('1') || title.includes('أول') || title.includes('رئيسي')));

  if (isAbuAmmar) {
    return 3;
  }

  // 4 — ياسر (ياسر فتحي نور الدين - مدير تشغيل / أوبريشن 2)
  if (
    name.includes('ياسر') ||
    ((title.includes('أوبريشن') || title.includes('تشغيل') || title.includes('operations')) &&
      (title.includes('2') || title.includes('ثاني') || title.includes('مساعد')))
  ) {
    return 4;
  }

  // هل هو من مديري العيادات (مصطفى أحمد كمال الدين، يوسف رسمي شعبان)؟
  const isMedicalManager =
    name.includes('مصطفي أحمد') ||
    name.includes('مصطفى أحمد') ||
    name.includes('يوسف رسمي') ||
    title.includes('مدير مجمع') ||
    (dept.includes('عياد') && title.includes('مدير'));

  // 7 — تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
  if (!isMedicalManager) {
    if (
      dept.includes('عياد') ||
      title.includes('تمريض') ||
      title.includes('معمل') ||
      title.includes('دكتورة المعمل') ||
      title.includes('استقبال') ||
      name.includes('رحاب مجدي') ||
      name.includes('ساميه') ||
      name.includes('سامية') ||
      name.includes('سمر احمد') ||
      name.includes('سمر أحمد') ||
      name.includes('سميرة سعيد') ||
      name.includes('سميره سعيد') ||
      name.includes('شروق عبد العليم') ||
      name.includes('شروق عبدالعليم')
    ) {
      return 7;
    }
  }

  // 5 — باقي المديرين (يشمل مديري العيادات مصطفى أحمد ويوسف رسمي، وباقي مديري الجمعية)
  if (
    title.includes('مدير') ||
    title.includes('manager') ||
    title.includes('head') ||
    title.includes('lead') ||
    title.includes('director') ||
    title.includes('رئيس') ||
    title.includes('نائب') ||
    title.includes('وكيل') ||
    isMedicalManager
  ) {
    return 5;
  }

  // 6 — باقي الموظفين
  return 6;
}

/**
 * فحص هل الموظف من تيم البنات بتوع الطاقم الطبي
 */
export function isClinicGirl(item: HierarchySortable): boolean {
  return getHierarchyRank(item) === 7;
}

/**
 * دالة مقارنة ترتيب حسب الهيكل الإداري — تُمرَّر إلى Array.sort()
 */
export function hierarchyCompare(a: HierarchySortable, b: HierarchySortable): number {
  const ra = getHierarchyRank(a);
  const rb = getHierarchyRank(b);
  if (ra !== rb) return ra - rb;
  // داخل نفس المستوى — ترتيب أبجدي عربي بالاسم
  const nameA = (a.fullNameAr || a.name || '').trim();
  const nameB = (b.fullNameAr || b.name || '').trim();
  return nameA.localeCompare(nameB, 'ar');
}

/**
 * ترتيب مصفوفة موظفين حسب الهيكل الإداري (يُعيد مصفوفة مرتبة جديدة).
 */
export function sortByHierarchy<T extends HierarchySortable>(items: T[]): T[] {
  return [...items].sort(hierarchyCompare);
}

