import { useMemo, useState, type FormEvent } from 'react';
import type { KnowledgeArticle } from '@ahla/shared-contracts';
import { BookOpen, Loader2, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useDeleteKnowledgeArticle, useKnowledgeArticles, useUpsertKnowledgeArticle } from './useKnowledge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

export function KnowledgePage() {
  const query = useKnowledgeArticles();
  const upsert = useUpsertKnowledgeArticle();
  const del = useDeleteKnowledgeArticle();
  const { toast } = useToast();
  const auth = useAuth();
  const canManage = Boolean(auth.access && (hasPermission(auth.access, 'knowledge.write') || auth.access.permissions.includes('*')));

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [editItem, setEditItem] = useState<KnowledgeArticle | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const articles = useMemo(() => query.data ?? [], [query.data]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return articles.filter((a) => {
      const matchSearch = !q || a.title.toLowerCase().includes(q) || (a.category ?? '').toLowerCase().includes(q);
      const matchStatus = statusFilter === 'all' || (statusFilter === 'published' && a.is_published) || (statusFilter === 'draft' && !a.is_published);
      return matchSearch && matchStatus;
    });
  }, [articles, search, statusFilter]);

  const dirty = Boolean(search.trim() || statusFilter !== 'all');
  const clearFilters = () => { setSearch(''); setStatusFilter('all'); };

  const publishedCount = articles.filter((a) => a.is_published).length;
  const draftCount = articles.length - publishedCount;
  const categories = [...new Set(articles.map((a) => a.category).filter(Boolean))] as string[];

  const handleDelete = async (item: KnowledgeArticle) => {
    if (!window.confirm(`حذف «${item.title}»؟`)) return;
    try {
      await del.mutateAsync(item.id);
      toast({ message: 'تم حذف المقال', tone: 'success' });
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
    }
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="المعرفة"
        title="قاعدة المعرفة"
        description="مكتبة مقالات إرشادية ومرجعية لكل الموظفين."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary" onClick={() => void query.refetch()} disabled={query.isFetching}>
              <RefreshCw className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
              تحديث
            </button>
            {canManage ? (
              <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
                <Plus className="size-4" aria-hidden="true" />
                مقال جديد
              </button>
            ) : null}
          </div>
        }
      />

      {query.isLoading ? (
        <MetricSkeletonRow count={3} />
      ) : (
        <section className="grid gap-3 sm:grid-cols-3">
          <MetricCard label="مقالات منشورة" value={publishedCount} icon={BookOpen} hint="متاحة للجميع" />
          <MetricCard label="مسودات" value={draftCount} icon={BookOpen} hint="غير منشورة" />
          <MetricCard label="تصنيفات" value={categories.length} icon={BookOpen} hint="فئات مختلفة" />
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالعنوان أو التصنيف…"
        resultText={`عرض ${filtered.length} من ${articles.length} مقال`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select className="input" value={statusFilter} onChange={(ev) => setStatusFilter(ev.target.value)} aria-label="تصفية حسب الحالة">
          <option value="all">كل الحالات</option>
          <option value="published">منشور</option>
          <option value="draft">مسودة</option>
        </select>
      </FilterBar>

      {query.isError ? (
        <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل المقالات…" />
      ) : filtered.length === 0 ? (
        <EmptyState
          title="لا توجد مقالات"
          description={canManage ? 'ابدأ بإنشاء أول مقال في قاعدة المعرفة.' : 'لم يُنشر أي مقال بعد.'}
          action={canManage ? (
            <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
              <Plus className="size-4" aria-hidden="true" /> إنشاء مقال
            </button>
          ) : undefined}
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {filtered.map((item) => (
            <article key={item.id} className="card flex flex-col overflow-hidden">
              <div className="border-b border-[var(--border)] p-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <h3 className="truncate font-black">{item.title}</h3>
                    {item.category ? <span className="muted text-xs">{item.category}</span> : null}
                  </div>
                  <StatusBadge status={item.is_published ? 'active' : 'pending'} label={item.is_published ? 'منشور' : 'مسودة'} />
                </div>
              </div>
              <div className="flex-1 p-4 text-sm leading-7 text-[var(--text-secondary)]">
                {item.body ? (
                  <p className="line-clamp-4">{item.body}</p>
                ) : (
                  <p className="muted">لا يوجد محتوى.</p>
                )}
              </div>
              <div className="flex items-center justify-between gap-2 border-t border-[var(--border)] px-4 py-3">
                <span className="muted text-xs">
                  {item.updated_at ? dateFormatter.format(new Date(item.updated_at)) : dateFormatter.format(new Date(item.created_at))}
                </span>
                {canManage ? (
                  <div className="flex gap-1">
                    <button
                      type="button"
                      title="تعديل"
                      aria-label={`تعديل ${item.title}`}
                      className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:bg-[var(--surface-muted)]"
                      disabled={upsert.isPending}
                      onClick={() => setEditItem(item)}
                    >
                      <BookOpen className="size-4" aria-hidden="true" />
                    </button>
                    <button
                      type="button"
                      title="حذف"
                      aria-label={`حذف ${item.title}`}
                      className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--danger)] transition hover:bg-red-50"
                      disabled={del.isPending}
                      onClick={() => void handleDelete(item)}
                    >
                      <Trash2 className="size-4" aria-hidden="true" />
                    </button>
                  </div>
                ) : null}
              </div>
            </article>
          ))}
        </div>
      )}

      {createOpen ? <ArticleDialog onClose={() => setCreateOpen(false)} /> : null}
      {editItem ? <ArticleDialog item={editItem} onClose={() => setEditItem(null)} /> : null}
    </div>
  );
}

function ArticleDialog({ item, onClose }: { item?: KnowledgeArticle; onClose: () => void }) {
  const upsert = useUpsertKnowledgeArticle();
  const { toast } = useToast();
  const [title, setTitle] = useState(item?.title ?? '');
  const [category, setCategory] = useState(item?.category ?? '');
  const [body, setBody] = useState(item?.body ?? '');
  const [isPublished, setIsPublished] = useState(item?.is_published ?? false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (title.trim().length < 3) {
      setError('العنوان مطلوب (3 أحرف على الأقل).');
      return;
    }
    try {
      await upsert.mutateAsync({
        id: item?.id ?? null,
        title,
        category: category || null,
        body: body || null,
        is_published: isPublished,
      });
      toast({ message: item ? 'تم تحديث المقال' : 'تم إنشاء المقال', tone: 'success' });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title={item ? 'تعديل مقال' : 'مقال جديد'} onClose={onClose} maxWidth="max-w-2xl">
      <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
        {error ? (
          <div className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div>
        ) : null}

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">العنوان <span className="text-[var(--danger)]">*</span></span>
          <input
            className="input"
            required
            minLength={3}
            autoFocus
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="عنوان المقال…"
          />
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">التصنيف</span>
          <input
            className="input"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            placeholder="مثلاً: إجراءات، سياسات، أسئلة شائعة…"
          />
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">المحتوى</span>
          <textarea
            className="input min-h-32 w-full"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="اكتب محتوى المقال هنا…"
          />
        </label>

        <label className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={isPublished}
            onChange={(e) => setIsPublished(e.target.checked)}
          />
          <span className="text-sm font-bold">نشر (يصبح مرئياً لكل الموظفين)</span>
        </label>

        <div className="flex justify-end gap-3 pt-2">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={upsert.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={upsert.isPending}>
            {upsert.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
            {item ? 'حفظ التعديلات' : 'إنشاء'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
