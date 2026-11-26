import type { LucideIcon } from 'lucide-react';
import {
  Archive,
  ArrowRight,
  BadgeCheck,
  BriefcaseBusiness,
  CalendarDays,
  CheckSquare,
  Clock3,
  CreditCard,
  Eye,
  FileText,
  Gauge,
  History,
  KeyRound,
  Mail,
  MailCheck,
  MapPin,
  Network,
  Pencil,
  Phone,
  ShieldCheck,
  Trash2,
  Trophy,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { isPhoneLikeCode, renderSafeIntlPhoneText } from '../../ui/phoneDisplay';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { Tabs } from '../../ui/Tabs';
import { useToast } from '../../ui/Toast';
import { UserAvatar } from '../../ui/UserAvatar';
import { MonthlyStatementSection } from '../attendance/MonthlyStatementSection';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission, useHrPrefix } from '../workspaces/access';
import { AssignShiftDialog } from './AssignShiftDialog';
import { EditEmployeeDialog } from './detail/EditEmployeeDialog';
import { AddDepartmentDialog, PrintableIdBadgeDialog } from './detail/EmployeeBadgeAndDeptDialogs';
import { Data, DepartmentsSection, Info } from './detail/EmployeeDetailPrimitives';
import {
  ArchiveEmployeeDialog,
  ChangeManagerDialog,
  DeleteEmployeeDialog,
  GrantRestCompDialog,
} from './detail/EmployeeLifecycleDialogs';
import { EmployeeActivityTimeline } from './EmployeeActivityTimeline';
import { EmployeeEditHistory } from './employeeDetailShared';
import { EmployeeKpiTab } from './EmployeeKpiTab';
import { EmployeeLeaveTab } from './EmployeeLeaveTab';
import { EmployeeLocationTab } from './EmployeeLocationTab';
import { EmployeeOrgChartTab } from './EmployeeOrgChartTab';
import { EmployeeRecognitionTab } from './EmployeeRecognitionTab';
import { EmployeeReportsTab } from './EmployeeReportsTab';
import { EmployeeRetentionScoreCard } from './EmployeeRetentionScoreCard';
import { EmployeeTasksTab } from './EmployeeTasksTab';
import {
  formatShiftTiming,
  useEmployee360,
  useEmployeeActiveShift,
  useResendInvite,
} from './useEmployees';

export { DeleteEmployeeDialog };

const dateFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium' });

const PENDING_ACCOUNT_STATES = new Set(['invited', 'onboarding', 'pending', 'draft']);

const ACCOUNT_STATUS_LABELS: Record<string, string> = {
  active: 'نشط',
  enabled: 'نشط',
  invited: 'بانتظار التفعيل',
  onboarding: 'بانتظار التفعيل',
  pending: 'بانتظار التفعيل',
  draft: 'مسودة',
  blocked: 'موقوف',
  suspended: 'موقوف',
  disabled: 'معطّل',
};

// ---------------------------------------------------------------------------
// EmployeeDetailPage — Main component
// ---------------------------------------------------------------------------
type EmployeeTabId = 'overview' | 'org-hierarchy' | 'timeline' | 'leaves' | 'attendance' | 'locations' | 'tasks' | 'kpi' | 'reports' | 'recognition';

const EMPLOYEE_TABS: { id: EmployeeTabId; label: string; icon: LucideIcon }[] = [
  { id: 'overview', label: 'النبذة', icon: Eye },
  { id: 'org-hierarchy', label: 'الهيكل والتسلسل الإداري', icon: Network },
  { id: 'timeline', label: 'سجل النشاط', icon: History },
  { id: 'leaves', label: 'الإجازات', icon: CalendarDays },
  { id: 'attendance', label: 'الحضور والانصراف', icon: Clock3 },
  { id: 'locations', label: 'مواقع العمل', icon: MapPin },
  { id: 'tasks', label: 'المهام', icon: CheckSquare },
  { id: 'kpi', label: 'الأداء', icon: Gauge },
  { id: 'reports', label: 'التقارير', icon: FileText },
  { id: 'recognition', label: 'لوحة الشرف والتميز', icon: Trophy },
];

