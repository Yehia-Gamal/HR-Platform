import {
  Activity,
  AlertOctagon,
  ArrowLeft,
  ArrowUpRight,
  BadgeCheck,
  BriefcaseBusiness,
  Building2,
  CalendarDays,
  CheckCircle2,
  Clock3,
  FileWarning,
  FolderKanban,
  Gavel,
  Gauge,
  HeartHandshake,
  Inbox,
  KeyRound,
  MapPin,
  Megaphone,
  Plus,
  ScrollText,
  Settings,
  ShieldAlert,
  ShieldCheck,
  Smartphone,
  Sparkles,
  TimerReset,
  UserCheck,
  UserMinus,
  UserX,
  Users,
} from 'lucide-react';
import { Link } from 'react-router';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { getShortName, getTimeGreeting } from '../../ui/formatDisplayName';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { safeErrorMessage } from '../../core/errorMapper';
import { relativeTime } from '../../core/formatTime';
import { AppBarChart } from '../../ui/charts/AppBarChart';
import { ChartCard } from '../../ui/charts/ChartCard';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { useDashboardOverview } from '../management/useManagementOverviews';
import { BroadcastAlertButton } from '../notifications/BroadcastAlert';
import { useAttendanceTodayOverview } from './useAttendanceTodayOverview';
import { notificationTargetPath } from '../notifications/notificationTarget';
import { notificationCategoryIcon, notificationCategoryLabel } from '../notifications/notificationMeta';
import { useNotifications } from '../notifications/useNotifications';

