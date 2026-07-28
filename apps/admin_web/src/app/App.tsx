import type { ReactNode } from 'react';
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
import { CreateEmployeePage } from '../features/employees/CreateEmployeePage';
import { EmployeeDetailPage } from '../features/employees/EmployeeDetailPage';
import { EmployeesPage } from '../features/employees/EmployeesPage';
import { DashboardPage } from '../features/workspaces/DashboardPage';
import { ActionCenterPage } from '../features/actions/ActionCenterPage';
import { AccessPage } from '../features/management/AccessPage';
import { OrganizationPage } from '../features/management/OrganizationPage';
import { RecruitmentPage } from '../features/management/RecruitmentPage';
import { ReportsPage } from '../features/management/ReportsPage';
import { SystemPage } from '../features/management/SystemPage';
import { NotificationsPage } from '../features/notifications/NotificationsPage';
import { OnboardingPage } from '../features/management/OnboardingPage';
import { AttendancePage } from '../features/attendance/AttendancePage';
import { OfficialFeedPage } from '../features/communications/OfficialFeedPage';
import { PerformancePage } from '../features/performance/PerformancePage';
import { RequestsPage } from '../features/requests/RequestsPage';
import { firstWebWorkspace, hasAnyPermission } from '../features/workspaces/access';
import { WorkspaceShell } from '../features/workspaces/WorkspaceShell';
import { MonthlyAttendanceReportPage } from '../features/attendance/MonthlyAttendanceReportPage';
import { AttendanceOperationsPage } from '../features/advanced/AttendanceOperationsPage';
import { KpiCyclesPage } from '../features/advanced/KpiCyclesPage';
import { DisputesPage } from '../features/advanced/DisputesPage';
/* V17 §4.2: dead imports removed — LifecycleOperationsPage, LearningPage, DocumentStudioPage, PeopleFinancePage, ReleaseGovernancePage, ServiceDeskPage */
import { ReportSchedulerPage } from '../features/management/ReportSchedulerPage';
import { EnterpriseManagementPage } from '../features/management/EnterpriseManagementPage';
import { AuditSecurityPage } from '../features/management/AuditSecurityPage';
import { IntegrationsJobsPage } from '../features/management/IntegrationsJobsPage';
import { LiveLocationPage } from '../features/management/LiveLocationPage';
import { ExecutiveMonitoringPage } from '../features/management/ExecutiveMonitoringPage';
import { OperationsCenterPage } from '../features/management/OperationsCenterPage';
import { OfficialHolidaysPage } from '../features/holidays/OfficialHolidaysPage';
import { DeviceApprovalPage } from '../features/devices/DeviceApprovalPage';
import { ForbiddenState } from '../ui/ForbiddenState';

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
          {/* V17 §4.2: hidden secondary modules — learning, documents, lifecycle */}
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
          {/* V17 §4.2: lifecycle hidden */}
          <Route path="access" element={<RequirePermission perm="access.role.read"><AccessPage /></RequirePermission>} />
          <Route path="settings" element={<RequirePermission perm="system.settings.read"><SystemPage /></RequirePermission>} />
          {/* V17 §4.2: governance + documents hidden */}
          <Route path="reports/scheduler" element={<RequirePermission perm="reports.schedule.manage"><ReportSchedulerPage /></RequirePermission>} />
          <Route path="enterprise" element={<RequirePermission perm="organization.entity.read"><EnterpriseManagementPage /></RequirePermission>} />
          <Route path="operations" element={<RequirePermission perm="tasks.read"><OperationsCenterPage /></RequirePermission>} />
          {/* V17 §4.2: helpdesk + people-finance (payroll ممنوع) hidden */}
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
