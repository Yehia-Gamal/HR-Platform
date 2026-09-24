import { describe, it, expect } from 'vitest';
import type { NotificationItem } from '@ahla/shared-contracts';
import { canonicalEntityType, isInternalAppPath, notificationTargetPath, notificationWorkspaceFromPath, parseActionDeepLink } from './notificationTarget';

const item = (partial: Partial<NotificationItem>): NotificationItem => ({
  id: '57000000-0000-4000-8000-000000000001',
  title: 'إشعار',
  body: null,
  category: 'general',
  priority: 'normal',
  actionUrl: null,
  entityType: null,
  entityId: null,
  isRead: false,
  createdAt: '2026-01-01T00:00:00.000Z',
  ...partial,
});

describe('isInternalAppPath', () => {
  it('يقبل المسارات الداخلية ضمن مساحات العمل', () => {
    expect(isInternalAppPath('/admin/disputes?case=abc')).toBe(true);
    expect(isInternalAppPath('/hr/requests')).toBe(true);
    expect(isInternalAppPath('/committee/disputes')).toBe(true);
    expect(isInternalAppPath('/me/penalties')).toBe(true);
  });

  it('يرفض مسارات الموبايل التي لا وجود لها في راوتر الويب', () => {
    // هذه كانت تُمرَّر كما هي فيبتلعها catch-all ويُعاد المستخدم للوحة التحكم.
    expect(isInternalAppPath('/attendance')).toBe(false);
    expect(isInternalAppPath('/reports/attendance')).toBe(false);
    expect(isInternalAppPath('/action/request/abc')).toBe(false);
  });

  it('يرفض روابط deep link الكاملة و البروتوكولات المخصصة', () => {
    expect(isInternalAppPath('https://ahla-shabab-management-os.vercel.app/action/request/abc')).toBe(false);
    expect(isInternalAppPath('ahlashabab://action/request/abc')).toBe(false);
    expect(isInternalAppPath('//example.com/x')).toBe(false);
  });

  it('يرفض null / فارغ', () => {
    expect(isInternalAppPath(null)).toBe(false);
    expect(isInternalAppPath(undefined)).toBe(false);
    expect(isInternalAppPath('')).toBe(false);
  });
});

describe('notificationWorkspaceFromPath', () => {
  it('يكتشف المساحة من المسار الحالي', () => {
    expect(notificationWorkspaceFromPath('/admin/notifications')).toBe('admin');
    expect(notificationWorkspaceFromPath('/committee/notifications')).toBe('committee');
    expect(notificationWorkspaceFromPath('/hr/notifications')).toBe('hr');
  });
});

describe('parseActionDeepLink', () => {
  it('يستخرج النوع والمعرّف من كل صيغ رابط الإجراء', () => {
    expect(parseActionDeepLink('https://host/action/live_location_request/abc')).toEqual({ kind: 'live_location_request', id: 'abc' });
    expect(parseActionDeepLink('ahlashabab://action/live_location/xyz')).toEqual({ kind: 'live_location', id: 'xyz' });
    expect(parseActionDeepLink('/action/request/req-1?x=1')).toEqual({ kind: 'request', id: 'req-1' });
  });

  it('يعود null لغير روابط الإجراء', () => {
    expect(parseActionDeepLink('/hr/requests')).toBeNull();
    expect(parseActionDeepLink(null)).toBeNull();
  });
});

describe('canonicalEntityType', () => {
  it('يوحّد صيغ الخلفية المتعددة', () => {
    expect(canonicalEntityType('requests')).toBe('request');
    expect(canonicalEntityType('request_decision')).toBe('request');
    expect(canonicalEntityType('kpi_evaluation')).toBe('kpi');
    expect(canonicalEntityType('dispute_case')).toBe('dispute');
    expect(canonicalEntityType('live_location_requests')).toBe('live_location_request');
    expect(canonicalEntityType('instant_penalty_doubled')).toBe('instant_penalty');
    expect(canonicalEntityType('daily_report_like')).toBe('daily_reports');
    expect(canonicalEntityType('work_assignments')).toBe('requests_page');
    expect(canonicalEntityType('kpi_appeals')).toBe('performance_page');
    expect(canonicalEntityType(null)).toBeNull();
  });
});

