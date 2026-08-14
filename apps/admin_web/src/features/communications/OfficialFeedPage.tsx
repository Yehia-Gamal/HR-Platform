import { BellRing, CheckCircle2, Eye, FileText, Heart, ImagePlus, ListPlus, Megaphone, Plus, Send, ShieldCheck, Trash2, X } from 'lucide-react';
import { useCallback, useMemo, useRef, useState } from 'react';
import { getSupabase } from '../../core/supabase';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { useToast } from '../../ui/Toast';
import { preparePostImage } from '../../ui/postImage';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import {
  useAnnouncementEngagement,
  useCreateDecisionDraft,
  useOfficialFeed,
  usePublishAnnouncement,
  useToggleReaction,
  useTransitionDecision,
} from './useOfficialFeed';

type PublishMode = 'announcement' | 'decision';
const REACTIONS = [
  { type: 'like', emoji: '👍', label: 'إعجاب' },
  { type: 'celebrate', emoji: '🎉', label: 'احتفال' },
  { type: 'support', emoji: '❤️', label: 'دعم' },
  { type: 'insightful', emoji: '💡', label: 'ملهم' },
] as const;

function AnnouncementReactionBar({ announcementId }: { announcementId: string }) {
  const engagement = useAnnouncementEngagement(announcementId);
  const toggle = useToggleReaction();
  const data = engagement.data;
  return (
    <div className="flex flex-wrap items-center gap-2 border-t border-[var(--border)] px-5 py-3">
      <div className="flex items-center gap-1 text-xs muted me-1">
        <Eye className="size-3.5" aria-hidden="true" />
        <span>{data?.viewerCount ?? 0}</span>
      </div>
      {REACTIONS.map((r) => {
        const active = (toggle.data?.myReaction ?? null) === r.type;
        const count = data?.reactions.filter((rx) => rx.reactionType === r.type).length ?? 0;
        return (
          <button
            key={r.type}
            type="button"
            aria-label={r.label}
            aria-pressed={active}
            disabled={toggle.isPending}
            onClick={() => toggle.mutate({ announcementId, reactionType: r.type })}
            className={`flex items-center gap-1 rounded-full px-2.5 py-1 text-xs transition ${
              active ? 'bg-brand/10 text-brand ring-1 ring-brand/30' : 'bg-[var(--surface-muted)] hover:bg-[var(--surface-raised)]'
            }`}
          >
            <span aria-hidden="true">{r.emoji}</span>
            {count > 0 ? <span>{count}</span> : null}
          </button>
        );
      })}
    </div>
  );
}

// ─── هوك حالة النموذج الرسمي ────────────────────────────────────────────────
function useOfficialFeedForm(publish: ReturnType<typeof usePublishAnnouncement>, createDecision: ReturnType<typeof useCreateDecisionDraft>) {
  const [mode, setMode] = useState<PublishMode>('announcement');
  const [form, setForm] = useState({
    title: '',
    body: '',
    category: 'general',
    priority: 'normal',
    requiresAcknowledgement: false,
    expectedOutcome: '',
    successMetric: '',
  });
  const [bannerUrl, setBannerUrl] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const [postType, setPostType] = useState<'standard' | 'poll'>('standard');
  const [pollOptions, setPollOptions] = useState<string[]>(['', '']);
  const [expiresAt, setExpiresAt] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

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
    setForm({ title: '', body: '', category: 'general', priority: 'normal', requiresAcknowledgement: false, expectedOutcome: '', successMetric: '' });
    setBannerUrl(null);
    setImagePreview(null);
    setImageError(null);
    setPostType('standard');
    setPollOptions(['', '']);
    setExpiresAt('');
  };

  const removeImage = useCallback(async () => {
    if (bannerUrl) {
      try {
        const supabase = await getSupabase();
        const urlPath = new URL(bannerUrl).pathname;
        const storagePath = urlPath.split('/announcement-images/')[1];
        if (storagePath) await supabase.storage.from('announcement-images').remove([storagePath]);
      } catch {
        /* best effort cleanup */
      }
    }
    setBannerUrl(null);
    setImagePreview(null);
    setImageError(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
  }, [bannerUrl]);

  const submit = async (): Promise<boolean> => {
    try {
      if (mode === 'announcement') {
        await publish.mutateAsync({ ...form, bannerUrl, postType, pollOptions, expiresAt: expiresAt || undefined });
      } else {
        await createDecision.mutateAsync(form);
      }
      resetAll();
      return true;
    } catch {
      return false; /* mutation error surfaced via isError banner */
    }
  };

  return {
    mode,
    setMode,
    form,
    setForm,
    bannerUrl,
    imagePreview,
    imageUploading,
    imageError,
    postType,
    setPostType,
    pollOptions,
    setPollOptions,
    expiresAt,
    setExpiresAt,
    fileInputRef,
    handleImageSelect,
    removeImage,
    resetAll,
    submit,
    isSubmitting: publish.isPending || createDecision.isPending,
    submitError: publish.isError || createDecision.isError,
  };
}

