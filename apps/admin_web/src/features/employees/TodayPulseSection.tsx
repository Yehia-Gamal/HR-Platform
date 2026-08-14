import { CheckCircle2, Clock3, MapPin, RefreshCw, UserMinus, FileDown } from 'lucide-react';
import { Fragment, useMemo, useState } from 'react';
import { Link } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { cairoTodayIso } from '../../core/cairoTime';
import { relativeTime, formatClock } from '../../core/formatTime';
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
import { useAttendanceTrend } from './useAttendanceTrend';
import { AttendanceTrendSparkline } from './AttendanceTrendSparkline';
import { exportPulseListPDF } from './exportPulseListPDF';

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

// الطلبات النشطة في الـ RPC لا تشمل 'completed' — فنعدّ 'accepted'/'active' كاستجابة.
const RESPONDED_STATUSES = ['accepted', 'active', 'completed'];

export function respondedCount(employees: EmployeeOverviewRow[]): number {
  return locationRequestEmployees(employees).filter((e) => e.activeRequestStatus && RESPONDED_STATUSES.includes(e.activeRequestStatus)).length;
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

const CARD_TONES: Record<PulseDialogKind, string> = {
  present: 'text-[var(--success)]',
  absent: 'text-[var(--danger)]',
  late: 'text-[var(--warning)]',
  location: 'text-[var(--brand-primary)]',
};

export function TodayPulseSection() {
  const auth = useAuth();
  const allowed = auth.access ? hasAnyPermission(auth.access, ['reports.attendance.read', 'live_location.request']) : false;
  const query = useTodayPulse(allowed);
  const trend = useAttendanceTrend(7, allowed);
  const [dialog, setDialog] = useState<PulseDialogKind | null>(null);
  const [selectedRequestId, setSelectedRequestId] = useState<string | null>(null);

  const employees = useMemo(() => query.data?.employees ?? [], [query.data]);
  const present = useMemo(() => presentEmployees(employees), [employees]);
  const absent = useMemo(() => absentEmployees(employees), [employees]);
  const late = useMemo(() => lateEmployees(employees), [employees]);
  const locationSents = useMemo(() => locationRequestEmployees(employees), [employees]);
  const responded = useMemo(() => respondedCount(employees), [employees]);
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
    {
      kind: 'late' as const,
      label: 'تأخّروا اليوم',
      value: late.length,
      icon: Clock3,
      hint: lateMinutes > 0 ? `إجمالي ${lateMinutes} دقيقة تأخير` : 'تُحسب من سياسة الوردية',
    },
    {
      kind: 'location' as const,
      label: 'أُرسل لهم طلب موقع',
      value: locationSents.length,
      icon: MapPin,
      hint: locationSents.length ? `${responded} من ${locationSents.length} استجابوا` : 'لا توجد طلبات نشطة',
    },
  ];

  return (
    <section className="space-y-3" aria-label="نبض اليوم">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-black text-[var(--text-muted)]">نبض اليوم — الحضور وطلبات الموقع</h2>
        <button
          type="button"
          className="icon-button"
          onClick={() => void query.refetch()}
          disabled={query.isFetching}
          aria-busy={query.isFetching}
          aria-label="تحديث نبض اليوم"
        >
          <RefreshCw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
        </button>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map((card) => {
          const buttonEl = (
            <button
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
                  <card.icon className={`size-5 ${CARD_TONES[card.kind]}`} aria-hidden="true" />
                </span>
              </div>
              <p className="mt-3 text-xs leading-5 text-[var(--text-muted)]">{card.hint}</p>
              <span className="mt-2 flex items-center gap-1 text-xs font-bold text-[var(--brand-primary)]">عرض القائمة</span>
              {card.kind === 'present' && trend.data ? <AttendanceTrendSparkline points={trend.data} /> : null}
            </button>
          );
          return <Fragment key={card.kind}>{buttonEl}</Fragment>;
        })}
      </div>

      {dialog ? (
        <DialogOverlay
          title={`${DIALOG_META[dialog].title} — ${dialogEmployees(dialog, employees).length} موظف`}
          onClose={() => setDialog(null)}
          maxWidth="max-w-2xl"
        >
          <PulseDialogBody
            kind={dialog}
            employees={employees}
            onSelectRequest={(id) => {
              setDialog(null);
              setSelectedRequestId(id);
            }}
          />
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
    <div className="space-y-3">
      {kind === 'present' ? (
        <div className="flex justify-end">
          <button type="button" className="btn-secondary !px-3 !py-2 text-xs" onClick={() => exportPulseListPDF(list, kind)}>
            <FileDown className="size-3.5" aria-hidden="true" />
            تصدير PDF
          </button>
        </div>
      ) : null}
      <ul className="max-h-[60vh] divide-y divide-[var(--border)] overflow-y-auto">
        {list.map((e) => (
          <li key={e.id} className="flex items-start justify-between gap-3 py-3">
            <div className="flex min-w-0 items-start gap-3">
              <UserAvatar displayName={e.name ?? ''} photoUrl={e.avatarUrl} size="sm" />
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <Link to={`/hr/employees/${e.id}`} className="truncate font-black hover:text-[var(--brand-primary)]">
                    {e.name}
                  </Link>
                  <StatusBadge value={e.status} label={ATTENDANCE_STATUS_LABELS[e.status] ?? e.status} />
                  {/* شارة التأخير — تظهر للمتأخر بغضون عن left_early */}
                  {e.status === 'late' && typeof e.lateMinutes === 'number' && e.lateMinutes > 0 ? (
                    <span className="status-badge status-warning">متأخر {e.lateMinutes} د</span>
                  ) : null}
                  {/* شارة الانصراف المبكر — مستقلة عن دقائق التأخير */}
                  {e.status === 'left_early' ? <span className="status-badge status-warning">انصرف مبكرًا</span> : null}
                  {/* نوع التكليف للمأمورية/القافلة/الفاندي */}
                  {e.assignmentType ? (
                    <span className="status-badge status-info">
                      {e.assignmentType === 'MISSION'
                        ? 'مأمورية'
                        : e.assignmentType === 'CONVOY'
                          ? 'قافلة'
                          : e.assignmentType === 'FUNDRAISING'
                            ? 'فاندي'
                            : e.assignmentType}
                    </span>
                  ) : null}
                </div>
                <p className="muted mt-1 text-xs">
                  {e.employeeCode ?? '—'} · {e.department ?? 'دون إدارة'}
                  {e.managerName ? ` · مدير: ${e.managerName}` : ''}
                </p>
                <p className="muted mt-1 text-xs">
                  {e.checkInAt ? `حضر ${formatClock(e.checkInAt)}` : 'لم يسجّل حضورًا بعد'}
                  {e.checkOutAt ? ` · انصرف ${formatClock(e.checkOutAt)}` : ''}
                  {e.lastLocationAt ? ` · آخر موقع: ${relativeTime(e.lastLocationAt)}` : ''}
                  {e.lastAddressAr ? ` — ${e.lastAddressAr}` : ''}
                </p>
              </div>
            </div>
            {e.activeRequestId ? (
              <button
                type="button"
                className="btn-secondary shrink-0 !px-3 !py-2 text-xs"
                onClick={() => {
                  if (e.activeRequestId) onSelectRequest(e.activeRequestId);
                }}
              >
                <MapPin className="size-3.5" aria-hidden="true" />
                نتيجة الموقع
              </button>
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}