export function EmployeeDetailPage() {
  const { employeeId } = useParams();
  const auth = useAuth();
  const query = useEmployee360(employeeId);
  const activeShiftQuery = useEmployeeActiveShift(employeeId);
  const resend = useResendInvite();
  const { toast } = useToast();
  const [resendMessage, setResendMessage] = useState<string | null>(null);
  const [resendError, setResendError] = useState<string | null>(null);
  const [showManagerDialog, setShowManagerDialog] = useState(false);
  const [showArchiveDialog, setShowArchiveDialog] = useState(false);
  const [showEditDialog, setShowEditDialog] = useState(false);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showAddDeptDialog, setShowAddDeptDialog] = useState(false);
  const [showGrantRestDialog, setShowGrantRestDialog] = useState(false);
  const [showBadgeDialog, setShowBadgeDialog] = useState(false);
  const [showShiftDialog, setShowShiftDialog] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const urlTab = searchParams.get('tab') as EmployeeTabId | null;
  const [activeTab, setActiveTabState] = useState<EmployeeTabId>(() => {
    if (urlTab && EMPLOYEE_TABS.some((t) => t.id === urlTab)) return urlTab;
    return 'overview';
  });

  const setActiveTab = (tab: EmployeeTabId) => {
    setActiveTabState(tab);
    const next = new URLSearchParams(searchParams);
    if (tab === 'overview') {
      next.delete('tab');
    } else {
      next.set('tab', tab);
    }
    setSearchParams(next, { replace: true });
  };
  const navigate = useNavigate();
  const location = useLocation();
  const hrPrefix = useHrPrefix();
  const item = query.data;

  const displayDepartments = useMemo(() => {
    if (item?.departments && item.departments.length > 0) {
      return item.departments.map((d) => d.departmentName).join(' / ');
    }
    return item?.department ?? 'بدون إدارة';
  }, [item?.departments, item?.department]);

  if (query.isError) {
    return <ErrorState title="تعذر فتح ملف الموظف" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />;
  }
  if (query.isLoading) {
    return <SkeletonCard className="h-72" />;
  }
  if (!item) {
    return <EmptyState title="تعذر فتح ملف الموظف" description="الملف غير موجود أو خارج نطاق صلاحيتك." />;
  }

  const canInvite = Boolean(auth.access && hasPermission(auth.access, 'people.employee.create'));
  const canEdit = Boolean(
    auth.access && (hasPermission(auth.access, 'people.employee.update_sensitive') || hasPermission(auth.access, 'people.employee.update_basic')),
  );
  const accountPending = PENDING_ACCOUNT_STATES.has((item.accountStatus ?? '').toLowerCase()) || PENDING_ACCOUNT_STATES.has((item.status ?? '').toLowerCase());
  const showResend = canInvite && accountPending && Boolean(employeeId);
  const canGrantRestComp = Boolean(
    auth.access && (hasPermission(auth.access, 'requests.leave.balance.adjust') || auth.access.workspaces?.includes('main_admin')),
  );

  const onResend = async () => {
    if (!employeeId) return;
    setResendMessage(null);
    setResendError(null);
    try {
      const msg = await resend.mutateAsync(employeeId);
      setResendMessage(msg);
      toast({ message: 'تم إرسال الدعوة: ' + msg, tone: 'success' });
    } catch (error) {
      const msg = safeErrorMessage(error);
      setResendError(msg);
      toast({ message: 'فشل إرسال الدعوة: ' + msg, tone: 'error' });
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الموظفون والهيكل"
        title={`ملف الموظف: ${item.fullNameAr}`}
        description={
          item.todayStatus ? (
            <span className="flex items-center gap-2 flex-wrap text-sm">
              <span>عرض شامل للبيانات الوظيفية والتشغيلية والحضور.</span>
              <span className="inline-flex items-center gap-1 font-bold text-[var(--text)]">
                • حالة اليوم:
                <span className="font-black text-[var(--brand-primary)]">
                  {item.todayStatus.statusLabel ?? 'لم يسجل بعد'}
                  {item.todayStatus.activityTitle ? ` (${item.todayStatus.activityTitle})` : ''}
                </span>
              </span>
            </span>
          ) : (
            'عرض شامل للبيانات الوظيفية والحضور والطلبات والأداء والمستندات.'
          )
        }
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <Link to={`${hrPrefix}/employees`} className="btn-secondary">
              <ArrowRight className="size-4" aria-hidden="true" />
              عودة للموظفين
            </Link>
            {canEdit ? (
              <button type="button" className="btn-primary" onClick={() => setShowEditDialog(true)}>
                <Pencil className="size-4" aria-hidden="true" />
                تعديل البيانات
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-secondary" onClick={() => setShowShiftDialog(true)}>
                <Clock3 className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                إسناد الوردية
              </button>
            ) : null}
            <button type="button" className="btn-secondary" onClick={() => setShowBadgeDialog(true)}>
              <CreditCard className="size-4" aria-hidden="true" />
              بطاقة الهوية الوظيفية
            </button>
            <Link
              to={location.pathname.startsWith('/admin') ? `/admin/hr/passwords?employeeId=${item.id}` : `/hr/passwords?employeeId=${item.id}`}
              className="btn-secondary"
              title="إدارة كلمة المرور وحساب الموظف"
            >
              <KeyRound className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
              كلمة المرور
            </Link>
            {canGrantRestComp ? (
              <button type="button" className="btn-secondary" onClick={() => setShowGrantRestDialog(true)}>
                <BadgeCheck className="size-4" aria-hidden="true" />
                منح بدل راحة
              </button>
            ) : null}
            {showResend ? (
              <button type="button" className="btn-secondary" disabled={resend.isPending} onClick={() => void onResend()}>
                <MailCheck className="size-4" aria-hidden="true" />
                {resend.isPending ? 'جارٍ الإرسال…' : 'إعادة إرسال دعوة التفعيل'}
              </button>
            ) : null}
            {canEdit && item.isActive ? (
              <button type="button" className="btn-secondary text-[var(--danger)] hover:bg-[var(--danger)]/10" onClick={() => setShowArchiveDialog(true)}>
                <Archive className="size-4" aria-hidden="true" />
                أرشفة الموظف
              </button>
            ) : null}
            {canEdit ? (
              <button type="button" className="btn-secondary text-[var(--danger)] hover:bg-[var(--danger)]/10" onClick={() => setShowDeleteDialog(true)}>
                <Trash2 className="size-4" aria-hidden="true" />
                حذف الموظف
              </button>
            ) : null}
          </div>
        }
      />

      {resendMessage ? (
        <div className="flex gap-2 rounded-xl border border-[var(--success)] bg-[var(--success-soft)] p-4 text-sm text-[var(--success)]">
          <MailCheck className="size-5 shrink-0" aria-hidden="true" />
          {resendMessage}
        </div>
      ) : null}
      {resendError ? <ErrorBanner message={resendError} /> : null}

      <Tabs
        tabs={EMPLOYEE_TABS.map((tab) => ({ id: tab.id, label: tab.label }))}
        activeTab={activeTab}
        onTabChange={(id) => setActiveTab(id as EmployeeTabId)}
        ariaLabel="أقسام ملف الموظف"
      >
        {activeTab === 'overview' ? (
          <div className="space-y-6">
            <section className="card flex flex-col gap-6 p-6 xl:flex-row xl:items-start xl:justify-between">
              {/* القسم الرئيسي لبيانات الموظف والهوية */}
              <div className="flex flex-col sm:flex-row items-start gap-5 flex-1 min-w-0">
                <UserAvatar displayName={item.fullNameAr} photoUrl={item.photoUrl} size="lg" eager />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-3">
                    <h2 className="text-2xl font-black">{item.fullNameAr}</h2>
                    <StatusBadge status={item.status} />
                    {/* شارة حالة اليوم التشغيلية الحية والبارزة */}
                    {item.todayStatus ? (
                      <span
                        className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-black shadow-sm transition-all ${
                          item.todayStatus.status === 'present'
                            ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border border-emerald-500/30'
                            : item.todayStatus.status === 'convoy'
                              ? 'bg-purple-500/15 text-purple-700 dark:text-purple-300 border border-purple-500/30'
                              : item.todayStatus.status === 'fundraising'
                                ? 'bg-teal-500/15 text-teal-700 dark:text-teal-300 border border-teal-500/30'
                                : item.todayStatus.status === 'mission'
                                  ? 'bg-blue-500/15 text-blue-700 dark:text-blue-300 border border-blue-500/30'
                                  : item.todayStatus.status === 'on_leave'
                                    ? 'bg-sky-500/15 text-sky-700 dark:text-sky-300 border border-sky-500/30'
                                    : item.todayStatus.status === 'late'
                                      ? 'bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30'
                                      : item.todayStatus.status === 'absent'
                                        ? 'bg-rose-500/15 text-rose-700 dark:text-rose-300 border border-rose-500/30'
                                        : 'bg-gray-500/15 text-gray-700 dark:text-gray-300 border border-gray-500/30'
                        }`}
                      >
                        <span className="relative flex size-2">
                          {['present', 'mission', 'convoy', 'fundraising'].includes(item.todayStatus.status ?? '') && (
                            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-current opacity-75" />
                          )}
                          <span className="relative inline-flex size-2 rounded-full bg-current" />
                        </span>
                        <span>
                          حالة اليوم: {item.todayStatus.statusLabel ?? 'لم يسجل بعد'}
                          {item.todayStatus.activityTitle ? ` — ${item.todayStatus.activityTitle}` : ''}
                        </span>
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-gray-500/10 text-gray-600 border border-gray-500/20">
                        <span className="size-1.5 rounded-full bg-gray-400" />
                        حالة اليوم: لم يسجل بعد
                      </span>
                    )}
                  </div>
                  <p className="muted mt-2 flex items-center gap-2">
                    <span className="font-semibold">{item.jobTitle ?? 'بدون مسمى وظيفي'}</span>
                    {!isPhoneLikeCode(item.employeeCode, item.phoneE164) && (
                      <>
                        <span>•</span>
                        <bdi
                          dir="ltr"
                          className="font-mono text-xs px-2 py-0.5 rounded bg-[var(--surface-muted)] text-[var(--text-secondary)] border border-[var(--border)] font-bold"
                        >
                          {item.employeeCode}
                        </bdi>
                      </>
                    )}
                  </p>
                  <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2.5 text-sm">
                    <Info icon={Network} label={displayDepartments} />
                    <Info icon={Phone} label={item.phoneE164 ? renderSafeIntlPhoneText(item.phoneE164) : 'بدون هاتف'} />
                    <Info icon={Mail} label={item.email ?? 'بدون بريد'} />
                    <Info
                      icon={ShieldCheck}
                      label={`الحساب: ${ACCOUNT_STATUS_LABELS[(item.accountStatus ?? '').toLowerCase()] ?? (accountPending ? 'بانتظار التفعيل' : 'غير متاح')}`}
                    />
                  </div>
                </div>
              </div>

              {/* بطاقة العلاقة الإدارية */}
              <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)] p-4 text-sm xl:w-84 xl:shrink-0">
                <div className="flex items-center justify-between border-b border-[var(--border)] pb-2.5">
                  <p className="font-black">العلاقة الإدارية</p>
                  <button
                    type="button"
                    onClick={() => setActiveTab('org-hierarchy')}
                    className="text-xs font-bold text-[var(--brand-primary)] hover:underline flex items-center gap-1"
                  >
                    <Network className="size-3.5" />
                    عرض الهيكل
                  </button>
                </div>
                <div className="mt-2.5 space-y-2 text-xs">
                  <div className="flex items-center justify-between gap-2">
                    <span className="muted">المدير المباشر:</span>
                    <div className="flex items-center gap-1.5 font-bold text-[var(--text)]">
                      <span>{item.managerName ?? 'غير معين'}</span>
                      {canEdit ? (
                        <button type="button" onClick={() => setShowManagerDialog(true)} className="text-brand font-bold text-xs hover:underline">
                          تغيير
                        </button>
                      ) : null}
                    </div>
                  </div>
                  <div className="flex items-center justify-between gap-2">
                    <span className="muted">المرؤوسون المباشرون:</span>
                    <span className="font-bold text-[var(--text)]">{item.directReports}</span>
                  </div>
                  <div className="border-t border-[var(--border)] pt-2">
                    <div className="flex items-center justify-between mb-1">
                      <span className="muted">الأدوار:</span>
                      {hasPermission(auth.access, 'access.role.read') ? (
                        <Link to="/admin/access" className="text-brand font-bold text-xs hover:underline">
                          إدارة الصلاحيات
                        </Link>
                      ) : null}
                    </div>
                    <p className="font-medium text-[var(--text-secondary)] leading-relaxed">{item.roles.map((role) => role.name).join('، ') || 'لا توجد'}</p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setActiveTab('org-hierarchy')}
                  className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-xl border border-[var(--brand-primary)]/30 bg-[var(--brand-primary-soft)]/20 px-3 py-2 text-xs font-bold text-[var(--brand-primary)] hover:bg-[var(--brand-primary)] hover:text-white transition"
                >
                  <Network className="size-3.5" />
                  الهيكل الإداري والمرؤوسون
                </button>
              </div>
            </section>

            {/* بطاقة الحالة التشغيلية واليومية */}
            <section className="card p-5 border-r-4 border-r-[var(--brand-primary)]">
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="flex size-10 items-center justify-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
                    <CalendarDays className="size-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-black text-base">الحالة التشغيلية واليومية</h3>
                      {item.todayStatus ? (
                        <span
                          className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-black ${
                            item.todayStatus.status === 'present'
                              ? 'bg-emerald-500/10 text-emerald-600 border border-emerald-500/30'
                              : item.todayStatus.status === 'convoy'
                                ? 'bg-purple-500/10 text-purple-600 border border-purple-500/30'
                                : item.todayStatus.status === 'fundraising'
                                  ? 'bg-teal-500/10 text-teal-600 border border-teal-500/30'
                                  : item.todayStatus.status === 'mission'
                                    ? 'bg-blue-500/10 text-blue-600 border border-blue-500/30'
                                    : item.todayStatus.status === 'on_leave'
                                      ? 'bg-sky-500/10 text-sky-600 border border-sky-500/30'
                                      : item.todayStatus.status === 'late'
                                        ? 'bg-amber-500/10 text-amber-600 border border-amber-500/30'
                                        : item.todayStatus.status === 'absent'
                                          ? 'bg-rose-500/10 text-rose-600 border border-rose-500/30'
                                          : 'bg-gray-500/10 text-gray-600 border border-gray-500/30'
                          }`}
                        >
                          <span className="size-1.5 rounded-full bg-current" />
                          {item.todayStatus.statusLabel ?? item.todayStatus.status}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-gray-500/10 text-gray-600 border border-gray-500/30">
                          لم يسجل بعد
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-[var(--text-secondary)] mt-0.5">متابعة الحالة التشغيلية والدوام لليوم الحالي</p>
                  </div>
                </div>

                {item.todayStatus?.activityTitle && (
                  <div className="flex items-center gap-1.5 rounded-xl bg-[var(--brand-primary-soft)]/20 border border-[var(--brand-primary)]/20 px-3 py-1.5 text-xs font-bold text-[var(--brand-primary)]">
                    <MapPin className="size-3.5" />
                    <span>الوجهة / النشاط: {item.todayStatus.activityTitle}</span>
                  </div>
                )}
              </div>

              <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-3 pt-3 border-t border-[var(--border)] text-sm">
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">وقت الحضور</span>
                  <span className="font-bold">
                    {item.todayStatus?.checkInAt
                      ? new Date(item.todayStatus.checkInAt).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })
                      : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">وقت الانصراف</span>
                  <span className="font-bold">
                    {item.todayStatus?.checkOutAt
                      ? new Date(item.todayStatus.checkOutAt).toLocaleTimeString('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit' })
                      : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">
                    {item.todayStatus?.lateMinutes && item.todayStatus.lateMinutes > 0 ? 'مدة التأخير' : 'ساعات العمل'}
                  </span>
                  <span className="font-bold">
                    {item.todayStatus?.lateMinutes && item.todayStatus.lateMinutes > 0
                      ? `${item.todayStatus.lateMinutes} دقيقة`
                      : item.todayStatus?.workMinutes && item.todayStatus.workMinutes > 0
                        ? `${(item.todayStatus.workMinutes / 60).toFixed(1)} ساعة`
                        : item.todayStatus?.status === 'convoy' || item.todayStatus?.status === 'mission' || item.todayStatus?.status === 'fundraising'
                          ? 'مهمة عمل رسمية'
                          : '—'}
                  </span>
                </div>
                <div>
                  <span className="text-xs text-[var(--text-secondary)] block">ملاحظة اليوم</span>
                  <span className="font-bold text-xs text-[var(--text-secondary)]">
                    {!item.todayStatus
                      ? 'لم يسجل بعد'
                      : item.todayStatus.status === 'convoy'
                        ? 'مشارك في قافلة مساعدات'
                        : item.todayStatus.status === 'fundraising'
                          ? 'يوم ترفيهي للموظفين (فاندي)'
                          : item.todayStatus.status === 'mission'
                            ? 'مأمورية عمل خارجية'
                            : item.todayStatus.status === 'on_leave'
                              ? 'إجازة رسمية معتمدة'
                              : item.todayStatus.status === 'present'
                                ? 'قيد الدوام'
                                : item.todayStatus.status === 'late'
                                  ? 'حضر مع تأخير'
                                  : item.todayStatus.status === 'absent'
                                    ? 'لم يسجل حضور'
                                    : 'لم يسجل بعد'}
                  </span>
                </div>
              </div>

              {/* قسم فترة العمل (الوردية المقررة) */}
              <div className="mt-4 pt-3 border-t border-[var(--border)] flex flex-wrap items-center justify-between gap-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-xs text-[var(--text-secondary)] font-semibold flex items-center gap-1.5">
                    <Clock3 className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
                    فترة العمل المقررة:
                  </span>
                  {activeShiftQuery.isLoading ? (
                    <span className="text-xs text-[var(--text-secondary)]">جارٍ التحميل…</span>
                  ) : (
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-bold text-[var(--text)]">{activeShiftQuery.data?.shiftName ?? 'الدوام الأساسي العام'}</span>
                      {activeShiftQuery.data ? (
                        <span className="text-xs text-[var(--text-secondary)] font-sans">
                          ({formatShiftTiming(activeShiftQuery.data.startTime, activeShiftQuery.data.endTime, activeShiftQuery.data.graceInMinutes)})
                        </span>
                      ) : null}
                      {activeShiftQuery.data?.isAssigned ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs font-black text-emerald-600 border border-emerald-500/20">
                          معتمدة ومسندة
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-gray-500/10 px-2 py-0.5 text-xs font-semibold text-gray-600 border border-gray-500/20">
                          الافتراضية العامة
                        </span>
                      )}
                    </div>
                  )}
                </div>
                {canEdit ? (
                  <button type="button" onClick={() => setShowShiftDialog(true)} className="btn-secondary btn-sm text-xs font-bold flex items-center gap-1.5">
                    <Pencil className="size-3.5" aria-hidden="true" />
                    تغيير الوردية
                  </button>
                ) : null}
              </div>
            </section>

            <section className="grid gap-5 sm:grid-cols-2 xl:grid-cols-4">
              <MetricCard
                label="أيام الحضور — 30 يومًا"
                value={item.attendance30.present}
                hint={`${item.attendance30.lateDays} أيام تأخير`}
                icon={BadgeCheck}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="أيام الغياب"
                value={item.attendance30.absent}
                icon={Clock3}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="الطلبات المعلقة"
                value={item.requestCounts.pending}
                hint={`${item.requestCounts.approved} معتمدة`}
                icon={FileText}
                onClick={() => document.getElementById('latest-requests')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
              <MetricCard
                label="أحدث تقييم"
                value={item.latestKpi?.finalScore ?? item.latestKpi?.currentStage ?? '—'}
                hint={item.latestKpi?.finalRating ?? undefined}
                icon={Gauge}
                onClick={() => document.getElementById('attendance-kpi-section')?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              />
            </section>

            <section className="grid gap-5 xl:grid-cols-2">
              <article className="card p-5">
                <h3 className="font-black">البيانات الوظيفية</h3>
                <div className="mt-4 grid gap-3 sm:grid-cols-2">
                  <Data label="الإدارة" value={displayDepartments} />
                  <Data label="الفرع" value={item.branch} />
                  <Data label="موقع العمل" value={item.workSite} />
                  <Data label="تاريخ التعيين" value={item.hireDate ? dateFormatter.format(new Date(item.hireDate)) : null} />
                </div>
              </article>

              <article className="card p-5">
                <h3 className="font-black">المستندات والعهد</h3>
                <div className="mt-4 space-y-3">
                  {item.documents.length === 0 ? <p className="muted text-sm">لا توجد مستندات متاحة.</p> : null}
                  {item.documents.slice(0, 5).map((doc) => (
                    <div key={doc.id} className="flex items-center justify-between rounded-xl bg-[var(--surface-muted)] p-3">
                      <div>
                        <p className="font-bold">{doc.title}</p>
                        <p className="muted mt-1 text-xs">{doc.expiryDate ? `ينتهي ${dateFormatter.format(new Date(doc.expiryDate))}` : doc.type}</p>
                      </div>
                      <StatusBadge value={doc.status} />
                    </div>
                  ))}
                  {item.assets
                    .filter((asset) => !asset.returnedAt)
                    .map((asset) => (
                      <div key={asset.id} className="flex items-center justify-between rounded-xl border border-[var(--border)] p-3">
                        <div>
                          <p className="font-bold">{asset.assetName}</p>
                          <p className="muted mt-1 text-xs">{asset.serial ?? asset.assetType}</p>
                        </div>
                        <BriefcaseBusiness className="size-5 text-[var(--text-muted)]" aria-label="عهدة قيد الاستلام" />
                      </div>
                    ))}
                </div>
              </article>
            </section>

            <section className="grid gap-5 xl:grid-cols-2">
              <article id="latest-requests" className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <h3 className="font-black">أحدث الطلبات</h3>
                </div>
                <div className="divide-y divide-[var(--border)]">
                  {item.recentRequests.length === 0 ? (
                    <p className="muted p-5 text-sm">لا توجد طلبات.</p>
                  ) : (
                    item.recentRequests.map((request) => (
                      <div key={request.id} className="flex items-center justify-between gap-3 p-4">
                        <div>
                          <p className="font-bold">{request.title ?? request.requestType}</p>
                          <p className="muted mt-1 text-xs">
                            طلب #{request.requestNumber} • {dateFormatter.format(new Date(request.createdAt))}
                          </p>
                        </div>
                        <StatusBadge value={request.status} />
                      </div>
                    ))
                  )}
                </div>
              </article>

              <article className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <h3 className="font-black">أحدث المهام</h3>
                </div>
                <div className="divide-y divide-[var(--border)]">
                  {item.recentTasks.length === 0 ? (
                    <p className="muted p-5 text-sm">لا توجد مهام.</p>
                  ) : (
                    item.recentTasks.map((task) => (
                      <div key={task.id} className="flex items-center justify-between gap-3 p-4">
                        <div>
                          <p className="font-bold">{task.title}</p>
                          <p className="muted mt-1 text-xs">{task.dueDate ? `الاستحقاق ${dateFormatter.format(new Date(task.dueDate))}` : 'بدون موعد'}</p>
                        </div>
                        <StatusBadge value={task.status} />
                      </div>
                    ))
                  )}
                </div>
              </article>
            </section>

            {/* الحضور والتقييم — آخر 30 يوماً (وجهة بطاقات الملخص) */}
            <section id="attendance-kpi-section" className="card p-5">
              <h3 className="font-black">الحضور والتقييم — آخر 30 يوماً</h3>
              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                <Data label="أيام حضور" value={String(item.attendance30.present)} />
                <Data label="أيام تأخير" value={String(item.attendance30.lateDays)} />
                <Data label="أيام غياب" value={String(item.attendance30.absent)} />
                <Data
                  label="أحدث تقييم"
                  value={
                    item.latestKpi ? [item.latestKpi.finalScore ?? item.latestKpi.currentStage, item.latestKpi.finalRating].filter(Boolean).join(' · ') : '—'
                  }
                />
              </div>
            </section>

            {/* مؤشر الاستقرار والولاء الوظيفي التنبؤي */}
            <EmployeeRetentionScoreCard employee={item} />

            {/* سجل النشاط والمحطات الإدارية */}
            <EmployeeActivityTimeline employee={item} />

            {/* إدارات الموظف — V17 multi-department */}
            {employeeId && <DepartmentsSection employeeId={employeeId} canEdit={canEdit} onAdd={() => setShowAddDeptDialog(true)} />}

            {/* آخر التعديلات الهامة على الملف */}
            {employeeId && <EmployeeEditHistory employeeId={employeeId} />}

            <p className="muted flex items-center gap-2 text-xs">
              <CalendarDays className="size-4" aria-hidden="true" />
              آخر تحديث:{' '}
              {item.lastUpdatedAt
                ? new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.lastUpdatedAt))
                : 'غير متوفر'}
            </p>
          </div>
        ) : null}

        {activeTab === 'org-hierarchy' && employeeId ? (
          <EmployeeOrgChartTab employeeId={employeeId} employee={item} onChangeManagerClick={canEdit ? () => setShowManagerDialog(true) : undefined} />
        ) : null}
        {activeTab === 'timeline' ? <EmployeeActivityTimeline employee={item} /> : null}
        {activeTab === 'leaves' && employeeId ? <EmployeeLeaveTab employeeId={employeeId} /> : null}
        {activeTab === 'attendance' && employeeId ? <MonthlyStatementSection employeeId={employeeId} /> : null}
        {activeTab === 'locations' && employeeId ? <EmployeeLocationTab employeeId={employeeId} /> : null}
        {activeTab === 'tasks' && employeeId ? <EmployeeTasksTab employeeId={employeeId} /> : null}
        {activeTab === 'kpi' && employeeId ? <EmployeeKpiTab employeeId={employeeId} /> : null}
        {activeTab === 'reports' && employeeId ? <EmployeeReportsTab employeeId={employeeId} /> : null}
        {activeTab === 'recognition' && employeeId ? <EmployeeRecognitionTab employeeId={employeeId} /> : null}
      </Tabs>

      {showManagerDialog && employeeId && (
        <ChangeManagerDialog
          employeeId={employeeId}
          currentManagerName={item.managerName}
          onClose={() => setShowManagerDialog(false)}
          onSuccess={() => {
            setShowManagerDialog(false);
            toast({ message: 'تم تغيير المدير المباشر بنجاح', tone: 'success' });
            void query.refetch();
          }}
        />
      )}
      {showArchiveDialog && employeeId && (
        <ArchiveEmployeeDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          onClose={() => setShowArchiveDialog(false)}
          onSuccess={() => {
            setShowArchiveDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showEditDialog && employeeId && (
        <EditEmployeeDialog
          item={item}
          onClose={() => setShowEditDialog(false)}
          onSuccess={() => {
            setShowEditDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showDeleteDialog && employeeId && (
        <DeleteEmployeeDialog
          employeeId={employeeId}
          employeeCode={item.employeeCode}
          employeeName={item.fullNameAr}
          onClose={() => setShowDeleteDialog(false)}
          onSuccess={() => {
            setShowDeleteDialog(false);
            void navigate('/hr/employees');
          }}
        />
      )}
      {showAddDeptDialog && employeeId && (
        <AddDepartmentDialog
          employeeId={employeeId}
          onClose={() => setShowAddDeptDialog(false)}
          onSuccess={() => {
            setShowAddDeptDialog(false);
            void query.refetch();
          }}
        />
      )}
      {showGrantRestDialog && employeeId ? (
        <GrantRestCompDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          onClose={() => setShowGrantRestDialog(false)}
          onSuccess={() => {
            setShowGrantRestDialog(false);
            void query.refetch();
          }}
        />
      ) : null}
      {showShiftDialog && employeeId ? (
        <AssignShiftDialog
          employeeId={employeeId}
          employeeName={item.fullNameAr}
          employeeCode={item.employeeCode}
          onClose={() => setShowShiftDialog(false)}
          onSuccess={() => {
            setShowShiftDialog(false);
            void activeShiftQuery.refetch();
            void query.refetch();
          }}
        />
      ) : null}
      {showBadgeDialog ? <PrintableIdBadgeDialog employee={item} onClose={() => setShowBadgeDialog(false)} /> : null}
    </div>
  );
}
