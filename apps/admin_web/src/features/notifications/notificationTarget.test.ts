import { describe, it, expect } from 'vitest';
import type { NotificationItem } from '@ahla/shared-contracts';
import { isInternalAppPath, notificationTargetPath, notificationWorkspaceFromPath } from './notificationTarget';

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
  it('يقبل المسارات الداخلية مع query', () => {
    expect(isInternalAppPath('/admin/disputes?case=abc')).toBe(true);
    expect(isInternalAppPath('/hr/requests')).toBe(true);
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

describe('notificationTargetPath', () => {
  it('يعطي الأولوية لـ actionUrl الداخلي الصالح', () => {
    const n = item({ actionUrl: '/admin/disputes?case=x', entityType: 'dispute' });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/disputes?case=x');
  });

  it('يتجاهل actionUrl الخارجي ويُركب الوجهة من entityType', () => {
    const n = item({ actionUrl: 'https://ahla-shabab-management-os.vercel.app/action/request/abc', entityType: 'request', entityId: 'abc' });
    expect(notificationTargetPath(n, 'admin')).toBe('/admin/hr/requests');
  });

  it('يرسم طلبات الإجازات إلى وجهة admin', () => {
    expect(notificationTargetPath(item({ entityType: 'request' }), 'admin')).toBe('/admin/hr/requests');
    expect(notificationTargetPath(item({ entityType: 'request_decision' }), 'admin')).toBe('/admin/hr/requests');
  });

  it('يرسم النزاعات مع entityId كاستعلام case=', () => {
    expect(notificationTargetPath(item({ entityType: 'dispute', entityId: 'case-uuid' }), 'admin')).toBe('/admin/disputes?case=case-uuid');
    expect(notificationTargetPath(item({ entityType: 'dispute', entityId: 'case-uuid' }), 'committee')).toBe('/committee/disputes?case=case-uuid');
  });

  it('يرسم الإعلانات والقرارات والتقدير إلى الخلاصة الرسمية', () => {
    for (const et of ['announcement', 'decision', 'recognition']) {
      expect(notificationTargetPath(item({ entityType: et }), 'admin')).toBe('/admin/official-feed');
      expect(notificationTargetPath(item({ entityType: et }), 'hr')).toBe('/hr/official-feed');
    }
  });

  it('يرسم تقارير اليوم إلى وجهة التقارير', () => {
    for (const et of ['daily_report', 'daily_report_like', 'daily_report_comment']) {
      expect(notificationTargetPath(item({ entityType: et }), 'admin')).toBe('/admin/daily-reports');
      expect(notificationTargetPath(item({ entityType: et }), 'hr')).toBe('/hr/daily-reports');
    }
  });

  it('مساحة hr لا تملك صفحة نزاعات', () => {
    expect(notificationTargetPath(item({ entityType: 'dispute' }), 'hr')).toBeNull();
  });

  it('مساحة committee تعرض النزاعات فقط', () => {
    expect(notificationTargetPath(item({ entityType: 'request' }), 'committee')).toBeNull();
  });

  it('بدون entityType و بدون actionUrl داخلي → لا وجهة', () => {
    expect(notificationTargetPath(item({ actionUrl: null, entityType: null }), 'admin')).toBeNull();
    expect(notificationTargetPath(item({ actionUrl: 'https://example.com/x', entityType: null }), 'admin')).toBeNull();
  });

  it('الأنواع المعلوماتية بلا خريطة → null (لا زر فتح)', () => {
    expect(notificationTargetPath(item({ entityType: 'attendance_manager_notify' }), 'admin')).toBeNull();
  });

  it('كل الخرائط تُنتج مسارات داخلية صالحة', () => {
    const types = ['request', 'kpi', 'attendance', 'dispute', 'decision', 'announcement', 'recognition', 'daily_report'];
    for (const ws of ['admin', 'hr', 'committee'] as const) {
      for (const et of types) {
        const path = notificationTargetPath(item({ entityType: et, entityId: 'id' }), ws);
        if (path !== null) {
          expect(path.startsWith(`/${ws}`)).toBe(true);
          expect(path.includes('://')).toBe(false);
        }
      }
    }
  });
});
