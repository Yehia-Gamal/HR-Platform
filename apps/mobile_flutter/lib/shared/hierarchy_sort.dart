// ترتيب الموظفين حسب الهيكل الإداري — مطابق لمنطق shared-contracts/hierarchySort.ts
// الترتيب: المدير التنفيذي → السكرتير التنفيذي → أوبريشن 1 → أوبريشن 2 → باقي المديرين → باقي الموظفين

int _hierarchyRank(String? jobTitle) {
  if (jobTitle == null || jobTitle.isEmpty) return 1000;
  final t = jobTitle.trim().toLowerCase();

  // 1 — المدير التنفيذي
  if (t.contains('مدير تنفيذي') || t == 'ceo' || t.contains('chief executive')) {
    return 1;
  }

  // 2 — السكرتير التنفيذي
  if (t.contains('سكرتير تنفيذي') ||
      t.contains('المساعد التنفيذي') ||
      t.contains('executive secretary') ||
      t.contains('executive assistant')) {
    return 2;
  }

  // 3 — أوبريشن 1 (مدير العمليات الأول / رئيسي)
  if ((t.contains('أوبريشن') &&
          (t.contains('أول') || t.contains('رئيسي'))) ||
      (t.contains('operations') &&
          (t.contains('1') ||
              t.contains('head') ||
              t.contains('lead') ||
              t.contains('senior'))) ||
      (t.contains('مدير عمليات') &&
          (t.contains('أول') || t.contains('رئيسي')))) {
    return 3;
  }

  // 4 — أوبريشن 2 (مدير العمليات الثاني / مساعد)
  if ((t.contains('أوبريشن') &&
          (t.contains('ثاني') || t.contains('مساعد'))) ||
      (t.contains('operations') &&
          (t.contains('2') ||
              t.contains('assistant') ||
              t.contains('junior'))) ||
      (t.contains('مدير عمليات') &&
          (t.contains('ثاني') || t.contains('مساعد')))) {
    return 4;
  }

  // 5 — أي مدير (مدير عام، مدير إداري، مدير مالي، etc.)
  if (t.contains('مدير') ||
      t.contains('manager') ||
      t.contains('head') ||
      t.contains('lead') ||
      t.contains('director')) {
    return 5;
  }

  // 6 — نائب المدير / وكيل
  if (t.contains('نائب') ||
      t.contains('وكيل') ||
      t.contains('deputy') ||
      t.contains('vice')) {
    return 6;
  }

  // 7 — أخصائي أول / مستشار
  if (t.contains('أول') ||
      t.contains('senior') ||
      t.contains('consultant') ||
      t.contains('مستشار')) {
    return 7;
  }

  // 8 — باقي الموظفين
  return 8;
}

/// مقارنة ترتيب حسب الهيكل الإداري — تُمرَّر إلى List.sort()
int hierarchyCompare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ra = _hierarchyRank(a['jobTitle'] as String?);
  final rb = _hierarchyRank(b['jobTitle'] as String?);
  if (ra != rb) return ra - rb;
  // داخل نفس المستوى — ترتيب أبجدي عربي
  return (a['fullNameAr'] as String? ?? '').compareTo(
    b['fullNameAr'] as String? ?? '',
  );
}

/// ترتيب مصفوفة موظفين حسب الهيكل الإداري (تُعيد مصفوفة جديدة)
List<T> sortByHierarchy<T>(List<T> items, String Function(T) getJobTitle, String Function(T) getName) {
  return [...items]..sort((a, b) {
      final ra = _hierarchyRank(getJobTitle(a));
      final rb = _hierarchyRank(getJobTitle(b));
      if (ra != rb) return ra - rb;
      return getName(a).compareTo(getName(b));
    });
}
