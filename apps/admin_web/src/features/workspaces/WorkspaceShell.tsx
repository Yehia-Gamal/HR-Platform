import type { WorkspaceId } from '@ahla/shared-contracts';
import {
  Activity,
  BadgeCheck,
  Bell,
  BookOpenCheck,
  BriefcaseBusiness,
  Building2,
  CalendarClock,
  Cable,
  ChevronDown,
  ClipboardList,
  FileClock,
  FileSignature,
  Gauge,
  Gavel,
  LayoutDashboard,
  ListChecks,
  LogOut,
  Megaphone,
  Menu,
  Headphones,
  MapPin,
  Network,
  PackageCheck,
  PanelRightClose,
  PanelRightOpen,
  Settings,
  ShieldAlert,
  ShieldCheck,
  Smartphone,
  Sparkles,
  TimerReset,
  Users,
  WalletCards,
  X,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import { AppLogo } from '../../ui/AppLogo';
import { RouteErrorBoundary } from '../../ui/RouteErrorBoundary';
import { ThemeToggle } from '../../ui/ThemeToggle';
import { UserAvatar } from '../../ui/UserAvatar';
import { WorkspaceSearch } from '../../ui/WorkspaceSearch';
import { getShortName } from '../../ui/formatDisplayName';
import { useAuth } from '../auth/AuthProvider';
import { useNotifications } from '../notifications/useNotifications';
import { hasAnyPermission } from './access';
import { isFeatureEnabled, type FeatureFlagKey } from '../../ui/featureFlags';

interface NavItem {
  label: string;
  to: string;
  icon: typeof LayoutDashboard;
  /** صلاحية واحدة أو عدة صلاحيات (OR) — يظهر العنصر إذا يملك المستخدم أي واحدة منها */
  permission?: string | string[];
  /** V23 §13 — إذا وُجد، لا يظهر العنصر إلا إذا كان الـ flag مفعّلًا */
  featureFlag?: FeatureFlagKey;
}
interface NavSection { title: string; items: NavItem[] }

const hrSections: NavSection[] = [
  { title: 'نظرة عامة', items: [
    { label: 'لوحة HR', to: '/hr', icon: LayoutDashboard },
    { label: 'الموظفون', to: '/hr/employees', icon: Users, permission: 'people.employee.read' },
  ] },
  { title: 'الوقت والخدمات', items: [
    { label: 'الحضور', to: '/hr/attendance', icon: Activity, permission: 'attendance.record.read' },
    { label: 'الورديات وإغلاق الحضور', to: '/hr/attendance/operations', icon: CalendarClock, permission: 'attendance.roster.read' },
    { label: 'كشف الحضور الشهري', to: '/hr/attendance/report', icon: FileSignature, permission: 'attendance.record.read' },
    { label: 'طلب إجازة', to: '/hr/requests', icon: ClipboardList, permission: 'requests.request.read' },
    { label: 'العطل الرسمية', to: '/hr/holidays', icon: CalendarClock, permission: 'holidays.manage' },
  ] },
  { title: 'الأداء والتطوير', items: [
    { label: 'KPI والأداء', to: '/hr/performance', icon: Gauge, permission: 'performance.kpi.read' },
    { label: 'التدريب والمهارات', to: '/hr/learning', icon: Sparkles, featureFlag: 'learning' },
  ] },
  { title: 'رحلة الموظف', items: [
    { label: 'التوظيف', to: '/hr/recruitment', icon: BriefcaseBusiness, permission: 'recruitment.requisition.read' },
    { label: 'Onboarding', to: '/hr/onboarding', icon: ListChecks, permission: 'onboarding.journey.read' },
    { label: 'دورة حياة الموظف', to: '/hr/lifecycle', icon: PackageCheck, featureFlag: 'lifecycle' },
    { label: 'استوديو المستندات', to: '/hr/documents', icon: FileSignature, featureFlag: 'documents' },
  ] },
  { title: 'التواصل والتحليلات', items: [
    { label: 'تقارير HR', to: '/hr/reports', icon: FileClock, permission: 'reports.people.read' },
    { label: 'الأخبار والقرارات', to: '/hr/official-feed', icon: Megaphone },
    { label: 'الإشعارات', to: '/hr/notifications', icon: Bell },
  ] },
];

const adminSections: NavSection[] = [
  { title: 'القيادة', items: [
    { label: 'لوحة الإدارة', to: '/admin', icon: LayoutDashboard },
    { label: 'مركز الإجراءات', to: '/admin/actions', icon: BadgeCheck },
    { label: 'مركز الموقع الحي', to: '/admin/live-location', icon: MapPin, permission: 'live_location.request' },
    { label: 'متابعة الموظفين اليومية', to: '/admin/live-location/monitoring', icon: MapPin, permission: 'live_location.request' },
    { label: 'الأخبار والقرارات', to: '/admin/official-feed', icon: Megaphone, permission: ['comms.announcement.read', 'comms.decision.read'] },
    { label: 'أجهزة الموظفين', to: '/admin/device-approvals', icon: Smartphone },
  ] },
  { title: 'الحوكمة والتنظيم', items: [
    { label: 'الهيكل المؤسسي', to: '/admin/organization', icon: Network },
    { label: 'دورات KPI والاعتراضات', to: '/admin/performance/cycles', icon: BadgeCheck, permission: 'performance.cycle.manage' },
    { label: 'لجنة الخلافات', to: '/admin/disputes', icon: Gavel, permission: 'relations.case.manage' },
    { label: 'الأدوار والصلاحيات', to: '/admin/access', icon: ShieldCheck, permission: 'access.role.read' },
    { label: 'الحوكمة والمخاطر', to: '/admin/governance', icon: ShieldAlert, featureFlag: 'governance' },
  ] },
  { title: 'الخدمات المؤسسية', items: [
    { label: 'دورة حياة الموظف', to: '/admin/lifecycle', icon: PackageCheck, featureFlag: 'lifecycle' },
    { label: 'استوديو المستندات', to: '/admin/documents', icon: FileSignature, featureFlag: 'documents' },
    { label: 'جدولة التقارير', to: '/admin/reports/scheduler', icon: TimerReset, permission: 'reports.schedule.manage' },
    { label: 'العمليات والمهام', to: '/admin/operations', icon: ClipboardList, permission: 'tasks.read' },
    { label: 'مكتب الخدمات', to: '/admin/helpdesk', icon: Headphones, featureFlag: 'helpdesk' },
    { label: 'الإدارة المؤسسية', to: '/admin/enterprise', icon: Building2 },
    { label: 'الرواتب والمالية', to: '/admin/finance', icon: WalletCards, featureFlag: 'peopleFinance' },
  ] },
  { title: 'النظام', items: [
    { label: 'التدقيق والأمان', to: '/admin/audit-security', icon: ShieldCheck, permission: 'audit.view' },
    { label: 'التكاملات والمهام الخلفية', to: '/admin/integrations', icon: Cable, permission: 'system.integration.view' },
    { label: 'إعدادات النظام', to: '/admin/settings', icon: Settings, permission: 'system.settings.read' },
    { label: 'الإشعارات', to: '/admin/notifications', icon: Bell },
  ] },
];

export function WorkspaceShell({ workspace }: { workspace: WorkspaceId }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const notificationsQuery = useNotifications();
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(() => window.localStorage.getItem('ahla-sidebar') === 'collapsed');
  const access = auth.access!;
  const sections = workspace === 'hr' ? hrSections : adminSections;
  const allowedSections = sections.map((section) => ({
    ...section,
    items: section.items.filter((item) =>
      (!item.permission || hasAnyPermission(access, item.permission)) &&
      (!item.featureFlag || isFeatureEnabled(item.featureFlag)),
    ),
  })).filter((section) => section.items.length > 0);
  const allItems = allowedSections.flatMap((section) => section.items.map((item) => ({ ...item, group: section.title })));

  const workspaceOptions = useMemo(
    () => [
      access.workspaces.includes('hr') ? { id: 'hr' as const, label: 'مساحة الموارد البشرية', path: '/hr' } : null,
      access.workspaces.includes('main_admin') ? { id: 'main_admin' as const, label: 'مساحة الإدارة الرئيسية', path: '/admin' } : null,
    ].filter(Boolean) as Array<{ id: 'hr' | 'main_admin'; label: string; path: string }>,
    [access.workspaces],
  );

  const currentWorkspaceLabel = workspace === 'hr' ? 'الموارد البشرية' : 'الإدارة الرئيسية';
  const currentItem = [...allItems].sort((a, b) => b.to.length - a.to.length).find((item) => location.pathname === item.to || location.pathname.startsWith(`${item.to}/`));
  const userMetadata = auth.session?.user.user_metadata;
  const profilePhotoUrl = access.photoUrl ?? (typeof userMetadata?.photo_url === 'string'
    ? userMetadata.photo_url
    : typeof userMetadata?.avatar_url === 'string' ? userMetadata.avatar_url : null);
  const unreadCount = (notificationsQuery.data ?? []).filter((item) => !item.isRead).length;
  const toggleCollapsed = () => {
    const next = !collapsed;
    setCollapsed(next);
    window.localStorage.setItem('ahla-sidebar', next ? 'collapsed' : 'expanded');
  };

  return (
    <div className={`app-shell ${collapsed ? 'sidebar-collapsed' : ''}`}>
      <a className="skip-link" href="#main-content">تخطي إلى المحتوى الرئيسي</a>
      {open ? <button aria-label="إغلاق القائمة" className="mobile-overlay" onClick={() => setOpen(false)} /> : null}
      <aside className={`app-sidebar ${open ? 'is-open' : ''}`}>
        <div className="sidebar-brand">
          <AppLogo compact={collapsed} />
          <button className="icon-button mobile-nav-control" aria-label="إغلاق" onClick={() => setOpen(false)}><X className="size-4.5" /></button>
        </div>

        <div className="workspace-switcher-wrap">
          {!collapsed ? <label className="sidebar-caption" htmlFor="workspace-switcher">مساحة العمل الحالية</label> : null}
          <div className="relative">
            <select
              id="workspace-switcher"
              aria-label="تبديل مساحة العمل"
              value={workspace}
              onChange={(event) => {
                const option = workspaceOptions.find((item) => item.id === event.target.value);
                if (option) navigate(option.path);
              }}
              className="workspace-switcher"
            >
              {workspaceOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
            </select>
            {!collapsed ? <ChevronDown className="pointer-events-none absolute start-3 top-3 size-4 text-[var(--text-muted)]" /> : null}
          </div>
        </div>

        <nav className="sidebar-nav" aria-label={currentWorkspaceLabel}>
          {allowedSections.map((section) => (
            <section key={section.title} className="sidebar-section">
              {!collapsed ? <h2>{section.title}</h2> : <span className="sidebar-divider" />}
              <div className="space-y-1">
                {section.items.map((item) => {
                  const Icon = item.icon;
                  const exact = item.to === '/hr' || item.to === '/admin';
                  return (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      end={exact}
                      title={collapsed ? item.label : undefined}
                      onClick={() => setOpen(false)}
                      className={({ isActive }) => `sidebar-link ${isActive ? 'is-active' : ''}`}
                    >
                      <Icon className="size-5 shrink-0" aria-hidden="true" />
                      {!collapsed ? <span className="truncate">{item.label}</span> : null}
                    </NavLink>
                  );
                })}
              </div>
            </section>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="sidebar-user">
            <UserAvatar displayName={access.displayName} photoUrl={profilePhotoUrl} eager />
            {!collapsed ? <div className="min-w-0 flex-1"><p className="truncate text-sm font-black" title={access.displayName}>{getShortName(access.displayName)}</p><p className="truncate text-xs text-[var(--text-muted)]">{currentWorkspaceLabel}</p></div> : null}
          </div>
          <button type="button" className="sidebar-logout" title="تسجيل الخروج" onClick={() => void auth.signOut()}>
            <LogOut className="size-4.5" aria-hidden="true" />
            {!collapsed ? <span>تسجيل الخروج</span> : null}
          </button>
        </div>
      </aside>

      <div className="app-content">
        <header className="app-header">
          <div className="header-context flex min-w-0 items-center gap-3">
            <button className="icon-button mobile-nav-control" aria-label="فتح القائمة" onClick={() => setOpen(true)}><Menu className="size-5" aria-hidden="true" /></button>
            <button className="icon-button desktop-nav-control" aria-label={collapsed ? 'توسيع القائمة' : 'تصغير القائمة'} onClick={toggleCollapsed}>
              {collapsed ? <PanelRightOpen className="size-4.5" aria-hidden="true" /> : <PanelRightClose className="size-4.5" aria-hidden="true" />}
            </button>
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--text-muted)]">
                <span className="header-workspace-name">{currentWorkspaceLabel}</span><span className="header-breadcrumb-separator">/</span><span className="truncate text-[var(--brand-primary)]">{currentItem?.label ?? 'الرئيسية'}</span>
              </div>
              <h1 className="truncate text-base font-black sm:text-lg">{currentItem?.label ?? currentWorkspaceLabel}</h1>
            </div>
          </div>

          <div className="header-actions flex items-center gap-2">
            <WorkspaceSearch destinations={allItems.map((item) => ({ label: item.label, to: item.to, group: item.group }))} />
            <ThemeToggle />
            <button type="button" className="icon-button relative" aria-label={unreadCount ? `الإشعارات، ${unreadCount} غير مقروء` : 'الإشعارات'} onClick={() => navigate(workspace === 'hr' ? '/hr/notifications' : '/admin/notifications')}>
              <Bell className="size-4.5" aria-hidden="true" />
              {unreadCount ? <span className="notification-count" aria-hidden="true">{unreadCount > 99 ? '99+' : unreadCount}</span> : null}
            </button>
            <details className="profile-menu">
              <summary className="header-profile" title={access.displayName} aria-label="فتح قائمة الحساب">
                <UserAvatar displayName={access.displayName} photoUrl={profilePhotoUrl} size="sm" eager announceName={false} />
                <span className="hidden max-w-32 truncate text-sm font-bold xl:inline">{getShortName(access.displayName)}</span>
                <ChevronDown className="hidden size-3.5 text-[var(--text-muted)] xl:block" />
              </summary>
              <div className="profile-popover">
                <div className="border-b border-[var(--border)] p-3">
                  <p className="truncate text-sm font-black">{access.displayName}</p>
                  <p className="mt-1 truncate text-xs text-[var(--text-muted)]">{access.employeeCode ?? currentWorkspaceLabel}</p>
                </div>
                <button type="button" onClick={() => navigate(workspace === 'hr' ? '/hr/notifications' : '/admin/notifications')}><Bell className="size-4" aria-hidden="true" />الإشعارات{unreadCount ? ` (${unreadCount})` : ''}</button>
                <button type="button" onClick={() => void auth.signOut()}><LogOut className="size-4" aria-hidden="true" />تسجيل الخروج</button>
              </div>
            </details>
          </div>
        </header>
        <main id="main-content" tabIndex={-1} key={location.pathname} className="page-container">
          <RouteErrorBoundary><Outlet /></RouteErrorBoundary>
        </main>
      </div>
    </div>
  );
}
