import { describe, expect, it } from 'vitest';
import { getHierarchyRank, isClinicGirl, hierarchyCompare, sortByHierarchy } from './hierarchySort';

describe('hierarchySort', () => {
  it('assigns correct ranks across all 7 hierarchy tiers', () => {
    // Rank 1: الشيخ محمد يوسف
    expect(getHierarchyRank({ fullNameAr: 'الشيخ محمد يوسف', jobTitle: 'المدير التنفيذي لجمعية خواطر' })).toBe(1);
    expect(getHierarchyRank({ fullNameAr: 'محمد يوسف زكي عبد الرحيم', jobTitle: 'مدير تنفيذي' })).toBe(1);

    // Rank 2: يحيى السبع
    expect(getHierarchyRank({ fullNameAr: 'يحيى جمال السبع', jobTitle: 'السكرتير التنفيذي' })).toBe(2);
    expect(getHierarchyRank({ fullNameAr: 'يحيى السبع', jobTitle: 'سكرتير تنفيذي' })).toBe(2);

    // Rank 3: أبو عمار
    expect(getHierarchyRank({ fullNameAr: 'محمد عبد الباسط محمد', jobTitle: 'مدير تشغيل' })).toBe(3);
    expect(getHierarchyRank({ fullNameAr: 'أبو عمار', jobTitle: 'مدير العمليات' })).toBe(3);

    // Rank 4: ياسر
    expect(getHierarchyRank({ fullNameAr: 'ياسر فتحي نور الدين', jobTitle: 'مدير تشغيل' })).toBe(4);

    // Rank 5: باقي المديرين
    expect(getHierarchyRank({ fullNameAr: 'مصطفى أحمد كمال الدين', jobTitle: 'مدير العيادات' })).toBe(5);
    expect(getHierarchyRank({ fullNameAr: 'يوسف رسمي شعبان', jobTitle: 'مدير العيادات' })).toBe(5);
    expect(getHierarchyRank({ fullNameAr: 'بلال نبيل', jobTitle: 'مدير الميديا' })).toBe(5);

    // Rank 6: باقي الموظفين
    expect(getHierarchyRank({ fullNameAr: 'طارق سيد محمد', jobTitle: 'سائق' })).toBe(6);
    expect(getHierarchyRank({ fullNameAr: 'عمار محمد عبد الباسط', jobTitle: 'أخصائي شؤون إدارية' })).toBe(6);
    expect(getHierarchyRank({ fullNameAr: 'عبد الملك محمد يوسف', jobTitle: 'متدرب تصميم' })).toBe(6);

    // Rank 7: بنات الطاقم الطبي
    expect(getHierarchyRank({ fullNameAr: 'رحاب مجدي', departmentName: 'العيادات' })).toBe(7);
    expect(getHierarchyRank({ fullNameAr: 'سامية أشرف', jobTitle: 'تمريض عيادات' })).toBe(7);
    expect(getHierarchyRank({ fullNameAr: 'سمر أحمد', department: 'العيادات الطبية' })).toBe(7);
    expect(getHierarchyRank({ fullNameAr: 'سميرة سعيد', jobTitle: 'طاقم طبي' })).toBe(7);
    expect(getHierarchyRank({ fullNameAr: 'شروق عبد العليم', department: 'العيادات' })).toBe(7);
    expect(getHierarchyRank({ fullNameAr: 'نجلاء عادل', department: 'العيادات' })).toBe(7);
  });

  it('detects clinic girls accurately', () => {
    expect(isClinicGirl({ fullNameAr: 'رحاب مجدي' })).toBe(true);
    expect(isClinicGirl({ fullNameAr: 'سامية أشرف' })).toBe(true);
    expect(isClinicGirl({ fullNameAr: 'طارق سيد' })).toBe(false);
    expect(isClinicGirl({ fullNameAr: 'مصطفى أحمد كمال الدين' })).toBe(false);
  });

  it('sorts a list strictly by hierarchy tiers', () => {
    const list = [
      { fullNameAr: 'رحاب مجدي', jobTitle: 'تمريض', departmentName: 'العيادات' },
      { fullNameAr: 'طارق سيد', jobTitle: 'سائق' },
      { fullNameAr: 'ياسر فتحي', jobTitle: 'مدير تشغيل' },
      { fullNameAr: 'الشيخ محمد يوسف', jobTitle: 'المدير التنفيذي' },
      { fullNameAr: 'يحيى جمال السبع', jobTitle: 'السكرتير التنفيذي' },
      { fullNameAr: 'مصطفى أحمد كمال الدين', jobTitle: 'مدير العيادات' },
      { fullNameAr: 'محمد عبد الباسط (أبو عمار)', jobTitle: 'مدير تشغيل' },
    ];

    const sorted = sortByHierarchy(list);

    expect(sorted[0]?.fullNameAr).toBe('الشيخ محمد يوسف');
    expect(sorted[1]?.fullNameAr).toBe('يحيى جمال السبع');
    expect(sorted[2]?.fullNameAr).toBe('محمد عبد الباسط (أبو عمار)');
    expect(sorted[3]?.fullNameAr).toBe('ياسر فتحي');
    expect(sorted[4]?.fullNameAr).toBe('مصطفى أحمد كمال الدين');
    expect(sorted[5]?.fullNameAr).toBe('طارق سيد');
    expect(sorted[6]?.fullNameAr).toBe('رحاب مجدي');
  });
});
