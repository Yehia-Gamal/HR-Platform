import type { KpiEvaluationForm } from '@ahla/shared-contracts';
import { AlertTriangle, CalendarCheck, CheckCircle2, Link2, RefreshCcw, Save, ShieldCheck, Target } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAdvanceKpi, useKpiEvaluationForm, useKpiFormCommands } from './usePerformance';
import { kpiWorkflowStatusText } from './workflowStatus';
import { safeErrorMessage } from '../../core/errorMapper';

type ScoreDraft = Record<string, { score: number; note: string }>;
type ComplianceDraft = Record<'PRAYER' | 'HALAQA', { required: number; actual: number; exempt: number; cancelled: number; note: string }>;

const stageLabel: Record<string, string> = {
  self: 'التقييم الذاتي',
  manager_review: 'مراجعة المدير المباشر',
  hr_review: 'مراجعة HR',
  finalized: 'مدرج في التقرير الشهري',
  closed: 'مغلق',
  archived: 'مؤرشف',
};

const tabCls = (active: boolean) => `rounded-lg px-4 py-2 text-sm font-bold transition ${active ? 'bg-white shadow text-brand dark:bg-[var(--surface)]' : 'text-[var(--text-muted)] hover:text-[var(--text)]'}`;

export function KpiEvaluationEditor({ evaluationId, onDone }: { evaluationId: string; onDone: () => void }) {
  const query = useKpiEvaluationForm(evaluationId);
  const commands = useKpiFormCommands(evaluationId);
  const advance = useAdvanceKpi();
  const form = query.data;
  const [note, setNote] = useState('');
  const [scores, setScores] = useState<ScoreDraft>({});
  const [compliance, setCompliance] = useState<ComplianceDraft>({
    PRAYER: { required: 0, actual: 0, exempt: 0, cancelled: 0, note: '' },
    HALAQA: { required: 0, actual: 0, exempt: 0, cancelled: 0, note: '' },
  });
  const [session, setSession] = useState({ heldAt: '', mode: 'ONSITE', discussionSummary: '', strengths: '', improvementPoints: '', nextMonthGoals: '', employeeNotes: '', managerNotes: '', employeeAttended: true, managerAttended: true });
  const [newGoal, setNewGoal] = useState({ title: '', description: '', target: 1, achieved: 0, unit: 'عدد', weight: 10, dueDate: '', evidence: '', employeeNote: '', managerNote: '', status: 'NOT_STARTED' });
  const [goalDrafts, setGoalDrafts] = useState<Record<string, { achieved: number; evidence: string; employeeNote: string; status: string }>>({});
  const [evidenceDraft, setEvidenceDraft] = useState({ criterionId: '', title: '', url: '', description: '' });
  const [tab, setTab] = useState<'goals' | 'criteria' | 'compliance' | 'session'>('goals');

  useEffect(() => {
    if (!form) return;
    setScores(Object.fromEntries(form.criteria.filter((item) => item.editable).map((item) => [item.id, { score: item.stageScores[form.editableStage ?? '']?.score ?? item.stageScores.self?.score ?? item.effectiveScore ?? 0, note: item.stageScores[form.editableStage ?? '']?.note ?? '' }])));
    setGoalDrafts(Object.fromEntries(form.goals.map((goal) => [goal.id, { achieved: goal.achievedValue, evidence: goal.evidenceSource ?? '', employeeNote: goal.employeeNote ?? '', status: goal.status }])));
    if (form.session) setSession({
      heldAt: form.session.heldAt?.slice(0, 16) ?? '', mode: form.session.mode ?? 'ONSITE', discussionSummary: form.session.discussionSummary ?? '', strengths: form.session.strengths ?? '', improvementPoints: form.session.improvementPoints ?? '', nextMonthGoals: form.session.nextMonthGoals ?? '', employeeNotes: form.session.employeeNotes ?? '', managerNotes: form.session.managerNotes ?? '', employeeAttended: form.session.employeeAttended, managerAttended: form.session.managerAttended,
    });
    setCompliance((current) => {
      const next = { ...current };
      for (const item of form.compliance) next[item.metric] = { required: item.requiredCount, actual: item.actualCount, exempt: item.exemptCount, cancelled: item.cancelledCount, note: item.note ?? '' };
      return next;
    });
  }, [form?.lastUpdatedAt]);

  const pending = advance.isPending || Object.values(commands).some((mutation) => mutation.isPending);
  const editableCriteria = useMemo(() => form?.criteria.filter((item) => item.editable) ?? [], [form]);

  if (query.isLoading) return <div className="card grid min-h-64 place-items-center"><RefreshCcw className="size-6 animate-spin text-brand" aria-hidden="true" /></div>;
  if (query.isError || !form) return <ErrorState title="تعذر فتح نموذج التقييم" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />;

  const saveGoal = async (goal: KpiEvaluationForm['goals'][number]) => {
    const draft = goalDrafts[goal.id];
    try {
      await commands.saveGoal.mutateAsync({ p_evaluation_id: form.id, p_goal_id: goal.id, p_title: goal.title, p_description: goal.description, p_target_value: goal.targetValue, p_achieved_value: draft.achieved, p_unit: goal.unit, p_weight: goal.weight, p_due_date: goal.dueDate, p_evidence_source: draft.evidence || null, p_employee_note: draft.employeeNote || null, p_manager_note: goal.managerNote, p_status: draft.status });
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };

  const createGoal = async () => {
    try {
      await commands.saveGoal.mutateAsync({ p_evaluation_id: form.id, p_goal_id: null, p_title: newGoal.title, p_description: newGoal.description || null, p_target_value: newGoal.target, p_achieved_value: newGoal.achieved, p_unit: newGoal.unit, p_weight: newGoal.weight, p_due_date: newGoal.dueDate || null, p_evidence_source: newGoal.evidence || null, p_employee_note: newGoal.employeeNote || null, p_manager_note: newGoal.managerNote || null, p_status: newGoal.status });
      setNewGoal({ title: '', description: '', target: 1, achieved: 0, unit: 'عدد', weight: 10, dueDate: '', evidence: '', employeeNote: '', managerNote: '', status: 'NOT_STARTED' });
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };

  const saveSession = async () => {
    try {
      await commands.saveSession.mutateAsync({ p_evaluation_id: form.id, p_session: { ...session, heldAt: session.heldAt ? new Date(session.heldAt).toISOString() : null, scheduledAt: null } });
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };
  const saveCompliance = async (metric: 'PRAYER' | 'HALAQA') => {
    const value = compliance[metric];
    try {
      await commands.saveCompliance.mutateAsync({ p_evaluation_id: form.id, p_metric: metric, p_required: value.required, p_actual: value.actual, p_exempt: value.exempt, p_cancelled: value.cancelled, p_note: value.note || null });
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };
  const addEvidence = async () => {
    try {
      await commands.addEvidence.mutateAsync({ p_evaluation_id: form.id, p_criterion_id: evidenceDraft.criterionId || null, p_type: evidenceDraft.url ? 'link' : 'note', p_title: evidenceDraft.title, p_description: evidenceDraft.description || null, p_storage_path: null, p_external_url: evidenceDraft.url || null });
      setEvidenceDraft({ criterionId: '', title: '', url: '', description: '' });
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };
  const submit = async () => {
    if (!form.editableStage) return;
    try {
      await advance.mutateAsync({
        evaluationId: form.id,
        action: form.editableStage as 'self' | 'hr_review' | 'manager_review',
        note,
        scores: ['self', 'manager_review'].includes(form.editableStage) ? editableCriteria.map((criterion) => ({ criterion_id: criterion.id, score: scores[criterion.id]?.score ?? 0, note: scores[criterion.id]?.note ?? '' })) : undefined,
      });
      onDone();
    } catch { /* mutation error surfaced via mutation.isError state */ }
  };

  return <section className="card overflow-hidden">
    <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[var(--border)] p-5">
      <div><div className="flex flex-wrap items-center gap-2"><StatusBadge value={form.currentStage} /><span className="muted text-xs">{kpiWorkflowStatusText(form.workflowStatus)}</span></div><div className="mt-2 flex items-center gap-3"><UserAvatar displayName={form.employeeName} /><div><h2 className="text-xl font-black">{form.employeeName}</h2><p className="muted text-sm">{form.employeeCode ?? 'بدون كود'} · {stageLabel[form.currentStage]}</p></div></div></div>
      <div className="text-start"><p className="text-2xl font-black">{form.finalScore ?? form.criteria.reduce((sum, item) => sum + (item.effectiveScore ?? 0), 0)} / 100</p><p className="muted text-xs">الموعد: {form.cycle.effectiveDeadline ? new Date(form.cycle.effectiveDeadline).toLocaleString('ar-EG') : '—'}</p><button className="btn-secondary mt-2" onClick={onDone}>إغلاق التفاصيل</button></div>
    </header>

    <div className="p-5">
      <nav className="mb-5 flex flex-wrap gap-1 rounded-xl bg-[var(--surface-muted)] p-1" role="tablist">
        <button role="tab" aria-selected={tab === 'goals'} className={tabCls(tab === 'goals')} onClick={() => setTab('goals')}>الأهداف</button>
        <button role="tab" aria-selected={tab === 'criteria'} className={tabCls(tab === 'criteria')} onClick={() => setTab('criteria')}>المعايير</button>
        {form.editableStage === 'hr_review' ? <button role="tab" aria-selected={tab === 'compliance'} className={tabCls(tab === 'compliance')} onClick={() => setTab('compliance')}>الالتزام</button> : null}
        {form.editableStage === 'manager_review' ? <button role="tab" aria-selected={tab === 'session'} className={tabCls(tab === 'session')} onClick={() => setTab('session')}>الجلسة</button> : null}
      </nav>

      <div className="space-y-6">
        {tab === 'goals' && <>
          <section>
            <div className="mb-3 flex items-center justify-between"><h3 className="flex items-center gap-2 font-black"><Target className="size-5 text-brand" aria-hidden="true" />الأهداف والأدلة</h3><strong>{form.goals.reduce((sum, goal) => sum + goal.weight, 0)} وزن</strong></div>
            <div className="grid gap-3 lg:grid-cols-2">{form.goals.map((goal) => {
              const draft = goalDrafts[goal.id];
              return <article className="rounded-2xl border border-[var(--border)] p-4" key={goal.id}><div className="flex justify-between gap-3"><div><strong>{goal.title}</strong><p className="muted text-xs">المستهدف {goal.targetValue} {goal.unit} · الوزن {goal.weight}</p></div><span className="font-black text-brand">{goal.calculatedScore}/{goal.weight}</span></div>{draft && form.editableStage === 'self' ? <div className="mt-3 grid gap-2"><label className="text-xs font-bold">المحقق<input className="input mt-1" type="number" min={0} value={draft.achieved} onChange={(event) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, achieved: Number(event.target.value) } }))} /></label><select className="input" value={draft.status} onChange={(event) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, status: event.target.value } }))}><option value="NOT_STARTED">لم يبدأ</option><option value="IN_PROGRESS">قيد التنفيذ</option><option value="COMPLETED">مكتمل</option><option value="PARTIALLY_COMPLETED">مكتمل جزئيًا</option><option value="BLOCKED">متعثر</option></select><input className="input" placeholder="مصدر إثبات الإنجاز" value={draft.evidence} onChange={(event) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, evidence: event.target.value } }))} /><textarea className="input" placeholder="ملاحظتك" value={draft.employeeNote} onChange={(event) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, employeeNote: event.target.value } }))} /><button className="btn-secondary" disabled={pending} onClick={() => void saveGoal(goal)}><Save className="size-4" aria-hidden="true" />حفظ تقدم الهدف</button></div> : <p className="muted mt-3 text-sm">المحقق: {goal.achievedValue} {goal.unit} · {goal.status}</p>}</article>;
            })}</div>
            {form.editableStage === 'manager_review' ? <div className="mt-4 rounded-2xl bg-[var(--surface-muted)] p-4"><h4 className="font-black">إضافة هدف شهري</h4><div className="mt-3 grid gap-2 md:grid-cols-4"><input className="input md:col-span-2" placeholder="اسم الهدف" value={newGoal.title} onChange={(event) => setNewGoal({ ...newGoal, title: event.target.value })} /><input className="input" type="number" min={0.01} value={newGoal.target} onChange={(event) => setNewGoal({ ...newGoal, target: Number(event.target.value) })} /><input className="input" type="number" min={0.01} max={40} value={newGoal.weight} onChange={(event) => setNewGoal({ ...newGoal, weight: Number(event.target.value) })} /><input className="input" placeholder="وحدة القياس" value={newGoal.unit} onChange={(event) => setNewGoal({ ...newGoal, unit: event.target.value })} /><input className="input" type="date" value={newGoal.dueDate} onChange={(event) => setNewGoal({ ...newGoal, dueDate: event.target.value })} /><button className="btn-secondary md:col-span-2" disabled={pending || newGoal.title.trim().length < 3} onClick={() => void createGoal()}>إضافة الهدف</button></div></div> : null}
          </section>

          {['self', 'manager_review'].includes(form.editableStage ?? '') ? <section className="rounded-2xl border border-[var(--border)] p-4"><h3 className="flex items-center gap-2 font-black"><Link2 className="size-5 text-brand" aria-hidden="true" />الأدلة</h3><div className="mt-3 grid gap-2 md:grid-cols-2"><select className="input" value={evidenceDraft.criterionId} onChange={(event) => setEvidenceDraft({ ...evidenceDraft, criterionId: event.target.value })}><option value="">دليل عام</option>{form.criteria.map((criterion) => <option key={criterion.id} value={criterion.id}>{criterion.name}</option>)}</select><input className="input" placeholder="عنوان الدليل" value={evidenceDraft.title} onChange={(event) => setEvidenceDraft({ ...evidenceDraft, title: event.target.value })} /><input className="input" type="url" placeholder="رابط اختياري" value={evidenceDraft.url} onChange={(event) => setEvidenceDraft({ ...evidenceDraft, url: event.target.value })} /><input className="input" placeholder="وصف الدليل" value={evidenceDraft.description} onChange={(event) => setEvidenceDraft({ ...evidenceDraft, description: event.target.value })} /><button className="btn-secondary md:col-span-2" disabled={pending || evidenceDraft.title.trim().length < 3} onClick={() => void addEvidence()}>إضافة الدليل</button></div>{form.evidence.length ? <ul className="mt-3 list-disc pe-5 text-sm">{form.evidence.map((item) => <li key={item.id}>{item.title}{item.externalUrl ? <> — <a className="text-brand underline" href={item.externalUrl} target="_blank" rel="noreferrer">فتح</a></> : null}</li>)}</ul> : null}</section> : null}
        </>}

        {tab === 'criteria' && <section><h3 className="mb-3 flex items-center gap-2 font-black"><ShieldCheck className="size-5 text-brand" aria-hidden="true" />البنود السبعة</h3><div className="grid gap-3 lg:grid-cols-2">{form.criteria.map((criterion) => <article className="rounded-2xl border border-[var(--border)] p-4" key={criterion.id}><div className="flex items-start justify-between gap-3"><div><strong>{criterion.name}</strong><p className="muted mt-1 text-xs">{criterion.description}</p></div><span className="whitespace-nowrap text-lg font-black">{criterion.effectiveScore ?? '—'} / {criterion.maxScore}</span></div>{criterion.stageScores.self ? <p className="muted mt-2 text-xs">المقترح الذاتي: {criterion.stageScores.self.score ?? '—'}{criterion.stageScores.self.note ? ` · ${criterion.stageScores.self.note}` : ''}</p> : null}{criterion.editable && scores[criterion.id] && form.editableStage !== 'hr_review' ? <div className="mt-3 grid gap-2"><input className="input" type="number" min={0} max={criterion.maxScore} step="0.25" value={scores[criterion.id].score} onChange={(event) => setScores((old) => ({ ...old, [criterion.id]: { ...old[criterion.id], score: Number(event.target.value) } }))} /><textarea className="input" placeholder={form.editableStage === 'self' ? 'ملاحظتك ودليلك على هذا البند' : 'تعليق المدير'} value={scores[criterion.id].note} onChange={(event) => setScores((old) => ({ ...old, [criterion.id]: { ...old[criterion.id], note: event.target.value } }))} /></div> : null}</article>)}</div></section>}

        {tab === 'compliance' && form.editableStage === 'hr_review' && <section className="grid gap-3 md:grid-cols-2">{(['PRAYER', 'HALAQA'] as const).map((metric) => { const value = compliance[metric]; return <article className="rounded-2xl bg-[var(--surface-muted)] p-4" key={metric}><h3 className="font-black">{metric === 'PRAYER' ? 'الصلاة في المسجد' : 'حلقة الشيخ وليد يوسف'}</h3><div className="mt-3 grid grid-cols-2 gap-2"><input className="input" type="number" min={0} placeholder="المطلوب" value={value.required} onChange={(event) => setCompliance({ ...compliance, [metric]: { ...value, required: Number(event.target.value) } })} /><input className="input" type="number" min={0} placeholder="الفعلي" value={value.actual} onChange={(event) => setCompliance({ ...compliance, [metric]: { ...value, actual: Number(event.target.value) } })} /><input className="input" type="number" min={0} placeholder="أعذار معتمدة" value={value.exempt} onChange={(event) => setCompliance({ ...compliance, [metric]: { ...value, exempt: Number(event.target.value) } })} /><input className="input" type="number" min={0} placeholder="ملغي إداريًا" value={value.cancelled} onChange={(event) => setCompliance({ ...compliance, [metric]: { ...value, cancelled: Number(event.target.value) } })} /></div><input className="input mt-2" placeholder="ملاحظة HR" value={value.note} onChange={(event) => setCompliance({ ...compliance, [metric]: { ...value, note: event.target.value } })} /><button className="btn-secondary mt-2" onClick={() => void saveCompliance(metric)}>حساب واعتماد الدرجة</button></article>; })}</section>}

        {tab === 'session' && form.editableStage === 'manager_review' && <section className="rounded-2xl border border-[var(--border)] p-4"><h3 className="flex items-center gap-2 font-black"><CalendarCheck className="size-5 text-brand" aria-hidden="true" />جلسة الموظف والمدير</h3><div className="mt-3 grid gap-3 md:grid-cols-2"><label className="text-xs font-bold">وقت الجلسة<input className="input mt-1" type="datetime-local" value={session.heldAt} onChange={(event) => setSession({ ...session, heldAt: event.target.value })} /></label><label className="text-xs font-bold">الطريقة<select className="input mt-1" value={session.mode} onChange={(event) => setSession({ ...session, mode: event.target.value })}><option value="ONSITE">حضوريًا</option><option value="REMOTE">عن بُعد</option></select></label><textarea className="input" placeholder="ملخص المناقشة" value={session.discussionSummary} onChange={(event) => setSession({ ...session, discussionSummary: event.target.value })} /><textarea className="input" placeholder="نقاط القوة" value={session.strengths} onChange={(event) => setSession({ ...session, strengths: event.target.value })} /><textarea className="input" placeholder="نقاط التحسين" value={session.improvementPoints} onChange={(event) => setSession({ ...session, improvementPoints: event.target.value })} /><textarea className="input" placeholder="أهداف الشهر القادم" value={session.nextMonthGoals} onChange={(event) => setSession({ ...session, nextMonthGoals: event.target.value })} /></div><button className="btn-secondary mt-3" disabled={pending} onClick={() => void saveSession()}><Save className="size-4" aria-hidden="true" />حفظ الجلسة</button></section>}

        {form.validationErrors.length ? <section className="rounded-2xl border border-amber-300 bg-amber-50 p-4 text-amber-950"><h3 className="flex items-center gap-2 font-black"><AlertTriangle className="size-5" aria-hidden="true" />متطلبات الاعتماد غير المكتملة</h3><ul className="mt-2 list-disc space-y-1 pe-5 text-sm">{form.validationErrors.map((item) => <li key={item}>{item}</li>)}</ul></section> : <p className="flex items-center gap-2 text-green-700"><CheckCircle2 className="size-5" aria-hidden="true" />كل متطلبات الاعتماد مكتملة.</p>}

        {form.editableStage ? <section className="rounded-2xl border border-[var(--border)] p-4"><label className="text-sm font-bold">ملاحظة المرحلة<textarea className="input mt-2 min-h-20" value={note} onChange={(event) => setNote(event.target.value)} /></label><div className="mt-3 flex flex-wrap gap-2">{form.editableStage !== 'self' ? <button className="btn-secondary" disabled={pending || note.trim().length < 5} onClick={() => { const target = form.editableStage === 'hr_review' ? 'self' : form.editableStage === 'manager_review' ? 'hr_review' : 'self'; commands.returnStage.mutate({ p_evaluation_id: form.id, p_target_stage: target, p_note: note }); }}>إعادة للتصحيح</button> : null}<button className="btn-primary" disabled={pending} onClick={() => void submit()}><CheckCircle2 className="size-4" aria-hidden="true" />{form.editableStage === 'manager_review' ? 'اعتماد النتيجة وإدراجها في التقرير' : 'اعتماد المرحلة وإرسال'}</button></div></section> : null}
      </div>
    </div>
  </section>;
}
