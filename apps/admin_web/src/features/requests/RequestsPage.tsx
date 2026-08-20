import { MISSION_EXECUTION_STATUS_LABELS, type RequestSummary, type WorkAssignment } from '@ahla/shared-contracts';
import { CalendarDays, Check, Clock, MapPin, RotateCcw, Truck, X } from 'lucide-react';
import { useMemo, useState } from 'react';
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
import { useMyLeaveBalances, useRequestDecision, useRequests, useWorkAssignments } from './useRequests';
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
};

/// تنسيق فترة الطلب من startDate/endDate (YYYY-MM-DD) بالعربية — يعرض
/// التاريخ الواحد إذا لم تُحدد نهاية.
function formatPeriodLabel(startDate: unknown, endDate: unknown): string {
  const fmt = new Intl.DateTimeFormat('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' });
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
type TypeTab = 'all' | 'leave' | 'mission' | 'convoy' | 'fundraising' | 'attendance_permit' | 'corrections';
const typeTabs: { key: TypeTab; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'leave', label: 'الإجازات' },
  { key: 'mission', label: 'المأموريات' },
  { key: 'convoy', label: 'القوافل' },
  { key: 'fundraising', label: 'الفاندي' },
  { key: 'attendance_permit', label: 'أذونات الحضور' },
  { key: 'corrections', label: 'تصحيحات الحضور' },
];

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
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [typeTab, setTypeTab] = useState<TypeTab>('all');
  const [selected, setSelected] = useState<RequestSummary | null>(null);
  const [comment, setComment] = useState('');
  const canDecide =
    auth.access != null &&
    (hasPermission(auth.access, 'requests.request.approve') || hasPermission(auth.access, 'requests.approve') || auth.access.workspaces.includes('main_admin'));
  const assignments = useWorkAssignments('team');
  // تصحيحات الحضور
  const correctionsQuery = useAttendanceOperations(currentMonth);
  const correctionsCommands = useAttendanceOperationsCommands();
  const [reviewNotes, setReviewNotes] = useState<Record<string, string>>({});
  const corrections = correctionsQuery.data?.corrections ?? [];

  const filtered = useMemo(
    () =>
      (query.data ?? []).filter((item) => {
        const haystack = `${item.employeeName} ${item.employeeCode ?? ''} ${item.title ?? ''} ${item.requestNumber}`.toLowerCase();
        return (
          haystack.includes(search.toLowerCase()) &&
          (status === 'all' || item.status === status) &&
          (typeTab === 'all' || typeTab === 'corrections' || item.requestType === typeTab)
        );
      }),
    [query.data, search, status, typeTab],
  );

  const submitDecision = async (kind: 'approve' | 'reject') => {
    if (!selected) return;
    if (kind === 'reject' && comment.trim().length < 3) return;
    try {
      await decision.mutateAsync({ requestId: selected.id, decision: kind, comment: comment.trim() });
      setSelected(null);
      setComment('');
      toast({ message: kind === 'approve' ? 'تم اعتماد الطلب بنجاح' : 'تم رفض الطلب', tone: 'success' });
    } catch {
      /* decision.isError displayed in dialog via ErrorBanner */
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="طلب إجازة" description="صندوق موحد للإجازات وتصحيحات الحضور والتكليفات (مأمورية، قافلة) والأذونات، مع مسار اعتماد واضح." />
      {balances.isLoading && !balances.data ? (
        <MetricSkeletonRow />
      ) : (
        <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {(balances.data ?? []).map((balance) => (
            <MetricCard
              key={balance.leaveTypeId}
              label={`رصيد ${balance.nameAr}`}
              value={balance.availableUnits}
              hint={`محجوز ${balance.reservedUnits} · مستهلك ${balance.consumedUnits}`}
              icon={CalendarDays}
            />
          ))}
        </section>
      )}
      <nav className="flex flex-wrap gap-2" aria-label="تصنيف الطلبات">
        {typeTabs.map((tab) => (
          <button
            key={tab.key}
            type="button"
            aria-pressed={typeTab === tab.key}
            className={`rounded-xl px-4 py-2 text-sm font-black ${typeTab === tab.key ? 'bg-brand text-white' : 'bg-[var(--surface-muted)]'}`}
            onClick={() => setTypeTab(tab.key)}
          >
            {tab.label}
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
                <article key={item.id} className="card flex flex-col gap-3 p-5">
                  {/* صف علوي: النوع + رقم الطلب + الحالة */}
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-lg bg-brand/10 px-2.5 py-1 text-xs font-black text-brand">{labels[item.requestType]}</span>
                    <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-xs font-black">#{item.requestNumber}</span>
                    <StatusBadge value={item.status} />
                  </div>

                  {/* العنوان */}
                  <h2 className="text-lg font-black leading-snug">{item.title || labels[item.requestType]}</h2>

                  {/* الموظف */}
                  <div className="flex items-center gap-2">
                    <UserAvatar displayName={item.employeeName} size="sm" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-bold">{item.employeeName}</p>
                      {!isPhoneLikeCode(item.employeeCode) ? <p className="muted truncate text-xs">كود: {item.employeeCode}</p> : null}
                    </div>
                  </div>

                  {/* السبب */}
                  <p className="line-clamp-2 text-sm leading-7 text-[var(--foreground)]/90">{item.reason || 'لم يضف الموظف سببًا تفصيليًا.'}</p>

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
                      {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.createdAt))}
                    </span>
                    {canDecide && item.status === 'pending' ? (
                      <button className="btn-primary ms-auto text-xs" onClick={() => setSelected(item)}>
                        مراجعة واتخاذ إجراء
                      </button>
                    ) : null}
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
          <label className="mt-5 block text-sm font-bold">
            ملاحظة القرار
            <textarea
              className="input mt-2 min-h-28 resize-y"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              placeholder="الرفض يتطلب سببًا واضحًا، والموافقة يمكن أن تتضمن ملاحظة."
            />
          </label>
          <p id="reject-hint" className="muted mt-2 text-xs">
            يتطلب الرفض إدخال سبب لا يقل عن ٣ أحرف.
          </p>
          {decision.isError ? (
            <div className="mt-3">
              <ErrorBanner message={safeErrorMessage(decision.error)} />
            </div>
          ) : null}
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
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
              style={{ background: 'var(--danger)' }}
              aria-describedby="reject-hint"
              disabled={decision.isPending || comment.trim().length < 3}
              onClick={() => void submitDecision('reject')}
            >
              <X className="size-5" aria-hidden="true" />
              رفض مع السبب
            </button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}