export function DashboardPage({ type }: { type: 'hr' | 'admin' }) {
  const auth = useAuth();
  const query = useDashboardOverview(type === 'hr' ? 'hr' : 'main_admin');
  const attendance = useAttendanceTodayOverview();
  const att = attendance.data;
  const data = query.data;
  const today = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date());

  // ─── كروت مؤشرات الأداء المتناسقة (4 أعمدة على شاشات 15 بوصة وما فوق) ─────────
  const cards = data
    ? type === 'hr'
      ? [
          {
            label: 'إجمالي الموظفين',
            value: data.employees,
            icon: Users,
            hint: `${data.activeEmployees} موظفًا نشطًا`,
            trend: data.employees ? `${Math.round((data.activeEmployees / data.employees) * 100)}% نشط` : undefined,
            to: '/hr/employees',
          },
          { label: 'طلبات معلقة', value: data.pendingRequests, icon: BadgeCheck, hint: 'وفق نطاق وصلاحيات المستخدم', to: '/hr/requests?status=pending' },
          { label: 'حضور يحتاج مراجعة', value: data.attendancePendingReview, icon: Clock3, hint: 'تصحيحات واستثناءات اليوم', to: '/hr/attendance' },
          { label: 'تقييمات قيد الدورة', value: data.pendingKpi, icon: Activity, hint: 'لم تصل للاعتماد النهائي', to: '/hr/performance' },
          { label: 'طلبات توظيف مفتوحة', value: data.openRequisitions, icon: BriefcaseBusiness, hint: 'طلبات معتمدة أو قيد النشر', to: '/hr/recruitment' },
        ]
      : [
          {
            label: 'إجمالي الموظفين',
            value: data.employees,
            icon: Users,
            hint: `${data.activeEmployees} موظفًا نشطًا بالمنظومة`,
            trend: data.employees ? `${Math.round((data.activeEmployees / data.employees) * 100)}% نشط` : undefined,
            to: '/admin/enterprise',
          },
          {
            label: 'حضور اليوم',
            value: att && att.expected > 0 ? `${Math.round((att.present / att.expected) * 100)}%` : '—',
            icon: UserCheck,
            hint: att ? `${att.present} حاضر من ${att.expected} متوقع اليوم` : 'نبض الحضور المباشر',
            trend: att && att.present > 0 ? `${att.present} حاضر` : undefined,
            to: '/admin/hr/attendance',
          },
          {
            label: 'إجراءات عاجلة',
            value: data.urgentActions,
            icon: ShieldAlert,
            hint: 'مهلتها خلال أربع ساعات',
            to: '/admin/actions',
          },
          {
            label: 'طلبات معلقة',
            value: data.pendingRequests,
            icon: BadgeCheck,
            hint: 'إجازات، مأموريات وتصحيحات',
            to: '/admin/hr/requests?status=pending',
          },
          {
            label: 'حضور يحتاج مراجعة',
            value: data.attendancePendingReview,
            icon: Clock3,
            hint: 'تصحيحات واستثناءات البصمة',
            to: '/admin/hr/attendance',
          },
          {
            label: 'تقييمات الأداء',
            value: data.pendingKpi,
            icon: Gauge,
            hint: 'قيد دورة KPI الحالية',
            to: '/admin/hr/performance',
          },
          {
            label: 'احتياج التوظيف',
            value: data.openRequisitions,
            icon: BriefcaseBusiness,
            hint: 'طلبات معتمدة قيد التعيين',
            to: '/admin/hr/recruitment',
          },
          {
            label: 'أخطاء غير محلولة',
            value: data.unresolvedErrors,
            icon: FileWarning,
            hint: 'من مركز المراقبة التقنية',
            to: '/admin/audit-security',
          },
        ]
    : [];

  const quickActions =
    type === 'hr'
      ? [
          { label: 'إضافة موظف', to: '/hr/employees/new', icon: Plus },
          { label: 'مراجعة الطلبات', to: '/hr/requests', icon: BadgeCheck },
          { label: 'تشغيل الحضور', to: '/hr/attendance/operations', icon: CalendarDays },
        ]
      : [
          { label: 'مركز الإجراءات', to: '/admin/actions', icon: ShieldAlert },
          { label: 'طلبات الموظفين', to: '/admin/hr/requests', icon: BadgeCheck },
          { label: 'قرار رسمي', to: '/admin/official-feed', icon: Plus },
          { label: 'مشاريع الجمعية', to: '/admin/association-projects', icon: FolderKanban },
          { label: 'حالة النظام', to: '/admin/settings', icon: Settings },
        ];

  const pulse = data
    ? type === 'hr'
      ? [
          { label: 'اكتمال الملفات النشطة', value: data.employees ? Math.round((data.activeEmployees / data.employees) * 100) : 0 },
          { label: 'الطلبات الخالية من التأخير', value: Math.max(0, 100 - Math.min(data.pendingRequests * 4, 55)) },
          { label: 'دورة الأداء الحالية', value: Math.max(15, 100 - Math.min(data.pendingKpi * 5, 78)) },
        ]
      : [
          { label: 'استقرار التشغيل التقني', value: Math.max(30, 100 - Math.min(data.unresolvedErrors * 9, 70)) },
          { label: 'معالجة الأولويات العاجلة', value: Math.max(20, 100 - Math.min(data.urgentActions * 8, 75)) },
          { label: 'الانتظام الإداري والطلبات', value: Math.max(25, 100 - Math.min(data.pendingRequests * 3, 65)) },
        ]
    : [];

  const priorities = data
    ? type === 'hr'
      ? [
          { title: `${data.attendancePendingReview} حالة حضور تحتاج مراجعة`, description: 'ابدأ بالتصحيحات الأقدم والأعلى تأثيرًا.', to: '/hr/attendance' },
          { title: `${data.pendingRequests} طلبًا داخل مسارات الاعتماد`, description: 'تابع الطلبات التي اقتربت من تجاوز SLA.', to: '/hr/requests?status=pending' },
          { title: `${data.openRequisitions} احتياج توظيف مفتوح`, description: 'راجع الموافقات وخطة المقابلات.', to: '/hr/recruitment' },
        ]
      : [
          { title: `${data.urgentActions} إجراء عاجل`, description: 'عناصر ذات أولوية زمنية أو أثر مؤسسي مرتفع.', to: '/admin/actions' },
          { title: `${data.pendingRequests} طلبًا ينتظر القرار`, description: 'رتبها حسب الأثر والموعد النهائي.', to: '/admin/hr/requests?status=pending' },
          { title: `${data.unresolvedErrors} خطأ تشغيلي غير مغلق`, description: 'راجع الحالة الفنية قبل أي إصدار جديد.', to: '/admin/settings' },
        ]
    : [];

  return (
    <div className="space-y-4">
      {/* ─── الترويسة التنفيذية المدمجة والأنيقة ──────────────────────────────────── */}
      <section className="dashboard-hero !p-4 sm:!p-5">
        <div className="dashboard-hero-grid items-center gap-3">
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <span className="hero-eyebrow !mb-0">{today}</span>
              <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-500/20 px-2 py-0.5 text-[11px] font-black text-emerald-200 backdrop-blur-sm">
                <span className="size-1.5 animate-pulse rounded-full bg-emerald-400" />
                المنظومة متصلة
              </span>
            </div>
            <h2 className="mt-1 text-xl font-black sm:text-2xl" title={auth.access?.displayName}>
              {getTimeGreeting()}، {getShortName(auth.access?.displayName ?? '')}
            </h2>
            <p className="mt-0.5 max-w-2xl text-xs leading-5 text-white/80">
              {type === 'hr'
                ? 'لوحة شؤون الموظفين — متابعة فورية للحضور والطلبات والاستحقاقات.'
                : 'لوحة القيادة المركزية — متابعة شاملة لكافة قطاعات وعمليات جمعية خواطر أحلى شباب.'}
            </p>
          </div>
          <div className="hero-actions flex-wrap gap-1.5">
            {quickActions.map((action) => {
              const Icon = action.icon;
              return (
                <Link key={action.to} to={action.to} className="hero-action !py-1.5 !px-3 !text-xs">
                  <Icon className="size-3.5" aria-hidden="true" />
                  {action.label}
                </Link>
              );
            })}
            <BroadcastAlertButton />
          </div>
        </div>
      </section>

      {query.isError ? (
        <ErrorState title="تعذر تحميل اللوحة" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && !data ? (
        <MetricSkeletonRow count={4} />
      ) : (
        <>
          {/* ─── شبكة المؤشرات التنفيذية المتناسقة (متوازنة تماماً بنظام 4×2) ────── */}
          <section
            className="grid grid-cols-2 gap-3 sm:grid-cols-2 md:grid-cols-4 lg:grid-cols-4"
            aria-label="المؤشرات الرئيسية"
          >
            {cards.map((card) => (
              <MetricCard key={card.label} {...card} compact={true} />
            ))}
          </section>

          {attendance.isError && <ErrorBanner message={safeErrorMessage(attendance.error)} />}

          {/* ─── نبض حضور وعمليات اليوم المباشرة (لكل من الإدارة و HR) ─────────────── */}
          {att ? (
            <section className="card p-4">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] pb-3">
                <div className="flex items-center gap-2.5">
                  <div className="grid size-9 place-items-center rounded-xl bg-brand/10 text-brand">
                    <UserCheck className="size-5" />
                  </div>
                  <div>
                    <h2 className="text-sm font-black">نبض الحضور المباشر اليوم — {att.date}</h2>
                    <p className="text-xs text-[var(--text-muted)]">
                      إجمالي المتوقع: {att.expected} موظفاً · الحضور الفعلي: {att.present} (
                      {att.expected > 0 ? Math.round((att.present / att.expected) * 100) : 0}%)
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <Link
                    to={type === 'admin' ? '/admin/hr/attendance?tab=executive' : '/hr/attendance?tab=executive'}
                    className="flex items-center gap-1 rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] px-2.5 py-1 text-xs font-bold transition-colors hover:bg-[var(--surface-raised)]"
                  >
                    <span>التقرير التنفيذي</span>
                    <ArrowUpRight className="size-3" />
                  </Link>
                  <Link
                    to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                    className="flex items-center gap-1 text-xs font-bold text-brand transition-colors hover:underline"
                  >
                    <span>شاشة الحضور والتتبع الحي</span>
                    <ArrowUpRight className="size-3.5" />
                  </Link>
                </div>
              </div>

              {/* شريط التوزيع البصري */}
              {att.expected > 0 && (
                <div className="mt-3.5 space-y-1.5">
                  <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-[var(--surface-muted)]">
                    <div
                      title={`حاضر: ${att.present}`}
                      className="bg-emerald-500 transition-all"
                      style={{ width: `${(att.present / att.expected) * 100}%` }}
                    />
                    <div
                      title={`متأخر: ${att.late}`}
                      className="bg-amber-500 transition-all"
                      style={{ width: `${(att.late / att.expected) * 100}%` }}
                    />
                    <div
                      title={`مأمورية / تكليف: ${att.onAssignment}`}
                      className="bg-sky-500 transition-all"
                      style={{ width: `${(att.onAssignment / att.expected) * 100}%` }}
                    />
                    <div
                      title={`إجازة معتمدة: ${att.onLeave}`}
                      className="bg-purple-500 transition-all"
                      style={{ width: `${(att.onLeave / att.expected) * 100}%` }}
                    />
                    <div
                      title={`غياب: ${att.absent}`}
                      className="bg-rose-500 transition-all"
                      style={{ width: `${(att.absent / att.expected) * 100}%` }}
                    />
                  </div>
                </div>
              )}

              {/* بطاقات توزيع الحضور الدقيقة */}
              <div className="mt-3.5 grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-6 text-xs">
                <Link
                  to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-emerald-500" />
                  <span className="font-bold">حاضر:</span>
                  <strong className="text-emerald-500">{att.present}</strong>
                </Link>
                <Link
                  to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-amber-500" />
                  <span className="font-bold">متأخر:</span>
                  <strong className="text-amber-500">{att.late}</strong>
                </Link>
                <Link
                  to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-sky-500" />
                  <span className="font-bold">مأمورية:</span>
                  <strong className="text-sky-500">{att.onAssignment}</strong>
                </Link>
                <Link
                  to={type === 'admin' ? '/admin/hr/leaves' : '/hr/leaves'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-purple-500" />
                  <span className="font-bold">إجازة:</span>
                  <strong className="text-purple-500">{att.onLeave}</strong>
                </Link>
                <Link
                  to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-slate-400" />
                  <span className="font-bold">لم يسجل:</span>
                  <strong>{att.notCheckedIn}</strong>
                </Link>
                <Link
                  to={type === 'admin' ? '/admin/hr/attendance' : '/hr/attendance'}
                  className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] p-2.5 transition-colors hover:bg-[var(--surface-raised)]"
                >
                  <span className="size-2 rounded-full bg-rose-500" />
                  <span className="font-bold">غياب:</span>
                  <strong className="text-rose-500">{att.absent}</strong>
                </Link>
              </div>
            </section>
          ) : null}

          {/* ─── خريطة مراكز المنظومة والوصول الشامل (كل شيء متاح من الداشبورد) ──── */}
          {type === 'admin' && (
            <section className="space-y-3">
              <div className="flex items-center justify-between">
                <h2 className="text-sm font-black text-[var(--text-secondary)]">مراكز العمل والخدمات المؤسسية</h2>
                <span className="text-xs text-[var(--text-muted)]">وصول سريع لكافة قطاعات النظام</span>
              </div>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {/* 1. الموظفون والتشكيل */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-blue-500/10 text-blue-500">
                        <Users className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">شؤون الموظفين والتشكيل</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">إدارة الموظفين، الهيكل، الأجهزة والعقود</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/hr/employees" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        دليل الموظفين
                      </Link>
                      <Link to="/admin/hr/employees/new" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        + إضافة موظف
                      </Link>
                      <Link to="/admin/enterprise" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        الهيكل المؤسسي
                      </Link>
                      <Link to="/admin/hr/devices" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        أجهزة البصمة
                      </Link>
                    </div>
                  </div>
                </div>

                {/* 2. الحضور والتتبع الميداني */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-emerald-500/10 text-emerald-500">
                        <Activity className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">العمليات والموقع الحي</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">سجلات البصمة، التتبع الميداني والورديات</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/hr/attendance" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        سجل الحضور
                      </Link>
                      <Link to="/admin/live-location" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        الموقع الحي للموظفين
                      </Link>
                      <Link to="/admin/executive-monitoring" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        المراقبة التنفيذية
                      </Link>
                    </div>
                  </div>
                </div>

                {/* 3. صندوق الطلبات والتكليفات */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-purple-500/10 text-purple-500">
                        <BadgeCheck className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">الطلبات والتكليفات</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">إجازات، مأموريات، قوافل، فاندي وتصحيحات</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/hr/requests" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        طلبات الموظفين
                      </Link>
                      <Link to="/admin/hr/requests?status=pending" className="rounded-lg bg-amber-500/10 text-amber-500 px-2.5 py-1 font-bold hover:bg-amber-500/20">
                        بانتظار الاعتماد ({data?.pendingRequests ?? 0})
                      </Link>
                      <Link to="/admin/hr/leaves" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        إدارة الإجازات
                      </Link>
                      <Link to="/admin/hr/holidays" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        العطل الرسمية
                      </Link>
                    </div>
                  </div>
                </div>

                {/* 4. المالية والغرامات الفورية */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-rose-500/10 text-rose-500">
                        <AlertOctagon className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">المالية والجزاءات الفورية</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">غرامات الحضور، الخصومات وصندوق التكافل</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/finance?tab=instant-penalties" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        غرامات الحضور والانصراف
                      </Link>
                      <Link to="/admin/fellowship-fund" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        صندوق التكافل والزمالة
                      </Link>
                    </div>
                  </div>
                </div>

                {/* 5. مشاريع الجمعية والأداء */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-amber-500/10 text-amber-500">
                        <FolderKanban className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">مشاريع الجمعية والأداء</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">المشاريع الجارية، دورات KPI والتدريب</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/association-projects" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        مشاريع الجمعية
                      </Link>
                      <Link to="/admin/hr/performance" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        الأداء والتقييمات
                      </Link>
                      <Link to="/admin/performance/cycles" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        دورات KPI والاعتراضات
                      </Link>
                      <Link to="/admin/knowledge" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        التدريب والمعرفة
                      </Link>
                    </div>
                  </div>
                </div>

                {/* 6. الأمان والحوكمة والرقابة */}
                <div className="card flex flex-col justify-between p-4 transition-all hover:border-[var(--brand-primary)]">
                  <div>
                    <div className="flex items-center gap-2.5">
                      <span className="grid size-9 place-items-center rounded-xl bg-slate-500/10 text-slate-400">
                        <ShieldCheck className="size-4.5" />
                      </span>
                      <div>
                        <h3 className="text-sm font-black">الأمان والحوكمة والرقابة</h3>
                        <p className="text-[11px] text-[var(--text-muted)]">لجنة الخلافات، سجل التدقيق والأدوار</p>
                      </div>
                    </div>
                    <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                      <Link to="/admin/disputes" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        لجنة الخلافات
                      </Link>
                      <Link to="/admin/audit-security" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        التدقيق والأمان
                      </Link>
                      <Link to="/admin/audit-trail" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        سجل التدقيق
                      </Link>
                      <Link to="/admin/access" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        الأدوار والصلاحيات
                      </Link>
                      <Link to="/admin/settings" className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 font-bold hover:bg-[var(--surface-raised)]">
                        الإعدادات
                      </Link>
                    </div>
                  </div>
                </div>
              </div>
            </section>
          )}

          {/* ─── نبض التشغيل + أولويات اليوم ────────────────────────────────────────── */}
          {data ? (
            <section className="grid gap-4 xl:grid-cols-[1.1fr_.9fr]">
              <article className="card p-4 sm:p-5">
                <div className="section-title-row">
                  <div>
                    <h2>نبض التشغيل</h2>
                    <p className="mt-1 text-xs text-[var(--text-muted)]">مؤشرات إرشادية تساعد على ترتيب العمل والجاهزية المؤسسية.</p>
                  </div>
                  <Sparkles className="size-5 text-[var(--brand-accent)]" aria-hidden="true" />
                </div>
                {pulse.map((item) => (
                  <div className="pulse-row" key={item.label}>
                    <div>
                      <div className="mb-2 flex items-center justify-between gap-3">
                        <span className="text-xs font-bold sm:text-sm">{item.label}</span>
                        <strong className="text-xs font-black text-[var(--brand-primary)] sm:text-sm">{item.value}%</strong>
                      </div>
                      <div
                        className="progress-track"
                        role="progressbar"
                        aria-label={item.label}
                        aria-valuenow={item.value}
                        aria-valuemin={0}
                        aria-valuemax={100}
                      >
                        <div className="progress-bar" style={{ width: `${item.value}%` }} />
                      </div>
                    </div>
                    <span className="grid size-8 place-items-center rounded-full bg-[var(--surface-muted)] text-xs font-black sm:size-9">
                      {item.value}
                    </span>
                  </div>
                ))}

                {/* رسم القوى العاملة المدمج */}
                <div className="mt-4 border-t border-[var(--border)] pt-3">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs font-bold text-[var(--text-secondary)]">توزيع القوى العاملة (نشط vs غير نشط)</span>
                    <span className="text-[11px] text-[var(--text-muted)]">{data.employees} إجمالي الموظفين</span>
                  </div>
                  <div className="flex h-3 w-full overflow-hidden rounded-full bg-[var(--surface-muted)]">
                    <div
                      title={`نشط: ${data.activeEmployees}`}
                      className="bg-brand transition-all"
                      style={{ width: `${data.employees > 0 ? (data.activeEmployees / data.employees) * 100 : 0}%` }}
                    />
                    <div
                      title={`غير نشط: ${Math.max(0, data.employees - data.activeEmployees)}`}
                      className="bg-slate-400 transition-all"
                      style={{ width: `${data.employees > 0 ? ((data.employees - data.activeEmployees) / data.employees) * 100 : 0}%` }}
                    />
                  </div>
                  <div className="mt-2 flex items-center justify-between text-[11px] text-[var(--text-muted)]">
                    <span className="flex items-center gap-1.5">
                      <span className="size-2 rounded-full bg-brand" />
                      نشط: {data.activeEmployees} ({data.employees > 0 ? Math.round((data.activeEmployees / data.employees) * 100) : 0}%)
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="size-2 rounded-full bg-slate-400" />
                      غير نشط / مؤقت: {Math.max(0, data.employees - data.activeEmployees)}
                    </span>
                  </div>
                </div>
              </article>

              <article className="card p-4 sm:p-5">
                <div className="section-title-row">
                  <div>
                    <h2>أولويات اليوم</h2>
                    <p className="mt-1 text-xs text-[var(--text-muted)]">مرتبة وفق الوقت والأثر التشغيلي المباشر.</p>
                  </div>
                </div>
                <div className="space-y-2">
                  {priorities.map((item) => (
                    <Link key={item.to + item.title} to={item.to} className="priority-item card-interactive !p-3">
                      <span className="priority-icon">
                        <Clock3 className="size-4" aria-hidden="true" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <strong className="block text-xs font-bold sm:text-sm">{item.title}</strong>
                        <small className="mt-0.5 block text-[11px] leading-4 text-[var(--text-muted)]">{item.description}</small>
                      </span>
                      <ArrowLeft className="mt-2 size-4 text-[var(--text-muted)]" aria-hidden="true" />
                    </Link>
                  ))}
                </div>
              </article>
            </section>
          ) : null}

          {/* ─── آخر الإشعارات والتنبيهات ────────────────────────────────────────── */}
          {data ? <RecentNotificationsSection type={type} /> : null}

          {/* ─── تذييل نطاق العرض وزمن آخر مزامنة ───────────────────────────────── */}
          {data ? (
            <section className="card flex flex-col gap-2 p-3 sm:flex-row sm:items-center sm:justify-between text-xs">
              <div className="flex items-center gap-2">
                <CheckCircle2 className="size-4 text-emerald-500" />
                <span className="font-bold text-[var(--text-secondary)]">نطاق اللوحة التنفيذية:</span>
                <span className="text-[var(--text-muted)]">
                  {type === 'admin' ? 'صلاحيات الإدارة العامة لكافة الفروع والقطاعات' : 'صلاحيات قسم الموارد البشرية'}
                </span>
              </div>
              <div className="text-[var(--text-muted)]">
                آخر مزامنة:{' '}
                {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(
                  new Date(data.lastUpdatedAt ?? Date.now()),
                )}
              </div>
            </section>
          ) : null}
        </>
      )}
    </div>
  );
}

/** أحدث الإشعارات في لوحة الويب — غير المقروء أولاً ثم الأحدث. */
function RecentNotificationsSection({ type }: { type: 'hr' | 'admin' }) {
  const q = useNotifications();
  const items = q.data ?? [];
  if (!items.length || q.isError) return null;

  const sorted = [...items].sort((a, b) => Number(a.isRead) - Number(b.isRead) || Date.parse(b.createdAt) - Date.parse(a.createdAt));
  const recent = sorted.slice(0, 5);
  const workspace = type === 'admin' ? 'admin' : 'hr';

  return (
    <section className="card p-4 sm:p-5">
      <div className="section-title-row">
        <div>
          <h2>آخر الإشعارات</h2>
          <p className="mt-1 text-xs text-[var(--text-muted)]">أحدث التنبيهات الموجهة إلى حسابك — غير المقروء أولاً.</p>
        </div>
        <Link
          to={workspace === 'admin' ? '/admin/notifications' : '/hr/notifications'}
          className="text-xs font-bold text-[var(--brand-primary)] hover:underline"
        >
          عرض الكل
        </Link>
      </div>

      <div className="mt-3 space-y-1.5">
        {recent.map((n) => {
          const Icon = notificationCategoryIcon(n.category);
          const target = notificationTargetPath(n, workspace);
          const urgent = n.priority === 'urgent' || n.priority === 'high';
          const card = (
            <div className="flex items-center gap-3 rounded-xl px-2.5 py-2 hover:bg-[var(--surface-muted)] transition-colors">
              <span
                aria-hidden="true"
                className={`grid size-9 shrink-0 place-items-center rounded-xl ${
                  urgent ? 'bg-[var(--danger-soft)] text-[var(--danger)]' : 'bg-[var(--surface-muted)] text-[var(--brand-primary)]'
                }`}
              >
                <Icon className="size-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-2">
                  <strong className="block truncate text-xs font-bold sm:text-sm">{n.title}</strong>
                  {!n.isRead ? <span className="size-2 shrink-0 rounded-full bg-[var(--brand-primary)]" aria-label="غير مقروء" /> : null}
                </span>
                <small className="muted mt-0.5 block text-[11px]">
                  {notificationCategoryLabel(n.category)} · {relativeTime(n.createdAt)}
                </small>
              </span>
              {urgent ? <StatusBadge value={n.priority} /> : null}
            </div>
          );
          return target ? (
            <Link key={n.id} to={target} className="block" aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}>
              {card}
            </Link>
          ) : (
            <div key={n.id}>{card}</div>
          );
        })}
      </div>
    </section>
  );
}
