import type { WorkspaceId } from '@ahla/shared-contracts';
import {
  Activity,
  BadgeCheck,
  Bell,
  BookOpen,
  BriefcaseBusiness,
  Building2,
  CalendarClock,
  CalendarDays,
  Cable,
  Camera,
  ChevronDown,
  ClipboardList,
  FileClock,
  FileSignature,
  Gauge,
  Gavel,
  KeyRound,
  LayoutDashboard,
  ListChecks,
  LogOut,
  Megaphone,
  Menu,
  Headphones,
  MapPin,
  PackageCheck,
  PanelRightClose,
  PanelRightOpen,
  ScrollText,
  Settings,
  ShieldAlert,
  ShieldCheck,
  Smartphone,
  Sparkles,
  TimerReset,
  Users,
  WalletCards,
  X,
  Search,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router';
import { AppLogo } from '../../ui/AppLogo';
import { RouteErrorBoundary } from '../../ui/RouteErrorBoundary';
import { ThemeToggle } from '../../ui/ThemeToggle';
import { UserAvatar } from '../../ui/UserAvatar';
import { WorkspaceSearch } from '../../ui/WorkspaceSearch';
import { getShortName } from '../../ui/formatDisplayName';
import { useAuth } from '../auth/AuthProvider';
import { useNotifications } from '../notifications/useNotifications';
import { hasAnyPermission, isUnifiedAdminActive } from './access';
import { ChangePhotoDialog } from './ChangePhotoDialog';
import { isFeatureEnabled, type FeatureFlagKey } from '../../ui/featureFlags';
import { HRCopilotDrawer } from '../ai/HRCopilotDrawer';

interface NavItem {
  label: string;
  to: string;
  icon: typeof LayoutDashboard;
  /** صلاحية واحدة أو عدة صلاحيات (OR) — يظهر العنصر إذا يملك المستخدم أي واحدة منها */
  permission?: string | string[];
  /** V23 §13 — إذا وُجد، لا يظهر العنصر إلا إذا كان الـ flag مفعّلًا */
  featureFlag?: FeatureFlagKey;
}
interface NavSection {
  title: string;
  items: NavItem[];
}

const hrSections: NavSection[] = [
  {
    title: 'نظرة عامة',
    items: [
      { label: 'لوحة HR', to: '/hr', icon: LayoutDashboard },
      { label: 'الموظفون والهيكل', to: '/hr/employees', icon: Users, permission: 'people.employee.read' },
      { label: 'هيكل المنظمة', to: '/hr/organization', icon: Building2, permission: 'organization.entity.read' },
      { label: 'أجهزة الموظفين', to: '/hr/devices', icon: Smartphone, permission: 'access.role.read' },
    ],
  },
  {
    title: 'الوقت والخدمات',
    items: [
      { label: 'الحضور', to: '/hr/attendance', icon: Activity, permission: 'attendance.record.read' },
      { label: 'طلب إجازة', to: '/hr/requests', icon: ClipboardList, permission: 'requests.request.read' },
      { label: 'إدارة الإجازات', to: '/hr/leaves', icon: CalendarDays, permission: 'requests.request.read' },
      { label: 'أدوات الإجازات والتكليفات', to: '/hr/leave-tools', icon: TimerReset, permission: 'requests.leave.balance.adjust' },
      { label: 'العطل الرسمية', to: '/hr/holidays', icon: CalendarClock, permission: 'holidays.manage' },
    ],
  },
  {
    title: 'الأداء والتطوير',
    items: [
      { label: 'KPI والأداء', to: '/hr/performance', icon: Gauge, permission: 'performance.kpi.read' },
      { label: 'التدريب والمهارات', to: '/hr/learning', icon: Sparkles, featureFlag: 'learning' },
    ],
  },
  {
    title: 'رحلة الموظف',
    items: [
      { label: 'التوظيف', to: '/hr/recruitment', icon: BriefcaseBusiness, permission: 'recruitment.requisition.read' },
      { label: 'تهيئة الموظفين', to: '/hr/onboarding', icon: ListChecks, permission: 'onboarding.journey.read' },
      { label: 'دورة حياة الموظف', to: '/hr/lifecycle', icon: PackageCheck, featureFlag: 'lifecycle' },
      { label: 'كلمات المرور والحسابات', to: '/hr/passwords', icon: KeyRound, permission: 'people.employee.read' },
      { label: 'المستندات', to: '/hr/documents', icon: FileSignature, featureFlag: 'documents' },
    ],
  },
  {
    title: 'التواصل والتقارير',
    items: [
      { label: 'التقارير والتحليلات', to: '/hr/reports', icon: FileClock, permission: 'reports.people.read' },
      { label: 'الأخبار والقرارات', to: '/hr/official-feed', icon: Megaphone, permission: ['comms.announcement.read', 'comms.decision.read'] },
      { label: 'التقارير اليومية', to: '/hr/daily-reports', icon: ClipboardList },
      { label: 'التدريب والمعرفة', to: '/hr/knowledge', icon: BookOpen },
      { label: 'الإشعارات', to: '/hr/notifications', icon: Bell },
    ],
  },
];

const adminSections: NavSection[] = [
  {
    title: 'نظرة عامة',
    items: [
      { label: 'لوحة التحكم', to: '/admin', icon: LayoutDashboard },
      { label: 'مركز الإجراءات', to: '/admin/actions', icon: BadgeCheck, permission: 'access.role.read' },
      { label: 'الإشعارات', to: '/admin/notifications', icon: Bell },
    ],
  },
  {
    title: 'الموظفون',
    items: [
      { label: 'الموظفون والهيكل', to: '/admin/hr/employees', icon: Users, permission: 'people.employee.read' },
      { label: 'كلمات المرور والحسابات', to: '/admin/hr/passwords', icon: KeyRound, permission: 'people.employee.read' },
      { label: 'هيكل المنظمة', to: '/admin/hr/organization', icon: Building2, permission: 'organization.entity.read' },
      { label: 'أجهزة الموظفين', to: '/admin/hr/devices', icon: Smartphone, permission: 'access.role.read' },
      { label: 'دورة حياة الموظف', to: '/admin/hr/lifecycle', icon: PackageCheck, permission: 'people.employee.read' },
      { label: 'تهيئة الموظفين', to: '/admin/hr/onboarding', icon: ListChecks, permission: 'onboarding.journey.read' },
      { label: 'التوظيف', to: '/admin/hr/recruitment', icon: BriefcaseBusiness, permission: 'recruitment.requisition.read' },
      { label: 'المستندات', to: '/admin/hr/documents', icon: FileSignature, permission: 'documents.document.read' },
    ],
  },
  {
    title: 'الحضور والموقع',
    items: [
      { label: 'الحضور', to: '/admin/hr/attendance', icon: Activity, permission: 'attendance.record.read' },
      { label: 'الموقع الحي للموظفين', to: '/admin/live-location', icon: MapPin, permission: 'live_location.request' },
      { label: 'المراقبة التنفيذية', to: '/admin/executive-monitoring', icon: Activity, permission: 'people.employee.read' },
    ],
  },
  {
    title: 'الطلبات والإجازات',
    items: [
      { label: 'طلبات الموظفين', to: '/admin/hr/requests', icon: ClipboardList, permission: 'requests.request.read' },
      { label: 'إدارة الإجازات', to: '/admin/hr/leaves', icon: CalendarDays, permission: 'requests.request.read' },
      { label: 'أدوات الإجازات والتكليفات', to: '/admin/hr/leave-tools', icon: TimerReset, permission: 'requests.leave.balance.adjust' },
      { label: 'العطل الرسمية', to: '/admin/hr/holidays', icon: CalendarDays, permission: 'holidays.manage' },
    ],
  },
  {
    title: 'الأداء والتطوير',
    items: [
      { label: 'KPI والأداء', to: '/admin/hr/performance', icon: Gauge, permission: 'performance.kpi.read' },
      { label: 'دورات KPI والاعتراضات', to: '/admin/performance/cycles', icon: BadgeCheck, permission: 'performance.cycle.manage' },
      { label: 'التدريب والمهارات', to: '/admin/hr/learning', icon: Sparkles, permission: 'learning.enroll' },
    ],
  },
  {
    title: 'القيادة والرقابة',
    items: [
      { label: 'لجنة الخلافات', to: '/admin/disputes', icon: Gavel, permission: ['disputes.case.manage', 'disputes.portal.access'] },
      { label: 'مكتب الخدمات', to: '/admin/helpdesk', icon: Headphones, featureFlag: 'helpdesk' },
      { label: 'الرواتب والمالية', to: '/admin/finance', icon: WalletCards, featureFlag: 'peopleFinance' },
    ],
  },
  {
    title: 'الأمن والتدقيق',
    items: [
      { label: 'التدقيق والأمان', to: '/admin/audit-security', icon: ShieldCheck, permission: 'audit.view' },
      { label: 'سجل التدقيق', to: '/admin/audit-trail', icon: ScrollText, permission: 'audit.view' },
      { label: 'الحوكمة والمخاطر', to: '/admin/governance', icon: ShieldAlert, featureFlag: 'governance' },
    ],
  },
  {
    title: 'النظام والتكامل',
    items: [
      { label: 'الأدوار والصلاحيات', to: '/admin/access', icon: ShieldCheck, permission: 'access.role.read' },
      { label: 'الإدارة المؤسسية', to: '/admin/enterprise', icon: Building2, permission: 'organization.entity.read' },
      { label: 'الإعدادات', to: '/admin/settings', icon: Settings, permission: 'system.settings.read' },
      { label: 'التكاملات والمهام الخلفية', to: '/admin/integrations', icon: Cable, permission: 'system.integration.view' },
      { label: 'لوحة المراقبة', to: '/admin/observability', icon: Activity, permission: 'system.release.read' },
    ],
  },
  {
    title: 'التقارير والتواصل',
    items: [
      { label: 'التقارير والتحليلات', to: '/admin/hr/reports', icon: FileClock, permission: 'reports.people.read' },
      { label: 'الأخبار والقرارات', to: '/admin/hr/official-feed', icon: Megaphone, permission: ['comms.announcement.read', 'comms.decision.read'] },
      { label: 'التقارير اليومية', to: '/admin/hr/daily-reports', icon: ClipboardList, permission: ['reports.daily.read', 'people.employee.read'] },
      { label: 'التدريب والمعرفة', to: '/admin/knowledge', icon: BookOpen, permission: 'knowledge.article.read' },
    ],
  },
];

const committeeSections: NavSection[] = [
  {
    title: 'لجنة الخلافات',
    items: [
      { label: 'القضايا', to: '/committee', icon: Gavel, permission: 'disputes.portal.access' },
      { label: 'سجل القضايا', to: '/committee/disputes', icon: ClipboardList, permission: 'disputes.portal.access' },
      { label: 'الإشعارات', to: '/committee/notifications', icon: Bell },
    ],
  },
];

export function WorkspaceShell({ workspace }: { workspace: WorkspaceId }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const notificationsQuery = useNotifications();
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const [changePhotoOpen, setChangePhotoOpen] = useState(false);
  const [isCopilotOpen, setIsCopilotOpen] = useState(false);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.altKey && (e.key === 'c' || e.key === 'C' || e.key === 'ؤ')) {
        e.preventDefault();
        setIsCopilotOpen((prev) => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
  const [collapsed, setCollapsed] = useState(() =>
    (() => {
      try {
        return window.localStorage.getItem('ahla-sidebar') === 'collapsed';
      } catch {
        return false;
      }
    })(),
  );
  // أكورديون الأقسام (بند تنظيم اللوحة): الأقسام مطوية افتراضياً إلا
  // القسم الذي يحوي الصفحة النشطة — والتغيير يُحفظ في المتصفح.
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>(() => {
    try {
      return JSON.parse(window.localStorage.getItem('ahla-sidebar-sections') ?? '{}') as Record<string, boolean>;
    } catch {
      return {};
    }
  });
  const toggleSection = (title: string) => {
    setExpandedSections((prev) => {
      const next = { ...prev, [title]: !(prev[title] ?? false) };
      try {
        window.localStorage.setItem('ahla-sidebar-sections', JSON.stringify(next));
      } catch {
        /* التخزين اختياري */
      }
      return next;
    });
  };
  const access = auth.access;
  if (!access) throw new Error('WorkspaceShell requires an authenticated session');
  // الأدمن الرئيسي يرى قائمة موحّدة واحدة تجمع الإدارة + HR + اللجنة —
  // بدون الحاجة لتبديل مساحات العمل.
  const unifiedAdmin = isUnifiedAdminActive(access.workspaces, location.pathname);
  const sections = workspace === 'hr' ? hrSections : workspace === 'committee' ? committeeSections : adminSections;
  const allowedSections = useMemo(
    () =>
      sections
        .map((section) => ({
          ...section,
          items: section.items.filter(
            (item) => (!item.permission || hasAnyPermission(access, item.permission)) && (!item.featureFlag || isFeatureEnabled(item.featureFlag)),
          ),
        }))
        .filter((section) => section.items.length > 0),
    [sections, access],
  );
  const allItems = useMemo(() => allowedSections.flatMap((section) => section.items.map((item) => ({ ...item, group: section.title }))), [allowedSections]);

  const workspaceOptions = useMemo(
    () =>
      [
        access.workspaces.includes('hr') ? { id: 'hr' as const, label: 'مساحة الموارد البشرية', path: '/hr' } : null,
        access.workspaces.includes('main_admin') ? { id: 'main_admin' as const, label: 'مساحة الإدارة الرئيسية', path: '/admin' } : null,
        access.workspaces.includes('committee') ? { id: 'committee' as const, label: 'لجنة الخلافات', path: '/committee' } : null,
      ].filter(Boolean) as Array<{ id: WorkspaceId; label: string; path: string }>,
    [access.workspaces],
  );

  const currentWorkspaceLabel =
    workspace === 'hr' ? 'الموارد البشرية' : workspace === 'committee' ? 'لجنة الخلافات' : unifiedAdmin ? 'المنصة الموحّدة' : 'الإدارة الرئيسية';
  const currentItem = [...allItems]
    .sort((a, b) => b.to.length - a.to.length)
    .find((item) => location.pathname === item.to || location.pathname.startsWith(`${item.to}/`));
  const userMetadata = auth.session?.user.user_metadata;
  const profilePhotoUrl =
    access.photoUrl ??
    (typeof userMetadata?.photo_url === 'string' ? userMetadata.photo_url : typeof userMetadata?.avatar_url === 'string' ? userMetadata.avatar_url : null);
  const unreadCount = (notificationsQuery.data ?? []).filter((item) => !item.isRead).length;
  const toggleCollapsed = () => {
    const next = !collapsed;
    setCollapsed(next);
    window.localStorage.setItem('ahla-sidebar', next ? 'collapsed' : 'expanded');
  };

  return (
    <div className={`app-shell ${collapsed ? 'sidebar-collapsed' : ''}`}>
      <a className="skip-link" href="#main-content">
        تخطي إلى المحتوى الرئيسي
      </a>
      {open ? <button aria-label="إغلاق القائمة" className="mobile-overlay" onClick={() => setOpen(false)} /> : null}
      <aside className={`app-sidebar ${open ? 'is-open' : ''}`}>
        <div className="sidebar-brand">
          <AppLogo compact={collapsed} />
          <button className="icon-button mobile-nav-control" aria-label="إغلاق" onClick={() => setOpen(false)}>
            <X className="size-4.5" />
          </button>
        </div>

        <div className="workspace-switcher-wrap">
          {/* الأدمن الرئيسي لديه قائمة موحّدة تجمع كل شيء — لا حاجة لتبديل مساحة العمل */}
          {unifiedAdmin ? (
            !collapsed ? (
              <div className="workspace-switcher-static">
                <ShieldCheck className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                <span>المنصة الموحّدة — كل الصفحات</span>
              </div>
            ) : null
          ) : (
            <>
              {!collapsed ? (
                <label className="sidebar-caption" htmlFor="workspace-switcher">
                  مساحة العمل الحالية
                </label>
              ) : null}
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
                  {workspaceOptions.map((option) => (
                    <option key={option.id} value={option.id}>
                      {option.label}
                    </option>
                  ))}
                </select>
                {!collapsed ? <ChevronDown className="pointer-events-none absolute start-3 top-3 size-4 text-[var(--text-muted)]" /> : null}
              </div>
            </>
          )}
        </div>

        <nav className="sidebar-nav" aria-label={currentWorkspaceLabel}>
          {allowedSections.map((section) => {
            // القسم الذي يحوي الصفحة النشطة يُوسَّع تلقائياً ما لم يطوِه المستخدم.
            const hasActive = section.items.some((item) => {
              const exact = item.to === '/hr' || item.to === '/admin' || item.to === '/committee';
              return exact ? location.pathname === item.to : location.pathname.startsWith(item.to);
            });
            const isExpanded = collapsed ? true : (expandedSections[section.title] ?? hasActive);
            return (
              <section key={section.title} className="sidebar-section">
                {!collapsed ? (
                  <button
                    type="button"
                    className="flex w-full items-center justify-between px-3 pb-1 pt-3 text-[11px] font-black uppercase tracking-wide text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)]"
                    onClick={() => toggleSection(section.title)}
                    aria-expanded={isExpanded}
                  >
                    <span>{section.title}</span>
                    <ChevronDown className={`size-3.5 transition-transform ${isExpanded ? '' : 'rotate-90'}`} aria-hidden="true" />
                  </button>
                ) : (
                  <span className="sidebar-divider" />
                )}
                {isExpanded ? (
                  <div className="space-y-1">
                    {section.items.map((item) => {
                      const Icon = item.icon;
                      const exact = item.to === '/hr' || item.to === '/admin' || item.to === '/committee';
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
                ) : null}
              </section>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          <div className="sidebar-user">
            <UserAvatar displayName={access.displayName} photoUrl={profilePhotoUrl} eager />
            {!collapsed ? (
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-black" title={access.displayName}>
                  {getShortName(access.displayName)}
                </p>
                <p className="truncate text-xs text-[var(--text-muted)]">{currentWorkspaceLabel}</p>
              </div>
            ) : null}
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
            <button className="icon-button mobile-nav-control" aria-label="فتح القائمة" onClick={() => setOpen(true)}>
              <Menu className="size-5" aria-hidden="true" />
            </button>
            <button
              className="icon-button desktop-nav-control"
              aria-label="لوحة الأوامر (Ctrl+K)"
              title="لوحة الأوامر (Ctrl+K)"
              onClick={() => window.dispatchEvent(new CustomEvent('ahla:command-palette'))}
            >
              <Search className="size-4.5" aria-hidden="true" />
            </button>
            <button className="icon-button desktop-nav-control" aria-label={collapsed ? 'توسيع القائمة' : 'تصغير القائمة'} onClick={toggleCollapsed}>
              {collapsed ? <PanelRightOpen className="size-4.5" aria-hidden="true" /> : <PanelRightClose className="size-4.5" aria-hidden="true" />}
            </button>
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 text-xs font-bold text-[var(--text-muted)]">
                <span className="header-workspace-name">{currentWorkspaceLabel}</span>
                <span className="header-breadcrumb-separator">/</span>
                <span className="truncate text-[var(--brand-primary)]">{currentItem?.label ?? 'الرئيسية'}</span>
              </div>
              <h1 className="truncate text-base font-black sm:text-lg">{currentItem?.label ?? currentWorkspaceLabel}</h1>
            </div>
          </div>

          <div className="header-actions flex items-center gap-2">
            <WorkspaceSearch destinations={allItems.map((item) => ({ label: item.label, to: item.to, group: item.group }))} />
            <ThemeToggle />
            {/* زر المساعد الإداري الذكي HR Copilot */}
            <button
              type="button"
              className={`icon-button relative ${isCopilotOpen ? 'bg-[var(--brand-primary)]/15 text-[var(--brand-primary)] ring-2 ring-[var(--brand-primary)]' : ''}`}
              aria-label="المساعد الإداري الذكي (Alt+C)"
              title="المساعد الإداري الذكي (Alt+C)"
              onClick={() => setIsCopilotOpen((prev) => !prev)}
            >
              <Sparkles className="size-4.5 text-amber-500" aria-hidden="true" />
            </button>
            <button
              type="button"
              className="icon-button relative"
              aria-label={unreadCount ? `الإشعارات، ${unreadCount} غير مقروء` : 'الإشعارات'}
              onClick={() =>
                navigate(workspace === 'hr' ? '/hr/notifications' : workspace === 'committee' ? '/committee/notifications' : '/admin/notifications')
              }
            >
              <Bell className="size-4.5" aria-hidden="true" />
              {unreadCount ? (
                <span className="notification-count" aria-hidden="true">
                  {unreadCount > 99 ? '99+' : unreadCount}
                </span>
              ) : null}
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
                <button
                  type="button"
                  onClick={() =>
                    navigate(workspace === 'hr' ? '/hr/notifications' : workspace === 'committee' ? '/committee/notifications' : '/admin/notifications')
                  }
                >
                  <Bell className="size-4" aria-hidden="true" />
                  الإشعارات{unreadCount ? ` (${unreadCount})` : ''}
                </button>
                <button
                  type="button"
                  onClick={(event) => {
                    event.currentTarget.closest('details')?.removeAttribute('open');
                    setChangePhotoOpen(true);
                  }}
                >
                  <Camera className="size-4" aria-hidden="true" />
                  تغيير صورتي
                </button>
                <button type="button" onClick={() => void auth.signOut()}>
                  <LogOut className="size-4" aria-hidden="true" />
                  تسجيل الخروج
                </button>
              </div>
            </details>
          </div>
        </header>
        <ChangePhotoDialog open={changePhotoOpen} currentPhotoUrl={profilePhotoUrl} onClose={() => setChangePhotoOpen(false)} />
        <HRCopilotDrawer isOpen={isCopilotOpen} onClose={() => setIsCopilotOpen(false)} />
        <main id="main-content" tabIndex={-1} key={location.pathname} className="page-container">
          <RouteErrorBoundary>
            <Outlet />
          </RouteErrorBoundary>
        </main>
      </div>
    </div>
  );
}
