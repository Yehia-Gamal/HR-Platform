import { BellRing, CheckCircle2, FileText, ImagePlus, Megaphone, Plus, Send, ShieldCheck, Trash2, User } from 'lucide-react';
import { useCallback, useMemo, useRef, useState } from 'react';
import { getSupabase } from '../../core/supabase';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { preparePostImage } from '../../ui/postImage';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useCreateDecisionDraft, useOfficialFeed, usePublishAnnouncement, useTransitionDecision } from './useOfficialFeed';

type PublishMode = 'announcement' | 'decision';

/** V23 Task-10: تسميات أنواع المنشورات بالعربية */
const POST_TYPE_LABELS: Record<string, string> = {
  announcement: 'إعلان',
  decision: 'قرار إداري',
  alert: 'تنبيه',
  poll: 'تصويت',
  meeting: 'اجتماع',
  holiday_notice: 'إشعار عطلة',
  kpi_notice: 'إشعار أداء',
  attendance_notice: 'إشعار حضور',
};

/** أنواع المنشورات المتاحة في وضع الإعلانات (غير القرارات) */
const ANNOUNCEMENT_POST_TYPES = [
  { value: 'announcement', label: 'إعلان' },
  { value: 'alert', label: 'تنبيه' },
  { value: 'poll', label: 'تصويت' },
  { value: 'meeting', label: 'اجتماع' },
  { value: 'holiday_notice', label: 'إشعار عطلة' },
  { value: 'kpi_notice', label: 'إشعار أداء' },
  { value: 'attendance_notice', label: 'إشعار حضور' },
] as const;

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
  const [form, setForm] = useState({ title: '', body: '', category: 'general', priority: 'normal', requiresAcknowledgement: false, expectedOutcome: '', successMetric: '', postType: 'announcement' });
  const [bannerUrl, setBannerUrl] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const allItems = query.data ?? [];
  const items = useMemo(() => allItems.filter((item) => {
    const queryText = search.trim().toLowerCase();
    const matchesSearch = !queryText || `${item.title} ${item.body} ${item.category}`.toLowerCase().includes(queryText);
    return matchesSearch && (kind === 'all' || item.kind === kind) && (priority === 'all' || item.priority === priority);
  }), [allItems, kind, priority, search]);
  const canPublish = hasPermission(auth.access!, 'comms.announcement.manage') || auth.access!.workspaces.includes('main_admin');
  const canManageDecision = hasPermission(auth.access!, 'comms.decision.manage') || auth.access!.workspaces.includes('main_admin');
  const canApproveDecision = hasPermission(auth.access!, 'comms.decision.approve') || auth.access!.workspaces.includes('main_admin');
  const handleImageSelect = useCallback(async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    setImageError(null);
    setImageUploading(true);
    try {
      const prepared = await preparePostImage(file);
      const supabase = await getSupabase();
      const path = `${crypto.randomUUID()}.webp`;
      const { error: uploadError } = await supabase.storage.from('announcement-images').upload(path, prepared, { contentType: 'image/webp', upsert: false });
      if (uploadError) throw uploadError;
      const { data: urlData } = supabase.storage.from('announcement-images').getPublicUrl(path);
      setBannerUrl(urlData.publicUrl);
      setImagePreview(URL.createObjectURL(prepared));
    } catch (err) {
      setImageError(safeErrorMessage(err));
    } finally {
      setImageUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  }, []);

  const resetAll = () => {
    setForm({ title: '', body: '', category: 'general', priority: 'normal', requiresAcknowledgement: false, expectedOutcome: '', successMetric: '', postType: 'announcement' });
    setBannerUrl(null);
    setImagePreview(null);
    setImageError(null);
  };


  const removeImage = useCallback(async () => {
    if (bannerUrl) {
      try {
        const supabase = await getSupabase();
        const urlPath = new URL(bannerUrl).pathname;
        const storagePath = urlPath.split('/announcement-images/')[1];
        if (storagePath) await supabase.storage.from('announcement-images').remove([storagePath]);
      } catch { /* best effort cleanup */ }
    }
    setBannerUrl(null);
    setImagePreview(null);
    setImageError(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  }, [bannerUrl]);

  const submit = async () => {
    if (mode === 'announcement') {
      await publish.mutateAsync({ ...form, bannerUrl, postType: form.postType });
    } else {
      await createDecision.mutateAsync(form);
    }
    setOpen(false);
    resetAll();
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
        const postTypeLabel = POST_TYPE_LABELS[item.postType ?? item.kind] ?? item.kind;
        return <article key={`${item.kind}-${item.id}`} className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <StatusBadge value={item.kind} />
                <span className="rounded-lg bg-[var(--surface-muted)] px-2 py-0.5 text-xs font-bold">{postTypeLabel}</span>
                <StatusBadge value={item.priority} />
                <StatusBadge value={item.status} />
              </div>
              <span className="muted text-xs">{item.publishedAt ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.publishedAt)) : 'غير منشور'}</span>
            </div>
            <h2 className="mt-4 text-xl font-black">{item.title}</h2>
            {item.imageUrl ? <img src={item.imageUrl} alt="" className="mt-3 h-44 w-full rounded-2xl object-cover" /> : null}
            <p className="mt-3 text-sm leading-8">{item.body}</p>
            {/* V23 Task-10: عرض اسم وصورة الناشر */}
            {item.authorName ? (
              <div className="mt-3 flex items-center gap-2 text-xs text-[var(--text-muted)]">
                {item.authorPhotoUrl ? (
                  <img src={item.authorPhotoUrl} alt="" className="size-6 rounded-full object-cover" />
                ) : (
                  <span className="grid size-6 place-items-center rounded-full bg-[var(--surface-muted)]"><User className="size-3" aria-hidden="true" /></span>
                )}
                <span className="font-bold">{item.authorName}</span>
              </div>
            ) : null}
          </div>
          {item.requiresAcknowledgement ? <div className="p-5"><div className="flex justify-between text-sm"><span>نسبة الاطلاع والإقرار</span><strong>{item.acknowledgedCount}{item.targetCount ? ` / ${item.targetCount}` : ''}</strong></div><div className="mt-2 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]" role="progressbar" aria-label="نسبة الاطلاع والإقرار" aria-valuemin={0} aria-valuemax={item.targetCount ?? 0} aria-valuenow={item.acknowledgedCount}><div className="h-full rounded-full bg-brand" style={{ width: `${item.targetCount ? Math.min(100, (item.acknowledgedCount / item.targetCount) * 100) : 0}%` }} /></div></div> : null}
          {action && canRun ? <div className="border-t border-[var(--border)] p-4"><button className="btn-secondary" disabled={transition.isPending} onClick={() => void transition.mutateAsync({ decisionId: item.id, action })}>{action === 'approve' ? <ShieldCheck className="size-4" aria-hidden="true" /> : <Send className="size-4" aria-hidden="true" />}{actionLabel[action]}</button></div> : null}
        </article>;
      })}
    </section>
    )}
    {open ? (
      <DialogOverlay title="إنشاء عنصر رسمي" onClose={() => setOpen(false)} maxWidth="max-w-2xl">
        <div className="grid grid-cols-2 gap-2 rounded-2xl bg-[var(--surface-muted)] p-1"><button type="button" className={`rounded-xl px-3 py-2 font-black ${mode === 'announcement' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`} onClick={() => setMode('announcement')}>خبر أو إعلان</button><button type="button" className={`rounded-xl px-3 py-2 font-black ${mode === 'decision' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`} onClick={() => setMode('decision')}>قرار إداري</button></div>
        <div className="mt-5 grid gap-4">
          <label className="text-sm font-bold">العنوان<input className="input mt-2" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></label>
          <label className="text-sm font-bold">المحتوى<textarea className="input mt-2 min-h-36 resize-y" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} /></label>
          {mode === 'announcement' ? <>
            {/* V23 Task-10: اختيار نوع المنشور */}
            <label className="text-sm font-bold">نوع المنشور
              <select className="input mt-2" value={form.postType} onChange={(e) => setForm({ ...form, postType: e.target.value })}>
                {ANNOUNCEMENT_POST_TYPES.map((pt) => <option key={pt.value} value={pt.value}>{pt.label}</option>)}
              </select>
            </label>
            <div>
              <span className="text-sm font-bold">صورة الإعلان (اختياري)</span>
              <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={handleImageSelect} />
              {imagePreview ? (
                <div className="relative mt-2">
                  <img src={imagePreview} alt="معاينة" className="h-40 w-full rounded-xl object-cover" />
                  <button type="button" className="absolute start-2 top-2 rounded-full bg-red-600 p-1 text-white shadow" aria-label="إزالة الصورة" onClick={() => void removeImage()}><Trash2 className="size-4" /></button>
                </div>
              ) : (
                <button type="button" className="mt-2 flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-[var(--border)] p-6 text-sm transition hover:border-brand hover:text-brand" disabled={imageUploading} onClick={() => fileInputRef.current?.click()}>
                  {imageUploading ? <span className="animate-pulse">جارٍ رفع الصورة…</span> : <><ImagePlus className="size-5" aria-hidden="true" />اضغط لاختيار صورة</>}
                </button>
              )}
              {imageError ? <p className="mt-1 text-xs text-red-500">{imageError}</p> : null}
            </div>
          </> : null}
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="text-sm font-bold">التصنيف<select className="input mt-2" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}><option value="general">عام</option><option value="hr">موارد بشرية</option><option value="policy">سياسة</option><option value="organizational">تنظيمي</option><option value="financial">مالي</option></select></label>
            {mode === 'announcement' ? <label className="text-sm font-bold">الأولوية<select className="input mt-2" value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })}><option value="normal">عادية</option><option value="high">مرتفعة</option><option value="urgent">عاجلة</option></select></label> : null}
          </div>
          {mode === 'decision' ? <div className="grid gap-4 sm:grid-cols-2"><label className="text-sm font-bold">النتيجة المتوقعة<input className="input mt-2" value={form.expectedOutcome} onChange={(e) => setForm({ ...form, expectedOutcome: e.target.value })} /></label><label className="text-sm font-bold">مؤشر قياس النجاح<input className="input mt-2" value={form.successMetric} onChange={(e) => setForm({ ...form, successMetric: e.target.value })} /></label></div> : null}
          <label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-4 text-sm font-bold"><input type="checkbox" checked={form.requiresAcknowledgement} onChange={(e) => setForm({ ...form, requiresAcknowledgement: e.target.checked })} />يتطلب إقرارًا بالاطلاع</label>
          {publish.isError || createDecision.isError ? <ErrorBanner message="تعذر حفظ العنصر الرسمي." /> : null}
          <button className="btn-primary" disabled={publish.isPending || createDecision.isPending || imageUploading || form.title.trim().length < 3 || form.body.trim().length < 10} onClick={() => void submit()}>{mode === 'decision' ? 'حفظ كمسودة قرار' : 'نشر الآن'}</button>
        </div>
      </DialogOverlay>
    ) : null}
  </div>;
}
