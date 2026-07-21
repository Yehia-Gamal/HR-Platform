import { CalendarDays, CheckCircle2, Download, Lock, RefreshCcw, Scale, Unlock, UsersRound } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useKpiAdmin, useKpiAdminCommands } from './useAdvancedOperations';

const monthNow = new Date().toISOString().slice(0, 7);
export function KpiCyclesPage() {
  const [month, setMonth] = useState(monthNow);
  const query = useKpiAdmin(month);
  const commands = useKpiAdminCommands();
  const [reason, setReason] = useState<Record<string, string>>({});
  const [extension, setExtension] = useState<Record<string, string>>({});
  const [appealNotes, setAppealNotes] = useState<Record<string, string>>({});
  const [policyRules, setPolicyRules] = useState({ late: 1, earlyLeave: 1, unexcusedAbsence: 4, missingPunch: 1, shortagePerHour: 1, maxShortagePerDay: 2 });
  const [ratingMins, setRatingMins] = useState({ excellent: 90, veryGood: 80, good: 70, acceptable: 60 });
  const data = query.data;
  const totals = useMemo(() => ({ cycles: data?.cycles.length ?? 0, evaluations: data?.cycles.reduce((sum, item) => sum + item.evaluations, 0) ?? 0, finalized: data?.cycles.reduce((sum, item) => sum + item.finalized, 0) ?? 0, appeals: data?.appeals.length ?? 0 }), [data]);

  useEffect(() => {
    if (!data?.policy) return;
    setPolicyRules((current) => ({ ...current, ...data.policy!.attendanceRules }));
    const byLabel = Object.fromEntries(data.policy.ratingBands.map((band) => [band.label, band.min]));
    setRatingMins({ excellent: byLabel['ممتاز'] ?? 90, veryGood: byLabel['جيد جدًا'] ?? 80, good: byLabel['جيد'] ?? 70, acceptable: byLabel['مقبول'] ?? 60 });
  }, [data?.policy?.id]);

  const createCycle = async () => {
    if (!data?.officialTemplateId) return;
    const officialDeadline = new Date(`${month}-26T00:00:00+03:00`).toISOString();
    await commands.createCycle.mutateAsync({ p_month: `${month}-01`, p_template_id: data.officialTemplateId, p_self_due: officialDeadline, p_manager_due: officialDeadline, p_secretary_due: officialDeadline, p_executive_due: officialDeadline, p_open_now: false });
  };

  const downloadReport = async (cycleId: string) => {
    const report = await commands.getReport.mutateAsync({ p_cycle_id: cycleId }) as { evaluations?: Array<Record<string, unknown>> };
    const rows = report.evaluations ?? [];
    const csv = ['الموظف,الكود,المرحلة,الحالة,النتيجة,التقدير', ...rows.map((row) => [row.employeeName, row.employeeCode, row.stage, row.workflowStatus, row.finalScore, row.finalRating].map((value) => `"${String(value ?? '').replaceAll('"', '""')}"`).join(','))].join('\n');
    const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' })); link.download = `kpi-${month}.csv`; link.click(); URL.revokeObjectURL(link.href);
  };

  const savePolicy = () => commands.updatePolicy.mutateAsync({
    p_name: 'السياسة الرسمية لتقييم الأداء', p_attendance_rules: policyRules,
    p_rating_bands: [
      { min: ratingMins.excellent, max: 100, label: 'ممتاز' },
      { min: ratingMins.veryGood, max: ratingMins.excellent - 0.01, label: 'جيد جدًا' },
      { min: ratingMins.good, max: ratingMins.veryGood - 0.01, label: 'جيد' },
      { min: ratingMins.acceptable, max: ratingMins.good - 0.01, label: 'مقبول' },
      { min: 0, max: ratingMins.acceptable - 0.01, label: 'يحتاج إلى تحسين' },
    ],
    p_allow_target_overachievement: false, p_effective_from: new Date().toISOString().slice(0, 10),
  });

  return <div className="space-y-6">
    <PageHeader title="دورات KPI الرسمية" description="الدورة من يوم 20 إلى 25 بتوقيت القاهرة. السكرتير التنفيذي يستطيع الفتح والإغلاق والتمديد استثنائيًا مع تسجيل السبب تلقائيًا." actions={<label className="text-sm font-bold">الشهر<input className="input mt-1" type="month" aria-label="الشهر" value={month} onChange={(e) => setMonth(e.target.value)} /></label>} />
    {query.isError ? <ErrorState title="تعذر تحميل دورات KPI" description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : query.isLoading && !data ? <><MetricSkeletonRow /><ListSkeleton rows={3} /></> : <>
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="الدورات" value={totals.cycles} icon={CalendarDays} /><MetricCard label="التقييمات" value={totals.evaluations} icon={UsersRound} /><MetricCard label="المكتملة" value={totals.finalized} icon={CheckCircle2} hint={totals.evaluations ? `${Math.round(totals.finalized / totals.evaluations * 100)}% من التقييمات مكتملة` : undefined} /><MetricCard label="الاعتراضات" value={totals.appeals} icon={Scale} /></section>

    <section className="grid gap-6 xl:grid-cols-[420px_1fr]">
      <form className="card space-y-3 p-5" onSubmit={(e) => { e.preventDefault(); void createCycle(); }}>
        <h2 className="text-lg font-black">تجهيز دورة الشهر</h2>
        <p className="muted text-sm">سيستخدم النظام القالب الرسمي: 40 أهداف + 20 كفاءة + 35 سلوك وانضباط + 5 مبادرات، ويفتحها تلقائيًا يوم 20.</p>
        {data?.policy ? <div className="rounded-2xl bg-[var(--surface-muted)] p-4 text-sm"><strong>{data.policy.name}</strong><p className="muted mt-1">الإصدار {data.policy.version} · الحضور محسوب تلقائيًا من السجلات الحالية</p></div> : null}
        <button className="btn-primary w-full" disabled={commands.createCycle.isPending || !data?.officialTemplateId}>تجهيز الدورة وتوزيع التقييمات</button>
      </form>

      <section className="card p-5"><div className="flex items-center justify-between"><h2 className="text-lg font-black">الدورات الحالية</h2><span className="muted text-sm">الموظف ← المدير ← السكرتير ← المدير التنفيذي</span></div>
        <div className="mt-4 space-y-3">{data?.cycles.length === 0 ? <EmptyState title="لا توجد دورات لهذا الشهر" description="جهّز دورة الشهر من البطاقة المجاورة." /> : data?.cycles.map((cycle) => <article key={cycle.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex items-center gap-2"><strong>{new Intl.DateTimeFormat('ar-EG', { month: 'long', year: 'numeric' }).format(new Date(cycle.periodMonth))}</strong><StatusBadge value={cycle.status} /></div><p className="muted mt-1 text-sm">{cycle.templateName ?? 'قالب غير محدد'} · {cycle.finalized}/{cycle.evaluations} مكتمل · {cycle.overdue ?? 0} متأخر</p><p className="muted mt-1 text-xs">الفتح: {cycle.scheduledOpenAt ? new Date(cycle.scheduledOpenAt).toLocaleString('ar-EG') : '—'} · النهاية: {cycle.effectiveDeadline ? new Date(cycle.effectiveDeadline).toLocaleString('ar-EG') : '—'}</p>{cycle.overrideReason ? <p className="mt-2 text-xs text-[var(--warning)]">آخر سبب استثنائي: {cycle.overrideReason}</p> : null}</div><div className="flex flex-wrap gap-2"><button className="btn-secondary" disabled={commands.refreshAttendance.isPending} onClick={() => void commands.refreshAttendance.mutateAsync({ p_cycle_id: cycle.id })}><RefreshCcw className="size-4" aria-hidden="true" />تحديث الحضور الآلي</button><button className="btn-secondary" onClick={() => void downloadReport(cycle.id)}><Download className="size-4" aria-hidden="true" />تقرير CSV</button></div></div><div className="mt-3 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]"><div className="h-full bg-brand" style={{ width: `${cycle.evaluations ? Math.round(cycle.finalized / cycle.evaluations * 100) : 0}%` }} /></div>{data.canManageCycles ? <div className="mt-4 grid gap-2 lg:grid-cols-[1fr_220px_auto_auto_auto]"><input className="input" placeholder="سبب الفتح أو الإغلاق أو التمديد — إلزامي" value={reason[cycle.id] ?? ''} onChange={(e) => setReason((old) => ({ ...old, [cycle.id]: e.target.value }))} /><input className="input" type="datetime-local" aria-label="تاريخ ووقت التمديد" value={extension[cycle.id] ?? ''} onChange={(e) => setExtension((old) => ({ ...old, [cycle.id]: e.target.value }))} /><button className="btn-secondary" disabled={(reason[cycle.id]?.trim().length ?? 0) < 5} onClick={() => void commands.manageCycle.mutateAsync({ p_cycle_id: cycle.id, p_action: cycle.status === 'locked' ? 'reopen' : 'open', p_reason: reason[cycle.id], p_extended_until: null })}><Unlock className="size-4" aria-hidden="true" />فتح</button><button className="btn-secondary" disabled={(reason[cycle.id]?.trim().length ?? 0) < 5 || !extension[cycle.id]} onClick={() => void commands.manageCycle.mutateAsync({ p_cycle_id: cycle.id, p_action: 'extend', p_reason: reason[cycle.id], p_extended_until: new Date(extension[cycle.id]).toISOString() })}>تمديد</button><button className="btn-secondary" disabled={(reason[cycle.id]?.trim().length ?? 0) < 5} onClick={() => void commands.manageCycle.mutateAsync({ p_cycle_id: cycle.id, p_action: 'close', p_reason: reason[cycle.id], p_extended_until: null })}><Lock className="size-4" aria-hidden="true" />إغلاق</button></div> : null}</article>)}</div>
      </section>
    </section>

    {data?.canManageCycles ? <section className="card p-5"><h2 className="text-lg font-black">سياسة الخصم والتصنيف</h2><p className="muted mt-1 text-sm">أي تعديل ينشئ إصدارًا جديدًا؛ نتائج الشهور السابقة تظل محتفظة بسياساتها الأصلية.</p><div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">{([
      ['late', 'خصم التأخير'], ['earlyLeave', 'خصم الانصراف المبكر'], ['unexcusedAbsence', 'خصم الغياب'], ['missingPunch', 'خصم البصمة الناقصة'], ['shortagePerHour', 'خصم ساعة النقص'], ['maxShortagePerDay', 'حد خصم النقص يوميًا'],
    ] as const).map(([key, label]) => <label className="text-xs font-bold" key={key}>{label}<input className="input mt-1" type="number" min={0} step="0.25" value={policyRules[key]} onChange={(e) => setPolicyRules({ ...policyRules, [key]: Number(e.target.value) })} /></label>)}</div><div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><label className="text-xs font-bold">بداية ممتاز<input className="input mt-1" type="number" min={0} max={100} value={ratingMins.excellent} onChange={(e) => setRatingMins({ ...ratingMins, excellent: Number(e.target.value) })} /></label><label className="text-xs font-bold">بداية جيد جدًا<input className="input mt-1" type="number" min={0} max={100} value={ratingMins.veryGood} onChange={(e) => setRatingMins({ ...ratingMins, veryGood: Number(e.target.value) })} /></label><label className="text-xs font-bold">بداية جيد<input className="input mt-1" type="number" min={0} max={100} value={ratingMins.good} onChange={(e) => setRatingMins({ ...ratingMins, good: Number(e.target.value) })} /></label><label className="text-xs font-bold">بداية مقبول<input className="input mt-1" type="number" min={0} max={100} value={ratingMins.acceptable} onChange={(e) => setRatingMins({ ...ratingMins, acceptable: Number(e.target.value) })} /></label></div><button className="btn-primary mt-4" disabled={commands.updatePolicy.isPending || !(ratingMins.excellent > ratingMins.veryGood && ratingMins.veryGood > ratingMins.good && ratingMins.good > ratingMins.acceptable)} onClick={() => void savePolicy()}>حفظ إصدار جديد من السياسة</button></section> : null}

    <section className="card p-5"><h2 className="text-lg font-black">اعتراضات التقييم</h2>{data?.appeals.length === 0 ? <EmptyState title="لا توجد اعتراضات معلقة" description="تظهر هنا اعتراضات الموظفين على النتائج النهائية." /> : <div className="mt-4 space-y-3">{data?.appeals.map((appeal) => <article key={appeal.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><strong>{appeal.employeeName}</strong><p className="muted mt-1 text-sm">{appeal.reason}</p>{appeal.requestedOutcome ? <p className="mt-2 text-sm">المطلوب: {appeal.requestedOutcome}</p> : null}</div><StatusBadge value={appeal.status} /></div><div className="mt-3 grid gap-2 md:grid-cols-[1fr_auto_auto]"><input className="input" placeholder="قرار ومبررات المراجعة" value={appealNotes[appeal.id] ?? ''} onChange={(e) => setAppealNotes((v) => ({ ...v, [appeal.id]: e.target.value }))} /><button className="btn-primary" onClick={() => void commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'accepted', p_note: appealNotes[appeal.id] ?? '' })}>قبول وإعادة للتنفيذي</button><button className="btn-secondary" onClick={() => void commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'rejected', p_note: appealNotes[appeal.id] ?? '' })}>رفض</button></div></article>)}</div>}</section>
    </>}
  </div>;
}
