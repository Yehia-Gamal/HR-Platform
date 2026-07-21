import type { KpiEvaluationForm } from '@ahla/shared-contracts';
import { AlertTriangle, CalendarCheck, CheckCircle2, RefreshCcw, Save, ShieldCheck, Target } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAdvanceKpi, useKpiEvaluationForm, useKpiFormCommands } from './usePerformance';
import { kpiWorkflowStatusText } from './workflowStatus';

type ScoreDraft = Record<string, { score: number; note: string }>;
type ComplianceDraft = Record<'PRAYER' | 'HALAQA', { required: number; actual: number; exempt: number; cancelled: number; note: string }>;

const stageLabel: Record<string, string> = {
  self: 'إدخال الموظف', manager: 'تقييم المدير', hr: 'اعتماد HR', acknowledgement: 'اطلاع الموظف',
  secretary: 'مراجعة السكرتير التنفيذي', executive: 'اعتماد المدير التنفيذي', finalized: 'معتمد', closed: 'مؤرشف',
};

export function KpiEvaluationEditor({ evaluationId, onDone }: { evaluationId: string; onDone: () => void }) {
  const query = useKpiEvaluationForm(evaluationId);
  const commands = useKpiFormCommands(evaluationId);
  const advance = useAdvanceKpi();
  const form = query.data;
  const [note, setNote] = useState('');
  const [appeal, setAppeal] = useState('');
  const [scores, setScores] = useState<ScoreDraft>({});
  const [compliance, setCompliance] = useState<ComplianceDraft>({
    PRAYER: { required: 0, actual: 0, exempt: 0, cancelled: 0, note: '' },
    HALAQA: { required: 0, actual: 0, exempt: 0, cancelled: 0, note: '' },
  });
  const [session, setSession] = useState({ heldAt: '', mode: 'ONSITE', discussionSummary: '', strengths: '', improvementPoints: '', nextMonthGoals: '', employeeNotes: '', managerNotes: '', employeeAttended: true, managerAttended: true });
  const [newGoal, setNewGoal] = useState({ title: '', description: '', target: 1, achieved: 0, unit: 'عدد', weight: 10, dueDate: '', evidence: '', employeeNote: '', managerNote: '', status: 'NOT_STARTED' });
  const [goalDrafts, setGoalDrafts] = useState<Record<string, { achieved: number; evidence: string; employeeNote: string; status: string }>>({});
  const [override, setOverride] = useState<Record<string, { score: number; reason: string }>>({});

  useEffect(() => {
    if (!form) return;
    setScores(Object.fromEntries(form.criteria.filter((item) => item.editable).map((item) => [item.id, { score: item.effectiveScore ?? 0, note: item.stageScores[form.editableStage ?? '']?.note ?? '' }])));
    setGoalDrafts(Object.fromEntries(form.goals.map((goal) => [goal.id, { achieved: goal.achievedValue, evidence: goal.evidenceSource ?? '', employeeNote: goal.employeeNote ?? '', status: goal.status }])));
    if (form.session) setSession({
      heldAt: form.session.heldAt?.slice(0, 16) ?? '', mode: form.session.mode ?? 'ONSITE', discussionSummary: form.session.discussionSummary ?? '', strengths: form.session.strengths ?? '', improvementPoints: form.session.improvementPoints ?? '', nextMonthGoals: form.session.nextMonthGoals ?? '', employeeNotes: form.session.employeeNotes ?? '', managerNotes: form.session.managerNotes ?? '', employeeAttended: form.session.employeeAttended, managerAttended: form.session.managerAttended,
    });
    const nextCompliance = { ...compliance };
    for (const item of form.compliance) nextCompliance[item.metric] = { required: item.requiredCount, actual: item.actualCount, exempt: item.exemptCount, cancelled: item.cancelledCount, note: item.note ?? '' };
    setCompliance(nextCompliance);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form?.lastUpdatedAt]);

  const pending = advance.isPending || Object.values(commands).some((mutation) => mutation.isPending);
  const manualCriteria = useMemo(() => form?.criteria.filter((item) => item.editable) ?? [], [form]);

  if (query.isLoading) return <div className="card grid min-h-64 place-items-center"><RefreshCcw className="size-6 animate-spin text-brand" /></div>;
  if (query.isError || !form) return <EmptyState title="تعذر فتح نموذج التقييم" description={query.error instanceof Error ? query.error.message : 'أعد المحاولة.'} />;

  const saveGoal = async (goal: KpiEvaluationForm['goals'][number]) => {
    const draft = goalDrafts[goal.id];
    await commands.saveGoal.mutateAsync({ p_evaluation_id: form.id, p_goal_id: goal.id, p_title: goal.title, p_description: goal.description, p_target_value: goal.targetValue, p_achieved_value: draft.achieved, p_unit: goal.unit, p_weight: goal.weight, p_due_date: goal.dueDate, p_evidence_source: draft.evidence || null, p_employee_note: draft.employeeNote || null, p_manager_note: goal.managerNote, p_status: draft.status });
  };

  const createGoal = async () => {
    await commands.saveGoal.mutateAsync({ p_evaluation_id: form.id, p_goal_id: null, p_title: newGoal.title, p_description: newGoal.description || null, p_target_value: newGoal.target, p_achieved_value: newGoal.achieved, p_unit: newGoal.unit, p_weight: newGoal.weight, p_due_date: newGoal.dueDate || null, p_evidence_source: newGoal.evidence || null, p_employee_note: newGoal.employeeNote || null, p_manager_note: newGoal.managerNote || null, p_status: newGoal.status });
    setNewGoal({ title: '', description: '', target: 1, achieved: 0, unit: 'عدد', weight: 10, dueDate: '', evidence: '', employeeNote: '', managerNote: '', status: 'NOT_STARTED' });
  };

  const saveSession = () => commands.saveSession.mutateAsync({ p_evaluation_id: form.id, p_session: { ...session, heldAt: session.heldAt ? new Date(session.heldAt).toISOString() : null, scheduledAt: null } });
  const saveCompliance = async (metric: 'PRAYER' | 'HALAQA') => {
    const value = compliance[metric];
    await commands.saveCompliance.mutateAsync({ p_evaluation_id: form.id, p_metric: metric, p_required: value.required, p_actual: value.actual, p_exempt: value.exempt, p_cancelled: value.cancelled, p_note: value.note || null });
  };
  const submit = async () => {
    if (form.editableStage === 'acknowledgement') {
      await commands.acknowledge.mutateAsync({ p_evaluation_id: form.id, p_note: note || null, p_appeal_reason: appeal || null });
    } else if (form.editableStage) {
      await advance.mutateAsync({ evaluationId: form.id, action: form.editableStage as 'self' | 'manager' | 'hr' | 'secretary' | 'executive', note, scores: form.editableStage === 'manager' ? manualCriteria.map((criterion) => ({ criterion_id: criterion.id, score: scores[criterion.id]?.score ?? 0, note: scores[criterion.id]?.note ?? '' })) : undefined });
    }
    onDone();
  };

  return <section className="card overflow-hidden">
    <header className="flex flex-wrap items-start justify-between gap-4 border-b border-[var(--border)] p-5">
      <div><div className="flex flex-wrap items-center gap-2"><StatusBadge value={form.currentStage} /><span className="muted text-xs">{kpiWorkflowStatusText(form.workflowStatus)}</span></div><h2 className="mt-2 text-xl font-black">{form.employeeName}</h2><p className="muted text-sm">{form.employeeCode ?? 'بدون كود'} · {stageLabel[form.currentStage]}</p></div>
      <div className="text-left"><p className="text-2xl font-black">{form.finalScore ?? form.criteria.reduce((sum, item) => sum + (item.effectiveScore ?? 0), 0)} / 100</p><p className="muted text-xs">الموعد: {form.cycle.effectiveDeadline ? new Date(form.cycle.effectiveDeadline).toLocaleString('ar-EG') : '—'}</p><button className="btn-secondary mt-2" onClick={onDone}>إغلاق التفاصيل</button></div>
    </header>

    <div className="space-y-6 p-5">
      <section><div className="mb-3 flex items-center justify-between"><h3 className="flex items-center gap-2 font-black"><Target className="size-5 text-brand" />الأهداف — 40 درجة</h3><strong>{form.goals.reduce((sum, goal) => sum + goal.weight, 0)} / 40 وزن</strong></div>
        <div className="grid gap-3 lg:grid-cols-2">{form.goals.map((goal) => { const draft = goalDrafts[goal.id]; return <article className="rounded-2xl border border-[var(--border)] p-4" key={goal.id}><div className="flex justify-between gap-3"><div><strong>{goal.title}</strong><p className="muted text-xs">المستهدف {goal.targetValue} {goal.unit} · الوزن {goal.weight}</p></div><span className="font-black text-brand">{goal.calculatedScore}/{goal.weight}</span></div>{draft && form.editableStage === 'self' ? <div className="mt-3 grid gap-2"><label className="text-xs font-bold">المحقق<input className="input mt-1" type="number" min={0} value={draft.achieved} onChange={(e) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, achieved: Number(e.target.value) } }))} /></label><select className="input" value={draft.status} onChange={(e) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, status: e.target.value } }))}><option value="NOT_STARTED">لم يبدأ</option><option value="IN_PROGRESS">قيد التنفيذ</option><option value="COMPLETED">مكتمل</option><option value="PARTIALLY_COMPLETED">مكتمل جزئيًا</option><option value="BLOCKED">متعثر</option></select><input className="input" placeholder="مصدر إثبات الإنجاز" value={draft.evidence} onChange={(e) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, evidence: e.target.value } }))} /><textarea className="input" placeholder="ملاحظتك" value={draft.employeeNote} onChange={(e) => setGoalDrafts((old) => ({ ...old, [goal.id]: { ...draft, employeeNote: e.target.value } }))} /><button className="btn-secondary" disabled={pending} onClick={() => void saveGoal(goal)}><Save className="size-4" />حفظ تقدم الهدف</button></div> : <p className="muted mt-3 text-sm">المحقق: {goal.achievedValue} {goal.unit} · {goal.status}</p>}</article>; })}</div>
        {form.editableStage === 'manager' ? <div className="mt-4 rounded-2xl bg-[var(--surface-muted)] p-4"><h4 className="font-black">إضافة هدف شهري</h4><div className="mt-3 grid gap-2 md:grid-cols-4"><input className="input md:col-span-2" placeholder="اسم الهدف" value={newGoal.title} onChange={(e) => setNewGoal({ ...newGoal, title: e.target.value })} /><input className="input" type="number" min={0.01} placeholder="المستهدف" value={newGoal.target} onChange={(e) => setNewGoal({ ...newGoal, target: Number(e.target.value) })} /><input className="input" type="number" min={0.01} max={40} placeholder="الوزن" value={newGoal.weight} onChange={(e) => setNewGoal({ ...newGoal, weight: Number(e.target.value) })} /><input className="input" placeholder="وحدة القياس" value={newGoal.unit} onChange={(e) => setNewGoal({ ...newGoal, unit: e.target.value })} /><input className="input" type="date" value={newGoal.dueDate} onChange={(e) => setNewGoal({ ...newGoal, dueDate: e.target.value })} /><button className="btn-secondary md:col-span-2" disabled={pending || newGoal.title.trim().length < 3} onClick={() => void createGoal()}>إضافة الهدف</button></div></div> : null}
      </section>

      {form.editableStage === 'manager' ? <section className="rounded-2xl border border-[var(--border)] p-4"><h3 className="flex items-center gap-2 font-black"><CalendarCheck className="size-5 text-brand" />جلسة الموظف والمدير — إلزامية</h3><div className="mt-3 grid gap-3 md:grid-cols-2"><label className="text-xs font-bold">وقت انعقاد الجلسة<input className="input mt-1" type="datetime-local" value={session.heldAt} onChange={(e) => setSession({ ...session, heldAt: e.target.value })} /></label><label className="text-xs font-bold">طريقة الجلسة<select className="input mt-1" value={session.mode} onChange={(e) => setSession({ ...session, mode: e.target.value })}><option value="ONSITE">حضوريًا</option><option value="REMOTE">عن بُعد</option></select></label><textarea className="input" placeholder="ملخص المناقشة" value={session.discussionSummary} onChange={(e) => setSession({ ...session, discussionSummary: e.target.value })} /><textarea className="input" placeholder="نقاط القوة" value={session.strengths} onChange={(e) => setSession({ ...session, strengths: e.target.value })} /><textarea className="input" placeholder="نقاط التحسين" value={session.improvementPoints} onChange={(e) => setSession({ ...session, improvementPoints: e.target.value })} /><textarea className="input" placeholder="أهداف الشهر القادم" value={session.nextMonthGoals} onChange={(e) => setSession({ ...session, nextMonthGoals: e.target.value })} /><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={session.employeeAttended} onChange={(e) => setSession({ ...session, employeeAttended: e.target.checked })} />حضر الموظف</label><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={session.managerAttended} onChange={(e) => setSession({ ...session, managerAttended: e.target.checked })} />حضر المدير</label></div><button className="btn-secondary mt-3" disabled={pending} onClick={() => void saveSession()}><Save className="size-4" />حفظ بيانات الجلسة</button></section> : null}

      <section><h3 className="mb-3 flex items-center gap-2 font-black"><ShieldCheck className="size-5 text-brand" />الدرجات الرسمية</h3><div className="grid gap-3 lg:grid-cols-2">{form.criteria.map((criterion) => <article className="rounded-2xl border border-[var(--border)] p-4" key={criterion.id}><div className="flex items-start justify-between gap-3"><div><strong>{criterion.name}</strong><p className="muted mt-1 text-xs">{criterion.description}</p></div><span className="whitespace-nowrap text-lg font-black">{criterion.effectiveScore ?? '—'} / {criterion.maxScore}</span></div>{criterion.code === 'ATTENDANCE' && form.attendance ? <div className="mt-3 grid grid-cols-3 gap-2 text-center text-xs"><span>تأخير {form.attendance.lateCount}</span><span>انصراف مبكر {form.attendance.earlyLeaveCount}</span><span>غياب {form.attendance.unexcusedAbsenceCount}</span><span>نقص {form.attendance.shortagePenalty}</span><span>بصمة ناقصة {form.attendance.missingPunchCount}</span><span className={form.attendance.hasPendingItems ? 'text-red-600' : 'text-green-700'}>{form.attendance.hasPendingItems ? 'معلّق' : 'مكتمل'}</span></div> : null}{criterion.editable && scores[criterion.id] ? <div className="mt-3 grid gap-2"><input className="input" type="number" min={0} max={criterion.maxScore} step="0.25" value={scores[criterion.id].score} onChange={(e) => setScores((old) => ({ ...old, [criterion.id]: { ...old[criterion.id], score: Number(e.target.value) } }))} /><textarea className="input" placeholder="تعليق المراجع" value={scores[criterion.id].note} onChange={(e) => setScores((old) => ({ ...old, [criterion.id]: { ...old[criterion.id], note: e.target.value } }))} /></div> : null}{form.editableStage === 'secretary' ? <div className="mt-3 grid gap-2 md:grid-cols-[100px_1fr_auto]"><input className="input" type="number" min={0} max={criterion.maxScore} value={override[criterion.id]?.score ?? criterion.effectiveScore ?? 0} onChange={(e) => setOverride((old) => ({ ...old, [criterion.id]: { score: Number(e.target.value), reason: old[criterion.id]?.reason ?? '' } }))} /><input className="input" placeholder="سبب التعديل الاستثنائي" value={override[criterion.id]?.reason ?? ''} onChange={(e) => setOverride((old) => ({ ...old, [criterion.id]: { score: old[criterion.id]?.score ?? criterion.effectiveScore ?? 0, reason: e.target.value } }))} /><button className="btn-secondary" disabled={(override[criterion.id]?.reason.length ?? 0) < 8} onClick={() => void commands.overrideScore.mutateAsync({ p_evaluation_id: form.id, p_criterion_id: criterion.id, p_score: override[criterion.id]?.score ?? criterion.effectiveScore, p_reason: override[criterion.id]?.reason })}>تعديل موثق</button></div> : null}</article>)}</div></section>

      {form.editableStage === 'hr' ? <section className="grid gap-3 md:grid-cols-2">{(['PRAYER', 'HALAQA'] as const).map((metric) => { const value = compliance[metric]; return <article className="rounded-2xl bg-[var(--surface-muted)] p-4" key={metric}><h3 className="font-black">{metric === 'PRAYER' ? 'الصلاة في المسجد' : 'حلقة الشيخ وليد يوسف'}</h3><div className="mt-3 grid grid-cols-2 gap-2"><label className="text-xs">المطلوب<input className="input mt-1" type="number" min={0} value={value.required} onChange={(e) => setCompliance({ ...compliance, [metric]: { ...value, required: Number(e.target.value) } })} /></label><label className="text-xs">الفعلي<input className="input mt-1" type="number" min={0} value={value.actual} onChange={(e) => setCompliance({ ...compliance, [metric]: { ...value, actual: Number(e.target.value) } })} /></label><label className="text-xs">أعذار معتمدة<input className="input mt-1" type="number" min={0} value={value.exempt} onChange={(e) => setCompliance({ ...compliance, [metric]: { ...value, exempt: Number(e.target.value) } })} /></label><label className="text-xs">ملغي إداريًا<input className="input mt-1" type="number" min={0} value={value.cancelled} onChange={(e) => setCompliance({ ...compliance, [metric]: { ...value, cancelled: Number(e.target.value) } })} /></label></div><input className="input mt-2" placeholder="ملاحظة HR" value={value.note} onChange={(e) => setCompliance({ ...compliance, [metric]: { ...value, note: e.target.value } })} /><button className="btn-secondary mt-2" onClick={() => void saveCompliance(metric)}>حساب واعتماد الدرجة</button></article>; })}</section> : null}

      {form.validationErrors.length ? <section className="rounded-2xl border border-amber-300 bg-amber-50 p-4 text-amber-950"><h3 className="flex items-center gap-2 font-black"><AlertTriangle className="size-5" />متطلبات الاعتماد غير المكتملة</h3><ul className="mt-2 list-disc space-y-1 pr-5 text-sm">{form.validationErrors.map((item) => <li key={item}>{item}</li>)}</ul></section> : <p className="flex items-center gap-2 text-green-700"><CheckCircle2 className="size-5" />كل متطلبات الاعتماد مكتملة.</p>}

      {form.editableStage ? <section className="rounded-2xl border border-[var(--border)] p-4"><label className="text-sm font-bold">ملاحظة المرحلة<textarea className="input mt-2 min-h-20" value={note} onChange={(e) => setNote(e.target.value)} /></label>{form.editableStage === 'acknowledgement' ? <label className="mt-3 block text-sm font-bold">اعتراض اختياري<textarea className="input mt-2 min-h-20" placeholder="اكتب سبب الاعتراض، ولا يعني التأكيد موافقتك على الدرجة." value={appeal} onChange={(e) => setAppeal(e.target.value)} /></label> : null}<div className="mt-3 flex flex-wrap gap-2">{form.editableStage !== 'self' && form.editableStage !== 'acknowledgement' ? <button className="btn-secondary" disabled={pending} onClick={() => { const target = form.editableStage === 'manager' ? 'self' : form.editableStage === 'hr' ? 'manager' : form.editableStage === 'secretary' ? 'hr' : 'secretary'; void commands.returnStage.mutateAsync({ p_evaluation_id: form.id, p_target_stage: target, p_note: note }); }}>إعادة للتصحيح</button> : null}<button className="btn-primary" disabled={pending} onClick={() => void submit()}><CheckCircle2 className="size-4" />{form.editableStage === 'executive' ? 'الاعتماد النهائي' : form.editableStage === 'acknowledgement' ? 'تأكيد الاطلاع وإرسال' : 'اعتماد المرحلة وإرسال'}</button></div></section> : null}
    </div>
  </section>;
}
