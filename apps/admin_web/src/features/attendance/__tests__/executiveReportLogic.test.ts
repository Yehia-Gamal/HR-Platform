import { describe, expect, it } from 'vitest';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import {
  calculateTrueLateMinutes,
  classifyEmployee,
  computeDepartmentSummaries,
  computeEndOfDayMetrics,
  computeExecutiveMetrics,
  formatShiftBadge,
  generateComparativeAudit,
  generateSecurityVerificationCode,
  parseShiftWindow,
  sanitizeLeaveReason,
  sanitizeMissionPurpose,
} from '../executiveReportLogic';

const createMockItem = (overrides: Partial<AttendanceRosterItem>): AttendanceRosterItem => ({
  employeeId: '00000000-0000-0000-0000-000000000000',
  employeeName: 'موظف تجريبي',
  employeeCode: 'EMP-001',
  departmentName: 'إدارة عامة',
  status: 'present',
  lateMinutes: 0,
  firstCheckIn: null,
  lastCheckOut: null,
  shiftName: 'الدوام الأساسي (10 ص – 6 م)',
  locationRequestStatus: null,
  ...overrides,
});

describe('executiveReportLogic', () => {
  it('حساب التأخير الحقيقي لصف 21: وردية 10 ص وبصمة 12:34 م = 154 دقيقة (ساعتان و34 دقيقة)', () => {
    const shift = parseShiftWindow('الدوام الأساسي (10 ص – 6 م)');
    expect(shift).not.toBeNull();
    expect(shift?.startHour).toBe(10);
    expect(shift?.startMinute).toBe(0);

    // بصمة الساعة 12:34 م (توقيت مصر)
    const checkIn = '2026-10-19T12:34:00+03:00';
    const late = calculateTrueLateMinutes(checkIn, shift);
    expect(late).toBe(154); // 2 hours and 34 minutes
  });

  it('حساب التأخير لصف 5: وردية العيادات المسائية 3 م – 11 م وحضور 2:22 م = 0 دقيقة (حضر مبكراً في الموعد)', () => {
    const shift = parseShiftWindow('الوردية المسائية (3 ع – 11 م)');
    expect(shift).not.toBeNull();
    expect(shift?.startHour).toBe(15);

    // بصمة الساعة 2:22 م
    const checkIn = '2026-10-19T14:22:00+03:00';
    const late = calculateTrueLateMinutes(checkIn, shift);
    expect(late).toBe(0); // مبكر
  });

  it('استبعاد غير المجدولين ومن لم يبدأ دوامهم بعد من الغياب غير المبرر عند توليد التقرير الساعة 2:25 م', () => {
    // 2:25 م = 14:25 = 14 * 60 + 25 = 865 دقيقة من منتصف الليل
    const currentMinutes = 14 * 60 + 25;

    // موظف بلا وردية مقررة
    const unscheduledEmp = createMockItem({
      employeeId: '11111111-1111-1111-1111-111111111111',
      employeeName: 'طارق سيد إبراهيم',
      departmentName: 'إدارة الحركة',
      status: 'unexcused_absent',
      shiftName: null,
    });
    const c1 = classifyEmployee(unscheduledEmp, currentMinutes);
    expect(c1.category).toBe('unscheduled_rest');

    // موظف عيادات ورديته 3 م ولم يأتِ وقته بعد (الساعة 2:25 م)
    const clinicEmp = createMockItem({
      employeeId: '22222222-2222-2222-2222-222222222222',
      employeeName: 'رحاب عاطف يوسف أحمد',
      departmentName: 'إدارة العيادات الطبية',
      status: 'unexcused_absent',
      shiftName: 'فترة العيادات المسائية (3 ع – 11 م)',
      isClinicMedicalStaff: true,
    });
    const c2 = classifyEmployee(clinicEmp, currentMinutes);
    expect(c2.category).toBe('shift_not_started');

    // موظف ورديته بدأت (10 ص) ولم يحضر حتى 2:25 م وبلا عذر
    const realAbsentEmp = createMockItem({
      employeeId: '33333333-3333-3333-3333-333333333333',
      employeeName: 'مصطفى أحمد خيري',
      departmentName: 'إدارة العلاقات العامة',
      status: 'unexcused_absent',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
    });
    const c3 = classifyEmployee(realAbsentEmp, currentMinutes);
    expect(c3.category).toBe('unexcused_absent');

    // حساب المؤشرات: الغياب الحقيقي 1 فقط، وغير المجدولين لا يضخمون الغياب
    const metrics = computeExecutiveMetrics([c1, c2, c3]);
    expect(metrics.unexcusedAbsent).toBe(1);
    expect(metrics.shiftNotStartedYet).toBe(1);
    expect(metrics.unscheduledRest).toBe(1);
  });

  it('فصل المأموريات: تمييز من خرج قبل الاعتماد (طلب معلق) عن المعتمد رسمياً', () => {
    const currentMinutes = 14 * 60 + 25;

    const pendingMissionEmp = createMockItem({
      employeeId: '44444444-4444-4444-4444-444444444444',
      employeeName: 'حاتم محمد سالم',
      departmentName: 'إدارة الحركة',
      status: 'present',
      firstCheckIn: '2026-10-19T09:44:00+03:00',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
      hasPendingRequest: true,
      pendingRequestType: 'mission',
      pendingRequestNumber: 5544,
      pendingRequestTitle: 'مأمورية أورمان أكتوبر',
    });

    const classified = classifyEmployee(pendingMissionEmp, currentMinutes);
    expect(classified.category).toBe('present_mission_pending');
    expect(classified.isPendingMission).toBe(true);

    const metrics = computeExecutiveMetrics([classified]);
    expect(metrics.missionsPendingLeft).toBe(1);
    expect(metrics.needsDecisionCount).toBeGreaterThanOrEqual(1);
  });

  it('حجب التفاصيل الطبية الشخصية لأقارب الموظف من التقرير العام لحماية الخصوصية', () => {
    const rawReason = 'طبيب مع والدته بعمل عملية مياه بيضاء';
    const sanitized = sanitizeLeaveReason(rawReason, 'إجازة اعتيادية');
    expect(sanitized).not.toContain('عملية');
    expect(sanitized).not.toContain('مياه بيضاء');
    expect(sanitized).toContain('إجازة اعتيادية مسجلة نظامياً');
  });

  it('تلخيص وتصحيح نصوص أغراض ووجهات المأموريات', () => {
    const raw = sanitizeMissionPurpose('مأمورية', 'نازل اشتري سلك ووصلات');
    expect(raw.purpose).toContain('شراء مستلزمات عمل');
    expect(raw.purpose).not.toContain('نازل اشتري');
  });

  it('تنسيق نصوص الورديات وتوحيد "3 ع" إلى "3 م" وتوضيح وسم العيادات', () => {
    const formatted = formatShiftBadge('فترة العيادات المسائية (3 ع – 11 م)');
    expect(formatted).toBe('فترة العيادات المسائية (3 م – 11 م)');

    const clinicBadge = formatShiftBadge('عيادات (١)');
    expect(clinicBadge).toBe('العيادات الطبية (الفترة المسائية 3 م – 11 م)');

    const clinicBadgeHindi = formatShiftBadge('عيادات (1)');
    expect(clinicBadgeHindi).toBe('العيادات الطبية (الفترة المسائية 3 م – 11 م)');
  });

  it('توليد كود أمني غير متوقع مرتبط بـ Hash المحتوى', () => {
    const res1 = generateSecurityVerificationCode('2026-10-19', 32, 21, 1);
    const res2 = generateSecurityVerificationCode('2026-10-19', 32, 21, 1);
    const resDifferent = generateSecurityVerificationCode('2026-10-19', 32, 20, 2);

    expect(res1.code).toBe(res2.code);
    expect(res1.code).not.toBe(resDifferent.code);
    expect(res1.code).toContain('EXEC-20261019-');
    expect(res1.code.length).toBeGreaterThan(15);
  });

  it('تجميع ملخص الإدارات بشكل دقيق', () => {
    const currentMinutes = 14 * 60 + 25;
    const emp1 = createMockItem({
      employeeId: '11111111-1111-1111-1111-111111111111',
      employeeName: 'أحمد',
      departmentName: 'إدارة المشتريات',
      status: 'present',
      firstCheckIn: '2026-10-19T09:50:00+03:00',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
    });
    const emp2 = createMockItem({
      employeeId: '22222222-2222-2222-2222-222222222222',
      employeeName: 'محمود',
      departmentName: 'إدارة المشتريات',
      status: 'unexcused_absent',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
    });

    const summaries = computeDepartmentSummaries([classifyEmployee(emp1, currentMinutes), classifyEmployee(emp2, currentMinutes)]);

    expect(summaries.length).toBe(1);
    expect(summaries[0].departmentName).toBe('إدارة المشتريات');
    expect(summaries[0].total).toBe(2);
    expect(summaries[0].present).toBe(1);
    expect(summaries[0].absent).toBe(1);
    expect(summaries[0].commitmentRate).toBe(50);
  });

  it('حساب مؤشرات إغلاق نهاية اليوم: الانصراف المبكر، بصمة الانصراف الناقصة، وساعات العمل', () => {
    // نهاية اليوم: الساعة 19:00 (7:00 م) = 19 * 60 = 1140 دقيقة
    const endOfDayMinutes = 19 * 60;

    // موظف انصرف مبكراً: ورديته تنتهي 6:00 م (18:00) وانصرف 4:30 م (16:30)
    const earlyEmp = createMockItem({
      employeeId: '55555555-5555-5555-5555-555555555555',
      employeeName: 'سامي كمال',
      departmentName: 'إدارة تكنولوجيا المعلومات',
      status: 'present',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
      firstCheckIn: '2026-10-19T10:00:00+03:00',
      lastCheckOut: '2026-10-19T16:30:00+03:00',
    });

    // موظف حضر ولم يسجل انصراف والوردية انتهت (بصمة انصراف ناقصة)
    const missingOutEmp = createMockItem({
      employeeId: '66666666-6666-6666-6666-666666666666',
      employeeName: 'إبراهيم حسن',
      departmentName: 'إدارة المالية',
      status: 'present',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
      firstCheckIn: '2026-10-19T09:55:00+03:00',
      lastCheckOut: null,
    });

    // موظف عمل ساعات إضافية (من 9:00 ص حتى 7:00 م = 10 ساعات)
    const overtimeEmp = createMockItem({
      employeeId: '77777777-7777-7777-7777-777777777777',
      employeeName: 'عمر خالد',
      departmentName: 'إدارة العمليات',
      status: 'present',
      shiftName: 'الدوام الأساسي (10 ص – 6 م)',
      firstCheckIn: '2026-10-19T09:00:00+03:00',
      lastCheckOut: '2026-10-19T19:00:00+03:00',
    });

    const classified = [
      classifyEmployee(earlyEmp, endOfDayMinutes),
      classifyEmployee(missingOutEmp, endOfDayMinutes),
      classifyEmployee(overtimeEmp, endOfDayMinutes),
    ];

    const eod = computeEndOfDayMetrics(classified, endOfDayMinutes);

    expect(eod.totalCheckedIn).toBe(3);
    expect(eod.completedCheckouts).toBe(2);
    expect(eod.missingCheckoutsCount).toBe(1);
    expect(eod.missingCheckoutList[0].item.employeeName).toBe('إبراهيم حسن');

    expect(eod.earlyDeparturesCount).toBe(1);
    expect(eod.earlyDepartureList[0].item.employeeName).toBe('سامي كمال');
    expect(eod.earlyDepartureList[0].earlyDepartureMinutes).toBe(90); // 1.5 hours early

    expect(eod.overtimeCount).toBe(1);
    expect(eod.overtimeList[0].item.employeeName).toBe('عمر خالد');
    expect(eod.overtimeList[0].overtimeMinutes).toBe(120); // 2 hours overtime
  });

  it('توليد بنود التدقيق المقارن قبل وبعد التصحيح المنطقي', () => {
    const metrics = computeExecutiveMetrics([]);
    const audit = generateComparativeAudit(metrics);
    expect(audit.length).toBeGreaterThanOrEqual(6);
    expect(audit.some((a) => a.metric.includes('الغياب غير المبرر'))).toBe(true);
    expect(audit.some((a) => a.metric.includes('الصف 21'))).toBe(true);
    expect(audit.some((a) => a.metric.includes('الصف 5'))).toBe(true);
  });
});
