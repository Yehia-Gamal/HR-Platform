import { BellRing, CheckCircle2, FileText, Megaphone, Plus, Send, ShieldCheck, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useCreateDecisionDraft, useOfficialFeed, usePublishAnnouncement, useTransitionDecision } from './useOfficialFeed';

type PublishMode = 'announcement' | 'decision';

export function OfficialFeedPage() {
  const auth = useAuth();
  const query = useOfficialFeed();
  const publish = usePublishAnnouncement();
  const createDecision = useCreateDecisionDraft();
  const transition = useTransitionDecision();
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<PublishMode>('announcement');
  const [search, setSearch] = useState('');
  const [kind, setKind] = useState('all');
  const [priority, setPriority] = useState('all');
  const [form, setForm] = useState({ title: '', body: '', category: 'general', priority: 'normal', requiresAcknowledgement: false, expectedOutcome: '', successMetric: '' });
  const allItems = query.data ?? [];
  const items = useMemo(() => allItems.filter((item) => {
    const queryText = search.trim().toLowerCase();
    const matchesSearch = !queryText || `${item.title} ${item.body} ${item.category}`.toLowerCase().includes(queryText);
    return matchesSearch && (kind === 'all' || item.kind === kind) && (priority === 'all' || item.priority === priority);
  }), [allItems, kind, priority, search]);
  const canPublish = hasPermission(auth.access!, 'comms.announcement.manage') || auth.access!.workspaces.includes('main_admin');
  const canManageDecision = hasPermission(auth.access!, 'comms.decision.manage') || auth.access!.workspaces.includes('main_admin');
  const canApproveDecision = hasPermission(auth.access!, 'comms.decision.approve') || auth.access!.workspaces.includes('main_admin');

  const reset = () => setForm({ title: '', body: '', category: 'general', priority: 'normal', requiresAcknowledgement: false, expectedOutcome: '', successMetric: '' });
  const submit = async () => {
    if (mode === 'announcement') {
      await publish.mutateAsync(form);
    } else {
      await createDecision.mutateAsync(form);
    }
    setOpen(false);
    reset();
  };

  const nextAction = (status: string): 'submit_review' | 'approve' | 'publish' | 'archive' | null => {
    if (status === 'draft') return 'submit_review';
    if (status === 'in_review') return 'approve';
    if (status === 'approved' || status === 'scheduled') return 'publish';
    if (status === 'published') return 'archive';
    return null;
  };

  const actionLabel: Record<string, string> = {
    submit_review: 'إرسال للمراجعة',
    approve: 'اعتماد القرار',
    publish: 'نشر القرار',
    archive: 'أرشفة القرار',
  };

  return <div className="space-y-6">
    <PageHeader
      title="القناة الرسمية للأخبار والقرارات"
      description="قناة أحادية الاتجاه، مع دورة قرار رسمية: مسودة ← مراجعة ← اعتماد ← نشر، وإصدارات وسجل تدقيق."
      actions={canPublish ? <button className="btn-primary" onClick={() => setOpen(true)}><Plus className="size-4" aria-hidden="true" />عنصر رسمي جديد</button> : undefined}
    />
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="المنشورات" value={allItems.length} icon={Megaphone} />
      <MetricCard label="القرارات" value={allItems.filter((x) => x.kind === 'decision').length} icon={FileText} />
      <MetricCard label="تحتاج إقرارًا" value={allItems.filter((x) => x.requiresAcknowledgement).length} icon={CheckCircle2} />
      <MetricCard label="عاجل" value={allItems.filter((x) => x.priority === 'urgent').length} icon={BellRing} />
    </section>
    <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث في عنوان أو محتوى المنشور" resultText={`عرض ${items.length} من ${allItems.length} عنصر رسمي`} isDirty={Boolean(search || kind !== 'all' || priority !== 'all')} onClear={() => { setSearch(''); setKind('all'); setPriority('all'); }}><select className="input" aria-label="نوع العنصر الرسمي" value={kind} onChange={(event) => setKind(event.target.value)}><option value="all">كل الأنواع</option><option value="announcement">خبر أو إعلان</option><option value="decision">قرار إداري</option></select><select className="input" aria-label="أولوية العنصر الرسمي" value={priority} onChange={(event) => setPriority(event.target.value)}><option value="all">كل الأولويات</option><option value="normal">عادية</option><option value="high">مرتفعة</option><option value="urgent">عاجلة</option></select></FilterBar>
    {query.isError ? (
      <ErrorState title="تعذر تحميل القناة" description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} />
    ) : query.isLoading && allItems.length === 0 ? (
      <ListSkeleton rows={4} label="جارٍ تحميل القناة الرسمية" />
    ) : allItems.length > 0 && items.length === 0 ? (
      <EmptyState title="لا توجد نتائج مطابقة" description="جرّب تغيير كلمة البحث أو مسح الفلاتر الحالية." />
    ) : (
    <section className="grid gap-4 xl:grid-cols-2">
      {items.map((item) => {
        const action = item.kind === 'decision' ? nextAction(item.status) : null;
        const canRun = action === 'approve' ? canApproveDecision : canManageDecision;
        return <article key={`${item.kind}-${item.id}`} className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <div className="flex flex-wrap items-center justify-between gap-2"><div className="flex items-center gap-2"><StatusBadge value={item.kind} /><StatusBadge value={item.priority} /><StatusBadge value={item.status} /></div><span className="muted text-xs">{item.publishedAt ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.publishedAt)) : 'غير منشور'}</span></div>
            <h2 className="mt-4 text-xl font-black">{item.title}</h2>
            <p className="mt-3 text-sm leading-8">{item.body}</p>
          </div>
          {item.requiresAcknowledgement ? <div className="p-5"><div className="flex justify-between text-sm"><span>نسبة الاطلاع والإقرار</span><strong>{item.acknowledgedCount}{item.targetCount ? ` / ${item.targetCount}` : ''}</strong></div><div className="mt-2 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]" role="progressbar" aria-label="نسبة الاطلاع والإقرار" aria-valuemin={0} aria-valuemax={item.targetCount ?? 0} aria-valuenow={item.acknowledgedCount}><div className="h-full rounded-full bg-brand" style={{ width: `${item.targetCount ? Math.min(100, (item.acknowledgedCount / item.targetCount) * 100) : 0}%` }} /></div></div> : null}
          {action && canRun ? <div className="border-t border-[var(--border)] p-4"><button className="btn-secondary" disabled={transition.isPending} onClick={() => void transition.mutateAsync({ decisionId: item.id, action })}>{action === 'approve' ? <ShieldCheck className="size-4" aria-hidden="true" /> : <Send className="size-4" aria-hidden="true" />}{actionLabel[action]}</button></div> : null}
        </article>;
      })}
    </section>
    )}
    {open ? <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4"><section className="card w-full max-w-2xl p-6" role="dialog" aria-modal="true" aria-labelledby="official-feed-modal-title"><div className="flex items-center justify-between"><h2 id="official-feed-modal-title" className="text-xl font-black">إنشاء عنصر رسمي</h2><button className="rounded-xl border border-[var(--border)] p-2" aria-label="إغلاق" onClick={() => setOpen(false)}><X className="size-5" aria-hidden="true" /></button></div>
      <div className="mt-5 grid grid-cols-2 gap-2 rounded-2xl bg-[var(--surface-muted)] p-1"><button className={`rounded-xl px-3 py-2 font-black ${mode === 'announcement' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`} onClick={() => setMode('announcement')}>خبر أو إعلان</button><button className={`rounded-xl px-3 py-2 font-black ${mode === 'decision' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`} onClick={() => setMode('decision')}>قرار إداري</button></div>
      <div className="mt-5 grid gap-4"><label className="text-sm font-bold">العنوان<input className="input mt-2" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></label><label className="text-sm font-bold">المحتوى<textarea className="input mt-2 min-h-36 resize-y" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} /></label><div className="grid gap-4 sm:grid-cols-2"><label className="text-sm font-bold">التصنيف<select className="input mt-2" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}><option value="general">عام</option><option value="hr">موارد بشرية</option><option value="policy">سياسة</option><option value="organizational">تنظيمي</option><option value="financial">مالي</option></select></label>{mode === 'announcement' ? <label className="text-sm font-bold">الأولوية<select className="input mt-2" value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })}><option value="normal">عادية</option><option value="high">مرتفعة</option><option value="urgent">عاجلة</option></select></label> : null}</div>{mode === 'decision' ? <div className="grid gap-4 sm:grid-cols-2"><label className="text-sm font-bold">النتيجة المتوقعة<input className="input mt-2" value={form.expectedOutcome} onChange={(e) => setForm({ ...form, expectedOutcome: e.target.value })} /></label><label className="text-sm font-bold">مؤشر قياس النجاح<input className="input mt-2" value={form.successMetric} onChange={(e) => setForm({ ...form, successMetric: e.target.value })} /></label></div> : null}<label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-4 text-sm font-bold"><input type="checkbox" checked={form.requiresAcknowledgement} onChange={(e) => setForm({ ...form, requiresAcknowledgement: e.target.checked })} />يتطلب إقرارًا بالاطلاع</label>{publish.isError || createDecision.isError ? <ErrorBanner message="تعذر حفظ العنصر الرسمي." /> : null}<button className="btn-primary" disabled={publish.isPending || createDecision.isPending || form.title.trim().length < 3 || form.body.trim().length < 10} onClick={() => void submit()}>{mode === 'decision' ? 'حفظ كمسودة قرار' : 'نشر الآن'}</button></div></section></div> : null}
  </div>;
}
