import type { RequestSummary, WorkAssignment } from '@ahla/shared-contracts';
import { CalendarDays, Check, Clock, RotateCcw, Truck, X } from 'lucide-react';
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
  late_permit: 'إذن حضور',
  early_permit: 'إذن انصراف',
  attendance_correction: 'تصحيح حضور',
};
const assignmentLabels: Record<WorkAssignment['assignmentType'], string> = { MISSION: 'مأمورية', CONVOY: 'قافلة', FUNDRAISING: 'فاندي' };
type TypeTab = 'all' | 'leave' | 'mission' | 'convoy' | 'attendance_permit' | 'corrections';
const typeTabs: { key: TypeTab; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'leave', label: 'الإجازات' },
  { key: 'mission', label: 'المأموريات' },
  { key: 'convoy', label: 'القوافل' },
  { key: 'attendance_permit', label: 'أذونات الحضور' },
  { key: 'corrections', label: 'تصحيحات الحضور' },
];

const currentMonth = cairoMonthIso();

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
    hasPermission(auth.access!, 'requests.request.approve') ||
    hasPermission(auth.access!, 'requests.approve') ||
    auth.access!.workspaces.includes('main_admin');
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
      <PageHeader
        title="طلب اجازة"
        description="صندوق موحد للإجازات وتصحيحات الحضور وتكليفات العمل (مأمورية/قافلة/فاندي) والأذونات، يعمل بمراحل واعتمادات خادمية ومنع الموافقة الذاتية."
      />
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
                <article key={item.id} className="card p-5">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-1 text-xs font-black">#{item.requestNumber}</span>
                        <StatusBadge value={item.status} />
                      </div>
                      <h2 className="mt-3 text-lg font-black">{item.title || labels[item.requestType]}</h2>
                      <div className="mt-1 flex items-center gap-2">
                        <UserAvatar displayName={item.employeeName} size="sm" />
                        <p className="muted text-sm">
                          {item.employeeName} · {item.employeeCode || 'بدون كود'}
                        </p>
                      </div>
                    </div>
                    <span className="text-sm font-bold text-brand">{labels[item.requestType]}</span>
                  </div>
                  <p className="mt-4 line-clamp-2 text-sm leading-7">{item.reason || 'لم يضف الموظف سببًا تفصيليًا.'}</p>
                  <div className="mt-4 flex flex-wrap items-center gap-3 border-t border-[var(--border)] pt-4 text-xs">
                    <span className="inline-flex items-center gap-1 muted">
                      <Clock className="size-4" aria-hidden="true" />
                      {item.activeStepName || 'اكتمل المسار'}
                    </span>
                    <span className="muted">
                      {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.createdAt))}
                    </span>
                    {canDecide && item.status === 'pending' ? (
                      <button className="btn-primary ms-auto" onClick={() => setSelected(item)}>
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
          <div className="flex items-center gap-2 mb-5">
            <UserAvatar displayName={selected.employeeName} size="sm" />
            <p className="muted text-sm">{selected.employeeName}</p>
          </div>
          <p id="decision-reason" className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm leading-7">
            {selected.reason || 'لا يوجد سبب تفصيلي.'}
          </p>
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
