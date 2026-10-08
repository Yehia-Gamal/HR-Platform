import {
  MISSION_EXECUTION_STATUS_LABELS,
  REQUEST_STATUS_LABELS,
  type RequestSummary,
  type WorkAssignment,
  type AttendanceOperationsCatalog,
} from '@ahla/shared-contracts';
import { CalendarDays, Check, CheckCircle2, Clock, Clock3, CornerUpLeft, FileX, Inbox, ListChecks, MapPin, RefreshCw, RotateCcw, Truck, X } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router';
import { useUrlState } from '../../core/useUrlState';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { UserAvatar } from '../../ui/UserAvatar';
import { useBulkApprove, useMyLeaveBalances, useRequestDecision, useRequestDetail, useRequests, useWorkAssignments, type Decision } from './useRequests';
import { DecisionInsights, RequestJourney } from './RequestJourney';
import { useAttendanceOperations, useAttendanceOperationsCommands } from '../advanced/useAdvancedOperations';
import { safeErrorMessage } from '../../core/errorMapper';
import { cairoMonthIso } from '../../core/cairoTime';

const labels: Record<RequestSummary['requestType'], string> = {
  leave: 'إجازة',
  mission: 'مأمورية',
  convoy: 'قافلة',
  fundraising: 'فاندي',
  late_permit: 'إذن حضور',
  early_permit: 'إذن انصراف',
  attendance_correction: 'تصحيح حضور',
  shift_change: 'تغيير فترة العمل',
};

/// تنسيق فترة الطلب من startDate/endDate (YYYY-MM-DD) بالعربية — يعرض
/// التاريخ الواحد إذا لم تُحدد نهاية.
function formatPeriodLabel(startDate: unknown, endDate: unknown): string {
  const fmt = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { day: 'numeric', month: 'short', year: 'numeric' });
  const parse = (value: unknown): Date | null => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(value)) return null;
    const parsed = new Date(`${value.slice(0, 10)}T00:00:00`);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  };
  const start = parse(startDate);
  const end = parse(endDate);
  if (!start) return 'بدون فترة محددة';
  if (!end || end.getTime() === start.getTime()) return fmt.format(start);
  return `${fmt.format(start)} — ${fmt.format(end)}`;
}
const assignmentLabels: Record<WorkAssignment['assignmentType'], string> = { MISSION: 'مأمورية', CONVOY: 'قافلة', FUNDRAISING: 'فاندي' };
/// كشف ما إذا كان النص المخزن في حقل الكود هو في الحقيقة رقم هاتف أو قيمة بلا فائدة —
/// يحدث هذا لدى بعض السجلات القديمة حيث حُفظ الهاتف في خانة الكود.
function isPhoneLikeCode(code: string | null | undefined): boolean {
  if (!code) return true;
  const trimmed = code.trim();
  if (!trimmed) return true;
  // رقم دولي أو رقم طويل تسلسلي لا يشبه كود الموظف
  return /^\+?\d{9,}$/.test(trimmed);
}

const currentMonth = cairoMonthIso();

/** بانتظار قراري: علم الخادم (0646) — ولا يبتّ أحد في طلبه. */
function isAwaitingMe(item: RequestSummary): boolean {
  return item.status === 'pending' && !item.isMine && (item.awaitingMe ?? item.canDecide ?? false);
}

/** شارة المرحلة الحالية للطلب مع لونها */
function TierBadge({ workflowStatus, activeStepName }: { workflowStatus: string; activeStepName: string | null }) {
  const label = activeStepName;
  if (!label) return null;
  const colorClass =
    workflowStatus === 'awaiting_operator'
      ? 'bg-[var(--warning)]/15 text-[var(--warning)]'
      : workflowStatus === 'escalated'
        ? 'bg-[var(--danger)]/15 text-[var(--danger)]'
        : 'bg-brand/10 text-brand';
  return <span className={`rounded-lg px-2 py-0.5 text-xs font-black ${colorClass}`}>{label}</span>;
}

/** النص الزمني المتبقي حتى انتهاء مهلة الخطوة الحالية */
function EscalationCountdown({ dueAt }: { dueAt: string | null }) {
  if (!dueAt) return null;
  const diff = new Date(dueAt).getTime() - Date.now();
  if (diff <= 0) return <span className="text-[var(--danger)] text-xs font-bold">تجاوز المهلة</span>;
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  const label = h > 0 ? `${h}س ${m}د` : `${m} دقيقة`;
  return <span className="muted text-xs">متبقي {label}</span>;
}

