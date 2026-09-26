import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { NotificationOpenRedirect } from '../NotificationOpenRedirect';

let notifReturn: Record<string, unknown> = {};
const markMutate = vi.fn();
let access: Record<string, unknown> = {};

vi.mock('../useNotifications', () => ({
  useNotifications: () => notifReturn,
  useMarkNotificationsRead: () => ({ mutate: markMutate }),
}));
vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', access }),
}));

function Where() {
  const loc = useLocation();
  return <p data-testid="where">{loc.pathname + loc.search}</p>;
}

function renderAt(id: string) {
  return render(
    <MemoryRouter initialEntries={[`/notification/${id}`]}>
      <Routes>
        <Route path="/notification/:notificationId" element={<NotificationOpenRedirect />} />
        <Route path="*" element={<Where />} />
      </Routes>
    </MemoryRouter>,
  );
}

const base = {
  title: 'إشعار',
  body: null,
  category: 'request',
  priority: 'normal',
  actionUrl: null,
  isRead: false,
  createdAt: '2026-09-26T08:00:00Z',
};

describe('NotificationOpenRedirect — نقرة إشعار المتصفح', () => {
  it('يفتح الطلب نفسه في مساحة الأدمن', () => {
    access = { defaultWorkspace: 'main_admin', workspaces: ['main_admin', 'hr'] };
    notifReturn = { isLoading: false, data: [{ ...base, id: 'n1', entityType: 'request', entityId: 'r-9' }] };
    renderAt('n1');
    expect(screen.getByTestId('where').textContent).toBe('/admin/hr/requests?request=r-9');
    expect(markMutate).toHaveBeenCalledWith(['n1']);
  });

  it('لا يتبع actionUrl الموبايل (/attendance) بل يبني وجهة الحضور في يوم الحدث', () => {
    access = { defaultWorkspace: 'hr', workspaces: ['hr'] };
    notifReturn = {
      isLoading: false,
      data: [{ ...base, id: 'n2', actionUrl: '/attendance', entityType: 'attendance_daily', entityId: 'a1', metadata: { workDate: '2026-09-20' } }],
    };
    renderAt('n2');
    expect(screen.getByTestId('where').textContent).toBe('/hr/attendance/details?category=scheduled&date=2026-09-20');
  });

  it('إشعار غير موجود في قائمة المستخدم → صفحة الإشعارات لا الرئيسية', () => {
    access = { defaultWorkspace: 'hr', workspaces: ['hr'] };
    notifReturn = { isLoading: false, data: [] };
    renderAt('unknown');
    expect(screen.getByTestId('where').textContent).toBe('/hr/notifications');
  });

  it('إشعار معلوماتي بلا وجهة → صفحة الإشعارات', () => {
    access = { defaultWorkspace: 'main_admin', workspaces: ['main_admin'] };
    notifReturn = { isLoading: false, data: [{ ...base, id: 'n3', entityType: 'broadcast_alert', entityId: 'b1' }] };
    renderAt('n3');
    expect(screen.getByTestId('where').textContent).toBe('/admin/notifications');
  });
});
