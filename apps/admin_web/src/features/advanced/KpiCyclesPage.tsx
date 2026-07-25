import { Archive, CalendarDays, CheckCircle2, Download, Lock, PauseCircle, RefreshCcw, Scale, Unlock, UsersRound, XCircle } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useKpiAdmin, useKpiAdminCommands } from './useAdvancedOperations';

const monthNow = new Date().toISOString().slice(0, 7);

export function KpiCyclesPage() {
  const [month, setMonth] = useState(monthNow);
  const query = useKpiAdmin(month);
  const commands = useKpiAdminCommands();
  const [reason, setReason] = useState<Record<string, string>>({});
  const [extension, setExtension] = useState<Record<string, string>>({});
  const [openAt, setOpenAt] = useState<Record<string, string>>({});
  const [deadlineAt, setDeadlineAt] = useState<Record<string, string>>({});
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
  const control = (cycleId: string, action: string, extendedUntil: string | null = null) => commands.manageCycle.mutateAsync({ p_cycle_id: cycleId, p_action: action, p_reason: reason[cycleId], p_extended_until: extendedUntil });
  const reschedule = (cycleId: string) => commands.rescheduleCycle.mutateAsync({ p_cycle_id: cycleId, p_open_at: new Date(openAt[cycleId]).toISOString(), p_deadline_at: new Date(deadlineAt[cycleId]).toISOString(), p_reason: reason[cycleId] });
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
    <PageHeader title="دورات KPI الرسمية" description="السكرتير التنفيذي وحده يجهز ويفتح ويعلق ويمدد ويغلق ويؤرشف الدورة. المسار: الموظف ← HR ← المدير المباشر للاعتماد ← التقرير الشهري." actions={<label className="text-sm font-bold">الشهر<input className="input mt-1" type="month" value={month} onChange={(event) => setMonth(event.target.value)} /></label>} />
    {query.isError ? <ErrorState title="تعذر تحميل دورات KPI" description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : query.isLoading && !data ? <><MetricSkeletonRow /><ListSkeleton rows={3} /></> : <>
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="الدورات" value={totals.cycles} icon={CalendarDays} /><MetricCard label="التقييمات" value={totals.evaluations} icon={UsersRound} /><MetricCard label="المدرجة في التقارير" value={totals.finalized} icon={CheckCircle2} /><MetricCard label="الاعتراضات" value={totals.appeals} icon={Scale} /></section>

      {data?.canManageCycles ? <form className="card flex flex-wrap items-center justify-between gap-4 p-5" onSubmit={(event) => { event.preventDefault(); void createCycle(); }}><div><h2 className="text-lg font-black">تجهيز دورة الشهر</h2><p className="muted text-sm">القالب الرسمي سبعة بنود بإجمالي 100 درجة، والفتح المجدول يوم 20.</p></div><button className="btn-primary" disabled={commands.createCycle.isPending || !data.officialTemplateId}>تجهيز الدورة</button></form> : null}

      <section className="space-y-3">{data?.cycles.length === 0 ? <EmptyState title="لا توجد دورات" description="جهّز دورة الشهر من البطاقة السابقة." /> : data?.cycles.map((cycle) => {
        const validReason = (reason[cycle.id]?.trim().length ?? 0) >= 5;
        return <article key={cycle.id} className="card p-5">
          <div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex items-center gap-2"><strong>{new Intl.DateTimeFormat('ar-EG', { month: 'long', year: 'numeric' }).format(new Date(cycle.periodMonth))}</strong><StatusBadge value={cycle.status} /></div><p className="muted mt-1 text-sm">{cycle.finalized}/{cycle.evaluations} مدرج · {cycle.overdue ?? 0} متأخر · المتوسط {cycle.averageScore ?? '—'}</p><p className="muted mt-1 text-xs">الفتح: {cycle.scheduledOpenAt ? new Date(cycle.scheduledOpenAt).toLocaleString('ar-EG') : '—'} · النهاية: {cycle.effectiveDeadline ? new Date(cycle.effectiveDeadline).toLocaleString('ar-EG') : '—'}</p>{cycle.overrideReason ? <p className="mt-2 text-xs text-[var(--warning)]">آخر سبب إداري: {cycle.overrideReason}</p> : null}</div><div className="flex flex-wrap gap-2"><button className="btn-secondary" onClick={() => void commands.refreshAttendance.mutateAsync({ p_cycle_id: cycle.id })}><RefreshCcw className="size-4" />تحديث الحضور</button><button className="btn-secondary" onClick={() => void downloadReport(cycle.id)}><Download className="size-4" />CSV</button></div></div>
          <div className="mt-3 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]"><div className="h-full bg-brand" style={{ width: `${cycle.evaluations ? Math.round(cycle.finalized / cycle.evaluations * 100) : 0}%` }} /></div>
          {data.canManageCycles ? <div className="mt-4 space-y-3 rounded-2xl bg-[var(--surface-muted)] p-4">
            <input className="input" placeholder="سبب الإجراء الإداري — إلزامي" value={reason[cycle.id] ?? ''} onChange={(event) => setReason((old) => ({ ...old, [cycle.id]: event.target.value }))} />
            <div className="flex flex-wrap gap-2"><button className="btn-secondary" disabled={!validReason} onClick={() => void control(cycle.id, cycle.status === 'locked' ? 'reopen' : 'open')}><Unlock className="size-4" />فتح/إعادة فتح</button><button className="btn-secondary" disabled={!validReason || cycle.status !== 'open'} onClick={() => void control(cycle.id, 'suspend')}><PauseCircle className="size-4" />تعليق</button><button className="btn-secondary" disabled={!validReason || !['open', 'draft'].includes(cycle.status)} onClick={() => void control(cycle.id, 'cancel_open')}><XCircle className="size-4" />إلغاء الفتح</button><button className="btn-secondary" disabled={!validReason} onClick={() => void control(cycle.id, 'close')}><Lock className="size-4" />إغلاق</button><button className="btn-secondary" disabled={!validReason || cycle.status !== 'locked'} onClick={() => void control(cycle.id, 'archive')}><Archive className="size-4" />أرشفة</button></div>
            <div className="grid gap-2 md:grid-cols-[1fr_auto]"><input className="input" type="datetime-local" value={extension[cycle.id] ?? ''} onChange={(event) => setExtension((old) => ({ ...old, [cycle.id]: event.target.value }))} /><button className="btn-secondary" disabled={!validReason || !extension[cycle.id]} onClick={() => void control(cycle.id, 'extend', new Date(extension[cycle.id]).toISOString())}>تمديد الموعد</button></div>
            <div className="grid gap-2 md:grid-cols-[1fr_1fr_auto]"><input className="input" type="datetime-local" aria-label="موعد الفتح الجديد" value={openAt[cycle.id] ?? ''} onChange={(event) => setOpenAt((old) => ({ ...old, [cycle.id]: event.target.value }))} /><input className="input" type="datetime-local" aria-label="موعد الإغلاق الجديد" value={deadlineAt[cycle.id] ?? ''} onChange={(event) => setDeadlineAt((old) => ({ ...old, [cycle.id]: event.target.value }))} /><button className="btn-secondary" disabled={!validReason || !openAt[cycle.id] || !deadlineAt[cycle.id]} onClick={() => void reschedule(cycle.id)}>تعديل البداية والنهاية</button></div>
          </div> : null}
        </article>;
      })}</section>

      {data?.canManageCycles && data.policy ? <section className="card p-5"><h2 className="text-lg font-black">سياسة الخصم والتصنيف</h2><p className="muted mt-1 text-sm">الحفظ ينشئ إصدارًا جديدًا ويحافظ على نتائج الدورات السابقة.</p><div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">{([['late', 'التأخير'], ['earlyLeave', 'الانصراف المبكر'], ['unexcusedAbsence', 'الغياب'], ['missingPunch', 'البصمة الناقصة'], ['shortagePerHour', 'نقص الساعة'], ['maxShortagePerDay', 'حد النقص اليومي']] as const).map(([key, label]) => <label className="text-xs font-bold" key={key}>{label}<input className="input mt-1" type="number" min={0} step="0.25" value={policyRules[key]} onChange={(event) => setPolicyRules({ ...policyRules, [key]: Number(event.target.value) })} /></label>)}</div><div className="mt-4 grid gap-3 sm:grid-cols-4"><input className="input" type="number" aria-label="بداية ممتاز" value={ratingMins.excellent} onChange={(event) => setRatingMins({ ...ratingMins, excellent: Number(event.target.value) })} /><input className="input" type="number" aria-label="بداية جيد جدًا" value={ratingMins.veryGood} onChange={(event) => setRatingMins({ ...ratingMins, veryGood: Number(event.target.value) })} /><input className="input" type="number" aria-label="بداية جيد" value={ratingMins.good} onChange={(event) => setRatingMins({ ...ratingMins, good: Number(event.target.value) })} /><input className="input" type="number" aria-label="بداية مقبول" value={ratingMins.acceptable} onChange={(event) => setRatingMins({ ...ratingMins, acceptable: Number(event.target.value) })} /></div><button className="btn-primary mt-4" disabled={commands.updatePolicy.isPending || !(ratingMins.excellent > ratingMins.veryGood && ratingMins.veryGood > ratingMins.good && ratingMins.good > ratingMins.acceptable)} onClick={() => void savePolicy()}>حفظ إصدار سياسة جديد</button></section> : null}

      <section className="card p-5"><h2 className="text-lg font-black">اعتراضات التقييم</h2>{data?.appeals.length === 0 ? <EmptyState title="لا توجد اعتراضات معلقة" description="تظهر هنا الاعتراضات على النتائج المعتمدة." /> : <div className="mt-4 space-y-3">{data?.appeals.map((appeal) => <article key={appeal.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex items-start justify-between gap-3"><div className="flex items-center gap-2"><UserAvatar displayName={appeal.employeeName} size="sm" /><strong>{appeal.employeeName}</strong><p className="muted mt-1 text-sm">{appeal.reason}</p></div><StatusBadge value={appeal.status} /></div><div className="mt-3 grid gap-2 md:grid-cols-[1fr_auto_auto]"><input className="input" placeholder="قرار ومبررات المراجعة" value={appealNotes[appeal.id] ?? ''} onChange={(event) => setAppealNotes((old) => ({ ...old, [appeal.id]: event.target.value }))} /><button className="btn-primary" disabled={(appealNotes[appeal.id]?.trim().length ?? 0) < 8} onClick={() => void commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'accepted', p_note: appealNotes[appeal.id] })}>قبول وإعادة للمدير</button><button className="btn-secondary" disabled={(appealNotes[appeal.id]?.trim().length ?? 0) < 8} onClick={() => void commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'rejected', p_note: appealNotes[appeal.id] })}>رفض</button></div></article>)}</div>}</section>
    </>}
  </div>;
}
