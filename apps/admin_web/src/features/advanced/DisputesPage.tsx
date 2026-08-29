import { AlertTriangle, Clock3, MessageSquareText, ShieldAlert, UserCheck } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { useDisputeCommands, useDisputeOperations, useDisputeParticipantDirectory } from './useAdvancedOperations';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';
import { type DisputeCase, type Person, type RunFn, terminalStatuses } from './components';
import {
  DisputeCaseListItem,
  DisputeCaseDetailHeader,
  DisputeAcceptCaseForm,
  DisputeTransitionForm,
  DisputeCommitteeForm,
  DisputeNotesSection,
  DisputeSessionsSection,
  DisputeMinutesForm,
  DisputeDecisionForm,
  DisputeDecisionDisplay,
  DisputeAdminActionPipeline,
  DisputeSettlementForm,
  DisputeActionTracker,
  DisputeAppealsPanel,
  DisputePartiesPanel,
} from './components';

export function DisputesPage() {
  const { toast } = useToast();
  const query = useDisputeOperations();
  const directory = useDisputeParticipantDirectory();
  const commands = useDisputeCommands();
  const [params, setParams] = useSearchParams();
  const [selectedCase, setSelectedCase] = useState(params.get('case') ?? '');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('open');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [feedback, setFeedback] = useState<{ tone: 'success' | 'error'; text: string } | null>(null);

  const cases = useMemo(() => query.data?.cases ?? [], [query.data?.cases]);
  const people = (directory.data ?? []) as Person[];
  const selected = cases.find((item) => item.id === selectedCase) ?? null;
  const summary = query.data?.summary;

  useEffect(() => {
    const requested = params.get('case');
    if (requested && requested !== selectedCase) setSelectedCase(requested);
  }, [params, selectedCase]);
  // نختار أول قضية تلقائيًا مرة واحدة فقط عند أول تحميل — لا نكتب فوق إلغاء الاختيار عند refetch
  const initialSelectRef = useRef(false);
  useEffect(() => {
    if (!initialSelectRef.current && !selectedCase && cases.length) {
      initialSelectRef.current = true;
      setSelectedCase(cases[0].id);
    }
  }, [cases, selectedCase]);

  const filteredCases = useMemo(() => {
    const needle = search.trim().toLocaleLowerCase('ar');
    return cases.filter((item) => {
      if (statusFilter === 'open' && terminalStatuses.has(item.status)) return false;
      if (statusFilter === 'overdue' && !item.overdue) return false;
      if (!['all', 'open', 'overdue'].includes(statusFilter) && item.status !== statusFilter) return false;
      if (priorityFilter !== 'all' && item.priority !== priorityFilter) return false;
      return !needle || `${item.caseNumber} ${item.title} ${item.actorName} ${item.respondentName}`.toLocaleLowerCase('ar').includes(needle);
    });
  }, [cases, search, statusFilter, priorityFilter]);

  const chooseCase = (item: DisputeCase) => {
    setSelectedCase(item.id);
    setParams({ case: item.id }, { replace: true });
    setFeedback(null);
  };

  const run: RunFn = async (task, success) => {
    setFeedback(null);
    try {
      await task();
      setFeedback({ tone: 'success', text: success });
      toast({ message: success, tone: 'success' });
    } catch (error) {
      toast({ message: safeErrorMessage(error), tone: 'error' });
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader title="لجنة حل المشكلات والخلافات" description="مسار سري متكامل من الاستلام خلال 24 ساعة إلى الإفادات والجلسات والقرار والتنفيذ والإغلاق." />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="جديدة" value={summary?.new ?? 0} icon={ShieldAlert} onClick={() => setStatusFilter('open')} />
        <MetricCard label="تجاوزت 24 ساعة" value={summary?.overdue ?? 0} icon={Clock3} onClick={() => setStatusFilter('overdue')} />
        <MetricCard
          label="بانتظار إفادات"
          value={summary?.waitingStatements ?? 0}
          icon={MessageSquareText}
          onClick={() => setStatusFilter('waiting_for_respondent')}
        />
        <MetricCard label="تنفيذات معلقة" value={summary?.pendingExecution ?? 0} icon={UserCheck} onClick={() => setStatusFilter('pending_execution')} />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="رقم المشكلة أو العنوان أو أحد الأطراف…"
        resultText={`${filteredCases.length} نتيجة`}
        isDirty={search !== '' || statusFilter !== 'open' || priorityFilter !== 'all'}
        onClear={() => {
          setSearch('');
          setStatusFilter('open');
          setPriorityFilter('all');
        }}
      >
        <select className="input" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} aria-label="فلتر الحالة">
          <option value="open">القضايا المفتوحة</option>
          <option value="overdue">المتأخرة</option>
          <option value="submitted">الجديدة</option>
          <option value="under_review">قيد المراجعة</option>
          <option value="waiting_for_respondent">بانتظار الطرف</option>
          <option value="session_scheduled">جلسة محددة</option>
          <option value="committee_deliberation">قيد المداولة</option>
          <option value="decision_issued">صدر القرار</option>
          <option value="action_proposed">بانتظار قرار تنفيذي</option>
          <option value="pending_execution">بانتظار التنفيذ</option>
          <option value="executed">تم التنفيذ</option>
          <option value="escalated_to_executive">المصعدة</option>
          <option value="closed">المغلقة</option>
          <option value="all">كل الحالات</option>
        </select>
        <select className="input" value={priorityFilter} onChange={(event) => setPriorityFilter(event.target.value)} aria-label="فلتر الأولوية">
          <option value="all">كل الأولويات</option>
          <option value="normal">عادية</option>
          <option value="urgent">عاجلة</option>
          <option value="critical">حرجة</option>
        </select>
      </FilterBar>

      {query.isError ? <ErrorState title="تعذر تحميل القضايا" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} /> : null}

      <section className="grid gap-6 xl:grid-cols-[390px_minmax(0,1fr)]">
        <div className="card p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-black">القضايا</h2>
            <span className="muted text-xs">{filteredCases.length} نتيجة</span>
          </div>
          <div className="mt-4 max-h-[calc(100vh-280px)] space-y-2 overflow-y-auto ps-1">
            {query.isLoading ? (
              <ListSkeleton rows={4} label="جارٍ تحميل القضايا" />
            ) : (
              filteredCases.map((item) => (
                <DisputeCaseListItem key={item.id} item={item} isSelected={selectedCase === item.id} onSelect={() => chooseCase(item)} />
              ))
            )}
          </div>
          {!query.isLoading && filteredCases.length === 0 ? <EmptyState title="لا توجد قضايا مطابقة" description="غيّر الفلاتر أو عبارة البحث." /> : null}
        </div>

        {selected ? (
          <div key={selected.id} className="min-w-0 space-y-5">
            {feedback ? (
              <div
                role="status"
                className={`rounded-2xl border p-4 text-sm font-bold ${feedback.tone === 'success' ? 'border-[var(--success)]/30 bg-[var(--success-soft)] text-[var(--success)]' : 'border-[var(--danger)]/30 bg-[var(--danger-soft)] text-[var(--danger)]'}`}
              >
                {feedback.text}
              </div>
            ) : null}

            <DisputeCaseDetailHeader selected={selected} />

            {['submitted', 'needs_more_information'].includes(selected.status) ? (
              <DisputeAcceptCaseForm selected={selected} people={people} commands={commands} run={run} />
            ) : null}

            <DisputeTransitionForm selected={selected} commands={commands} run={run} />

            {[
              'accepted',
              'under_review',
              'waiting_for_respondent',
              'waiting_for_witness',
              'returned_to_committee',
              'reopened',
              'session_scheduled',
              'committee_deliberation',
            ].includes(selected.status) ? (
              <DisputeCommitteeForm selected={selected} people={people} commands={commands} run={run} />
            ) : null}

            {selected.members.length ? <DisputeNotesSection selected={selected} commands={commands} run={run} /> : null}

            {selected.members.length >= 2 ? <DisputeSessionsSection selected={selected} commands={commands} run={run} /> : null}

            {selected.sessions.some((item) => item.status === 'scheduled') ? <DisputeMinutesForm selected={selected} commands={commands} run={run} /> : null}

            {selected.sessions.some((item) => item.status === 'held') && !selected.decision ? (
              <DisputeDecisionForm selected={selected} people={people} commands={commands} run={run} />
            ) : null}

            {selected.decision ? <DisputeDecisionDisplay selected={selected} /> : null}

            {selected.decision ? <DisputeAdminActionPipeline selected={selected} commands={commands} run={run} /> : null}

            {selected.decision && selected.status !== 'closed' ? <DisputeSettlementForm selected={selected} commands={commands} run={run} /> : null}

            {selected.actions.length ? <DisputeActionTracker selected={selected} commands={commands} run={run} /> : null}

            {selected.appeals.length ? <DisputeAppealsPanel selected={selected} commands={commands} run={run} /> : null}

            <DisputePartiesPanel selected={selected} />
          </div>
        ) : (
          <div className="card grid min-h-[420px] place-items-center p-8">
            <EmptyState title="اختر قضية" description="اختر قضية من القائمة لمراجعة تفاصيلها وإدارة مسارها." />
          </div>
        )}
      </section>

      {(summary?.critical ?? 0) > 0 ? (
        <div
          role="alert"
          className="fixed bottom-5 start-5 z-30 flex max-w-sm items-start gap-3 rounded-2xl border border-[var(--danger)]/30 bg-[var(--surface)] p-4 shadow-xl"
        >
          <AlertTriangle className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" aria-hidden="true" />
          <div>
            <strong>توجد قضايا حرجة</strong>
            <p className="muted mt-1 text-xs">راجعها فورًا وحدد ما إذا كانت تحتاج تصعيدًا للمدير التنفيذي.</p>
          </div>
        </div>
      ) : null}
    </div>
  );
}
