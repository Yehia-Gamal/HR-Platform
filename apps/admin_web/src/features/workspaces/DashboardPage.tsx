import {
  Activity,
  ArrowLeft,
  BadgeCheck,
  BriefcaseBusiness,
  CalendarDays,
  Clock3,
  FileWarning,
  MapPin,
  Plus,
  ShieldAlert,
  Sparkles,
  UserCheck,
  UserMinus,
  UserX,
  Users,
} from 'lucide-react';
import { Link } from 'react-router-dom';
import { ErrorState } from '../../ui/ErrorState';
import { getShortName, getTimeGreeting } from '../../ui/formatDisplayName';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { useAuth } from '../auth/AuthProvider';
import { useDashboardOverview } from '../management/useManagementOverviews';
import { useAttendanceTodayOverview } from './useAttendanceTodayOverview';

export function DashboardPage({ type }: { type: 'hr' | 'admin' }) {
  const auth = useAuth();
  const query = useDashboardOverview(type === 'hr' ? 'hr' : 'main_admin');
  const attendance = useAttendanceTodayOverview();
  const att = attendance.data;
  const data = query.data;
  const today = new Intl.DateTimeFormat('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date());
  const cards = data ? (type === 'hr' ? [
    { label: 'إجمالي الموظفين', value: data.employees, icon: Users, hint: `${data.activeEmployees} موظفًا نشطًا`, trend: data.employees ? `${Math.round((data.activeEmployees / data.employees) * 100)}% نشط` : undefined },
    { label: 'طلبات معلقة', value: data.pendingRequests, icon: BadgeCheck, hint: 'وفق نطاق وصلاحيات المستخدم' },
    { label: 'حضور يحتاج مراجعة', value: data.attendancePendingReview, icon: Clock3, hint: 'تصحيحات واستثناءات اليوم' },
    { label: 'تقييمات قيد الدورة', value: data.pendingKpi, icon: Activity, hint: 'لم تصل للاعتماد النهائي' },
    { label: 'طلبات توظيف مفتوحة', value: data.openRequisitions, icon: BriefcaseBusiness, hint: 'طلبات معتمدة أو قيد النشر' },
  ] : [
    { label: 'إجمالي الموظفين', value: data.employees, icon: Users, hint: `${data.activeEmployees} موظفًا نشطًا`, trend: data.employees ? `${Math.round((data.activeEmployees / data.employees) * 100)}% نشط` : undefined },
    { label: 'إجراءات عاجلة', value: data.urgentActions, icon: ShieldAlert, hint: 'مهلتها خلال أربع ساعات' },
    { label: 'طلبات معلقة', value: data.pendingRequests, icon: BadgeCheck, hint: 'عبر المسارات المصرح بها' },
    { label: 'قرارات منشورة', value: data.publishedDecisions, icon: Activity, hint: 'داخل القناة الرسمية' },
    { label: 'أخطاء غير محلولة', value: data.unresolvedErrors, icon: FileWarning, hint: 'من مركز المراقبة التقنية' },
  ]) : [];

  const quickActions = type === 'hr' ? [
    { label: 'إضافة موظف', to: '/hr/employees/new', icon: Plus },
    { label: 'مراجعة الطلبات', to: '/hr/requests', icon: BadgeCheck },
    { label: 'تشغيل الحضور', to: '/hr/attendance/operations', icon: CalendarDays },
  ] : [
    { label: 'مركز الإجراءات', to: '/admin/actions', icon: ShieldAlert },
    { label: 'قرار رسمي', to: '/admin/official-feed', icon: Plus },
    { label: 'حالة النظام', to: '/admin/settings', icon: Activity },
  ];

  const pulse = data ? (type === 'hr' ? [
    { label: 'اكتمال الملفات النشطة', value: data.employees ? Math.round((data.activeEmployees / data.employees) * 100) : 0 },
    { label: 'الطلبات الخالية من التأخير', value: Math.max(0, 100 - Math.min(data.pendingRequests * 4, 55)) },
    { label: 'دورة الأداء الحالية', value: Math.max(15, 100 - Math.min(data.pendingKpi * 5, 78)) },
  ] : [
    { label: 'استقرار التشغيل', value: Math.max(30, 100 - Math.min(data.unresolvedErrors * 9, 70)) },
    { label: 'معالجة الأولويات', value: Math.max(20, 100 - Math.min(data.urgentActions * 8, 75)) },
    { label: 'الانتظام الإداري', value: Math.max(25, 100 - Math.min(data.pendingRequests * 3, 65)) },
  ]) : [];

  const priorities = data ? (type === 'hr' ? [
    { title: `${data.attendancePendingReview} حالة حضور تحتاج مراجعة`, description: 'ابدأ بالتصحيحات الأقدم والأعلى تأثيرًا.', to: '/hr/attendance' },
    { title: `${data.pendingRequests} طلبًا داخل مسارات الاعتماد`, description: 'تابع الطلبات التي اقتربت من تجاوز SLA.', to: '/hr/requests' },
    { title: `${data.openRequisitions} احتياج توظيف مفتوح`, description: 'راجع الموافقات وخطة المقابلات.', to: '/hr/recruitment' },
  ] : [
    { title: `${data.urgentActions} إجراء عاجل`, description: 'عناصر ذات أولوية زمنية أو أثر مؤسسي مرتفع.', to: '/admin/actions' },
    { title: `${data.pendingRequests} طلبًا ينتظر القرار`, description: 'رتبها حسب الأثر والموعد النهائي.', to: '/admin/actions' },
    { title: `${data.unresolvedErrors} خطأ تشغيلي غير مغلق`, description: 'راجع الحالة الفنية قبل أي إصدار جديد.', to: '/admin/settings' },
  ]) : [];

  return <div className="space-y-5">
    <section className="dashboard-hero">
      <div className="dashboard-hero-grid">
        <div>
          <p className="hero-eyebrow">{today}</p>
          <h2 className="text-2xl font-black sm:text-3xl" title={auth.access?.displayName}>{getTimeGreeting()}، {getShortName(auth.access?.displayName ?? '')}</h2>
          <p className="mt-2 max-w-2xl text-sm leading-7 text-white/80">
            {type === 'hr' ? 'هذه صورة تشغيلية مباشرة للموظفين والحضور والطلبات والأداء.' : 'هنا أهم القرارات والمخاطر والإجراءات التي تحتاج انتباهك اليوم.'}
          </p>
        </div>
        <div className="hero-actions">
          {quickActions.map((action) => { const Icon = action.icon; return <Link key={action.to} to={action.to} className="hero-action"><Icon className="size-4" aria-hidden="true" />{action.label}</Link>; })}
        </div>
      </div>
    </section>

    {query.isError ? (
      <ErrorState
        title="تعذر تحميل اللوحة"
        description={query.error instanceof Error ? query.error.message : undefined}
        onRetry={() => void query.refetch()}
      />
    ) : query.isLoading && !data ? (
      <MetricSkeletonRow count={5} />
    ) : (
      <>
        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5" aria-label="المؤشرات الرئيسية">
          {cards.map((card) => <MetricCard key={card.label} {...card} />)}
        </section>

        {type === 'hr' && att ? (() => {
          const breakdownCards = [
            { label: 'حاضر', value: att.present, icon: UserCheck, hint: `من ${att.expected} متوقع` },
            { label: 'متأخر', value: att.late, icon: Clock3, hint: 'سجّل حضور بعد الموعد' },
            { label: 'لم يسجّل بعد', value: att.notCheckedIn, icon: UserMinus, hint: 'لم يسجّل دخول حتى الآن' },
            { label: 'إجازة', value: att.onLeave, icon: CalendarDays, hint: 'في إجازة معتمدة' },
            { label: 'تكليف خارجي', value: att.onAssignment, icon: MapPin, hint: 'مكلف خارج المقر' },
            { label: 'غياب', value: att.absent, icon: UserX, hint: 'غير مبرر حتى الآن' },
          ].filter((c) => c.value > 0);
          return breakdownCards.length > 0 ? <section>
            <h2 className="mb-3 text-sm font-black text-[var(--text-muted)]">توزيع حضور اليوم — {att.date}</h2>
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6" aria-label="توزيع الحضور">
              {breakdownCards.map((card) => <MetricCard key={card.label} {...card} />)}
            </div>
          </section> : null;
        })() : null}

        {data ? <section className="grid gap-4 xl:grid-cols-[1.2fr_.8fr]">
          <article className="card p-5">
            <div className="section-title-row"><div><h2>نبض التشغيل</h2><p className="mt-1 text-xs text-[var(--text-muted)]">مؤشرات إرشادية تساعد على ترتيب العمل ولا تستبدل التقارير التفصيلية.</p></div><Sparkles className="size-5 text-[var(--brand-accent)]" aria-hidden="true" /></div>
            {pulse.map((item) => <div className="pulse-row" key={item.label}><div><div className="mb-2 flex items-center justify-between gap-3"><span className="text-sm font-bold">{item.label}</span><strong className="text-sm text-[var(--brand-primary)]">{item.value}%</strong></div><div className="progress-track" role="progressbar" aria-label={item.label} aria-valuenow={item.value} aria-valuemin={0} aria-valuemax={100}><div className="progress-bar" style={{ width: `${item.value}%` }} /></div></div><span className="grid size-9 place-items-center rounded-full bg-[var(--surface-muted)] text-xs font-black">{item.value}</span></div>)}
          </article>

          <article className="card p-5">
            <div className="section-title-row"><div><h2>أولويات اليوم</h2><p className="mt-1 text-xs text-[var(--text-muted)]">مرتبة وفق الوقت والأثر التشغيلي.</p></div></div>
            {priorities.map((item) => <Link key={item.to + item.title} to={item.to} className="priority-item card-interactive"><span className="priority-icon"><Clock3 className="size-4" aria-hidden="true" /></span><span className="min-w-0 flex-1"><strong className="block text-sm">{item.title}</strong><small className="mt-1 block leading-5 text-[var(--text-muted)]">{item.description}</small></span><ArrowLeft className="mt-2 size-4 text-[var(--text-muted)]" aria-hidden="true" /></Link>)}
          </article>
        </section> : null}

        {data ? <section className="card flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm font-black">نطاق العرض</p><p className="mt-1 text-xs text-[var(--text-muted)]">تظهر المؤشرات والمهام المسموح بها فقط وفق دورك ومسؤولياتك الحالية.</p></div><div className="rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs font-bold text-[var(--text-muted)]">آخر مزامنة: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(data.lastUpdatedAt))}</div></section> : null}
      </>
    )}
  </div>;
}
