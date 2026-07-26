import { CalendarClock, CheckCircle2, Clock3, Save, UsersRound } from 'lucide-react';
import { useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAttendanceOperations, useAttendanceOperationsCommands } from './useAdvancedOperations';

const currentMonth = new Date().toISOString().slice(0, 7);

export function AttendanceOperationsPage() {
  const [month, setMonth] = useState(currentMonth);
  const query = useAttendanceOperations(month);
  const commands = useAttendanceOperationsCommands();
  const emptyShift = { id: '', name: '', start: '10:00', end: '18:00', breakMinutes: 0, graceIn: 15, graceOut: 0, active: true };
  const [shift, setShift] = useState(emptyShift);
  const data = query.data;

  const saveShift = async () => {
    await commands.saveShift.mutateAsync({ p_shift_id: shift.id || null, p_name: shift.name, p_start: shift.start, p_end: shift.end, p_break_minutes: shift.breakMinutes, p_grace_in: shift.graceIn, p_grace_out: shift.graceOut, p_active: shift.active });
    setShift(emptyShift);
  };

  return <div className="space-y-6">
    <PageHeader title="الورديات وإغلاق الحضور" description="إدارة تعريفات الورديات، جداول العمل، العمل الإضافي، وإغلاق الشهر بسجل تدقيق. تصحيحات الحضور انتقلت إلى صفحة طلب إجازة." actions={<label className="text-sm font-bold"><span className="block">الشهر</span><input type="month" aria-label="الشهر" className="input mt-1" value={month} onChange={(e) => setMonth(e.target.value)} /></label>} />
    {query.isError ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : !data ? <><MetricSkeletonRow count={5} /><ListSkeleton rows={3} /></> : <>
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="الأيام المجدولة" value={data.summary.scheduled} icon={CalendarClock} />
      <MetricCard label="الحضور" value={data.summary.present} icon={CheckCircle2} />
      <MetricCard label="الغياب" value={data.summary.absent} icon={UsersRound} />
      <MetricCard label="إضافي معلق" value={data.summary.pendingOvertime} icon={Clock3} />
    </section>

    <section className="grid gap-6 xl:grid-cols-[380px_1fr]">
      <form className="card space-y-3 p-5" onSubmit={(e) => { e.preventDefault(); void saveShift(); }}>
        <h2 className="text-lg font-black">تعريف وردية</h2>
        <input className="input" placeholder="توقيت العمل (مثال: الدوام الرسمي 10 ص – 6 م)" value={shift.name} onChange={(e) => setShift({ ...shift, name: e.target.value })} required />
        <div className="grid grid-cols-2 gap-3"><label className="text-sm font-bold">البداية<input type="time" className="input mt-1" value={shift.start} onChange={(e) => setShift({ ...shift, start: e.target.value })} /></label><label className="text-sm font-bold">النهاية<input type="time" className="input mt-1" value={shift.end} onChange={(e) => setShift({ ...shift, end: e.target.value })} /></label></div>
        <div className="grid grid-cols-3 gap-3"><label className="text-xs font-bold">الراحة<input type="number" min="0" className="input mt-1" value={shift.breakMinutes} onChange={(e) => setShift({ ...shift, breakMinutes: Number(e.target.value) })} /></label><label className="text-xs font-bold">سماح الدخول<input type="number" min="0" className="input mt-1" value={shift.graceIn} onChange={(e) => setShift({ ...shift, graceIn: Number(e.target.value) })} /></label><label className="text-xs font-bold">سماح الخروج<input type="number" min="0" className="input mt-1" value={shift.graceOut} onChange={(e) => setShift({ ...shift, graceOut: Number(e.target.value) })} /></label></div>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={shift.active} onChange={(e) => setShift({ ...shift, active: e.target.checked })} /> نشطة</label>
        <button className="btn-primary w-full" disabled={commands.saveShift.isPending}><Save className="size-4" />حفظ الوردية</button>
      </form>
      <section className="card p-5"><h2 className="text-lg font-black">الورديات الحالية</h2><div className="mt-4 grid gap-3 sm:grid-cols-2">{data?.shifts.map((item) => <button key={item.id} className="card-interactive rounded-2xl border border-[var(--border)] p-4 text-right" onClick={() => setShift({ id: item.id, name: item.name, start: item.startTime.slice(0, 5), end: item.endTime.slice(0, 5), breakMinutes: item.breakMinutes, graceIn: item.graceInMinutes, graceOut: 0, active: item.active })}><div className="flex items-center justify-between"><strong>{item.name}</strong><StatusBadge value={item.active ? 'active' : 'inactive'} /></div><p className="muted mt-2 text-sm">{item.startTime.slice(0, 5)} — {item.endTime.slice(0, 5)} · سماح {item.graceInMinutes} دقيقة</p></button>)}</div></section>
    </section>

    <section className="card p-5"><h2 className="text-lg font-black">جداول الورديات (Rosters)</h2><p className="muted mt-1 text-sm">الجداول المنشورة والمستبدَلة لكل إدارة/فريق خلال الفترة.</p>
      {data && data.rosters.length ? <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{data.rosters.map((roster) => <article key={roster.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex items-center justify-between gap-2"><strong className="truncate">{roster.name}</strong><StatusBadge value={roster.status} /></div><p className="muted mt-2 text-sm">{roster.code} · {roster.periodStart} — {roster.periodEnd} · {roster.days} يوم</p>{roster.publishedAt ? <p className="muted mt-1 text-xs">نُشر {new Date(roster.publishedAt).toLocaleDateString('ar-EG')}</p> : null}</article>)}</div> : <EmptyState title="لا توجد جداول ورديات" description="الجداول المنشورة من مركز العمليات أو التطبيق ستظهر هنا." />}
    </section>


    <section className="grid gap-6 lg:grid-cols-2"><div className="card p-5"><h2 className="text-lg font-black">فترات الحضور</h2>{data && data.periods.length === 0 ? <EmptyState title="لا توجد فترات" description="ستظهر فترات الحضور المفتوحة والمغلقة هنا." /> : <div className="mt-4 space-y-3">{data?.periods.map((period) => <article key={period.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex items-center justify-between"><strong>{period.periodMonth}</strong><StatusBadge value={period.status} /></div>{period.status === 'closed' ? <button className="btn-secondary mt-3 w-full" onClick={() => { const reason = window.prompt('سبب إعادة فتح الفترة (8 أحرف على الأقل)'); if (reason) void commands.unlockPeriod.mutateAsync({ p_period_id: period.id, p_reason: reason }); }}>إعادة فتح الفترة</button> : null}</article>)}</div>}<button className="btn-primary mt-4 w-full" disabled={commands.closePeriod.isPending} onClick={() => void commands.closePeriod.mutateAsync({ p_month: `${month}-01`, p_legal_entity_id: null, p_branch_id: null })}>إغلاق الشهر</button></div>
      <div className="card p-5"><h2 className="text-lg font-black">العمل الإضافي</h2>{data && data.overtime.length === 0 ? <EmptyState title="لا يوجد عمل إضافي" description="طلبات العمل الإضافي في الشهر المحدد ستظهر هنا." /> : <div className="mt-4 space-y-3">{data?.overtime.map((item) => <article key={item.id} className="rounded-2xl border border-[var(--border)] p-4"><div className="flex items-center justify-between"><div className="flex items-center gap-2"><UserAvatar displayName={item.employeeName} size="sm" /><strong>{item.employeeName}</strong><p className="muted text-sm">{item.workDate} · {item.requestedMinutes} دقيقة</p></div><StatusBadge value={item.status} /></div>{item.status === 'pending' ? <div className="mt-3 flex gap-2"><button className="btn-primary flex-1" onClick={() => void commands.decideOvertime.mutateAsync({ p_id: item.id, p_decision: 'approved', p_approved_minutes: item.requestedMinutes, p_note: null })}>اعتماد</button><button className="btn-secondary flex-1" onClick={() => void commands.decideOvertime.mutateAsync({ p_id: item.id, p_decision: 'rejected', p_approved_minutes: 0, p_note: 'غير معتمد' })}>رفض</button></div> : null}</article>)}</div>}</div>
    </section>
    </>}
  </div>;
}
