import { lazy, Suspense, type ReactNode } from 'react';
import type { WorkspaceId } from '@ahla/shared-contracts';
import { Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { LoadingScreen } from '../ui/LoadingScreen';
import { safeErrorMessage } from '../core/errorMapper';
import { useAuth } from '../features/auth/AuthProvider';
import { LoginPage } from '../features/auth/LoginPage';
import { isPasswordRecoveryLocation, PasswordSetupPage } from '../features/auth/PasswordSetupPage';
import { MobileRedirectPage } from '../features/auth/MobileRedirectPage';
import { WebReleaseCheckError, WebReleaseStatusPage } from '../features/auth/WebReleaseStatusPage';
import { useRegisterWebDevice, useWebReleasePolicy } from '../features/auth/useWebReleasePolicy';
import { firstWebWorkspace, hasAnyPermission } from '../features/workspaces/access';
import { WorkspaceShell } from '../features/workspaces/WorkspaceShell';
import { ForbiddenState } from '../ui/ForbiddenState';

// ---------------------------------------------------------------------------
// Code-splitting: كل صفحة تُحمّل فقط عند الانتقال إليها — يقلّل الـ bundle
// الأولي من ~800 KB إلى ~300 KB ويسرّع أول تحميل بشكل ملحوظ.
// ---------------------------------------------------------------------------
const DashboardPage = lazy(() => import('../features/workspaces/DashboardPage').then(m => ({ default: m.DashboardPage })));
const EmployeesPage = lazy(() => import('../features/employees/EmployeesPage').then(m => ({ default: m.EmployeesPage })));
const CreateEmployeePage = lazy(() => import('../features/employees/CreateEmployeePage').then(m => ({ default: m.CreateEmployeePage })));
const EmployeeDetailPage = lazy(() => import('../features/employees/EmployeeDetailPage').then(m => ({ default: m.EmployeeDetailPage })));
const AttendancePage = lazy(() => import('../features/attendance/AttendancePage').then(m => ({ default: m.AttendancePage })));
const AttendanceOperationsPage = lazy(() => import('../features/advanced/AttendanceOperationsPage').then(m => ({ default: m.AttendanceOperationsPage })));
const MonthlyAttendanceReportPage = lazy(() => import('../features/attendance/MonthlyAttendanceReportPage').then(m => ({ default: m.MonthlyAttendanceReportPage })));
const PerformancePage = lazy(() => import('../features/performance/PerformancePage').then(m => ({ default: m.PerformancePage })));
const RecruitmentPage = lazy(() => import('../features/management/RecruitmentPage').then(m => ({ default: m.RecruitmentPage })));
const OnboardingPage = lazy(() => import('../features/management/OnboardingPage').then(m => ({ default: m.OnboardingPage })));
const ReportsPage = lazy(() => import('../features/management/ReportsPage').then(m => ({ default: m.ReportsPage })));
const OfficialHolidaysPage = lazy(() => import('../features/holidays/OfficialHolidaysPage').then(m => ({ default: m.OfficialHolidaysPage })));
const RequestsPage = lazy(() => import('../features/requests/RequestsPage').then(m => ({ default: m.RequestsPage })));
const DeviceApprovalPage = lazy(() => import('../features/devices/DeviceApprovalPage').then(m => ({ default: m.DeviceApprovalPage })));
const OrganizationPage = lazy(() => import('../features/management/OrganizationPage').then(m => ({ default: m.OrganizationPage })));
const OfficialFeedPage = lazy(() => import('../features/communications/OfficialFeedPage').then(m => ({ default: m.OfficialFeedPage })));
const NotificationsPage = lazy(() => import('../features/notifications/NotificationsPage').then(m => ({ default: m.NotificationsPage })));
const ActionCenterPage = lazy(() => import('../features/actions/ActionCenterPage').then(m => ({ default: m.ActionCenterPage })));
const LiveLocationPage = lazy(() => import('../features/management/LiveLocationPage').then(m => ({ default: m.LiveLocationPage })));
const ExecutiveMonitoringPage = lazy(() => import('../features/management/ExecutiveMonitoringPage').then(m => ({ default: m.ExecutiveMonitoringPage })));
const KpiCyclesPage = lazy(() => import('../features/advanced/KpiCyclesPage').then(m => ({ default: m.KpiCyclesPage })));
const DisputesPage = lazy(() => import('../features/advanced/DisputesPage').then(m => ({ default: m.DisputesPage })));
const AccessPage = lazy(() => import('../features/management/AccessPage').then(m => ({ default: m.AccessPage })));
const SystemPage = lazy(() => import('../features/management/SystemPage').then(m => ({ default: m.SystemPage })));
const ReportSchedulerPage = lazy(() => import('../features/management/ReportSchedulerPage').then(m => ({ default: m.ReportSchedulerPage })));
const EnterpriseManagementPage = lazy(() => import('../features/management/EnterpriseManagementPage').then(m => ({ default: m.EnterpriseManagementPage })));
const OperationsCenterPage = lazy(() => import('../features/management/OperationsCenterPage').then(m => ({ default: m.OperationsCenterPage })));
const AuditSecurityPage = lazy(() => import('../features/management/AuditSecurityPage').then(m => ({ default: m.AuditSecurityPage })));
const IntegrationsJobsPage = lazy(() => import('../features/management/IntegrationsJobsPage').then(m => ({ default: m.IntegrationsJobsPage })));
/* V17 §4.2: feature-flagged pages — shown only when the corresponding flag in featureFlags.ts is true */
const ComingSoonPage = lazy(() => import('../ui/ComingSoonPage').then(m => ({ default: m.ComingSoonPage })));

export function App() {
  const auth = useAuth();
  const release = useWebReleasePolicy();
  useRegisterWebDevice();

  // Mobile deep-link redirect — no auth required, shown before any other check.
  if (window.location.pathname === '/mobile-redirect') return <MobileRedirectPage />;

  if (release.isLoading) return <LoadingScreen />;
  if (release.isError) return <WebReleaseCheckError message={safeErrorMessage(release.error)} onRetry={() => void release.refetch()} />;
  if (release.data && ['maintenance','update_required','blocked'].includes(release.data.action)) return <WebReleaseStatusPage policy={release.data} onRetry={() => void release.refetch()} />;

  if (isPasswordRecoveryLocation()) return <PasswordSetupPage />;

  if (auth.status === 'loading') return <LoadingScreen />;
  if (auth.status === 'anonymous' || !auth.access) return <LoginPage />;
  if (auth.session?.user.user_metadata.must_change_password === true) {
    return <PasswordSetupPage />;
  }

  const defaultWorkspace = firstWebWorkspace(auth.access);
  if (!defaultWorkspace) {
    return (
      <main className="grid min-h-screen place-items-center p-6">
        <section className="card max-w-lg p-7 text-center">
          <h1 className="text-xl font-bold">لا توجد مساحة ويب مصرح بها</h1>
          <p className="muted mt-2 leading-7">هذا الحساب مخصص لتطبيق Flutter أو لا يملك مساحة ويب إدارية مصرحًا بها.</p>
          <button className="mt-5 rounded-xl bg-brand px-4 py-2.5 font-bold text-white" onClick={() => void auth.signOut()}>تسجيل الخروج</button>
        </section>
      </main>
    );
  }

  return (
    <Suspense fallback={<LoadingScreen />}>
    <Routes>
      <Route path="/" element={<Navigate to={workspacePath(defaultWorkspace)} replace />} />

      <Route element={<WorkspaceGuard workspace="hr" />}>
        <Route path="/hr" element={<WorkspaceShell workspace="hr" />}>
          <Route index element={<DashboardPage type="hr" />} />
          <Route path="employees" element={<RequirePermission perm="people.employee.read"><EmployeesPage /></RequirePermission>} />
          <Route path="employees/new" element={<RequirePermission perm="people.employee.create"><CreateEmployeePage /></RequirePermission>} />
          <Route path="employees/:employeeId" element={<RequirePermission perm="people.employee.read"><EmployeeDetailPage /></RequirePermission>} />
          <Route path="attendance" element={<RequirePermission perm="attendance.record.read"><AttendancePage /></RequirePermission>} />
          <Route path="attendance/operations" element={<RequirePermission perm="attendance.roster.read"><AttendanceOperationsPage /></RequirePermission>} />
          <Route path="attendance/report" element={<RequirePermission perm="attendance.record.read"><MonthlyAttendanceReportPage /></RequirePermission>} />
          <Route path="performance" element={<RequirePermission perm="performance.kpi.read"><PerformancePage /></RequirePermission>} />
          <Route path="recruitment" element={<RequirePermission perm="recruitment.requisition.read"><RecruitmentPage /></RequirePermission>} />
          <Route path="onboarding" element={<RequirePermission perm="onboarding.journey.read"><OnboardingPage /></RequirePermission>} />
          <Route path="reports" element={<RequirePermission perm="reports.people.read"><ReportsPage /></RequirePermission>} />
          <Route path="holidays" element={<RequirePermission perm="holidays.manage"><OfficialHolidaysPage /></RequirePermission>} />
          <Route path="requests" element={<RequirePermission perm="requests.request.read"><RequestsPage /></RequirePermission>} />
          <Route path="devices" element={<RequirePermission perm="access.role.read"><DeviceApprovalPage /></RequirePermission>} />
          <Route path="organization" element={<RequirePermission perm="organization.org_chart.read"><OrganizationPage /></RequirePermission>} />
          <Route path="learning" element={<ComingSoonPage title="التدريب والمهارات" />} />
          <Route path="lifecycle" element={<ComingSoonPage title="دورة حياة الموظف" />} />
          <Route path="documents" element={<ComingSoonPage title="استوديو المستندات" />} />
          <Route path="official-feed" element={<RequirePermission perm={['comms.announcement.read', 'comms.decision.read']}><OfficialFeedPage /></RequirePermission>} />
          <Route path="notifications" element={<NotificationsPage />} />
        </Route>
      </Route>

      <Route element={<WorkspaceGuard workspace="main_admin" />}>
        <Route path="/admin" element={<WorkspaceShell workspace="main_admin" />}>
          <Route index element={<DashboardPage type="admin" />} />
          <Route path="actions" element={<RequirePermission perm="access.role.read"><ActionCenterPage /></RequirePermission>} />
          <Route path="live-location" element={<RequirePermission perm="live_location.request"><LiveLocationPage /></RequirePermission>} />
          <Route path="live-location/monitoring" element={<RequirePermission perm="live_location.request"><ExecutiveMonitoringPage /></RequirePermission>} />
          <Route path="device-approvals" element={<RequirePermission perm="access.role.read"><DeviceApprovalPage /></RequirePermission>} />
          <Route path="official-feed" element={<RequirePermission perm={['comms.announcement.read', 'comms.decision.read']}><OfficialFeedPage /></RequirePermission>} />
          <Route path="organization" element={<RequirePermission perm="organization.org_chart.read"><OrganizationPage /></RequirePermission>} />
          <Route path="performance/cycles" element={<RequirePermission perm="performance.cycle.manage"><KpiCyclesPage /></RequirePermission>} />
          <Route path="disputes" element={<RequirePermission perm="relations.case.manage"><DisputesPage /></RequirePermission>} />
          <Route path="lifecycle" element={<ComingSoonPage title="دورة حياة الموظف" />} />
          <Route path="access" element={<RequirePermission perm="access.role.read"><AccessPage /></RequirePermission>} />
          <Route path="settings" element={<RequirePermission perm="system.settings.read"><SystemPage /></RequirePermission>} />
          <Route path="governance" element={<ComingSoonPage title="الحوكمة والمخاطر" />} />
          <Route path="documents" element={<ComingSoonPage title="استوديو المستندات" />} />
          <Route path="reports/scheduler" element={<RequirePermission perm="reports.schedule.manage"><ReportSchedulerPage /></RequirePermission>} />
          <Route path="enterprise" element={<RequirePermission perm="organization.entity.read"><EnterpriseManagementPage /></RequirePermission>} />
          <Route path="operations" element={<RequirePermission perm="tasks.read"><OperationsCenterPage /></RequirePermission>} />
          <Route path="helpdesk" element={<ComingSoonPage title="مكتب الخدمات" />} />
          <Route path="finance" element={<ComingSoonPage title="الرواتب والمالية" />} />
          <Route path="audit-security" element={<RequirePermission perm="audit.view"><AuditSecurityPage /></RequirePermission>} />
          <Route path="integrations" element={<RequirePermission perm="system.integration.view"><IntegrationsJobsPage /></RequirePermission>} />
          <Route path="notifications" element={<NotificationsPage />} />
        </Route>
      </Route>

      <Route element={<WorkspaceGuard workspace="committee" />}>
        <Route path="/committee" element={<WorkspaceShell workspace="committee" />}>
          <Route index element={<RequirePermission perm="disputes.portal.access"><DisputesPage /></RequirePermission>} />
          <Route path="disputes" element={<RequirePermission perm="disputes.portal.access"><DisputesPage /></RequirePermission>} />
          <Route path="notifications" element={<NotificationsPage />} />
        </Route>
      </Route>

      <Route path="*" element={<Navigate to={workspacePath(defaultWorkspace)} replace />} />
    </Routes>
    </Suspense>
  );
}

function WorkspaceGuard({ workspace }: { workspace: WorkspaceId }) {
  const auth = useAuth();
  if (!auth.access?.workspaces.includes(workspace)) {
    const fallback = firstWebWorkspace(auth.access!);
    return <Navigate to={workspacePath(fallback ?? 'hr')} replace />;
  }
  return <Outlet />;
}

function workspacePath(workspace: WorkspaceId) {
  if (workspace === 'main_admin') return '/admin';
  if (workspace === 'committee') return '/committee';
  return '/hr';
}

// CTB-01: per-route permission guard so deep-linking a page requires the same
// permission the sidebar uses to show it. Defense-in-depth over server RLS/RPC —
// the server remains the source of truth; this stops the page from mounting and
// firing its reads for a user who lacks the permission.
// يدعم صلاحية واحدة أو عدة صلاحيات (OR) — يمر إذا يملك المستخدم أي واحدة منها.
function RequirePermission({ perm, children }: { perm: string | string[]; children: ReactNode }) {
  const auth = useAuth();
  if (!auth.access || !hasAnyPermission(auth.access, perm)) {
    return <ForbiddenState />;
  }
  return <>{children}</>;
}
