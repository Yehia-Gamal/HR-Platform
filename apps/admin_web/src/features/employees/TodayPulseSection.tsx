import { CheckCircle2, Clock3, MapPin, UserMinus } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { cairoTodayIso } from '../../core/cairoTime';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasAnyPermission } from '../workspaces/access';
import { loadDomainMocks } from '../mock/loadDomainMocks';
import { ATTENDANCE_STATUS_LABELS } from '../management/statusLabels';
import { LiveLocationResultCard } from '../management/LiveLocationResultCard';
import type { EmployeeOverviewRow, ExecutiveOverviewData } from '../management/controlCenterTypes';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorState } from '../../ui/ErrorState';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';

// قسم "نبض اليوم" في دليل الموظفين: من حضر ومن تغيّب ومن تأخّر
// ومن أُرسل له طلب موقع — كل بطاقة قابلة للنقر وتفتح قائمة الموظفين المعنيين.

const PRESENT_STATUSES = ['present', 'late', 'checked_out', 'left_early'];

export type PulseDialogKind = 'present' | 'absent' | 'late' | 'location';

export function presentEmployees(employees: EmployeeOverviewRow[]): EmployeeOverviewRow[] {
  return employees.filter((e) => PRESENT_STATUSES.includes(e.status));
}

export function absentEmployees(employees: EmployeeOverviewRow[]): EmployeeOverviewRow[] {
  return employees.filter((e) => e.status === 'absent');
}

export function lateEmployees(employees: EmployeeOverviewRow[]): EmployeeOverviewRow[] {
  return employees.filter((e) => e.status === 'late' || e.status === 'left_early');
}

export function locationRequestEmployees(employees: EmployeeOverviewRow[]): EmployeeOverviewRow[] {
  return employees.filter((e) => Boolean(e.activeRequestId));
}

export function totalLateMinutes(employees: EmployeeOverviewRow[]): number {
  return lateEmployees(employees).reduce((sum, e) => sum + Math.max(0, e.lateMinutes ?? 0), 0);
}

export function presentPercent(employees: EmployeeOverviewRow[]): number {
  if (!employees.length) return 0;
  return Math.round((presentEmployees(employees).length / employees.length) * 100);
}

export function useTodayPulse(enabled: boolean) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['today-pulse', auth.isMock],
    enabled: enabled && auth.status === 'authenticated',
    refetchInterval: auth.isMock ? false : 60_000,
    staleTime: 30_000,
    queryFn: async (): Promise<ExecutiveOverviewData> => {
      if (auth.isMock) return (await loadDomainMocks()).mockDailyPulse;
      const data = await rpc<ExecutiveOverviewData | null>('get_executive_attendance_overview', { p_date: cairoTodayIso() });
      return (data ?? { summary: { total: 0 }, employees: [] }) as ExecutiveOverviewData;
    },
  });
}

function relative(value: string | null): string {
  if (!value) return '—';
  const m = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 60000));
  if (m < 1) return 'الآن';
  if (m < 60) return `منذ ${m} د`;
  const h = Math.round(m / 60);
  return h < 24 ? `منذ ${h} س` : `منذ ${Math.round(h / 24)} يوم`;
}

function time(value: string | null): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-EG', { hour: '2-digit', minute: '2-digit' }).format(new Date(value));
}

const DIALOG_META: Record<PulseDialogKind, { title: string; empty: string }> = {
  present: { title: 'حضروا اليوم', empty: 'لم يسجّل أحد حضوره بعد اليوم.' },
  absent: { title: 'تغيّبوا اليوم', empty: 'لا يوجد غياب مسجّل اليوم.' },
  late: { title: 'تأخّروا اليوم', empty: 'لا يوجد تأخير مسجّل اليوم.' },
  location: { title: 'طلبات الموقع المرسلة', empty: 'لا توجد طلبات موقع نشطة اليوم.' },
};

function dialogEmployees(kind: PulseDialogKind, employees: EmployeeOverviewRow[]): EmployeeOverviewRow[] {
  if (kind === 'present') return presentEmployees(employees);
  if (kind === 'absent') return absentEmployees(employees);
  if (kind === 'late') return lateEmployees(employees);
  return locationRequestEmployees(employees);
}

