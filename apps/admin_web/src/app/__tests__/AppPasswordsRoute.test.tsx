import { render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router';
import { App } from '../App';
import { ToastProvider } from '../../ui/Toast';

vi.mock('../../core/supabaseClient', () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null } }),
      onAuthStateChange: vi.fn().mockReturnValue({ data: { subscription: { unsubscribe: vi.fn() } } }),
    },
    rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({ data: null, error: null }),
    }),
  },
}));

vi.mock('../../features/auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'authenticated',
    user: { id: 'admin-1', email: 'admin@ahlashabab.org' },
    session: { user: { id: 'admin-1', app_metadata: {} } },
    access: {
      userId: 'admin-1',
      employeeId: null,
      displayName: 'يحيى جمال',
      employeeCode: null,
      photoUrl: null,
      roles: ['admin'],
      permissions: ['*'],
      workspaces: ['main_admin', 'hr'],
      defaultWorkspace: 'main_admin',
      attendancePolicy: {
        attendanceRequired: false,
        selfPunchEnabled: false,
        liveLocationResponseEnabled: false,
      },
    },
    isLoading: false,
    signOut: vi.fn(),
  }),
  AuthProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('../../features/auth/useWebReleasePolicy', () => ({
  useWebReleasePolicy: () => ({ isLoading: false, isError: false, data: null }),
  useRegisterWebDevice: () => {},
}));

vi.mock('../../features/notifications/useNotifications', () => ({
  useNotifications: () => ({
    data: [],
  }),
}));

vi.mock('../../features/employees/useEmployees', () => ({
  useEmployees: () => ({
    data: [
      {
        id: 'emp-1',
        employeeCode: 'EMP-001',
        fullNameAr: 'أحمد علي',
        fullNameEn: 'Ahmed Ali',
        department: 'الإدارة',
        jobTitle: 'مبرمج',
        phoneE164: '+201000000000',
        status: 'active',
      },
    ],
    isLoading: false,
    isError: false,
    refetch: vi.fn(),
  }),
  useSetEmployeePassword: () => ({
    isPending: false,
    mutateAsync: vi.fn(),
  }),
  useResendInvite: () => ({
    isPending: false,
    mutateAsync: vi.fn(),
  }),
}));

function renderApp(initialPath: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <ToastProvider>
        <MemoryRouter initialEntries={[initialPath]}>
          <App />
        </MemoryRouter>
      </ToastProvider>
    </QueryClientProvider>,
  );
}

describe('EmployeePasswordsPage routing', () => {
  it('renders EmployeePasswordsPage at /admin/hr/passwords', async () => {
    renderApp('/admin/hr/passwords');

    await waitFor(() => {
      expect(screen.getByText('إدارة كلمات المرور وحسابات الموظفين')).toBeTruthy();
    });
  });

  it('catch-all does not hang on unknown sub-paths (no infinite redirect)', async () => {
    // Before the fix, this test would hang forever because the relative
    // Navigate to="employees" would keep appending /employees endlessly.
    // With the fix using absolute paths, it cleanly redirects and terminates.
    renderApp('/admin/hr/some-unknown-page');

    // Just verify the app renders without hanging — the redirect terminates
    await waitFor(() => {
      expect(document.querySelector('.app-shell')).toBeTruthy();
    });
  });
});
