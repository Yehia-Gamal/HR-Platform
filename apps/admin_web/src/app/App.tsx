import { lazy, Suspense, type ReactNode } from 'react';
import type { WorkspaceId } from '@ahla/shared-contracts';
import { Navigate, Outlet, Route, Routes, useLocation } from 'react-router';
import { LoadingScreen } from '../ui/LoadingScreen';
import { safeErrorMessage } from '../core/errorMapper';
import { useAuth } from '../features/auth/AuthProvider';
import { LoginPage } from '../features/auth/LoginPage';
import { isPasswordRecoveryLocation, PasswordSetupPage } from '../features/auth/PasswordSetupPage';
import { MobileRedirectPage } from '../features/auth/MobileRedirectPage';
import { WebReleaseCheckError, WebReleaseStatusPage } from '../features/auth/WebReleaseStatusPage';
import { useRegisterWebDevice, useWebReleasePolicy } from '../features/auth/useWebReleasePolicy';
import { firstWebWorkspace, hasAnyPermission, hrPathToAdmin } from '../features/workspaces/access';
import { WorkspaceShell } from '../features/workspaces/WorkspaceShell';
import { ForbiddenState } from '../ui/ForbiddenState';
import { FeatureGate } from '../ui/FeatureGate';

// ---------------------------------------------------------------------------
// Code-splitting: كل صفحة تُحمّل فقط عند الانتقال إليها — يقلّل الـ bundle
// الأولي من ~800 KB إلى ~300 KB ويسرّع أول تحميل بشكل ملحوظ.
// ---------------------------------------------------------------------------
const DashboardPage = lazy(() => import('../features/workspaces/DashboardPage').then((m) => ({ default: m.DashboardPage })));
const EmployeesPage = lazy(() => import('../features/employees/EmployeesPage').then((m) => ({ default: m.EmployeesPage })));
const CreateEmployeePage = lazy(() => import('../features/employees/CreateEmployeePage').then((m) => ({ default: m.CreateEmployeePage })));
const EmployeeDetailPage = lazy(() => import('../features/employees/EmployeeDetailPage').then((m) => ({ default: m.EmployeeDetailPage })));
const AttendancePage = lazy(() => import('../features/attendance/AttendancePage').then((m) => ({ default: m.AttendancePage })));
const AttendanceDrilldownPage = lazy(() =>
  import('../features/attendance/AttendanceDrilldownPage').then((m) => ({ default: m.AttendanceDrilldownPage })),
);
const AttendanceOperationsPage = lazy(() => import('../features/advanced/AttendanceOperationsPage').then((m) => ({ default: m.AttendanceOperationsPage })));
const MonthlyAttendanceReportPage = lazy(() =>
  import('../features/attendance/MonthlyAttendanceReportPage').then((m) => ({ default: m.MonthlyAttendanceReportPage })),
);
const PerformancePage = lazy(() => import('../features/performance/PerformancePage').then((m) => ({ default: m.PerformancePage })));
const RecruitmentPage = lazy(() => import('../features/management/RecruitmentPage').then((m) => ({ default: m.RecruitmentPage })));
const OnboardingPage = lazy(() => import('../features/management/OnboardingPage').then((m) => ({ default: m.OnboardingPage })));
const ReportsPage = lazy(() => import('../features/management/ReportsPage').then((m) => ({ default: m.ReportsPage })));
const OfficialHolidaysPage = lazy(() => import('../features/holidays/OfficialHolidaysPage').then((m) => ({ default: m.OfficialHolidaysPage })));
const RequestsPage = lazy(() => import('../features/requests/RequestsPage').then((m) => ({ default: m.RequestsPage })));
const DeviceApprovalPage = lazy(() => import('../features/devices/DeviceApprovalPage').then((m) => ({ default: m.DeviceApprovalPage })));
const OrganizationPage = lazy(() => import('../features/management/OrganizationPage').then((m) => ({ default: m.OrganizationPage })));
const OfficialFeedPage = lazy(() => import('../features/communications/OfficialFeedPage').then((m) => ({ default: m.OfficialFeedPage })));
const DailyReportsFeedPage = lazy(() => import('../features/reports/DailyReportsFeedPage').then((m) => ({ default: m.DailyReportsFeedPage })));
const NotificationsPage = lazy(() => import('../features/notifications/NotificationsPage').then((m) => ({ default: m.NotificationsPage })));
const ActionCenterPage = lazy(() => import('../features/actions/ActionCenterPage').then((m) => ({ default: m.ActionCenterPage })));
const LiveLocationPage = lazy(() => import('../features/management/LiveLocationPage').then((m) => ({ default: m.LiveLocationPage })));
const KpiCyclesPage = lazy(() => import('../features/advanced/KpiCyclesPage').then((m) => ({ default: m.KpiCyclesPage })));
const DisputesPage = lazy(() => import('../features/advanced/DisputesPage').then((m) => ({ default: m.DisputesPage })));
const AccessPage = lazy(() => import('../features/management/AccessPage').then((m) => ({ default: m.AccessPage })));
const SystemPage = lazy(() => import('../features/management/SystemPage').then((m) => ({ default: m.SystemPage })));
const ReportSchedulerPage = lazy(() => import('../features/management/ReportSchedulerPage').then((m) => ({ default: m.ReportSchedulerPage })));
const EnterpriseManagementPage = lazy(() => import('../features/management/EnterpriseManagementPage').then((m) => ({ default: m.EnterpriseManagementPage })));
const OperationsCenterPage = lazy(() => import('../features/management/OperationsCenterPage').then((m) => ({ default: m.OperationsCenterPage })));
const AuditSecurityPage = lazy(() => import('../features/management/AuditSecurityPage').then((m) => ({ default: m.AuditSecurityPage })));
const ObservabilityDashboardPage = lazy(() => import('../features/observability/ObservabilityDashboardPage').then((m) => ({ default: m.ObservabilityDashboardPage })));
const IntegrationsJobsPage = lazy(() => import('../features/management/IntegrationsJobsPage').then((m) => ({ default: m.IntegrationsJobsPage })));
const AnalyticsDashboardPage = lazy(() => import('../features/analytics/AnalyticsDashboardPage').then((m) => ({ default: m.AnalyticsDashboardPage })));
/* V17 §4.2: feature-flagged pages — shown only when the corresponding flag in featureFlags.ts is true */
const LearningPage = lazy(() => import('../features/learning/LearningPage').then((m) => ({ default: m.LearningPage })));
const LifecyclePage = lazy(() => import('../features/lifecycle/LifecyclePage').then((m) => ({ default: m.LifecyclePage })));
const ExecutiveMonitoringPage = lazy(() => import('../features/management/ExecutiveMonitoringPage').then((m) => ({ default: m.ExecutiveMonitoringPage })));
const OrgChartPage = lazy(() => import('../features/management/OrgChartPage').then((m) => ({ default: m.OrgChartPage })));
const DocumentsPage = lazy(() => import('../features/documents/DocumentsPage').then((m) => ({ default: m.DocumentsPage })));
const FinancePage = lazy(() => import('../features/finance/FinancePage').then((m) => ({ default: m.FinancePage })));
const KnowledgePage = lazy(() => import('../features/knowledge/KnowledgePage').then((m) => ({ default: m.KnowledgePage })));
const HelpdeskPage = lazy(() => import('../features/helpdesk/HelpdeskPage').then((m) => ({ default: m.HelpdeskPage })));
const GovernancePage = lazy(() => import('../features/governance/GovernancePage').then((m) => ({ default: m.GovernancePage })));
const EmployeePenaltiesPage = lazy(() => import('../features/finance/EmployeePenaltiesPage').then((m) => ({ default: m.EmployeePenaltiesPage })));
const InstapayPage = lazy(() => import('../features/finance/InstapayPage').then((m) => ({ default: m.InstapayPage })));
const AuditTrailPage = lazy(() => import('../features/management/AuditTrailPage').then((m) => ({ default: m.AuditTrailPage })));
const SystemSettingsPage = lazy(() => import('../features/management/SystemSettingsPage').then((m) => ({ default: m.SystemSettingsPage })));
const LeavesPage = lazy(() => import('../features/leaves/LeavesPage').then((m) => ({ default: m.LeavesPage })));