export function RequestsPage() {
  const { toast } = useToast();
  const auth = useAuth();
  const query = useRequests();
  const decision = useRequestDecision();
  const balances = useMyLeaveBalances();
  const [showPersonalBalances, setShowPersonalBalances] = useState(false);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useUrlState('status', 'all');
  // تبويب التصنيف مرتبط بالعنوان — يبقى بعد التحديث والمشاركة.
  const [typeTab, setTypeTab] = useUrlState('type', 'all');
  const [selected, setSelected] = useState<RequestSummary | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const requestParam = searchParams.get('request');
  // فتح طلب محدد من الرابط (?request={id}) — الصادر من إشعار أو /action/request.
  // تُحذف المعلمة بعد فتح الحوار حتى لا يُعاد فتحه عند كل تحديث.
  useEffect(() => {
    if (!requestParam) return;
    const match = (query.data ?? []).find((item) => item.id === requestParam);
    if (match) {
      setSelected(match);
      setSearchParams(
        (prev) => {
          const next = new URLSearchParams(prev);
          next.delete('request');
          return next;
        },
        { replace: true },
      );
    }
  }, [requestParam, query.data, setSearchParams]);
  const [comment, setComment] = useState('');
  // نطاق القائمة: بانتظاري / طلباتي / الكل — من أعلام الخادم (0646).
  const [scope, setScope] = useUrlState('scope', 'all');
  const detail = useRequestDetail(selected?.id ?? null);
  const bulkApprove = useBulkApprove();
  const [picked, setPicked] = useState<Set<string>>(() => new Set());
  const [bulkOpen, setBulkOpen] = useState(false);
  const [bulkComment, setBulkComment] = useState('');
  const canDecide =
    auth.access != null &&
    (hasPermission(auth.access, 'requests.request.approve') ||
      hasPermission(auth.access, 'requests.approve') ||
      hasPermission(auth.access, 'requests.decide') ||
      auth.access.roles.some((r) =>
        [
          'admin',
          'super-admin',
          'executive',
          'executive-director',
          'general-manager',
          'hr-manager',
          'hr-specialist',
          'hr-officer',
          'operations-manager',
        ].includes(r),
      ) ||
      auth.access.workspaces.includes('main_admin'));
  // قرار هذا الطلب تحديدًا: علم الخادم أولًا (لا يبتّ أحد في طلبه، وكل مرحلة لأصحابها)،
  // ثم الصلاحية العامة مع خادم أقدم لا يرسل العلم.
  const canDecideOn = (item: RequestSummary) => item.status === 'pending' && !item.isMine && (item.canDecide ?? canDecide);
  const assignments = useWorkAssignments('team');
  // تصحيحات الحضور
  const correctionsQuery = useAttendanceOperations(currentMonth);
  const correctionsCommands = useAttendanceOperationsCommands();
  const [reviewNotes, setReviewNotes] = useState<Record<string, string>>({});
  // مراجع ثابتة: `?? []` ينشئ مصفوفة جديدة في كل رسم فيُعاد حساب المقاييس كل مرة.
  const corrections = useMemo<AttendanceOperationsCatalog['corrections']>(() => correctionsQuery.data?.corrections ?? [], [correctionsQuery.data]);

  const allRequests = useMemo(() => query.data ?? [], [query.data]);
  const metrics = useMemo(() => {
    const total = allRequests.length;
    const pendingRequests = allRequests.filter((r) => r.status === 'pending').length;
    const pendingCorrections = corrections.filter((c) => c.status === 'pending').length;
    const totalPending = pendingRequests + pendingCorrections;
    const approved = allRequests.filter((r) => r.status === 'approved').length;
    const rejected = allRequests.filter((r) => r.status === 'rejected').length;
    const cancelled = allRequests.filter((r) => r.status === 'cancelled').length;

    const leaves = allRequests.filter((r) => r.requestType === 'leave').length;
    const missions = allRequests.filter((r) => r.requestType === 'mission').length;
    const convoys = allRequests.filter((r) => r.requestType === 'convoy').length;
    const fundraising = allRequests.filter((r) => r.requestType === 'fundraising').length;
    const permits = allRequests.filter((r) => r.requestType === 'late_permit' || r.requestType === 'early_permit').length;
    const shiftChanges = allRequests.filter((r) => r.requestType === 'shift_change').length;

    return {
      total,
      totalPending,
      pendingRequests,
      pendingCorrections,
      approved,
      rejected,
      cancelled,
      leaves,
      missions,
      convoys,
      fundraising,
      permits,
      shiftChanges,
      approvalRate: total > 0 ? Math.round((approved / total) * 100) : 0,
    };
  }, [allRequests, corrections]);

  const scopeCounts = useMemo(
    () => ({
      awaiting: allRequests.filter(isAwaitingMe).length,
      mine: allRequests.filter((r) => r.isMine).length,
    }),
    [allRequests],
  );

  const filtered = useMemo(
    () =>
      (query.data ?? [])
        .filter((item) => {
          const haystack = `${item.employeeName} ${item.employeeCode ?? ''} ${item.title ?? ''} ${item.requestNumber}`.toLowerCase();
          return (
            haystack.includes(search.toLowerCase()) &&
            (status === 'all' || item.status === status) &&
            (scope === 'all' || (scope === 'awaiting' ? isAwaitingMe(item) : item.isMine === true)) &&
            (typeTab === 'all' ||
              typeTab === 'corrections' ||
              // تبويب «أذونات الحضور» يجمع نوعين (يطابق عدّاده metrics.permits) —
              // كانت المقارنة الحرفية بـ 'attendance_permit' تُفرغ القائمة رغم العدّاد.
              (typeTab === 'attendance_permit' ? item.requestType === 'late_permit' || item.requestType === 'early_permit' : item.requestType === typeTab))
          );
        })
        // الأحدث أولًا (قاعدة المالك لكل قائمة) — الاستعجال شارة «بانتظارك» لا ترتيب.
        .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()),
    [query.data, search, status, typeTab, scope],
  );

  // التحديد للاعتماد الجماعي: ما بانتظاري فقط، ويُنظَّف عند تغيّر القائمة.
  const pickable = useMemo(() => filtered.filter(isAwaitingMe), [filtered]);
  useEffect(() => {
    setPicked((prev) => {
      const allowed = new Set(pickable.map((r) => r.id));
      const next = new Set([...prev].filter((id) => allowed.has(id)));
      return next.size === prev.size ? prev : next;
    });
  }, [pickable]);
  const togglePick = (id: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const submitBulk = async () => {
    const ids = [...picked];
    if (ids.length === 0) return;
    const result = await bulkApprove.mutateAsync({ requestIds: ids, comment: bulkComment.trim() });
    setBulkOpen(false);
    setBulkComment('');
    setPicked(new Set());
    toast(
      result.failed.length === 0
        ? { message: `اعتُمد ${result.approved} من الطلبات`, tone: 'success' }
        : { message: `اعتُمد ${result.approved}، وتعذّر ${result.failed.length} (قد يكون غيّر حالته أحد غيرك)`, tone: 'error' },
    );
  };

  const submitDecision = async (kind: Decision) => {
    if (!selected) return;
    if (kind !== 'approve' && comment.trim().length < 3) return;
    try {
      await decision.mutateAsync({ requestId: selected.id, decision: kind, comment: comment.trim() });
      setSelected(null);
      setComment('');
      toast({
        message: kind === 'approve' ? 'تم اعتماد الطلب بنجاح' : kind === 'return' ? 'أُعيد الطلب لصاحبه للتعديل' : 'تم رفض الطلب',
        tone: 'success',
      });
    } catch {
      /* decision.isError displayed in dialog via ErrorBanner */
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="المنصة الموحدة"
        title="طلبات الموظفين"
        description="لوحة مركزية شاملة لمتابعة واعتماد طلبات الموظفين (إجازات، مأموريات، قوافل، فاندي، أذونات، وتصحيحات الحضور) عبر المنظومة."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => setShowPersonalBalances(true)}
              className="flex h-9 items-center gap-1.5 rounded-lg border border-[var(--border)] px-3 text-xs font-bold transition-colors hover:bg-[var(--surface-raised)]"
              title="عرض رصيد إجازاتي الشخصي كـ موظف"
            >
              <CalendarDays className="size-4 text-brand" />
              <span>رصيدي الشخصي</span>
            </button>
            <button
              type="button"
              onClick={() => {
                void query.refetch();
                void correctionsQuery.refetch();
              }}
              className="flex h-9 items-center gap-1.5 rounded-lg border border-[var(--border)] px-3 text-xs font-bold transition-colors hover:bg-[var(--surface-raised)]"
              title="تحديث البيانات"
            >
              <RefreshCw className="size-3.5" />
              <span className="hidden sm:inline">تحديث</span>
            </button>
          </div>
        }
      />
      {query.isLoading && !query.data ? (
        <MetricSkeletonRow />
      ) : (
        <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <MetricCard
            label="إجمالي الطلبات بالمنظومة"
            value={metrics.total}
            hint={`${metrics.leaves} إجازة · ${metrics.missions} مأمورية · ${metrics.permits} إذن`}
            icon={Inbox}
            compact={true}
            onClick={() => {
              setStatus('all');
              setTypeTab('all');
            }}
          />
          <MetricCard
            label="بانتظار الاعتماد"
            value={metrics.totalPending}
            hint={
              metrics.pendingCorrections > 0 ? `${metrics.pendingRequests} طلبات + ${metrics.pendingCorrections} تصحيح معلق` : 'طلبات معلقة تتطلب اتخاذ قرار'
            }
            icon={Clock3}
            compact={true}
            onClick={() => {
              setStatus('pending');
            }}
          />
          <MetricCard
            label="طلبات معتمدة"
            value={metrics.approved}
            hint={metrics.total > 0 ? `نسبة الاعتماد ${metrics.approvalRate}% من إجمالي الطلبات` : 'تمت الموافقة عليها'}
            icon={CheckCircle2}
            compact={true}
            onClick={() => {
              setStatus('approved');
            }}
          />
          <MetricCard
            label="مرفوضة أو ملغية"
            value={metrics.rejected + metrics.cancelled}
            hint={`${metrics.rejected} مرفوضة · ${metrics.cancelled} ملغية`}
            icon={FileX}
            compact={true}
            onClick={() => {
              setStatus('rejected');
            }}
          />
        </section>
      )}
      <nav className="flex flex-wrap gap-2" aria-label="تصنيف الطلبات">
        {[
          { key: 'all' as const, label: 'الكل', count: metrics.total },
          { key: 'leave' as const, label: 'الإجازات', count: metrics.leaves },
          { key: 'mission' as const, label: 'المأموريات', count: metrics.missions },
          { key: 'convoy' as const, label: 'القوافل', count: metrics.convoys },
          { key: 'fundraising' as const, label: 'الفاندي', count: metrics.fundraising },
          { key: 'attendance_permit' as const, label: 'أذونات الحضور', count: metrics.permits },
          { key: 'shift_change' as const, label: 'فترات العمل', count: metrics.shiftChanges },
          { key: 'corrections' as const, label: 'تصحيحات الحضور', count: corrections.length },
        ].map((tab) => (
          <button
            key={tab.key}
            type="button"
            aria-pressed={typeTab === tab.key}
            className={`rounded-xl px-4 py-2 text-sm font-black transition-colors flex items-center gap-2 ${
              typeTab === tab.key ? 'bg-brand text-white shadow-sm' : 'bg-[var(--surface-muted)] text-[var(--text-secondary)] hover:bg-[var(--surface-raised)]'
            }`}
            onClick={() => setTypeTab(tab.key)}
          >
            <span>{tab.label}</span>
            {typeof tab.count === 'number' && tab.count > 0 ? (
              <span
                className={`rounded-full px-2 py-0.5 text-xs font-bold ${
                  typeTab === tab.key ? 'bg-white/20 text-white' : 'bg-[var(--surface-raised)] text-[var(--text-muted)]'
                }`}
              >
                {tab.count}
              </span>
            ) : null}
          </button>
        ))}
      </nav>

      {/* ─── تصحيحات الحضور ─── */}
      {typeTab === 'corrections' ? (
        <section className="card p-5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="flex items-center gap-2 text-lg font-black">
              <RotateCcw className="size-5 text-brand" aria-hidden="true" />
              تصحيحات الحضور
            </h2>
            <span className="muted text-sm">الموافقة تعدّل سجل اليوم خادميًا، والرفض يحتاج سببًا.</span>
          </div>
          {correctionsCommands.decideCorrection.isError ? <ErrorBanner message={safeErrorMessage(correctionsCommands.decideCorrection.error)} /> : null}
          {correctionsQuery.isError ? (
            <ErrorState description={safeErrorMessage(correctionsQuery.error)} onRetry={() => void correctionsQuery.refetch()} />
          ) : correctionsQuery.isLoading ? (
            <ListSkeleton rows={3} />
          ) : corrections.length === 0 ? (
            <EmptyState title="لا توجد تصحيحات" description="لا توجد طلبات تصحيح في الشهر الحالي." />
          ) : (
            <div className="mt-4 space-y-3">
              {corrections.map((item) => (
                <article key={item.id} className="rounded-2xl border border-[var(--border)] p-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <UserAvatar displayName={item.employeeName} size="sm" />
                      <strong>{item.employeeName}</strong>
                      <p className="muted text-sm">
                        {item.workDate} · {item.type} · {item.reason}
                      </p>
                    </div>
                    <StatusBadge value={item.status} />
                  </div>
                  {item.status === 'pending' ? (
                    <div className="mt-3 grid gap-2 md:grid-cols-[1fr_auto_auto]">
                      <input
                        className="input"
                        placeholder="ملاحظة القرار"
                        value={reviewNotes[item.id] ?? ''}
                        onChange={(e) => setReviewNotes((v) => ({ ...v, [item.id]: e.target.value }))}
                      />
                      <button
                        className="btn-primary"
                        onClick={() =>
                          correctionsCommands.decideCorrection.mutate(
                            { p_id: item.id, p_decision: 'approved', p_note: reviewNotes[item.id] || null },
                            {
                              onSuccess: () => toast({ message: 'تم اعتماد التصحيح بنجاح', tone: 'success' }),
                              onError: () => toast({ message: 'تعذر اعتماد التصحيح', tone: 'error' }),
                            },
                          )
                        }
                      >
                        اعتماد
                      </button>
                      <button
                        className="btn-secondary"
                        onClick={() =>
                          correctionsCommands.decideCorrection.mutate(
                            { p_id: item.id, p_decision: 'rejected', p_note: reviewNotes[item.id] || '' },
                            {
                              onSuccess: () => toast({ message: 'تم رفض التصحيح', tone: 'success' }),
                              onError: () => toast({ message: 'تعذر رفض التصحيح', tone: 'error' }),
                            },
                          )
                        }
                      >
                        رفض
                      </button>
                    </div>
                  ) : null}
                </article>
              ))}
            </div>
          )}
        </section>
      ) : (
        <>
          {/* ─── نطاق القائمة: بانتظاري / طلباتي / الكل ─── */}
          <div className="flex flex-wrap items-center gap-2" role="group" aria-label="نطاق الطلبات">
            {[
              { key: 'all', label: 'كل الطلبات', count: null as number | null },
              { key: 'awaiting', label: 'بانتظار قراري', count: scopeCounts.awaiting },
              { key: 'mine', label: 'طلباتي', count: scopeCounts.mine },
            ].map((tab) => (
              <button
                key={tab.key}
                type="button"
                aria-pressed={scope === tab.key}
                onClick={() => setScope(tab.key)}
                className={`flex items-center gap-2 rounded-full border px-4 py-1.5 text-sm font-bold transition-colors ${
                  scope === tab.key ? 'border-brand bg-brand/10 text-brand' : 'border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-raised)]'
                }`}
              >
                <span>{tab.label}</span>
                {tab.count ? (
                  <span className={`rounded-full px-2 py-0.5 text-xs ${tab.key === 'awaiting' ? 'bg-[var(--warning)] text-white' : 'bg-[var(--surface-muted)]'}`}>
                    {tab.count}
                  </span>
                ) : null}
              </button>
            ))}
            {pickable.length > 1 ? (
              <button
                type="button"
                className="ms-auto inline-flex items-center gap-1.5 rounded-lg border border-[var(--border)] px-3 py-1.5 text-xs font-bold hover:bg-[var(--surface-raised)]"
                onClick={() => setPicked(picked.size === pickable.length ? new Set() : new Set(pickable.map((r) => r.id)))}
              >
                <ListChecks className="size-4 text-brand" aria-hidden="true" />
                {picked.size === pickable.length ? 'إلغاء التحديد' : `تحديد كل ما بانتظاري (${pickable.length})`}
              </button>
            ) : null}
          </div>
          {picked.size > 0 ? (
            <div className="sticky top-2 z-10 flex flex-wrap items-center gap-3 rounded-2xl border border-[var(--success)]/40 bg-[var(--surface-raised)] px-4 py-3 shadow-sm">
              <strong className="text-sm">حددت {picked.size} للاعتماد</strong>
              <button type="button" className="btn-secondary text-xs" onClick={() => setPicked(new Set())}>
                إلغاء
              </button>
              <button
                type="button"
                className="ms-auto inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-black text-white"
                style={{ background: 'var(--success)' }}
                onClick={() => setBulkOpen(true)}
              >
                <Check className="size-4" aria-hidden="true" />
                اعتماد المحدد
              </button>
            </div>
          ) : null}
          {/* ─── قائمة الطلبات العادية ─── */}
          <FilterBar
            searchValue={search}
            onSearchChange={setSearch}
            searchPlaceholder="بحث بالاسم أو الكود أو رقم الطلب"
            resultText={`عرض ${filtered.length} من ${(query.data ?? []).length} طلب`}
            isDirty={Boolean(search || status !== 'all')}
            onClear={() => {
              setSearch('');
              setStatus('all');
            }}
          >
            <select className="input" aria-label="تصفية الطلبات حسب الحالة" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="all">كل الحالات</option>
              <option value="pending">قيد المراجعة</option>
              <option value="approved">معتمد</option>
              <option value="rejected">مرفوض</option>
              <option value="cancelled">ملغي</option>
            </select>
          </FilterBar>
          {query.isError ? (
            <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
          ) : query.isLoading && !query.data ? (
            <ListSkeleton rows={4} />
          ) : filtered.length === 0 ? (
            <EmptyState title="لا توجد طلبات" description="لا توجد عناصر مطابقة للفلاتر الحالية." />
          ) : (
            <section className="grid gap-4 xl:grid-cols-2">
              {filtered.map((item) => (
                <article
                  key={item.id}
                  className={`card flex flex-col gap-3 p-5 ${picked.has(item.id) ? 'ring-2 ring-[var(--success)]' : ''}`}
                >
                  {/* صف علوي: النوع + رقم الطلب + الحالة */}
                  <div className="flex flex-wrap items-center gap-2">
                    {isAwaitingMe(item) ? (
                      <input
                        type="checkbox"
                        className="size-4 accent-[var(--success)]"
                        aria-label={`تحديد الطلب #${item.requestNumber} للاعتماد الجماعي`}
                        checked={picked.has(item.id)}
                        onChange={() => togglePick(item.id)}
                      />
                    ) : null}
                    <span className="rounded-lg bg-brand/10 px-2.5 py-1 text-xs font-black text-brand">{labels[item.requestType]}</span>
                    <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-xs font-black">#{item.requestNumber}</span>
                    <StatusBadge value={item.status} />
                    {isAwaitingMe(item) ? (
                      <span className="rounded-lg bg-[var(--warning)]/15 px-2 py-1 text-xs font-black text-[var(--warning)]">بانتظارك</span>
                    ) : item.isMine ? (
                      <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-xs font-bold">طلبي</span>
                    ) : null}
                  </div>

                  {/* العنوان */}
                  <h2 className="text-base font-black leading-snug break-words line-clamp-2" title={item.title || labels[item.requestType]}>
                    {item.title || labels[item.requestType]}
                  </h2>

                  {/* الموظف */}
                  <div className="flex items-center gap-2">
                    <UserAvatar displayName={item.employeeName} size="sm" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-bold">{item.employeeName}</p>
                      <p className="muted truncate text-xs">
                        {[item.employeeJobTitle, item.employeeDepartment, !isPhoneLikeCode(item.employeeCode) ? `كود: ${item.employeeCode}` : null]
                          .filter(Boolean)
                          .join(' · ')}
                      </p>
                    </div>
                  </div>

                  {/* السبب */}
                  <p className="line-clamp-2 text-sm leading-relaxed text-[var(--text-muted)] break-words">{item.reason || 'لم يضف الموظف سببًا تفصيليًا.'}</p>

                  {/* التكليف: المكان + الوقت المخطط + حالة التنفيذ */}
                  {item.requestType === 'mission' || item.requestType === 'convoy' || item.requestType === 'fundraising' ? (
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-2xl bg-[var(--surface-muted)] px-3 py-2 text-sm">
                      {typeof item.payload?.startDate === 'string' || typeof item.payload?.endDate === 'string' ? (
                        <span className="inline-flex items-center gap-1.5 font-bold">
                          <CalendarDays className="size-3.5 text-brand" aria-hidden="true" />
                          {formatPeriodLabel(item.payload.startDate, item.payload.endDate)}
                        </span>
                      ) : null}
                      {typeof item.payload?.location === 'string' ? (
                        <span className="inline-flex items-center gap-1.5 font-bold">
                          <MapPin className="size-3.5 text-brand" aria-hidden="true" />
                          {item.payload.location}
                        </span>
                      ) : null}
                      {typeof item.payload?.startTime === 'string' || typeof item.payload?.endTime === 'string' ? (
                        <span className="muted inline-flex items-center gap-1.5">
                          <Clock className="size-3.5" aria-hidden="true" />
                          {typeof item.payload?.startTime === 'string' ? item.payload.startTime : '?'}
                          {' — '}
                          {typeof item.payload?.endTime === 'string' ? item.payload.endTime : '?'}
                        </span>
                      ) : null}
                      {item.missionExecution?.status && item.missionExecution.status !== 'not_started' ? (
                        <span
                          className={`ms-auto rounded-lg px-2 py-1 text-xs font-black ${
                            item.missionExecution.status === 'completed'
                              ? 'bg-[var(--success)]/15 text-[var(--success)]'
                              : 'bg-[var(--warning)]/15 text-[var(--warning)]'
                          }`}
                        >
                          {MISSION_EXECUTION_STATUS_LABELS[item.missionExecution.status]}
                        </span>
                      ) : null}
                    </div>
                  ) : null}
                  {/* تغيير فترة العمل: الوردية المطلوبة وتاريخ السريان */}
                  {item.requestType === 'shift_change' && typeof item.payload?.shiftName === 'string' ? (
                    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-2xl bg-brand/5 border border-brand/20 px-3 py-2 text-sm">
                      <span className="inline-flex items-center gap-1.5 font-bold text-brand">
                        <Clock3 className="size-4 text-brand" aria-hidden="true" />
                        الوردية المطلوبة: {item.payload.shiftName}
                      </span>
                      {typeof item.payload?.effectiveFrom === 'string' ? (
                        <span className="muted inline-flex items-center gap-1.5 text-xs">
                          <CalendarDays className="size-3.5" aria-hidden="true" />
                          سريان من: {new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium' }).format(new Date(item.payload.effectiveFrom))}
                        </span>
                      ) : null}
                    </div>
                  ) : null}

                  {/* تذييل: المرحلة + الوقت + زر الإجراء */}
                  <div className="mt-auto flex flex-wrap items-center gap-x-3 gap-y-2 border-t border-[var(--border)] pt-3 text-xs">
                    {item.status === 'pending' ? (
                      <TierBadge workflowStatus={item.workflowStatus} activeStepName={item.activeStepName} />
                    ) : (
                      <span className="inline-flex items-center gap-1.5 muted">
                        <Clock className="size-3.5" aria-hidden="true" />
                        {item.activeStepName || 'اكتمل المسار'}
                      </span>
                    )}
                    {item.status === 'pending' && item.decisionDueAt ? <EscalationCountdown dueAt={item.decisionDueAt} /> : null}
                    <span className="muted">
                      {new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.createdAt))}
                    </span>
                    {canDecideOn(item) ? (
                      <button className="btn-primary ms-auto text-xs" onClick={() => setSelected(item)}>
                        مراجعة واتخاذ إجراء
                      </button>
                    ) : (
                      <button className="btn-secondary ms-auto text-xs" onClick={() => setSelected(item)}>
                        التفاصيل والمسار
                      </button>
                    )}
                  </div>
                </article>
              ))}
            </section>
          )}
          <section aria-labelledby="wa-heading" className="space-y-3">
            <h2 id="wa-heading" className="flex items-center gap-2 text-lg font-black">
              <Truck className="size-5 text-brand" aria-hidden="true" />
              تكليفات العمل (مأمورية / قافلة / فاندي)
            </h2>
            <p className="muted text-sm">تكليفات عمل رسمية لا تُخصم من رصيد الإجازات ولا تُحتسب غيابًا.</p>
            {(assignments.data ?? []).length === 0 ? (
              <EmptyState title="لا توجد تكليفات" description="لم تُنشأ تكليفات عمل بعد." />
            ) : (
              <div className="grid gap-4 xl:grid-cols-2">
                {(assignments.data ?? []).map((asg) => (
                  <article key={asg.id} className="card p-5">
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-xs font-black">#{asg.assignmentNumber}</span>
                          <StatusBadge value={asg.status} />
                        </div>
                        <h3 className="mt-3 text-lg font-black">{asg.title}</h3>
                        <p className="muted mt-1 text-sm">{asg.location || 'بدون مكان محدد'}</p>
                      </div>
                      <span className="text-sm font-bold text-brand">{assignmentLabels[asg.assignmentType]}</span>
                    </div>
                    {asg.assignmentType === 'FUNDRAISING' && asg.targetAmount != null ? (
                      <p className="mt-3 text-sm">
                        المستهدف المالي: <strong>{asg.targetAmount.toLocaleString('ar-EG')}</strong>
                      </p>
                    ) : null}
                    <div className="mt-4 flex flex-wrap items-center gap-3 border-t border-[var(--border)] pt-4 text-xs">
                      <span className="muted">
                        {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: asg.isFullDay ? undefined : 'short' }).format(
                          new Date(asg.startAt),
                        )}
                      </span>
                      {!asg.isFullDay ? <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 font-bold">بالساعات</span> : null}
                    </div>
                  </article>
                ))}
              </div>
            )}
          </section>
        </>
      )}
      {selected ? (
        <DialogOverlay
          title={`طلب #${selected.requestNumber} — ${selected.title || labels[selected.requestType]}`}
          onClose={() => setSelected(null)}
          maxWidth="max-w-xl"
        >
          <div className="flex flex-wrap items-center gap-3 mb-5">
            <UserAvatar displayName={selected.employeeName} size="sm" />
            <p className="muted text-sm flex-1">{selected.employeeName}</p>
            {selected.status === 'pending' ? <TierBadge workflowStatus={selected.workflowStatus} activeStepName={selected.activeStepName} /> : null}
            {selected.status === 'pending' && selected.decisionDueAt ? <EscalationCountdown dueAt={selected.decisionDueAt} /> : null}
          </div>
          <p id="decision-reason" className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm leading-7">
            {selected.reason || 'لا يوجد سبب تفصيلي.'}
          </p>
          {(selected.requestType === 'mission' || selected.requestType === 'convoy' || selected.requestType === 'fundraising') && selected.missionExecution ? (
            <div className="mt-4 space-y-2 rounded-2xl border border-[var(--border)] p-4 text-sm">
              <p className="flex flex-wrap items-center gap-2">
                <strong>سجل التنفيذ:</strong>
                <span
                  className={`rounded-lg px-2 py-0.5 text-xs font-black ${
                    selected.missionExecution.status === 'completed'
                      ? 'bg-[var(--success)]/15 text-[var(--success)]'
                      : selected.missionExecution.status === 'in_progress'
                        ? 'bg-[var(--warning)]/15 text-[var(--warning)]'
                        : 'bg-[var(--surface-muted)]'
                  }`}
                >
                  {MISSION_EXECUTION_STATUS_LABELS[selected.missionExecution.status]}
                </span>
              </p>
              {selected.missionExecution.startedAt ? (
                <p className="muted">
                  بدأت: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(selected.missionExecution.startedAt))}
                </p>
              ) : null}
              {selected.missionExecution.endedAt ? (
                <p className="muted">
                  انتهت: {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(selected.missionExecution.endedAt))}
                </p>
              ) : null}
              {selected.missionExecution.actualMinutes != null ? <p className="muted">المدة الفعلية: {selected.missionExecution.actualMinutes} دقيقة</p> : null}
              {selected.missionExecution.report ? (
                <p className="leading-7">
                  <strong>التقرير:</strong> {selected.missionExecution.report}
                </p>
              ) : null}
            </div>
          ) : null}
          {selected.requestType === 'shift_change' && typeof selected.payload?.shiftName === 'string' ? (
            <div className="mt-4 rounded-2xl border border-brand/20 bg-brand/5 p-4 text-sm space-y-2">
              <div className="flex items-center gap-2">
                <Clock3 className="size-4 text-brand" aria-hidden="true" />
                <strong className="text-brand">تفاصيل الوردية وفترة العمل المطلوبة:</strong>
              </div>
              <div className="grid gap-2 sm:grid-cols-2 pt-1 text-xs">
                <div className="rounded-xl bg-[var(--surface-raised)] p-3 border border-[var(--border)]">
                  <span className="muted block">الوردية المطلوبة:</span>
                  <strong className="text-sm text-[var(--text-primary)]">{selected.payload.shiftName}</strong>
                </div>
                {typeof selected.payload?.effectiveFrom === 'string' ? (
                  <div className="rounded-xl bg-[var(--surface-raised)] p-3 border border-[var(--border)]">
                    <span className="muted block">تاريخ السريان المخطط:</span>
                    <strong className="text-sm text-[var(--text-primary)]">
                      {new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium' }).format(new Date(selected.payload.effectiveFrom))}
                    </strong>
                  </div>
                ) : null}
              </div>
              <p className="muted text-xs pt-1">
                * بمجرد الاعتماد، يتم تحديث فترة عمل الموظف الأساسية في النظام وتفعيل احتساب الحضور والتأخير على هذه الوردية تلقائياً.
              </p>
            </div>
          ) : null}
          {/* سياق القرار ومسار الطلب (0646/0651) */}
          {canDecideOn(selected) ? <DecisionInsights insights={detail.data?.insights} /> : null}
          {detail.isLoading ? <p className="muted mt-4 text-xs">جارٍ تحميل مسار الطلب…</p> : null}
          {detail.data ? <RequestJourney history={detail.data.history} employeeName={selected.employeeName} /> : null}
          {selected.status === 'pending' ? (
            canDecideOn(selected) && (detail.data?.canDecide ?? true) ? (
              <>
                <label className="mt-5 block text-sm font-bold">
                  ملاحظة القرار
                  <textarea
                    className="input mt-2 min-h-28 resize-y"
                    value={comment}
                    onChange={(e) => setComment(e.target.value)}
                    placeholder="الرفض والإعادة للتعديل يتطلبان سببًا واضحًا، والموافقة يمكن أن تتضمن ملاحظة."
                  />
                </label>
                <p id="reject-hint" className="muted mt-2 text-xs">
                  الرفض والإعادة للتعديل يتطلبان سببًا لا يقل عن ٣ أحرف. الإعادة ترجع الطلب لصاحبه ليعدّله ويعيد رفعه.
                </p>
                {decision.isError ? (
                  <div className="mt-3">
                    <ErrorBanner message={safeErrorMessage(decision.error)} />
                  </div>
                ) : null}
                <div className="mt-5 grid gap-3 sm:grid-cols-3">
                  <button
                    className="inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3 font-black text-white disabled:opacity-50"
                    style={{ background: 'var(--success)' }}
                    disabled={decision.isPending}
                    onClick={() => void submitDecision('approve')}
                  >
                    <Check className="size-5" aria-hidden="true" />
                    اعتماد
                  </button>
                  <button
                    className="inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3 font-black text-white disabled:opacity-50"
                    style={{ background: '#C2410C' }}
                    aria-describedby="reject-hint"
                    disabled={decision.isPending || comment.trim().length < 3}
                    onClick={() => void submitDecision('return')}
                  >
                    <CornerUpLeft className="size-5" aria-hidden="true" />
                    إعادة للتعديل
                  </button>
                  <button
                    className="inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3 font-black text-white disabled:opacity-50"
                    style={{ background: 'var(--danger)' }}
                    aria-describedby="reject-hint"
                    disabled={decision.isPending || comment.trim().length < 3}
                    onClick={() => void submitDecision('reject')}
                  >
                    <X className="size-5" aria-hidden="true" />
                    رفض مع السبب
                  </button>
                </div>
              </>
            ) : (
              <div className="mt-5 text-center p-3 rounded-xl bg-[var(--surface-muted)] text-sm muted">
                {selected.isMine
                  ? 'هذا طلبك — يبتّ فيه المعتمِد في مرحلته.'
                  : `القرار في هذه المرحلة${selected.activeStepName ? ` (${selected.activeStepName})` : ''} لغيرك.`}
              </div>
            )
          ) : (
            <div className="mt-5 text-center p-3 rounded-xl bg-[var(--surface-muted)] text-sm font-bold">
              حالة الطلب: {REQUEST_STATUS_LABELS[selected.status] ?? selected.status}
            </div>
          )}
        </DialogOverlay>
      ) : null}

      {bulkOpen ? (
        <DialogOverlay title={`اعتماد ${picked.size} من الطلبات`} onClose={() => setBulkOpen(false)} maxWidth="max-w-lg">
          <p className="muted text-sm leading-7">
            يُعتمد كل طلب على حدة في مرحلته الحالية؛ ما غيّر حالته غيرك في الأثناء يُترك كما هو ويُذكر لك. الرفض والإعادة للتعديل من صفحة كل طلب.
          </p>
          <ul className="mt-3 max-h-56 space-y-1 overflow-y-auto text-sm">
            {filtered
              .filter((r) => picked.has(r.id))
              .map((r) => (
                <li key={r.id} className="flex items-center gap-2">
                  <span className="rounded bg-brand/10 px-1.5 text-xs font-bold text-brand">{labels[r.requestType]}</span>
                  <span className="truncate">{r.employeeName}</span>
                  <span className="muted text-xs">#{r.requestNumber}</span>
                </li>
              ))}
          </ul>
          <label className="mt-4 block text-sm font-bold">
            ملاحظة للجميع (اختياري)
            <input className="input mt-2" value={bulkComment} onChange={(e) => setBulkComment(e.target.value)} />
          </label>
          {bulkApprove.isError ? (
            <div className="mt-3">
              <ErrorBanner message={safeErrorMessage(bulkApprove.error)} />
            </div>
          ) : null}
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" className="btn-secondary" onClick={() => setBulkOpen(false)}>
              تراجع
            </button>
            <button
              type="button"
              className="inline-flex items-center gap-2 rounded-xl px-4 py-2 font-black text-white disabled:opacity-50"
              style={{ background: 'var(--success)' }}
              disabled={bulkApprove.isPending}
              onClick={() => void submitBulk()}
            >
              <Check className="size-4" aria-hidden="true" />
              {bulkApprove.isPending ? 'جارٍ الاعتماد…' : 'اعتماد الكل'}
            </button>
          </div>
        </DialogOverlay>
      ) : null}

      {showPersonalBalances ? (
        <DialogOverlay onClose={() => setShowPersonalBalances(false)} title="أرصدة إجازاتي الشخصية">
          <div className="space-y-4">
            <p className="muted text-sm">
              أرصدة الإجازات السنوية والعارضة وبدل الراحة الخاصة بحساب الموظف:{' '}
              <strong className="text-[var(--text-primary)]">{auth.access?.displayName}</strong>
            </p>
            {balances.isLoading && !balances.data ? (
              <ListSkeleton rows={3} />
            ) : (balances.data ?? []).length === 0 ? (
              <EmptyState title="لا توجد أرصدة مسجلة" description="لم يتم العثور على سجل رصيد إجازات لهذا الحساب." />
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {(balances.data ?? []).map((balance) => (
                  <div key={balance.leaveTypeId} className="rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-4 shadow-sm">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-bold">{balance.nameAr}</span>
                      <span className="text-2xl font-black text-brand">{balance.availableUnits}</span>
                    </div>
                    <div className="mt-2 flex items-center justify-between border-t border-[var(--border)] pt-2 text-xs text-[var(--text-muted)]">
                      <span>المحجوز: {balance.reservedUnits}</span>
                      <span>المستهلك: {balance.consumedUnits}</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
            <div className="flex justify-end pt-2">
              <button type="button" className="btn-secondary" onClick={() => setShowPersonalBalances(false)}>
                إغلاق
              </button>
            </div>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}
