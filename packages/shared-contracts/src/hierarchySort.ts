// ترتيب الموظفين حسب الهيكل الإداري — يُستخدم في ويب وموبايل
// الترتيب: المدير التنفيذي → السكرتير التنفيذي → أوبريشن 1 → أوبريشن 2 → باقي المديرين → باقي الموظفين

/** منطق ترتيب الهيكل الإداري — يُعيّن رقماً ترتيبياً لكل مسمى وظيفي. */
function hierarchyRank(jobTitle: string | null | undefined): number {
  if (!jobTitle) return 1000;
  const t = jobTitle.trim().toLowerCase();

  // 1 — المدير التنفيذي
  if (t.includes('مدير تنفيذي') || t === 'ceo' || t.includes('chief executive')) return 1;

  // 2 — السكرتير التنفيذي
  if (t.includes('سكرتير تنفيذي') || t.includes('المساعد التنفيذي') || t.includes('executive secretary') || t.includes('executive assistant')) return 2;

  // 3 — أوبريشن 1 (مدير العمليات الأول / رئيسي)
  if (
    (t.includes('أوبريشن') && (t.includes('أول') || t.includes('رئيسي'))) ||
    (t.includes('operations') && (t.includes('1') || t.includes('head') || t.includes('lead') || t.includes('senior'))) ||
    (t.includes('مدير عمليات') && (t.includes('أول') || t.includes('رئيسي')))
  ) return 3;

  // 4 — أوبريشن 2 (مدير العمليات الثاني / مساعد)
  if (
    (t.includes('أوبريشن') && (t.includes('ثاني') || t.includes('مساعد'))) ||
    (t.includes('operations') && (t.includes('2') || t.includes('assistant') || t.includes('junior'))) ||
    (t.includes('مدير عمليات') && (t.includes('ثاني') || t.includes('مساعد')))
  ) return 4;

  // 5 — أي مدير (مدير عام، مدير إداري،مدير مالي، etc.)
  if (t.includes('مدير') || t.includes('manager') || t.includes('head') || t.includes('lead') || t.includes('director')) return 5;

  // 6 — نائب المدير / وكيل
  if (t.includes('نائب') || t.includes('وكيل') || t.includes('deputy') || t.includes('vice')) return 6;

  // 7 — أخصائي أول / مستشار
  if (t.includes('أول') || t.includes('senior') || t.includes('consultant') || t.includes('مستشار')) return 7;

  // 8 — باقي الموظفين
  return 8;
}

/**
 * دالة مقارنة ترتيب حسب الهيكل الإداري — تُمرَّر إلى Array.sort()
 * المخرج: رقم سالب/صفر/موجب مثل compareFn القياسية.
 */
export function hierarchyCompare(a: { jobTitle?: string | null }, b: { jobTitle?: string | null }): number {
  const ra = hierarchyRank(a.jobTitle);
  const rb = hierarchyRank(b.jobTitle);
  if (ra !== rb) return ra - rb;
  // داخل نفس المستوى — ترتيب أبجدي عربي
  return (a.jobTitle ?? '').localeCompare(b.jobTitle ?? '', 'ar');
}

/**
 * ترتيب مصفوفة موظفين حسب الهيكل الإداري (يُعدّل المصفوفة الأصلية + يُعيدها).
 */
export function sortByHierarchy<T extends { jobTitle?: string | null }>(items: T[]): T[] {
  return [...items].sort(hierarchyCompare);
}