export function App() {
  // Mobile deep-link redirect — no auth required, shown before any other check.
  if (window.location.pathname === '/mobile-redirect') return <MobileRedirectPage />;

  // روابط التفعيل والاسترداد (بما فيها الروابط المنتهية) يجب أن تسبق بوابات
  // الإصدار والمصادقة حتى لا تظهر للموظف شاشة مساحة ويب غير مصرح بها.
  if (isPasswordRecoveryLocation()) return <PasswordSetupPage />;

  return <AuthenticatedApp />;
}

function AuthenticatedApp() {
  const auth = useAuth();
  const release = useWebReleasePolicy();
  useRegisterWebDevice();

  if (release.isLoading) return <LoadingScreen />;
  if (release.isError) return <WebReleaseCheckError message={safeErrorMessage(release.error)} onRetry={() => void release.refetch()} />;
  if (release.data && ['maintenance', 'update_required', 'blocked'].includes(release.data.action))
    return <WebReleaseStatusPage policy={release.data} onRetry={() => void release.refetch()} />;

  if (auth.status === 'loading') return <LoadingScreen />;
  if (auth.status === 'anonymous' || !auth.access) return <LoginPage />;
  if (auth.session?.user.app_metadata?.must_change_password === true) {
    return <PasswordSetupPage />;
  }

  const defaultWorkspace = firstWebWorkspace(auth.access);
  if (!defaultWorkspace) {
    return (
      <main className="grid min-h-screen place-items-center p-6">
        <section className="card max-w-lg p-7 text-center">
          <h1 className="text-xl font-bold">لا توجد مساحة ويب مصرح بها</h1>
          <p className="muted mt-2 leading-7">هذا الحساب مخصص لتطبيق Flutter أو لا يملك مساحة ويب إدارية مصرحًا بها.</p>
          <button className="mt-5 rounded-xl bg-brand px-4 py-2.5 font-bold text-white" onClick={() => void auth.signOut()}>
            تسجيل الخروج
          </button>
        </section>
      </main>
    );
  }

  return (
    <Suspense fallback={<LoadingScreen />}>
      <Routes>
        <Route path="/" element={<Navigate to={workspacePath(defaultWorkspace)} replace />} />

        {/* مساحة الموارد البشرية المستقلة — تبقى كما هي لحسابات HR التي لا تملك main_admin */}
        <Route element={<LegacyHrRedirect />}>
          <Route element={<WorkspaceGuard workspace="hr" />}>
            <Route path="/hr" element={<WorkspaceShell workspace="hr" />}>
              <Route index element={<DashboardPage type="hr" />} />
              <Route path="*" element={<HrWorkspaceRoutes />} />
            </Route>
          </Route>
        </Route>

        {/* المساحة الموحّدة للأدمن الرئيسي — تجمع الإدارة + HR + اللجنة في قائمة واحدة */}
        <Route element={<WorkspaceGuard workspace="main_admin" />}>
          <Route path="/admin" element={<WorkspaceShell workspace="main_admin" />}>
            <Route index element={<DashboardPage type="admin" />} />
            {/* صفحات HR داخل القائمة الموحّدة */}
            <Route path="hr" element={<DashboardPage type="hr" />} />
            <Route path="hr/*" element={<HrWorkspaceRoutes />} />
            <Route
              path="actions"
              element={
                <RequirePermission perm="access.role.read">
                  <ActionCenterPage />
                </RequirePermission>
              }
            />
            <Route
              path="live-location"
              element={
                <RequirePermission perm="live_location.request">
                  <LiveLocationPage />
                </RequirePermission>
              }
            />
            <Route
              path="official-feed"
              element={
                <RequirePermission perm={['comms.announcement.read', 'comms.decision.read']}>
                  <OfficialFeedPage />
                </RequirePermission>
              }
            />
            <Route path="daily-reports" element={<RequirePermission perm={['reports.daily.read', 'people.employee.read']}><DailyReportsFeedPage /></RequirePermission>} />
            <Route path="executive-monitoring" element={<RequirePermission perm="people.employee.read"><ExecutiveMonitoringPage /></RequirePermission>} />
            <Route
              path="org-chart"
              element={
                <RequirePermission perm="organization.org_chart.read">
                  <OrgChartPage />
                </RequirePermission>
              }
            />
            <Route
              path="organization"
              element={
                <RequirePermission perm="organization.org_chart.read">
                  <OrganizationPage />
                </RequirePermission>
              }
            />
            <Route
              path="performance/cycles"
              element={
                <RequirePermission perm="performance.cycle.manage">
                  <KpiCyclesPage />
                </RequirePermission>
              }
            />
            <Route
              path="disputes"
              element={
                <RequirePermission perm={['disputes.case.manage', 'disputes.portal.access']}>
                  <DisputesPage />
                </RequirePermission>
              }
            />
            <Route path="lifecycle" element={<RequirePermission perm="people.employee.read"><LifecyclePage /></RequirePermission>} />
            <Route
              path="access"
              element={
                <RequirePermission perm="access.role.read">
                  <AccessPage />
                </RequirePermission>
              }
            />
            <Route
              path="settings"
              element={
                <RequirePermission perm="system.settings.read">
                  <SystemPage />
                </RequirePermission>
              }
            />
            <Route path="governance" element={<FeatureGate feature="governance"><GovernancePage /></FeatureGate>} />
            <Route
              path="reports/scheduler"
              element={
                <RequirePermission perm="reports.schedule.manage">
                  <ReportSchedulerPage />
                </RequirePermission>
              }
            />
            <Route
              path="analytics"
              element={
                <RequirePermission perm="reports.people.read">
                  <AnalyticsDashboardPage />
                </RequirePermission>
              }
            />
            <Route
              path="enterprise"
              element={
                <RequirePermission perm="organization.entity.read">
                  <EnterpriseManagementPage />
                </RequirePermission>
              }
            />
            <Route
              path="operations"
              element={
                <RequirePermission
                  perm={['reports.read', 'operations.mission.manage', 'operations.convoy.manage']}
                >
                  <OperationsCenterPage />
                </RequirePermission>
              }
            />
            <Route path="helpdesk" element={<FeatureGate feature="helpdesk"><HelpdeskPage /></FeatureGate>} />
            <Route path="finance" element={<FeatureGate feature="peopleFinance"><FinancePage /></FeatureGate>} />
            <Route
              path="finance/penalties"
              element={
                <RequirePermission perm={['payroll.run.manage', 'payroll.run.approve']}>
                  <EmployeePenaltiesPage />
                </RequirePermission>
              }
            />
            <Route
              path="finance/instapay"
              element={
                <RequirePermission perm={['payroll.run.manage', 'payroll.run.approve', 'payroll.payslip.read']}>
                  <InstapayPage />
                </RequirePermission>
              }
            />
            <Route
              path="audit-trail"
              element={
                <RequirePermission perm="audit.view">
                  <AuditTrailPage />
                </RequirePermission>
              }
            />
            <Route
              path="system-settings"
              element={
                <RequirePermission perm="settings.manage">
                  <SystemSettingsPage />
                </RequirePermission>
              }
            />
            <Route
              path="audit-security"
              element={
                <RequirePermission perm="audit.view">
                  <AuditSecurityPage />
                </RequirePermission>
              }
            />
            <Route
              path="observability"
              element={
                <RequirePermission perm="system.release.read">
                  <ObservabilityDashboardPage />
                </RequirePermission>
              }
            />
            <Route
              path="integrations"
              element={
                <RequirePermission perm="system.integration.view">
                  <IntegrationsJobsPage />
                </RequirePermission>
              }
            />
            {/* notifications/knowledge: مرئيان لكل أعضاء المساحة — لا يحتاجان permission خاص */}
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="knowledge" element={<RequirePermission perm="knowledge.article.read"><KnowledgePage /></RequirePermission>} />
          </Route>
        </Route>

        <Route element={<WorkspaceGuard workspace="committee" />}>
          <Route path="/committee" element={<WorkspaceShell workspace="committee" />}>
            <Route
              index
              element={
                <RequirePermission perm="disputes.portal.access">
                  <DisputesPage />
                </RequirePermission>
              }
            />
            <Route
              path="disputes"
              element={
                <RequirePermission perm="disputes.portal.access">
                  <DisputesPage />
                </RequirePermission>
              }
            />
            <Route path="notifications" element={<NotificationsPage />} />
          </Route>
        </Route>

        <Route path="*" element={<Navigate to={workspacePath(defaultWorkspace)} replace />} />
      </Routes>
    </Suspense>
  );
}

