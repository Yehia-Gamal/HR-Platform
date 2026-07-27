import type { DisputeOperationsCatalog } from '@ahla/shared-contracts';
import {
  AlertTriangle, Briefcase, CalendarPlus, CheckCircle2, ClipboardCheck, Clock3, FileText, Gavel, MessageSquareText,
  RotateCcw, Scale, Send, ShieldAlert, ShieldCheck, UserCheck, UsersRound,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { safeErrorMessage } from '../../core/errorMapper';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { useDisputeCommands, useDisputeOperations, useDisputeParticipantDirectory } from './useAdvancedOperations';

type DisputeCase = DisputeOperationsCatalog['cases'][number];

const terminalStatuses = new Set(['closed', 'rejected', 'cancelled_by_employee']);
const caseTypes: Record<string, string> = {
  employee_conflict: 'خلاف بين موظفين', inappropriate_conduct: 'سوء تعامل أو أسلوب غير لائق', verbal_abuse: 'رفع صوت أو إساءة لفظية',
  management_chain: 'عدم احترام التسلسل الإداري', direct_manager: 'مشكلة مع مدير مباشر', department_conflict: 'مشكلة بين إدارتين',
  misunderstanding: 'سوء تفاهم', work_environment: 'بيئة العمل', donor_beneficiary: 'مشكلة مع متبرع أو مستفيد',
  administrative_violation: 'مخالفة إدارية', agreement_breach: 'عدم تنفيذ اتفاق سابق', other: 'مشكلة أخرى',
};
const transitionLabels: Record<string, string> = {
  request_more_information: 'طلب استكمال بيانات', reject: 'رفض شكلي', start_review: 'بدء/استئناف المراجعة',
  request_respondent_statement: 'طلب إفادة الطرف الآخر', request_witness_statement: 'طلب إفادة شاهد',
  start_deliberation: 'بدء المداولة', escalate: 'تصعيد للمدير التنفيذي', return_to_committee: 'إعادة إلى اللجنة',
  resolve_friendly: 'حل ودي', close: 'إغلاق بعد التنفيذ', reopen: 'إعادة فتح', extend_review: 'تمديد مهلة المراجعة 24 ساعة', change_priority: 'تغيير الأولوية',
};

function formatDate(value?: string | null, withTime = true) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-EG', withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' }).format(new Date(value));
}

function remainingLabel(value?: string | null) {
  if (!value) return 'لا توجد مهلة';
  const hours = Math.ceil((new Date(value).getTime() - Date.now()) / 3_600_000);
  if (hours < 0) return `متأخرة ${Math.abs(hours)} س`;
  if (hours === 0) return 'أقل من ساعة';
  return `متبقي ${hours} س`;
}

function actionsFor(item: DisputeCase) {
  const result: string[] = [];
  if (['submitted', 'needs_more_information'].includes(item.status)) result.push('request_more_information', 'reject', 'extend_review');
  if (['accepted', 'reopened', 'returned_to_committee'].includes(item.status)) result.push('start_review');
  if (['accepted', 'under_review', 'waiting_for_respondent', 'waiting_for_witness'].includes(item.status)) {
    result.push('request_respondent_statement', 'request_witness_statement', 'start_deliberation');
  }
  if (!terminalStatuses.has(item.status) && item.status !== 'escalated_to_executive') result.push('escalate');
  if (item.status === 'escalated_to_executive') result.push('return_to_committee');
  if (['under_review', 'waiting_for_respondent', 'waiting_for_witness', 'committee_deliberation'].includes(item.status)) result.push('resolve_friendly');
  if (['decision_issued', 'settlement_pending', 'executed', 'resolved_friendly'].includes(item.status)) result.push('close');
  if (['closed', 'rejected'].includes(item.status)) result.push('reopen');
  if (!terminalStatuses.has(item.status)) result.push('change_priority');
  return [...new Set(result)];
}