export function TodayPulseSection() {
  const auth = useAuth();
  const allowed = auth.access ? hasAnyPermission(auth.access, ['reports.attendance.read', 'live_location.request']) : false;
  const query = useTodayPulse(allowed);
  const [dialog, setDialog] = useState<PulseDialogKind | null>(null);
  const [selectedRequestId, setSelectedRequestId] = useState<string | null>(null);

  const employees = useMemo(() => query.data?.employees ?? [], [query.data]);
  const present = useMemo(() => presentEmployees(employees), [employees]);
  const absent = useMemo(() => absentEmployees(employees), [employees]);
  const late = useMemo(() => lateEmployees(employees), [employees]);
  const locationSents = useMemo(() => locationRequestEmployees(employees), [employees]);
  const locationResponded = useMemo(
    () => locationSents.filter((e) => e.activeRequestStatus === 'completed').length,
    [locationSents],
  );
  const lateMinutes = useMemo(() => totalLateMinutes(employees), [employees]);
  const pct = useMemo(() => presentPercent(employees), [employees]);

  if (!allowed) return null;
  if (query.isLoading) return <MetricSkeletonRow />;
  if (query.isError) {
    return (
      <section aria-label="نبض اليوم">
        <ErrorState title="تعذّر تحميل نبض اليوم" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      </section>
    );
  }
  if (!employees.length) return null;

  const cards = [
    { kind: 'present' as const, label: 'حضروا اليوم', value: present.length, icon: CheckCircle2, hint: `${pct}% من إجمالي ${employees.length} موظفًا` },
    { kind: 'absent' as const, label: 'تغيّبوا اليوم', value: absent.length, icon: UserMinus, hint: 'بعد استبعاد الإجازات والمأموريات' },
    { kind: 'late' as const, label: 'تأخّروا اليوم', value: late.length, icon: Clock3, hint: lateMinutes > 0 ? `إجمالي ${lateMinutes} دقيقة تأخير` : 'تُحسب من سياسة الوردية' },
    {
      kind: 'location' as const,
      label: 'أُرسل لهم طلب موقع',
      value: locationSents.length,
      icon: MapPin,
      hint: locationSents.length ? `${locationResponded} من ${locationSents.length} استجابوا` : 'لا توجد طلبات نشطة',
    },
  ];

  return (
    <section className="space-y-3" aria-label="نبض اليوم">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-black text-[var(--text-muted)]">نبض اليوم — الحضور وطلبات الموقع</h2>
        {query.isFetching ? <span className="text-xs text-[var(--text-muted)]">جارٍ التحديث…</span> : null}
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map((card) => (
          <button
            key={card.kind}
            type="button"
            onClick={() => setDialog(card.kind)}
            className="metric-card metric-card--linked cursor-pointer text-start transition-shadow hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--brand-primary)]"
            aria-label={`${card.label}: ${card.value} — اضغط لعرض القائمة`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-xs font-extrabold text-[var(--text-muted)]">{card.label}</p>
                <p className="mt-2 text-3xl font-black tracking-tight">{card.value}</p>
              </div>
              <span className="metric-icon">
                <card.icon className="size-5" aria-hidden="true" />
              </span>
            </div>
            <p className="mt-3 text-xs leading-5 text-[var(--text-muted)]">{card.hint}</p>
            <span className="mt-2 flex items-center gap-1 text-xs font-bold text-[var(--brand-primary)]">عرض القائمة</span>
          </button>
        ))}
      </div>

      {dialog ? (
        <DialogOverlay title={`${DIALOG_META[dialog].title} — ${dialogEmployees(dialog, employees).length} موظف`} onClose={() => setDialog(null)} maxWidth="max-w-2xl">
          <PulseDialogBody kind={dialog} employees={employees} onSelectRequest={(id) => { setDialog(null); setSelectedRequestId(id); }} />
        </DialogOverlay>
      ) : null}

      {selectedRequestId ? (
        <DialogOverlay title="نتيجة طلب الموقع" onClose={() => setSelectedRequestId(null)} maxWidth="max-w-2xl">
          <LiveLocationResultCard requestId={selectedRequestId} />
        </DialogOverlay>
      ) : null}
    </section>
  );
}

function PulseDialogBody({
  kind,
  employees,
  onSelectRequest,
}: {
  kind: PulseDialogKind;
  employees: EmployeeOverviewRow[];
  onSelectRequest: (requestId: string) => void;
}) {
  const list = dialogEmployees(kind, employees);
  if (!list.length) {
    return <p className="py-8 text-center text-sm text-[var(--text-muted)]">{DIALOG_META[kind].empty}</p>;
  }
  return (
    <ul className="max-h-[60vh] divide-y divide-[var(--border)] overflow-y-auto">
      {list.map((e) => (
        <li key={e.id} className="flex items-start justify-between gap-3 py-3">
          <div className="flex min-w-0 items-start gap-3">
            <UserAvatar displayName={e.name ?? ''} size="sm" />
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <Link to={`/hr/employees/${e.id}`} className="truncate font-black hover:text-[var(--brand-primary)]">
                  {e.name}
                </Link>
                <StatusBadge value={e.status} label={ATTENDANCE_STATUS_LABELS[e.status] ?? e.status} />
                {kind === 'late' && typeof e.lateMinutes === 'number' && e.lateMinutes > 0 ? (
                  <span className="status-badge status-warning">{e.status === 'left_early' ? 'انصرف مبكرًا' : `متأخر ${e.lateMinutes} د`}</span>
                ) : null}
              </div>
              <p className="muted mt-1 text-xs">
                {e.employeeCode ?? '—'} · {e.department ?? 'دون إدارة'}
              </p>
              <p className="muted mt-1 text-xs">
                {e.checkInAt ? `حضر ${time(e.checkInAt)}` : 'لم يسجّل حضورًا بعد'}
                {e.lastLocationAt ? ` · آخر موقع: ${relative(e.lastLocationAt)}` : ''}
                {e.lastAddressAr ? ` — ${e.lastAddressAr}` : ''}
              </p>
            </div>
          </div>
          {e.activeRequestId ? (
            <button type="button" className="btn-secondary shrink-0 !px-3 !py-2 text-xs" onClick={() => { if (e.activeRequestId) onSelectRequest(e.activeRequestId); }}>
              <MapPin className="size-3.5" aria-hidden="true" />
              نتيجة الموقع
            </button>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