export function OfficialFeedPage() {
  const { toast } = useToast();
  const auth = useAuth();
  const query = useOfficialFeed();
  const publish = usePublishAnnouncement();
  const createDecision = useCreateDecisionDraft();
  const transition = useTransitionDecision();
  const [open, setOpen] = useState(false);
  const [engagementItem, setEngagementItem] = useState<{ id: string; title: string } | null>(null);
  const engagementQuery = useAnnouncementEngagement(engagementItem?.id);
  const [search, setSearch] = useState('');
  const [kind, setKind] = useState('all');
  const [priority, setPriority] = useState('all');
  const {
    mode,
    setMode,
    form,
    setForm,
    imagePreview,
    imageUploading,
    imageError,
    postType,
    setPostType,
    pollOptions,
    setPollOptions,
    expiresAt,
    setExpiresAt,
    fileInputRef,
    handleImageSelect,
    removeImage,
    submit,
    isSubmitting,
    submitError,
  } = useOfficialFeedForm(publish, createDecision);
  const allItems = useMemo(() => query.data ?? [], [query.data]);
  const items = useMemo(
    () =>
      allItems.filter((item) => {
        const queryText = search.trim().toLowerCase();
        const matchesSearch = !queryText || `${item.title} ${item.body} ${item.category}`.toLowerCase().includes(queryText);
        return matchesSearch && (kind === 'all' || item.kind === kind) && (priority === 'all' || item.priority === priority);
      }),
    [allItems, kind, priority, search],
  );
  // hasPermission already grants full-access roles via the '*' wildcard,
  // so the previous `|| workspaces.includes('main_admin')` fallback was
  // redundant and risked granting capabilities to non-permissioned admins.
  const canPublish = hasPermission(auth.access, 'comms.announcement.manage');
  const canManageDecision = hasPermission(auth.access, 'comms.decision.manage');
  const canApproveDecision = hasPermission(auth.access, 'comms.decision.approve');

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

  return (
    <div className="space-y-6">
      <PageHeader
        title="القناة الرسمية للأخبار والقرارات"
        description="قناة أحادية الاتجاه، مع دورة قرار رسمية: مسودة ← مراجعة ← اعتماد ← نشر، وإصدارات وسجل تدقيق."
        actions={
          canPublish ? (
            <button className="btn-primary" onClick={() => setOpen(true)}>
              <Plus className="size-4" aria-hidden="true" />
              عنصر رسمي جديد
            </button>
          ) : undefined
        }
      />
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="المنشورات" value={allItems.length} icon={Megaphone} />
        <MetricCard label="القرارات" value={allItems.filter((x) => x.kind === 'decision').length} icon={FileText} />
        <MetricCard label="تحتاج إقرارًا" value={allItems.filter((x) => x.requiresAcknowledgement).length} icon={CheckCircle2} />
        <MetricCard label="عاجل" value={allItems.filter((x) => x.priority === 'urgent').length} icon={BellRing} />
      </section>
      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث في عنوان أو محتوى المنشور"
        resultText={`عرض ${items.length} من ${allItems.length} عنصر رسمي`}
        isDirty={Boolean(search || kind !== 'all' || priority !== 'all')}
        onClear={() => {
          setSearch('');
          setKind('all');
          setPriority('all');
        }}
      >
        <select className="input" aria-label="نوع العنصر الرسمي" value={kind} onChange={(event) => setKind(event.target.value)}>
          <option value="all">كل الأنواع</option>
          <option value="announcement">خبر أو إعلان</option>
          <option value="decision">قرار إداري</option>
        </select>
        <select className="input" aria-label="أولوية العنصر الرسمي" value={priority} onChange={(event) => setPriority(event.target.value)}>
          <option value="all">كل الأولويات</option>
          <option value="normal">عادية</option>
          <option value="high">مرتفعة</option>
          <option value="urgent">عاجلة</option>
        </select>
      </FilterBar>
      {transition.isError ? <ErrorBanner message={`تعذر تنفيذ إجراء القرار: ${safeErrorMessage(transition.error)}`} /> : null}
      {query.isError ? (
        <ErrorState title="تعذر تحميل القناة" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && allItems.length === 0 ? (
        <ListSkeleton rows={4} label="جارٍ تحميل القناة الرسمية" />
      ) : allItems.length === 0 ? (
        <EmptyState title="لا توجد منشورات بعد" description="لم يتم نشر أي خبر أو قرار رسمي حتى الآن." />
      ) : items.length === 0 ? (
        <EmptyState title="لا توجد نتائج مطابقة" description="جرّب تغيير كلمة البحث أو مسح الفلاتر الحالية." />
      ) : (
        <section className="grid gap-4 xl:grid-cols-2">
          {items.map((item) => {
            const action = item.kind === 'decision' ? nextAction(item.status) : null;
            const canRun = action === 'approve' ? canApproveDecision : canManageDecision;
            return (
              <article key={`${item.kind}-${item.id}`} className="card overflow-hidden">
                <div className="border-b border-[var(--border)] p-5">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <StatusBadge value={item.kind} />
                      <StatusBadge value={item.priority} />
                      <StatusBadge value={item.status} />
                    </div>
                    <span className="muted text-xs">
                      {item.publishedAt
                        ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.publishedAt))
                        : 'غير منشور'}
                    </span>
                  </div>
                  <h2 className="mt-4 text-xl font-black">{item.title}</h2>
                  {item.imageUrl ? <img src={item.imageUrl} alt={item.title} className="mt-3 h-44 w-full rounded-2xl object-cover" /> : null}
                  <p className="mt-3 text-sm leading-8">{item.body}</p>
                </div>
                {item.kind === 'announcement' ? (
                  <div className="grid grid-cols-3 gap-2 border-b border-[var(--border)] p-4 text-center">
                    <button
                      type="button"
                      className="rounded-xl bg-[var(--surface-muted)] p-3 transition hover:text-brand"
                      onClick={() => setEngagementItem({ id: item.id, title: item.title })}
                    >
                      <Eye className="mx-auto mb-1 size-5" aria-hidden="true" />
                      <strong className="block text-lg">{item.viewCount}</strong>
                      <span className="muted text-xs">شاهدوا</span>
                    </button>
                    <button
                      type="button"
                      className="rounded-xl bg-[var(--surface-muted)] p-3 transition hover:text-brand"
                      onClick={() => setEngagementItem({ id: item.id, title: item.title })}
                    >
                      <Heart className="mx-auto mb-1 size-5" aria-hidden="true" />
                      <strong className="block text-lg">{item.reactionCount}</strong>
                      <span className="muted text-xs">تفاعلوا</span>
                    </button>
                    <button
                      type="button"
                      className="rounded-xl bg-[var(--surface-muted)] p-3 transition hover:text-brand"
                      onClick={() => setEngagementItem({ id: item.id, title: item.title })}
                    >
                      <CheckCircle2 className="mx-auto mb-1 size-5" aria-hidden="true" />
                      <strong className="block text-lg">{item.acknowledgedCount}</strong>
                      <span className="muted text-xs">أقرّوا</span>
                    </button>
                  </div>
                ) : null}
                {item.requiresAcknowledgement ? (
                  <div className="p-5">
                    <div className="flex justify-between text-sm">
                      <span>نسبة الاطلاع والإقرار</span>
                      <strong>
                        {item.acknowledgedCount}
                        {item.targetCount ? ` / ${item.targetCount}` : ''}
                      </strong>
                    </div>
                    <div
                      className="mt-2 h-2 overflow-hidden rounded-full bg-[var(--surface-muted)]"
                      role="progressbar"
                      aria-label="نسبة الاطلاع والإقرار"
                      aria-valuemin={0}
                      aria-valuemax={item.targetCount ?? 0}
                      aria-valuenow={item.acknowledgedCount}
                    >
                      <div
                        className="h-full rounded-full bg-brand"
                        style={{ width: `${item.targetCount ? Math.min(100, (item.acknowledgedCount / item.targetCount) * 100) : 0}%` }}
                      />
                    </div>
                  </div>
                ) : null}
                {item.kind === 'announcement' && item.status === 'published' ? <AnnouncementReactionBar announcementId={item.id} /> : null}
                {action && canRun ? (
                  <div className="border-t border-[var(--border)] p-4">
                    <button
                      className="btn-secondary"
                      disabled={transition.isPending}
                      onClick={() =>
                        transition.mutate(
                          { decisionId: item.id, action },
                          {
                            onSuccess: () => toast({ message: `${actionLabel[action]} بنجاح`, tone: 'success' }),
                            onError: () => toast({ message: 'تعذر تنفيذ إجراء القرار', tone: 'error' }),
                          },
                        )
                      }
                    >
                      {action === 'approve' ? <ShieldCheck className="size-4" aria-hidden="true" /> : <Send className="size-4" aria-hidden="true" />}
                      {actionLabel[action]}
                    </button>
                  </div>
                ) : null}
              </article>
            );
          })}
        </section>
      )}
      {engagementItem ? (
        <DialogOverlay title={`مشاهدات وتفاعلات: ${engagementItem.title}`} onClose={() => setEngagementItem(null)} maxWidth="max-w-3xl">
          {engagementQuery.isLoading ? (
            <ListSkeleton rows={3} label="جارٍ تحميل المشاهدات والتفاعلات" />
          ) : engagementQuery.isError ? (
            <ErrorState
              title="تعذر تحميل أسماء المشاهدين والمتفاعلين"
              description={safeErrorMessage(engagementQuery.error)}
              onRetry={() => void engagementQuery.refetch()}
            />
          ) : engagementQuery.data ? (
            <div className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-2">
                <MetricCard label="المشاهدات" value={engagementQuery.data.viewerCount} icon={Eye} />
                <MetricCard label="التفاعلات" value={engagementQuery.data.reactionCount} icon={Heart} />
              </div>
              <EngagementPeople
                title="الأشخاص الذين تفاعلوا"
                empty="لم يتفاعل أحد مع الإعلان بعد."
                people={engagementQuery.data.reactions}
                icon={<Heart className="size-5" aria-hidden="true" />}
              />
            </div>
          ) : null}
        </DialogOverlay>
      ) : null}
      {open ? (
        <DialogOverlay title="إنشاء عنصر رسمي" onClose={() => setOpen(false)} maxWidth="max-w-2xl">
          <div className="grid grid-cols-2 gap-2 rounded-2xl bg-[var(--surface-muted)] p-1">
            <button
              type="button"
              className={`rounded-xl px-3 py-2 font-black ${mode === 'announcement' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`}
              onClick={() => setMode('announcement')}
            >
              خبر أو إعلان
            </button>
            <button
              type="button"
              className={`rounded-xl px-3 py-2 font-black ${mode === 'decision' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`}
              onClick={() => setMode('decision')}
            >
              قرار إداري
            </button>
          </div>
          <div className="mt-5 grid gap-4">
            <label className="text-sm font-bold">
              العنوان
              <input className="input mt-2" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
            </label>
            <label className="text-sm font-bold">
              المحتوى
              <textarea className="input mt-2 min-h-36 resize-y" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} />
            </label>
            {mode === 'announcement' ? (
              <div>
                <span className="text-sm font-bold">صورة الإعلان (اختياري)</span>
                <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={handleImageSelect} />
                {imagePreview ? (
                  <div className="relative mt-2">
                    <img src={imagePreview} alt="معاينة" className="h-40 w-full rounded-xl object-cover" />
                    <button
                      type="button"
                      className="absolute start-2 top-2 rounded-full bg-red-600 p-1 text-white shadow"
                      aria-label="إزالة الصورة"
                      onClick={() => void removeImage()}
                    >
                      <Trash2 className="size-4" aria-hidden="true" />
                    </button>
                  </div>
                ) : (
                  <button
                    type="button"
                    className="mt-2 flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-[var(--border)] p-6 text-sm transition hover:border-brand hover:text-brand"
                    disabled={imageUploading}
                    onClick={() => fileInputRef.current?.click()}
                  >
                    {imageUploading ? (
                      <span className="animate-pulse">جارٍ رفع الصورة…</span>
                    ) : (
                      <>
                        <ImagePlus className="size-5" aria-hidden="true" />
                        اضغط لاختيار صورة
                      </>
                    )}
                  </button>
                )}
                {imageError ? <p className="mt-1 text-xs text-[var(--danger)]">{imageError}</p> : null}
              </div>
            ) : null}
            {mode === 'announcement' ? (
              <div>
                <span className="text-sm font-bold">نوع المنشور</span>
                <div className="mt-2 grid grid-cols-2 gap-2 rounded-xl bg-[var(--surface-muted)] p-1">
                  <button
                    type="button"
                    className={`rounded-lg px-3 py-1.5 text-sm font-bold ${postType === 'standard' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`}
                    onClick={() => setPostType('standard')}
                  >
                    منشور عادي
                  </button>
                  <button
                    type="button"
                    className={`rounded-lg px-3 py-1.5 text-sm font-bold ${postType === 'poll' ? 'bg-[var(--surface-raised)] text-brand shadow-sm' : ''}`}
                    onClick={() => setPostType('poll')}
                  >
                    <ListPlus className="inline size-4 me-1" aria-hidden="true" />
                    تصويت
                  </button>
                </div>
                {postType === 'poll' ? (
                  <div className="mt-3 space-y-2">
                    <span className="text-sm font-bold">خيارات التصويت</span>
                    {pollOptions.map((opt, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <input
                          className="input flex-1"
                          placeholder={`الخيار ${i + 1}`}
                          value={opt}
                          onChange={(e) => {
                            const next = [...pollOptions];
                            next[i] = e.target.value;
                            setPollOptions(next);
                          }}
                        />
                        {pollOptions.length > 2 ? (
                          <button
                            type="button"
                            className="rounded-full p-1 text-[var(--danger)] hover:bg-red-50"
                            aria-label="حذف الخيار"
                            onClick={() => setPollOptions(pollOptions.filter((_, j) => j !== i))}
                          >
                            <X className="size-4" />
                          </button>
                        ) : null}
                      </div>
                    ))}
                    {pollOptions.length < 6 ? (
                      <button type="button" className="text-sm font-bold text-brand hover:underline" onClick={() => setPollOptions([...pollOptions, ''])}>
                        + إضافة خيار
                      </button>
                    ) : null}
                    <label className="block text-sm font-bold">
                      تاريخ انتهاء التصويت (اختياري)
                      <input type="datetime-local" className="input mt-2" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} />
                    </label>
                  </div>
                ) : null}
              </div>
            ) : null}
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="text-sm font-bold">
                التصنيف
                <select className="input mt-2" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
                  <option value="general">عام</option>
                  <option value="hr">موارد بشرية</option>
                  <option value="policy">سياسة</option>
                  <option value="organizational">تنظيمي</option>
                  <option value="financial">مالي</option>
                </select>
              </label>
              {mode === 'announcement' ? (
                <label className="text-sm font-bold">
                  الأولوية
                  <select className="input mt-2" value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })}>
                    <option value="normal">عادية</option>
                    <option value="high">مرتفعة</option>
                    <option value="urgent">عاجلة</option>
                  </select>
                </label>
              ) : null}
            </div>
            {mode === 'decision' ? (
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="text-sm font-bold">
                  النتيجة المتوقعة
                  <input className="input mt-2" value={form.expectedOutcome} onChange={(e) => setForm({ ...form, expectedOutcome: e.target.value })} />
                </label>
                <label className="text-sm font-bold">
                  مؤشر قياس النجاح
                  <input className="input mt-2" value={form.successMetric} onChange={(e) => setForm({ ...form, successMetric: e.target.value })} />
                </label>
              </div>
            ) : null}
            <label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-4 text-sm font-bold">
              <input type="checkbox" checked={form.requiresAcknowledgement} onChange={(e) => setForm({ ...form, requiresAcknowledgement: e.target.checked })} />
              يتطلب إقرارًا بالاطلاع
            </label>
            {submitError ? <ErrorBanner message="تعذر حفظ العنصر الرسمي." /> : null}
            <button
              className="btn-primary"
              disabled={isSubmitting || imageUploading || form.title.trim().length < 3 || form.body.trim().length < 10}
              onClick={() =>
                void submit().then((ok) => {
                  if (ok) {
                    setOpen(false);
                    toast({ message: mode === 'decision' ? 'تم حفظ مسودة القرار بنجاح' : 'تم نشر العنصر الرسمي بنجاح', tone: 'success' });
                  } else {
                    toast({ message: 'تعذر حفظ العنصر الرسمي', tone: 'error' });
                  }
                })
              }
            >
              {mode === 'decision' ? 'حفظ كمسودة قرار' : 'نشر الآن'}
            </button>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function EngagementPeople({
  title,
  empty,
  people,
  icon,
}: {
  title: string;
  empty: string;
  people: Array<{ employeeId: string; name: string; photoUrl: string | null; at: string; viewCount?: number; reactionType?: string }>;
  icon: React.ReactNode;
}) {
  const reactionLabels: Record<string, string> = {
    like: 'أعجبني',
    celebrate: 'احتفال',
    support: 'دعم',
    insightful: 'مفيد',
  };
  return (
    <section className="rounded-2xl border border-[var(--border)] p-4">
      <h3 className="mb-3 flex items-center gap-2 font-black">
        {icon}
        {title}
        <span className="muted text-sm">({people.length})</span>
      </h3>
      {people.length === 0 ? (
        <p className="muted py-4 text-center text-sm">{empty}</p>
      ) : (
        <div className="grid gap-2 sm:grid-cols-2">
          {people.map((person) => (
            <div key={person.employeeId} className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-3">
              <UserAvatar displayName={person.name} photoUrl={person.photoUrl} size="sm" announceName={false} />
              <div className="min-w-0 flex-1">
                <strong className="block truncate text-sm">{person.name}</strong>
                <span className="muted text-xs">
                  {person.reactionType ? `${reactionLabels[person.reactionType] ?? person.reactionType} · ` : ''}
                  {person.viewCount && person.viewCount > 1 ? `${person.viewCount} مرات · ` : ''}
                  {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(person.at))}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