export function DisputesPage() {
  const query = useDisputeOperations();
  const directory = useDisputeParticipantDirectory();
  const commands = useDisputeCommands();
  const [params, setParams] = useSearchParams();
  const [selectedCase, setSelectedCase] = useState(params.get('case') ?? '');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('open');
  const [priorityFilter, setPriorityFilter] = useState('all');
  const [feedback, setFeedback] = useState<{ tone: 'success' | 'error'; text: string } | null>(null);
  const [assignedTo, setAssignedTo] = useState('');
  const [quorum, setQuorum] = useState(2);
  const [members, setMembers] = useState<Array<{ employeeId: string; role: string }>>([]);
  const [transition, setTransition] = useState({ action: '', reason: '', targetId: '', summary: '', priority: 'normal' });
  const [note, setNote] = useState({ type: 'committee_note', text: '', visibility: 'committee_only' });
  const [session, setSession] = useState({ type: 'hearing', at: '', endsAt: '', location: '', modality: 'in_person' });
  const [minutes, setMinutes] = useState({ sessionId: '', text: '', outcome: '', recommendation: '', internalNotes: '' });
  const [attendance, setAttendance] = useState<Record<string, string>>({});
  const [decision, setDecision] = useState({ sessionId: '', text: '', rationale: '', outcome: 'mediation', ownerId: '', dueAt: '' });
  const [settlement, setSettlement] = useState({ type: 'written_apology', fromId: '', toId: '', text: '', place: '', dueAt: '' });
  const [proofs, setProofs] = useState<Record<string, string>>({});
  const [appealResolution, setAppealResolution] = useState<Record<string, string>>({});
  const [proposedAction, setProposedAction] = useState('');
  const [proposedActionDetail, setProposedActionDetail] = useState('');
  const [executionNotes, setExecutionNotes] = useState('');

  const cases = query.data?.cases ?? [];
  const people = directory.data ?? [];
  const selected = cases.find((item) => item.id === selectedCase) ?? null;
  const summary = query.data?.summary;

  useEffect(() => {
    const requested = params.get('case');
    if (requested && requested !== selectedCase) setSelectedCase(requested);
  }, [params, selectedCase]);
  useEffect(() => {
    if (!selectedCase && cases.length) setSelectedCase(cases[0].id);
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
    setAssignedTo(item.assignedTo ?? '');
    setQuorum(item.quorum);
    setMembers(item.members.filter((member) => member.active).map((member) => ({ employeeId: member.employeeId, role: member.role })));
    setTransition({ action: '', reason: '', targetId: '', summary: '', priority: item.priority });
    setProposedAction('');
    setProposedActionDetail('');
    setExecutionNotes('');
    setFeedback(null);
  };

  const run = async (task: () => Promise<unknown>, success: string) => {
    setFeedback(null);
    try {
      await task();
      setFeedback({ tone: 'success', text: success });
    } catch (error) {
      setFeedback({ tone: 'error', text: safeErrorMessage(error) });
    }
  };

  const submitTransition = async () => {
    if (!selected || !transition.action) return;
    const metadata: Record<string, unknown> = {};
    if (transition.targetId) metadata.employeeId = transition.targetId;
    if (transition.summary.trim()) metadata.summary = transition.summary.trim();
    if (transition.action === 'change_priority') metadata.priority = transition.priority;
    await run(() => commands.transitionCase.mutateAsync({
      p_case_id: selected.id, p_action: transition.action, p_reason: transition.reason.trim() || null, p_metadata: metadata,
    }), 'تم تنفيذ الإجراء وتسجيله في سجل التدقيق.');
  };

  return <div className="space-y-6">
    <PageHeader
      title="لجنة حل المشكلات والخلافات"
      description="مسار سري متكامل من الاستلام خلال 24 ساعة إلى الإفادات والجلسات والقرار والتنفيذ والإغلاق."
    />

    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="جديدة" value={summary?.new ?? 0} icon={ShieldAlert} />
      <MetricCard label="تجاوزت 24 ساعة" value={summary?.overdue ?? 0} icon={Clock3} />
      <MetricCard label="بانتظار إفادات" value={summary?.waitingStatements ?? 0} icon={MessageSquareText} />
      <MetricCard label="تنفيذات معلقة" value={summary?.pendingExecution ?? 0} icon={UserCheck} />
    </section>

    <FilterBar
      searchValue={search}
      onSearchChange={setSearch}
      searchPlaceholder="رقم المشكلة أو العنوان أو أحد الأطراف…"
      resultText={`${filteredCases.length} نتيجة`}
      isDirty={search !== '' || statusFilter !== 'open' || priorityFilter !== 'all'}
      onClear={() => { setSearch(''); setStatusFilter('open'); setPriorityFilter('all'); }}
    >
      <select className="input" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} aria-label="فلتر الحالة">
        <option value="open">القضايا المفتوحة</option><option value="overdue">المتأخرة</option><option value="submitted">الجديدة</option>
        <option value="under_review">قيد المراجعة</option><option value="waiting_for_respondent">بانتظار الطرف</option>
        <option value="session_scheduled">جلسة محددة</option><option value="committee_deliberation">قيد المداولة</option>
        <option value="decision_issued">صدر القرار</option><option value="action_proposed">بانتظار قرار تنفيذي</option><option value="pending_execution">بانتظار التنفيذ</option><option value="executed">تم التنفيذ</option><option value="resolved_friendly">حل ودي</option><option value="escalated_to_executive">المصعدة</option><option value="closed">المغلقة</option><option value="all">كل الحالات</option>
      </select>
      <select className="input" value={priorityFilter} onChange={(event) => setPriorityFilter(event.target.value)} aria-label="فلتر الأولوية">
        <option value="all">كل الأولويات</option><option value="normal">عادية</option><option value="urgent">عاجلة</option><option value="critical">حرجة</option>
      </select>
    </FilterBar>

    {query.isError ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : null}

    <section className="grid gap-6 xl:grid-cols-[390px_minmax(0,1fr)]">
      <div className="card p-4">
        <div className="flex items-center justify-between"><h2 className="text-lg font-black">القضايا</h2><span className="muted text-xs">{filteredCases.length} نتيجة</span></div>
        <div className="mt-4 max-h-[calc(100vh-280px)] space-y-2 overflow-y-auto pl-1">
          {query.isLoading ? <ListSkeleton rows={4} label="جارٍ تحميل القضايا" /> : filteredCases.map((item) => <button key={item.id} type="button" onClick={() => chooseCase(item)} className={`w-full rounded-2xl border p-4 text-right transition ${selectedCase === item.id ? 'border-[var(--brand-primary)] bg-[var(--surface-muted)]' : 'border-[var(--border)] hover:border-[var(--border-strong)]'}`}>
            <div className="flex items-start justify-between gap-2"><strong className="line-clamp-2">{item.title}</strong><StatusBadge value={item.status} /></div>
            <p className="muted mt-2 text-xs">{item.caseNumber ?? 'بدون رقم'} · {item.actorName ?? 'مقدم غير محدد'}</p>
            <div className="mt-3 flex flex-wrap items-center gap-2"><StatusBadge value={item.priority} />{item.overdue ? <StatusBadge value="overdue" /> : null}<span className="muted text-xs">{remainingLabel(item.reviewDueAt)}</span></div>
          </button>)}
        </div>
        {!query.isLoading && filteredCases.length === 0 ? <EmptyState title="لا توجد قضايا مطابقة" description="غيّر الفلاتر أو عبارة البحث." /> : null}
      </div>

      {selected ? <div className="min-w-0 space-y-5">
        {feedback ? <div role="status" className={`rounded-2xl border p-4 text-sm font-bold ${feedback.tone === 'success' ? 'border-[var(--success)]/30 bg-[var(--success-soft)] text-[var(--success)]' : 'border-[var(--danger)]/30 bg-[var(--danger-soft)] text-[var(--danger)]'}`}>{feedback.text}</div> : null}

        <section className="card p-5">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><StatusBadge value={selected.status} /><StatusBadge value={selected.priority} />{selected.overdue ? <StatusBadge value="overdue" /> : null}</div><h2 className="mt-3 text-xl font-black">{selected.title}</h2><p className="muted mt-1">{selected.caseNumber} · {caseTypes[selected.caseType] ?? selected.caseType}</p></div>
            <div className="rounded-2xl bg-[var(--surface-muted)] px-4 py-3 text-end"><span className="muted block text-xs">مهلة المراجعة</span><strong className={selected.overdue ? 'text-[var(--danger)]' : ''}>{remainingLabel(selected.reviewDueAt)}</strong></div>
          </div>
          <p className="mt-5 whitespace-pre-wrap leading-8">{selected.description ?? 'لا يوجد وصف.'}</p>
          <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <Info label="مقدم المشكلة" value={`${selected.actorName ?? '—'}${selected.actorDepartment ? ` — ${selected.actorDepartment}` : ''}`} />
            <Info label="الطرف الرئيسي" value={selected.respondentName ?? '—'} />
            <Info label="تاريخ الواقعة" value={formatDate(selected.incidentAt)} />
            <Info label="مكان الواقعة" value={selected.incidentLocation ?? '—'} />
            <Info label="الإجراء المطلوب" value={selected.requestedAction ?? '—'} />
            <Info label="التواصل مع المدير" value={selected.directManagerContacted == null ? 'غير محدد' : selected.directManagerContacted ? 'تم' : 'لم يتم'} />
            <Info label="محاولة حل ودي" value={selected.amicableAttempted == null ? 'غير محدد' : selected.amicableAttempted ? 'تمت' : 'لم تتم'} />
            <Info label="المسؤول الحالي" value={selected.assignedName ?? 'لم يُسند'} />
          </div>
        </section>

        {['submitted', 'needs_more_information'].includes(selected.status) ? <section className="card p-5">
          <h3 className="text-lg font-black">قبول المشكلة للدراسة</h3><p className="muted mt-1 text-sm">بعد القبول لا يستطيع مقدم المشكلة إلغاءها.</p>
          <div className="mt-4 grid gap-3 md:grid-cols-[1fr_140px_auto]">
            <select className="input" aria-label="المحقق أو المسؤول" value={assignedTo} onChange={(event) => setAssignedTo(event.target.value)}><option value="">المحقق أو المسؤول</option>{people.map((person) => <option key={person.id} value={person.id}>{person.name}{person.department ? ` — ${person.department}` : ''}</option>)}</select>
            <input className="input" type="number" min="1" aria-label="نصاب اللجنة" value={quorum} onChange={(event) => setQuorum(Number(event.target.value))} />
            <button className="btn-primary" disabled={!assignedTo || commands.acceptCase.isPending} onClick={() => void run(() => commands.acceptCase.mutateAsync({ p_case_id: selected.id, p_assigned_to: assignedTo, p_quorum: quorum, p_due_at: null }), 'تم قبول المشكلة وبدأ المسار الرسمي.')}><CheckCircle2 className="size-4" />قبول المشكلة</button>
          </div>
        </section> : null}

        <section className="card p-5">
          <h3 className="text-lg font-black">إدارة مسار القضية</h3>
          <div className="mt-4 grid gap-3 lg:grid-cols-2">
            <select className="input" aria-label="إجراء المسار" value={transition.action} onChange={(event) => setTransition({ ...transition, action: event.target.value })}><option value="">اختر الإجراء</option>{actionsFor(selected).map((action) => <option key={action} value={action}>{transitionLabels[action]}</option>)}</select>
            {['request_respondent_statement', 'request_witness_statement'].includes(transition.action) ? <select className="input" aria-label="الشخص المطلوبة إفادته" value={transition.targetId} onChange={(event) => setTransition({ ...transition, targetId: event.target.value })}><option value="">اختر الشخص</option>{selected.parties.filter((party) => transition.action === 'request_witness_statement' ? party.type === 'witness' : party.type === 'respondent').map((party) => <option key={party.id} value={party.employeeId}>{party.name}</option>)}</select> : null}
            {transition.action === 'change_priority' ? <select className="input" aria-label="الأولوية" value={transition.priority} onChange={(event) => setTransition({ ...transition, priority: event.target.value })}><option value="normal">عادية</option><option value="urgent">عاجلة</option><option value="critical">حرجة</option></select> : null}
            {['request_respondent_statement', 'request_witness_statement'].includes(transition.action) ? <input className="input" placeholder="ملخص مسموح بمشاركته في الإشعار" value={transition.summary} onChange={(event) => setTransition({ ...transition, summary: event.target.value })} /> : null}
            <textarea className="input min-h-20 lg:col-span-2" placeholder="سبب الإجراء (إلزامي للرفض والتصعيد والتمديد والإغلاق وإعادة الفتح وتغيير الأولوية)" value={transition.reason} onChange={(event) => setTransition({ ...transition, reason: event.target.value })} />
          </div>
          <button className="btn-primary mt-3" disabled={!transition.action || commands.transitionCase.isPending || (['request_respondent_statement', 'request_witness_statement'].includes(transition.action) && !transition.targetId)} onClick={() => void submitTransition()}><Send className="size-4" />تنفيذ وتسجيل الإجراء</button>
        </section>

        {['accepted', 'under_review', 'waiting_for_respondent', 'waiting_for_witness', 'returned_to_committee', 'reopened', 'session_scheduled', 'committee_deliberation'].includes(selected.status) ? <section className="card p-5">
          <div className="flex items-center justify-between"><div><h3 className="text-lg font-black">تشكيل اللجنة</h3><p className="muted mt-1 text-sm">لا يجوز اختيار أي طرف في المشكلة عضوًا باللجنة.</p></div><button className="btn-secondary" onClick={() => setMembers((current) => [...current, { employeeId: '', role: current.length ? 'member' : 'chair' }])}><UsersRound className="size-4" />إضافة عضو</button></div>
          <div className="mt-4 space-y-2">{members.map((member, index) => <div key={`${index}-${member.employeeId}`} className="grid gap-2 md:grid-cols-[1fr_160px_auto]">
            <select className="input" aria-label="عضو اللجنة" value={member.employeeId} onChange={(event) => setMembers((items) => items.map((item, i) => i === index ? { ...item, employeeId: event.target.value } : item))}><option value="">اختر الموظف</option>{people.filter((person) => !selected.parties.some((party) => party.employeeId === person.id)).map((person) => <option key={person.id} value={person.id}>{person.name}</option>)}</select>
            <select className="input" aria-label="دور العضو" value={member.role} onChange={(event) => setMembers((items) => items.map((item, i) => i === index ? { ...item, role: event.target.value } : item))}><option value="chair">رئيس</option><option value="secretary">مقرر</option><option value="member">عضو</option><option value="observer">مراقب</option><option value="advisor">مستشار</option></select>
            <button className="btn-secondary" onClick={() => setMembers((items) => items.filter((_, i) => i !== index))}>حذف</button>
          </div>)}</div>
          <button className="btn-primary mt-4" disabled={members.filter((item) => item.employeeId).length < 2 || !members.some((item) => item.role === 'chair') || commands.setCommittee.isPending} onClick={() => void run(() => commands.setCommittee.mutateAsync({ p_case_id: selected.id, p_members: members.filter((item) => item.employeeId) }), 'تم حفظ تشكيل اللجنة وبدء المراجعة.')}><UsersRound className="size-4" />حفظ تشكيل اللجنة</button>
        </section> : null}

        {selected.members.length ? <section className="card p-5">
          <h3 className="text-lg font-black">ملاحظات اللجنة والتوصيات</h3>
          <div className="mt-4 grid gap-3 md:grid-cols-[180px_180px_1fr_auto]">
            <select className="input" aria-label="نوع الملاحظة" value={note.type} onChange={(event) => setNote({ ...note, type: event.target.value })}><option value="committee_note">ملاحظة داخلية</option><option value="recommendation">توصية</option><option value="executive_note">ملاحظة تنفيذية</option></select>
            <select className="input" aria-label="ظهور الملاحظة" value={note.visibility} onChange={(event) => setNote({ ...note, visibility: event.target.value })}><option value="committee_only">اللجنة فقط</option><option value="parties">تظهر للأطراف</option><option value="complainant">لمقدم المشكلة</option><option value="respondent">للطرف الآخر</option></select>
            <input className="input" value={note.text} onChange={(event) => setNote({ ...note, text: event.target.value })} placeholder="اكتب الملاحظة أو التوصية…" />
            <button className="btn-primary" disabled={note.text.trim().length < 10 || commands.addStatement.isPending} onClick={() => void run(async () => { await commands.addStatement.mutateAsync({ p_case_id: selected.id, p_statement_type: note.type, p_statement_text: note.text, p_visibility: note.visibility }); setNote({ ...note, text: '' }); }, 'تم حفظ الملاحظة دون المساس بملاحظات الأعضاء الآخرين.')}><FileText className="size-4" />حفظ</button>
          </div>
          <div className="mt-4 space-y-2">{selected.statements.map((item) => <article key={item.id} className="rounded-2xl bg-[var(--surface-muted)] p-4"><div className="flex flex-wrap items-center justify-between gap-2"><strong>{item.submittedByName} · {item.type}</strong><span className="muted text-xs">{formatDate(item.submittedAt)}</span></div><p className="mt-2 whitespace-pre-wrap text-sm leading-7">{item.text}</p><span className="muted mt-2 block text-xs">الظهور: {item.visibility}</span></article>)}</div>
        </section> : null}

        {selected.members.length >= 2 ? <section className="card p-5">
          <h3 className="text-lg font-black">الجلسات</h3>
          <div className="mt-4 grid gap-3 lg:grid-cols-3">
            <select className="input" aria-label="نوع الجلسة" value={session.type} onChange={(event) => setSession({ ...session, type: event.target.value })}><option value="hearing">استماع</option><option value="investigation">تحقيق</option><option value="mediation">وساطة</option><option value="follow_up">متابعة</option><option value="decision">قرار</option></select>
            <input className="input" type="datetime-local" aria-label="بداية الجلسة" value={session.at} onChange={(event) => setSession({ ...session, at: event.target.value })} />
            <input className="input" type="datetime-local" aria-label="نهاية الجلسة" value={session.endsAt} onChange={(event) => setSession({ ...session, endsAt: event.target.value })} />
            <select className="input" aria-label="نمط الجلسة" value={session.modality} onChange={(event) => setSession({ ...session, modality: event.target.value })}><option value="in_person">حضورية</option><option value="remote">عن بُعد</option><option value="hybrid">هجين</option></select>
            <input className="input" placeholder="المكان أو رابط الاجتماع" value={session.location} onChange={(event) => setSession({ ...session, location: event.target.value })} />
            <button className="btn-primary" disabled={!session.at || commands.scheduleSession.isPending} onClick={() => void run(() => commands.scheduleSession.mutateAsync({ p_case_id: selected.id, p_type: session.type, p_scheduled_at: new Date(session.at).toISOString(), p_ends_at: session.endsAt ? new Date(session.endsAt).toISOString() : null, p_location: session.location || null, p_modality: session.modality, p_participants: [...selected.parties.map((party) => ({ employeeId: party.employeeId, role: party.type })), ...selected.members.map((member) => ({ employeeId: member.employeeId, role: 'committee' }))] }), 'تم تحديد الجلسة وإشعار المشاركين دون كشف تفاصيل سرية.')}><CalendarPlus className="size-4" />تحديد جلسة</button>
          </div>
          <div className="mt-5 space-y-2">{selected.sessions.map((item) => <button key={item.id} type="button" className="w-full rounded-xl border border-[var(--border)] p-3 text-right" onClick={() => { setMinutes({ ...minutes, sessionId: item.id }); setDecision({ ...decision, sessionId: item.id }); setAttendance(Object.fromEntries(selected.members.filter((member) => member.active).map((member) => [member.id, 'present']))); }}><div className="flex flex-wrap items-center justify-between gap-2"><span>{item.type} · {formatDate(item.scheduledAt)} · {item.location ?? 'دون مكان'}</span><StatusBadge value={item.status} /></div>{item.minutes ? <p className="muted mt-2 line-clamp-2 text-xs">{item.minutes}</p> : null}</button>)}</div>
        </section> : null}

        {selected.sessions.some((item) => item.status === 'scheduled') ? <section className="card p-5">
          <h3 className="text-lg font-black">محضر الجلسة والتحقق من النصاب</h3>
          <div className="mt-4 grid gap-3">
            <select className="input" aria-label="اختر جلسة مجدولة" value={minutes.sessionId} onChange={(event) => { setMinutes({ ...minutes, sessionId: event.target.value }); setAttendance(Object.fromEntries(selected.members.filter((member) => member.active).map((member) => [member.id, 'present']))); }}><option value="">اختر جلسة مجدولة</option>{selected.sessions.filter((item) => item.status === 'scheduled').map((item) => <option key={item.id} value={item.id}>{item.type} — {formatDate(item.scheduledAt)}</option>)}</select>
            <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">{selected.members.filter((member) => member.active).map((member) => <label key={member.id} className="rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">{member.name}<select className="input mt-2" aria-label={`حضور ${member.name}`} value={attendance[member.id] ?? 'present'} onChange={(event) => setAttendance({ ...attendance, [member.id]: event.target.value })}><option value="present">حاضر</option><option value="remote">عن بُعد</option><option value="absent">غائب</option><option value="excused">معتذر</option></select></label>)}</div>
            <textarea className="input min-h-36" placeholder="المحضر: أقوال الأطراف والشهود، نقاط الاتفاق والاختلاف، الأدلة والالتزامات…" value={minutes.text} onChange={(event) => setMinutes({ ...minutes, text: event.target.value })} />
            <input className="input" placeholder="نتيجة الجلسة" value={minutes.outcome} onChange={(event) => setMinutes({ ...minutes, outcome: event.target.value })} />
            <textarea className="input min-h-20" placeholder="توصية اللجنة" value={minutes.recommendation} onChange={(event) => setMinutes({ ...minutes, recommendation: event.target.value })} />
            <textarea className="input min-h-20" placeholder="ملاحظات داخلية لا تظهر للأطراف" value={minutes.internalNotes} onChange={(event) => setMinutes({ ...minutes, internalNotes: event.target.value })} />
            <button className="btn-primary" disabled={!minutes.sessionId || minutes.text.trim().length < 20 || commands.finalizeSession.isPending} onClick={() => void run(() => commands.finalizeSession.mutateAsync({ p_session_id: minutes.sessionId, p_minutes: minutes.text, p_attendance: selected.members.filter((member) => member.active).map((member) => ({ committeeMemberId: member.id, status: attendance[member.id] ?? 'absent' })), p_outcome: minutes.outcome || null, p_minutes_data: { recommendation: minutes.recommendation, internalNotes: minutes.internalNotes } }), 'تم حفظ المحضر وتأكيد النصاب ونقل القضية للمداولة.')}><CheckCircle2 className="size-4" />اعتماد المحضر</button>
          </div>
        </section> : null}

        {selected.sessions.some((item) => item.status === 'held') && !selected.decision ? <section className="card p-5">
          <h3 className="text-lg font-black">إصدار قرار اللجنة</h3>
          <div className="mt-4 grid gap-3"><select className="input" aria-label="اختر جلسة مكتملة" value={decision.sessionId} onChange={(event) => setDecision({ ...decision, sessionId: event.target.value })}><option value="">اختر جلسة مكتملة</option>{selected.sessions.filter((item) => item.status === 'held').map((item) => <option value={item.id} key={item.id}>{item.type} — {formatDate(item.heldAt, false)}</option>)}</select>
            <textarea className="input min-h-24" placeholder="نص القرار المسموح بإبلاغه للأطراف" value={decision.text} onChange={(event) => setDecision({ ...decision, text: event.target.value })} />
            <textarea className="input min-h-24" placeholder="الحيثيات والمبررات الداخلية" value={decision.rationale} onChange={(event) => setDecision({ ...decision, rationale: event.target.value })} />
            <div className="grid gap-3 md:grid-cols-3"><select className="input" aria-label="نتيجة القرار" value={decision.outcome} onChange={(event) => setDecision({ ...decision, outcome: event.target.value })}><option value="mediation">صلح أو تسوية</option><option value="warning">تنبيه إداري</option><option value="corrective_action">إجراء تصحيحي</option><option value="disciplinary_recommendation">توصية إدارية</option><option value="dismissed">حفظ لعدم الثبوت</option><option value="escalation">تصعيد</option><option value="other">قرار آخر</option></select><select className="input" aria-label="مسؤول التنفيذ" value={decision.ownerId} onChange={(event) => setDecision({ ...decision, ownerId: event.target.value })}><option value="">لا يحتاج مسؤول تنفيذ</option>{people.map((person) => <option value={person.id} key={person.id}>{person.name}</option>)}</select><input className="input" type="datetime-local" aria-label="موعد التنفيذ" value={decision.dueAt} onChange={(event) => setDecision({ ...decision, dueAt: event.target.value })} /></div>
            <button className="btn-primary" disabled={!decision.sessionId || decision.text.trim().length < 20 || decision.rationale.trim().length < 20 || commands.issueDecision.isPending} onClick={() => void run(() => commands.issueDecision.mutateAsync({ p_case_id: selected.id, p_session_id: decision.sessionId, p_text: decision.text, p_rationale: decision.rationale, p_outcome: decision.outcome, p_owner_id: decision.ownerId || null, p_due_at: decision.dueAt ? new Date(decision.dueAt).toISOString() : null }), 'صدر القرار وأُبلغ الأطراف ومسؤول التنفيذ.')}><Gavel className="size-4" />إصدار القرار</button>
          </div>
        </section> : null}

        {selected.decision ? <section className="card p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="text-lg font-black">القرار {selected.decision.number}</h3><p className="muted mt-1 text-sm">صدر {formatDate(selected.decision.issuedAt)}</p></div><StatusBadge value={selected.decision.status} /></div><p className="mt-4 whitespace-pre-wrap leading-8">{selected.decision.text}</p><details className="mt-4 rounded-2xl bg-[var(--surface-muted)] p-4"><summary className="cursor-pointer font-black">الحيثيات الداخلية</summary><p className="mt-3 whitespace-pre-wrap leading-7">{selected.decision.rationale}</p></details></section> : null}

        {selected.decision ? <section className="card p-5">
          <h3 className="text-lg font-black">مسار الإجراء الإداري</h3>
          <p className="muted mt-1 text-sm">ثلاث خطوات: اقتراح المقرر → قرار المدير التنفيذي → تنفيذ الموارد البشرية.</p>

          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <div className={`rounded-2xl border p-4 ${selected.proposedAdminAction ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}>
              <div className="flex items-center gap-2">
                <Briefcase className={`size-5 ${selected.proposedAdminAction ? 'text-[var(--success)]' : 'text-[var(--muted)]'}`} aria-hidden="true" />
                <strong className="text-sm">١. اقتراح المقرر</strong>
              </div>
              <StatusBadge value={selected.proposedAdminAction ? 'completed' : 'pending'} />
              {selected.proposedAdminAction ? <p className="mt-2 text-sm leading-7">{selected.proposedAdminAction}</p> : <p className="muted mt-2 text-xs">لم يُقترح إجراء بعد</p>}
            </div>

            <div className={`rounded-2xl border p-4 ${selected.executiveDecision === 'approved' ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : selected.executiveDecision === 'rejected' ? 'border-[var(--danger)]/30 bg-[var(--danger-soft)]' : selected.executiveDecision === 'modified' ? 'border-[var(--warning)]/30 bg-[var(--warning-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}>
              <div className="flex items-center gap-2">
                <ShieldCheck className={`size-5 ${selected.executiveDecision ? (selected.executiveDecision === 'approved' ? 'text-[var(--success)]' : selected.executiveDecision === 'rejected' ? 'text-[var(--danger)]' : 'text-[var(--warning)]') : 'text-[var(--muted)]'}`} aria-hidden="true" />
                <strong className="text-sm">٢. قرار المدير التنفيذي</strong>
              </div>
              {selected.executiveDecision ? <><StatusBadge value={selected.executiveDecision === 'approved' ? 'approved' : selected.executiveDecision === 'rejected' ? 'rejected' : 'modified'} />{selected.executiveDecisionReason ? <p className="mt-2 text-sm leading-7">{selected.executiveDecisionReason}</p> : null}{selected.approvedAdminAction && selected.executiveDecision === 'modified' ? <p className="mt-2 rounded-xl bg-[var(--surface)] p-3 text-sm leading-7"><strong className="block text-xs">الإجراء المعدّل:</strong>{selected.approvedAdminAction}</p> : null}</> : <p className="muted mt-2 text-xs">بانتظار قرار المدير التنفيذي (عبر التطبيق)</p>}
            </div>

            <div className={`rounded-2xl border p-4 ${selected.executedAt ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}>
              <div className="flex items-center gap-2">
                <ClipboardCheck className={`size-5 ${selected.executedAt ? 'text-[var(--success)]' : 'text-[var(--muted)]'}`} aria-hidden="true" />
                <strong className="text-sm">٣. تنفيذ الموارد البشرية</strong>
              </div>
              <StatusBadge value={selected.executedAt ? 'completed' : 'pending'} />
              {selected.executedAt ? <><p className="mt-2 text-sm leading-7">تم التنفيذ {formatDate(selected.executedAt)}</p>{selected.executionNotes ? <p className="mt-2 rounded-xl bg-[var(--surface)] p-3 text-sm leading-7">{selected.executionNotes}</p> : null}</> : <p className="muted mt-2 text-xs">لم يُنفذ بعد</p>}
            </div>
          </div>

          {!selected.proposedAdminAction ? <div className="mt-5 rounded-2xl border border-[var(--border)] p-4">
            <h4 className="font-bold">اقتراح الإجراء الإداري</h4>
            <p className="muted mt-1 text-xs">بصفتك مقرر اللجنة، اقترح الإجراء الإداري المناسب بناءً على قرار اللجنة.</p>
            <div className="mt-3 grid gap-3 sm:grid-cols-[200px_1fr_auto]">
              <select className="input" aria-label="نوع الإجراء" value={proposedAction} onChange={(event) => setProposedAction(event.target.value)}>
                <option value="">اختر نوع الإجراء</option>
                <option value="verbal_warning">إنذار شفهي</option><option value="written_warning">إنذار كتابي</option><option value="final_warning">إنذار نهائي</option>
                <option value="salary_deduction">خصم من الراتب</option><option value="suspension">إيقاف عن العمل</option><option value="demotion">تخفيض الدرجة</option>
                <option value="termination">إنهاء الخدمة</option><option value="transfer">نقل</option><option value="training_requirement">تدريب إلزامي</option><option value="no_action">لا إجراء</option>
              </select>
              <textarea className="input min-h-20" placeholder="تفاصيل الإجراء المقترح (3 أحرف على الأقل)…" value={proposedActionDetail} onChange={(event) => setProposedActionDetail(event.target.value)} aria-label="تفاصيل الإجراء" />
              <button className="btn-primary self-end" disabled={!proposedAction || proposedActionDetail.trim().length < 3 || commands.proposeAdminAction.isPending} onClick={() => void run(async () => { await commands.proposeAdminAction.mutateAsync({ p_case_id: selected.id, p_proposed_action: proposedAction, p_detail: proposedActionDetail.trim() }); setProposedAction(''); setProposedActionDetail(''); }, 'تم إرسال الاقتراح للمدير التنفيذي للمراجعة.')}><Briefcase className="size-4" />إرسال الاقتراح</button>
            </div>
          </div> : null}

          {selected.executiveDecision === 'approved' && !selected.executedAt ? <div className="mt-5 rounded-2xl border border-[var(--success)]/30 bg-[var(--success-soft)] p-4">
            <h4 className="font-bold text-[var(--success)]">تنفيذ الإجراء الإداري المعتمد</h4>
            <p className="muted mt-1 text-xs">الإجراء المعتمد: {selected.approvedAdminAction ?? selected.proposedAdminAction}</p>
            <div className="mt-3 flex flex-col gap-3 sm:flex-row">
              <textarea className="input min-h-20 flex-1" placeholder="ملاحظات التنفيذ وتفاصيل ما تم…" value={executionNotes} onChange={(event) => setExecutionNotes(event.target.value)} aria-label="ملاحظات التنفيذ" />
              <button className="btn-primary self-end" disabled={executionNotes.trim().length < 5 || commands.executeAdminAction.isPending} onClick={() => void run(async () => { await commands.executeAdminAction.mutateAsync({ p_case_id: selected.id, p_notes: executionNotes.trim() }); setExecutionNotes(''); }, 'تم تنفيذ الإجراء الإداري وتسجيله.')}><ClipboardCheck className="size-4" />تأكيد التنفيذ</button>
            </div>
          </div> : null}

          {selected.executiveDecision === 'modified' && !selected.executedAt ? <div className="mt-5 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning-soft)] p-4">
            <h4 className="font-bold text-[var(--warning)]">تنفيذ الإجراء الإداري المعدّل</h4>
            <p className="muted mt-1 text-xs">الإجراء المعدّل: {selected.approvedAdminAction}</p>
            <div className="mt-3 flex flex-col gap-3 sm:flex-row">
              <textarea className="input min-h-20 flex-1" placeholder="ملاحظات التنفيذ وتفاصيل ما تم…" value={executionNotes} onChange={(event) => setExecutionNotes(event.target.value)} aria-label="ملاحظات التنفيذ" />
              <button className="btn-primary self-end" disabled={executionNotes.trim().length < 5 || commands.executeAdminAction.isPending} onClick={() => void run(async () => { await commands.executeAdminAction.mutateAsync({ p_case_id: selected.id, p_notes: executionNotes.trim() }); setExecutionNotes(''); }, 'تم تنفيذ الإجراء الإداري المعدّل وتسجيله.')}><ClipboardCheck className="size-4" />تأكيد التنفيذ</button>
            </div>
          </div> : null}

          {selected.executiveDecision === 'rejected' ? <div className="mt-5 rounded-2xl border border-[var(--danger)]/30 bg-[var(--danger-soft)] p-4">
            <div className="flex items-center gap-2"><AlertTriangle className="size-5 text-[var(--danger)]" aria-hidden="true" /><h4 className="font-bold text-[var(--danger)]">رفض المدير التنفيذي الإجراء المقترح</h4></div>
            {selected.executiveDecisionReason ? <p className="mt-2 text-sm leading-7">{selected.executiveDecisionReason}</p> : null}
          </div> : null}
        </section> : null}

        {selected.decision && selected.status !== 'closed' ? <section className="card p-5"><h3 className="text-lg font-black">الاعتذار أو التسوية</h3><div className="mt-4 grid gap-3 md:grid-cols-2"><select className="input" aria-label="نوع التسوية" value={settlement.type} onChange={(event) => setSettlement({ ...settlement, type: event.target.value })}><option value="verbal_apology">اعتذار شفهي</option><option value="written_apology">اعتذار مكتوب</option><option value="group_apology">اعتذار في مجموعة العمل</option><option value="undertaking">تعهد</option><option value="mediation">تسوية</option><option value="follow_up">جلسة متابعة</option><option value="other">أخرى</option></select><select className="input" aria-label="المطلوب منه التنفيذ" value={settlement.fromId} onChange={(event) => setSettlement({ ...settlement, fromId: event.target.value })}><option value="">المطلوب منه التنفيذ</option>{selected.parties.map((party) => <option key={party.id} value={party.employeeId}>{party.name}</option>)}</select><select className="input" aria-label="المستفيد" value={settlement.toId} onChange={(event) => setSettlement({ ...settlement, toId: event.target.value })}><option value="">المستفيد</option>{selected.parties.map((party) => <option key={party.id} value={party.employeeId}>{party.name}</option>)}</select><input className="input" type="datetime-local" aria-label="موعد التنفيذ" value={settlement.dueAt} onChange={(event) => setSettlement({ ...settlement, dueAt: event.target.value })} /><textarea className="input min-h-20" placeholder="نص الاعتذار أو تفاصيل التسوية" value={settlement.text} onChange={(event) => setSettlement({ ...settlement, text: event.target.value })} /><input className="input" placeholder="مكان نشر الاعتذار (إن وجد)" value={settlement.place} onChange={(event) => setSettlement({ ...settlement, place: event.target.value })} /></div><button className="btn-secondary mt-3" disabled={!settlement.fromId || commands.recordSettlement.isPending} onClick={() => void run(() => commands.recordSettlement.mutateAsync({ p_case_id: selected.id, p_type: settlement.type, p_from: settlement.fromId, p_to: settlement.toId || null, p_text: settlement.text || null, p_publication_place: settlement.place || null, p_due_at: settlement.dueAt ? new Date(settlement.dueAt).toISOString() : null }), 'تم تسجيل التسوية وإسناد تنفيذها دون إرسال أي نص تلقائيًا.')}><Scale className="size-4" />تسجيل التسوية</button></section> : null}

        {selected.actions.length ? <section className="card p-5"><h3 className="text-lg font-black">متابعة تنفيذ القرارات</h3><div className="mt-4 space-y-3">{selected.actions.map((action) => <article key={action.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><strong>{action.type}</strong><p className="muted mt-1 text-sm">المسؤول: {action.assignedName ?? '—'} · الموعد: {formatDate(action.dueAt)}</p></div><StatusBadge value={action.status ?? 'pending'} /></div>{action.note ? <p className="mt-3 text-sm leading-7">{action.note}</p> : null}{action.status !== 'completed' ? <div className="mt-3 flex flex-col gap-2 sm:flex-row"><input className="input flex-1" placeholder="إثبات التنفيذ" value={proofs[action.id] ?? ''} onChange={(event) => setProofs({ ...proofs, [action.id]: event.target.value })} /><button className="btn-primary" disabled={(proofs[action.id] ?? '').trim().length < 5 || commands.completeAction.isPending} onClick={() => void run(() => commands.completeAction.mutateAsync({ p_action_id: action.id, p_proof: proofs[action.id] }), 'تم تسجيل إثبات التنفيذ. يمكن إغلاق القضية بعد اكتمال جميع الإجراءات.')}><UserCheck className="size-4" />تأكيد التنفيذ</button></div> : <p className="mt-3 rounded-xl bg-[var(--success-soft)] p-3 text-sm text-[var(--success)]">إثبات التنفيذ: {action.proof}</p>}</article>)}</div></section> : null}

        {selected.appeals.length ? <section className="card p-5"><h3 className="text-lg font-black">الاعتراضات</h3><div className="mt-4 space-y-3">{selected.appeals.map((appeal) => <article key={appeal.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex items-center justify-between gap-3"><strong>{appeal.appellantName}</strong><StatusBadge value={appeal.status} /></div><p className="mt-3 leading-7">{appeal.reason}</p>{['submitted', 'under_review'].includes(appeal.status) ? <div className="mt-3"><textarea className="input min-h-20" placeholder="سبب القرار في الاعتراض" value={appealResolution[appeal.id] ?? ''} onChange={(event) => setAppealResolution({ ...appealResolution, [appeal.id]: event.target.value })} /><div className="mt-2 flex gap-2"><button className="btn-primary" disabled={(appealResolution[appeal.id] ?? '').trim().length < 10} onClick={() => void run(() => commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'accepted', p_resolution: appealResolution[appeal.id] }), 'تم قبول الاعتراض وإعادة فتح المشكلة.') }><RotateCcw className="size-4" />قبول وإعادة فتح</button><button className="btn-secondary" disabled={(appealResolution[appeal.id] ?? '').trim().length < 10} onClick={() => void run(() => commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'rejected', p_resolution: appealResolution[appeal.id] }), 'تم رفض الاعتراض مع تسجيل السبب.')}>رفض الاعتراض</button></div></div> : appeal.resolution ? <p className="muted mt-3">النتيجة: {appeal.resolution}</p> : null}</article>)}</div></section> : null}

        <section className="card p-5"><h3 className="text-lg font-black">الأطراف وحالة الإشعار</h3><div className="mt-4 grid gap-3 md:grid-cols-2">{selected.parties.map((party) => <article key={party.id} className="rounded-2xl bg-[var(--surface-muted)] p-4"><div className="flex items-center justify-between"><strong>{party.name}</strong><StatusBadge value={party.notificationStatus} /></div><p className="muted mt-1 text-xs">{party.type} · {party.statementSubmittedAt ? `قدّم إفادته ${formatDate(party.statementSubmittedAt)}` : 'لم يقدم إفادة'}</p></article>)}</div></section>
      </div> : <div className="card grid min-h-[420px] place-items-center p-8"><EmptyState title="اختر قضية" description="اختر قضية من القائمة لمراجعة تفاصيلها وإدارة مسارها." /></div>}
    </section>

    {(summary?.critical ?? 0) > 0 ? <div role="alert" className="fixed bottom-5 left-5 z-30 flex max-w-sm items-start gap-3 rounded-2xl border border-[var(--danger)]/30 bg-[var(--surface)] p-4 shadow-xl"><AlertTriangle className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" aria-hidden="true" /><div><strong>توجد قضايا حرجة</strong><p className="muted mt-1 text-xs">راجعها فورًا وحدد ما إذا كانت تحتاج تصعيدًا للمدير التنفيذي.</p></div></div> : null}
  </div>;
}

function Info({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-[var(--surface-muted)] p-3"><span className="muted block text-xs">{label}</span><strong className="mt-1 block text-sm leading-6">{value}</strong></div>;
}