describe('notificationTargetPath', () => {
  it('يعطي الأولوية لـ actionUrl الداخلي الصالح', () => {
    const n = item({ actionUrl: '/admin/disputes?case=x', entityType: 'dispute' });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/disputes?case=x');
  });

  it('يتجاهل actionUrl الخارجي ويُركب الوجهة من entityType', () => {
    const n = item({ actionUrl: 'https://ahla-shabab-management-os.vercel.app/action/request/abc', entityType: 'request', entityId: 'abc' });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/hr/requests?request=abc');
  });

  it('يتجاهل actionUrl الذي لا يطابق أي مسار ويب', () => {
    // مسارات موبايل محضة كانت تُمرَّر كما هي فيبتلعها catch-all.
    const attendance = item({ actionUrl: '/attendance', entityType: 'attendance_daily', metadata: { workDate: '2026-08-24' } });
    expect(notificationTargetPath(attendance, 'admin')).toBe('/admin/hr/attendance/details?category=scheduled&date=2026-08-24');

    const weekly = item({ actionUrl: '/reports/attendance', entityType: 'weekly_executive_summary', metadata: { endDate: '2026-08-29' } });
    expect(notificationTargetPath(weekly, 'admin')).toBe('/admin/hr/attendance?tab=executive&date=2026-08-29');
  });

  it('يفتح الطلب نفسه لا قائمة الطلبات', () => {
    expect(notificationTargetPath(item({ entityType: 'request', entityId: 'r1' }), 'admin')).toBe('/admin/hr/requests?request=r1');
    expect(notificationTargetPath(item({ entityType: 'requests', entityId: 'r1' }), 'hr')).toBe('/hr/requests?request=r1');
    expect(notificationTargetPath(item({ entityType: 'request_decision', entityId: 'r1' }), 'admin')).toBe('/admin/hr/requests?request=r1');
  });

  it('يرسم النزاعات مع entityId كاستعلام case=', () => {
    expect(notificationTargetPath(item({ entityType: 'dispute', entityId: 'case-uuid' }), 'admin')).toBe('/admin/disputes?case=case-uuid');
    expect(notificationTargetPath(item({ entityType: 'dispute_case', entityId: 'case-uuid' }), 'admin')).toBe('/admin/disputes?case=case-uuid');
    expect(notificationTargetPath(item({ entityType: 'dispute', entityId: 'case-uuid' }), 'committee')).toBe('/committee/disputes?case=case-uuid');
  });

  it('يفتح المنشور الرسمي نفسه عبر focus', () => {
    for (const et of ['announcement', 'announcements', 'decision', 'recognition']) {
      expect(notificationTargetPath(item({ entityType: et, entityId: 'a1' }), 'admin')).toBe('/admin/official-feed?focus=a1');
      expect(notificationTargetPath(item({ entityType: et, entityId: 'a1' }), 'hr')).toBe('/hr/official-feed?focus=a1');
    }
  });

  it('يفتح التقرير اليومي نفسه عبر focus', () => {
    for (const et of ['daily_report', 'daily_report_like', 'daily_report_comment', 'daily_reports']) {
      expect(notificationTargetPath(item({ entityType: et, entityId: 'd1' }), 'admin')).toBe('/admin/daily-reports?focus=d1');
      expect(notificationTargetPath(item({ entityType: et, entityId: 'd1' }), 'hr')).toBe('/hr/daily-reports?focus=d1');
    }
  });

  // معرّفات هذه الكيانات من جداول أخرى — تمريرها كـ ?request= يفتح حواراً لا وجود له.
  it('الكيانات المجاورة للطلبات تفتح الصفحة بلا معرّف طلب خاطئ', () => {
    for (const et of ['work_assignments', 'service_requests', 'document_signature_requests']) {
      expect(notificationTargetPath(item({ entityType: et, entityId: 'asg-1' }), 'admin')).toBe('/admin/hr/requests');
      expect(notificationTargetPath(item({ entityType: et, entityId: 'asg-1' }), 'hr')).toBe('/hr/requests');
    }
    expect(notificationTargetPath(item({ entityType: 'kpi_appeals', entityId: 'ap-1' }), 'admin')).toBe('/admin/performance/cycles');
    expect(notificationTargetPath(item({ entityType: 'kpi_appeals', entityId: 'ap-1' }), 'hr')).toBe('/hr/performance');
  });

  it('يفتح يوم الحضور الذي وقع فيه الحدث والموظف صاحبه', () => {
    const n = item({ entityType: 'attendance_daily', entityId: 'x', metadata: { workDate: '2026-08-24', employeeId: 'emp-9' } });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/hr/attendance/details?category=scheduled&date=2026-08-24&focus=emp-9');
    expect(notificationTargetPath(n, 'hr')).toBe('/hr/attendance/details?category=scheduled&date=2026-08-24&focus=emp-9');
  });

  it('بلا تاريخ صالح في metadata يعود للوحة الحضور بدل مسار مكسور', () => {
    expect(notificationTargetPath(item({ entityType: 'attendance_corrections', entityId: 'c1' }), 'admin')).toBe('/admin/hr/attendance');
    expect(notificationTargetPath(item({ entityType: 'attendance_daily', metadata: { workDate: 'x' } }), 'admin')).toBe('/admin/hr/attendance');
  });

  it('يفتح الغرامة الفورية نفسها في تبويبها', () => {
    for (const et of ['instant_penalty', 'instant_penalty_doubled', 'instant_penalty_suspended', 'instant_penalty_reinstated', 'instant_penalty_lifted']) {
      expect(notificationTargetPath(item({ entityType: et, entityId: 'p1' }), 'admin')).toBe('/admin/finance?tab=instant-penalties&focus=p1');
    }
  });

  it('يفتح حركة صندوق الزمالة نفسها', () => {
    expect(notificationTargetPath(item({ entityType: 'fellowship_fund', entityId: 'f1' }), 'admin')).toBe('/admin/finance?tab=fellowship-fund&focus=f1');
  });

  it('يفتح تقييم KPI المحدد من metadata.evaluationId', () => {
    const n = item({ entityType: 'kpi_evaluation', entityId: 'cycle-1', metadata: { evaluationId: 'eval-7' } });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/performance/cycles?focus=eval-7');
    expect(notificationTargetPath(n, 'hr')).toBe('/hr/performance?focus=eval-7');
  });

  it('يفتح الجهاز المحدد في صفحة الأجهزة', () => {
    const n = item({ entityType: 'device', entityId: 'd0', metadata: { deviceId: 'dev-3' } });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/hr/devices?focus=dev-3');
    expect(notificationTargetPath(item({ entityType: 'device', entityId: 'd0' }), 'hr')).toBe('/hr/devices?focus=d0');
  });

  it('يحل روابط الإجراء الموحّدة حين لا يكفي entityType', () => {
    const n = item({ actionUrl: 'ahlashabab://action/live_location/loc-1', entityType: null });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/live-location?focus=loc-1');
  });

  it('مساحة hr لا تملك صفحة نزاعات', () => {
    expect(notificationTargetPath(item({ entityType: 'dispute', entityId: 'c' }), 'hr')).toBeNull();
  });

  it('مساحة committee تعرض النزاعات فقط', () => {
    expect(notificationTargetPath(item({ entityType: 'request', entityId: 'r' }), 'committee')).toBeNull();
    expect(notificationTargetPath(item({ entityType: 'instant_penalty', entityId: 'p' }), 'committee')).toBeNull();
  });

  it('بدون entityType و بدون actionUrl داخلي → لا وجهة', () => {
    expect(notificationTargetPath(item({ actionUrl: null, entityType: null }), 'admin')).toBeNull();
    expect(notificationTargetPath(item({ actionUrl: 'https://example.com/x', entityType: null }), 'admin')).toBeNull();
  });

  it('الأنواع المعلوماتية بلا وجهة → null (لا زر فتح)', () => {
    expect(notificationTargetPath(item({ entityType: 'attendance_manager_notify' }), 'admin')).toBeNull();
    expect(notificationTargetPath(item({ entityType: 'broadcast_alert', entityId: 'b1' }), 'admin')).toBeNull();
  });

  it('يرسم الرفاهية إلى الخلاصة الرسمية', () => {
    expect(notificationTargetPath(item({ entityType: 'wellbeing_requests', entityId: 'w1' }), 'admin')).toBe('/admin/official-feed?focus=w1');
    expect(notificationTargetPath(item({ entityType: 'wellbeing_requests', entityId: 'w1' }), 'hr')).toBe('/hr/official-feed?focus=w1');
  });

  it('يرسم إنهاء الخدمة إلى تبويب إنهاء الخدمة في صفحة المستندات الفعلية', () => {
    // المستندات تُركَّب تحت HrWorkspaceRoutes — /admin/documents لا وجود له.
    expect(notificationTargetPath(item({ entityType: 'offboarding_cases', entityId: 'ob-1' }), 'admin')).toBe('/admin/hr/documents?tab=offboarding&focus=ob-1');
    expect(notificationTargetPath(item({ entityType: 'offboarding_cases', entityId: 'ob-1' }), 'hr')).toBe('/hr/documents?tab=offboarding&focus=ob-1');
  });

  it('كل الخرائط تُنتج مسارات داخلية صالحة ضمن المساحة نفسها', () => {
    const types = [
      'request',
      'requests',
      'kpi',
      'kpi_evaluation',
      'attendance',
      'attendance_daily',
      'attendance_corrections',
      'dispute',
      'dispute_case',
      'decision',
      'announcement',
      'announcements',
      'recognition',
      'daily_report',
      'daily_reports',
      'instant_penalty',
      'fellowship_fund',
      'device',
      'work_assignments',
      'weekly_executive_summary',
      'live_location_request',
      'punch_reminder',
      'wellbeing_requests',
      'offboarding_cases',
    ];
    for (const ws of ['admin', 'hr', 'committee'] as const) {
      for (const et of types) {
        const path = notificationTargetPath(item({ entityType: et, entityId: 'id', metadata: { workDate: '2026-08-24' } }), ws);
        if (path !== null) {
          expect(path.startsWith(`/${ws}`)).toBe(true);
          expect(path.includes('://')).toBe(false);
        }
      }
    }
  });
});

describe('إشعارات مشاريع الجمعية', () => {
  const projectId = '57000000-0000-4000-8000-0000000000aa';
  it('تفتح لوحة المشروع نفسه في مساحة الأدمن', () => {
    expect(notificationTargetPath(item({ entityType: 'association_project', entityId: projectId }), 'admin')).toBe(
      `/admin/association-projects?project=${projectId}`,
    );
  });
  it('تفتح لوحة المشروع في مساحة HR', () => {
    expect(notificationTargetPath(item({ entityType: 'association_project', entityId: projectId }), 'hr')).toBe(
      `/hr/association-projects?project=${projectId}`,
    );
  });
});