/**
 * جميع مسارات صفحات الموارد البشرية — تُستعمل مرتين:
 * داخل /hr (لحسابات HR المستقلة) وداخل /admin/hr (للأدمن الرئيسي).
 */
function HrWorkspaceRoutes() {
  return (
    <Routes>
      <Route
        path="employees"
        element={
          <RequirePermission perm="people.employee.read">
            <EmployeesPage />
          </RequirePermission>
        }
      />
      <Route
        path="employees/new"
        element={
          <RequirePermission perm="people.employee.create">
            <CreateEmployeePage />
          </RequirePermission>
        }
      />
      <Route
        path="employees/:employeeId"
        element={
          <RequirePermission perm="people.employee.read">
            <EmployeeDetailPage />
          </RequirePermission>
        }
      />
      <Route
        path="attendance"
        element={
          <RequirePermission perm="attendance.record.read">
            <AttendancePage />
          </RequirePermission>
        }
      />
      <Route
        path="attendance/details"
        element={
          <RequirePermission perm="attendance.record.read">
            <AttendanceDrilldownPage />
          </RequirePermission>
        }
      />
      <Route
        path="attendance/operations"
        element={
          <RequirePermission perm="attendance.roster.read">
            <AttendanceOperationsPage />
          </RequirePermission>
        }
      />
      <Route
        path="attendance/report"
        element={
          <RequirePermission perm="attendance.record.read">
            <MonthlyAttendanceReportPage />
          </RequirePermission>
        }
      />
      <Route
        path="performance"
        element={
          <RequirePermission perm="performance.kpi.read">
            <PerformancePage />
          </RequirePermission>
        }
      />
      <Route
        path="recruitment"
        element={
          <RequirePermission perm="recruitment.requisition.read">
            <RecruitmentPage />
          </RequirePermission>
        }
      />
      <Route
        path="onboarding"
        element={
          <RequirePermission perm="onboarding.journey.read">
            <OnboardingPage />
          </RequirePermission>
        }
      />
      <Route
        path="reports"
        element={
          <RequirePermission perm="reports.people.read">
            <ReportsPage />
          </RequirePermission>
        }
      />
      <Route
        path="analytics"
        element={
          <RequirePermission perm="reports.people.read">
            <AnalyticsDashboardPage />
          </RequirePermission>
        }
      />
      <Route
        path="holidays"
        element={
          <RequirePermission perm="holidays.manage">
            <OfficialHolidaysPage />
          </RequirePermission>
        }
      />
      <Route
        path="requests"
        element={
          <RequirePermission perm="requests.request.read">
            <RequestsPage />
          </RequirePermission>
        }
      />
      <Route
        path="devices"
        element={
          <RequirePermission perm="access.role.read">
            <DeviceApprovalPage />
          </RequirePermission>
        }
      />
      <Route
        path="organization"
        element={
          <RequirePermission perm="organization.org_chart.read">
            <OrganizationPage />
          </RequirePermission>
        }
      />
      <Route path="leaves" element={<RequirePermission perm="requests.request.read"><LeavesPage /></RequirePermission>} />
      <Route path="learning" element={<RequirePermission perm="learning.enroll"><LearningPage /></RequirePermission>} />
      <Route path="lifecycle" element={<RequirePermission perm="people.employee.read"><LifecyclePage /></RequirePermission>} />
      <Route path="documents" element={<RequirePermission perm="documents.document.read"><DocumentsPage /></RequirePermission>} />
      <Route
        path="official-feed"
        element={
          <RequirePermission perm={['comms.announcement.read', 'comms.decision.read']}>
            <OfficialFeedPage />
          </RequirePermission>
        }
      />
      <Route path="daily-reports" element={<RequirePermission perm={['reports.daily.read', 'people.employee.read']}><DailyReportsFeedPage /></RequirePermission>} />
      <Route path="knowledge" element={<RequirePermission perm="knowledge.article.read"><KnowledgePage /></RequirePermission>} />
      <Route path="notifications" element={<NotificationsPage />} />
      <Route path="*" element={<Navigate to="employees" replace />} />
    </Routes>
  );
}

/**
 * إعادة توجيه تلقائية: الأدمن الرئيسي الذي يزور أي مسار /hr/*
 * يُنقل إلى نفس الصفحة داخل القائمة الموحّدة /admin/hr/*
 * حتى لا يغادر واجهته الموحّدة. حسابات HR المستقلة لا تتأثر.
 */
function LegacyHrRedirect() {
  const auth = useAuth();
  const location = useLocation();
  const isMainAdmin = auth.access?.workspaces.includes('main_admin') ?? false;
  const target = isMainAdmin ? hrPathToAdmin(location.pathname) : null;
  if (target) {
    return <Navigate to={`${target}${location.search}${location.hash}`} replace />;
  }
  return <Outlet />;
}

function WorkspaceGuard({ workspace }: { workspace: WorkspaceId }) {
  const auth = useAuth();
  if (!auth.access?.workspaces.includes(workspace)) {
    const fallback = auth.access ? firstWebWorkspace(auth.access) : undefined;
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
