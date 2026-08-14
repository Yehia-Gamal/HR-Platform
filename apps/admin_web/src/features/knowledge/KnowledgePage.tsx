import { useMemo, useState, type FormEvent } from 'react';
import type { KnowledgeArticle, KnowledgeCategory } from '@ahla/shared-contracts';
import { BookOpen, FolderPlus, Loader2, Plus, RefreshCw, Trash2 } from 'lucide-react';
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
import {
  useDeleteKnowledgeArticle,
  useDeleteKnowledgeCategory,
  useKnowledgeCatalog,
  useUpsertKnowledgeArticle,
  useUpsertKnowledgeCategory,
} from './useKnowledge';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });

export function KnowledgePage() {
  const auth = useAuth();
  const canWrite = Boolean(auth.access && (hasPermission(auth.access, 'knowledge.write') || auth.access.permissions.includes('*')));
  const canManageCategories = Boolean(auth.access && (hasPermission(auth.access, 'knowledge.manage') || auth.access.permissions.includes('*')));

  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'published' | 'draft'>('all');

  const query = useKnowledgeCatalog({ search, categoryId: categoryFilter || null, status: statusFilter });
  const upsert = useUpsertKnowledgeArticle();
  const del = useDeleteKnowledgeArticle();
  const { toast } = useToast();

  const [editItem, setEditItem] = useState<KnowledgeArticle | null>(null);
  const [createOpen, setCreateOpen] = useState(false);
  const [categoryOpen, setCategoryOpen] = useState(false);
  const [categoryDialogItem, setCategoryDialogItem] = useState<KnowledgeCategory | null>(null);

  const articles = useMemo(() => query.data?.articles ?? [], [query.data]);
  const catalogCategories = useMemo(() => query.data?.categories ?? [], [query.data]);

  const publishedCount = query.data?.publishedCount ?? 0;
  const draftCount = query.data?.draftCount ?? 0;
  const categories = catalogCategories;
  const canManage = canWrite || canManageCategories;

  const dirty = Boolean(search.trim() || statusFilter !== 'all' || categoryFilter);
  const clearFilters = () => {
    setSearch('');
    setStatusFilter('all');
    setCategoryFilter('');
  };

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
            {canManageCategories ? (
              <button type="button" className="btn-secondary" onClick={() => setCategoryOpen(true)}>
                <FolderPlus className="size-4" aria-hidden="true" />
                إدارة التصنيفات
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
          <MetricCard label="تصنيفات" value={categories.length} icon={FolderPlus} hint="فئات مُدارة" />
        </section>
      )}

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="ابحث بالعنوان أو المحتوى أو التصنيف…"
        resultText={`عرض ${articles.length} مقال`}
        isDirty={dirty}
        onClear={clearFilters}
      >
        <select
          className="input"
          value={statusFilter}
          onChange={(ev) => setStatusFilter(ev.target.value as 'all' | 'published' | 'draft')}
          aria-label="تصفية حسب الحالة"
        >
          <option value="all">كل الحالات</option>
          <option value="published">منشور</option>
          <option value="draft">مسودة</option>
        </select>
        <select className="input" value={categoryFilter} onChange={(ev) => setCategoryFilter(ev.target.value)} aria-label="تصفية حسب التصنيف">
          <option value="">كل التصنيفات</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </FilterBar>

      {query.isError ? (
        <ErrorState description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل المقالات…" />
      ) : articles.length === 0 ? (
        <EmptyState
          title="لا توجد مقالات"
          description={canManage ? 'ابدأ بإنشاء أول مقال في قاعدة المعرفة.' : 'لم يُنشر أي مقال بعد.'}
          action={
            canManage ? (
              <button type="button" className="btn-primary" onClick={() => setCreateOpen(true)}>
                <Plus className="size-4" aria-hidden="true" /> إنشاء مقال
              </button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {articles.map((item) => (
            <article key={item.id} className="card flex flex-col overflow-hidden">
              <div className="border-b border-[var(--border)] p-4">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <h3 className="truncate font-black">{item.title}</h3>
                    {item.category_name ? (
                      <span className="muted text-xs">{item.category_name}</span>
                    ) : item.category ? (
                      <span className="muted text-xs">{item.category}</span>
                    ) : null}
                  </div>
                  <StatusBadge status={item.is_published ? 'active' : 'pending'} label={item.is_published ? 'منشور' : 'مسودة'} />
                </div>
              </div>
              <div className="flex-1 p-4 text-sm leading-7 text-[var(--text-secondary)]">
                {item.body ? <p className="line-clamp-4">{item.body}</p> : <p className="muted">لا يوجد محتوى.</p>}
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

      {createOpen ? <ArticleDialog categories={catalogCategories} onClose={() => setCreateOpen(false)} /> : null}
      {editItem ? <ArticleDialog item={editItem} categories={catalogCategories} onClose={() => setEditItem(null)} /> : null}
      {categoryOpen ? <CategoriesDialog categories={catalogCategories} onClose={() => setCategoryOpen(false)} /> : null}
      {categoryDialogItem ? <CategoryDialog item={categoryDialogItem} onClose={() => setCategoryDialogItem(null)} /> : null}
    </div>
  );
}

function ArticleDialog({ item, categories, onClose }: { item?: KnowledgeArticle; categories: KnowledgeCategory[]; onClose: () => void }) {
  const upsert = useUpsertKnowledgeArticle();
  const { toast } = useToast();
  const [title, setTitle] = useState(item?.title ?? '');
  const [categoryId, setCategoryId] = useState(item?.category_id ?? '');
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
    const selected = categories.find((c) => c.id === categoryId);
    try {
      await upsert.mutateAsync({
        id: item?.id ?? null,
        title,
        category: selected?.name ?? null,
        category_id: categoryId || null,
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
        {error ? <div className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">
            العنوان <span className="text-[var(--danger)]">*</span>
          </span>
          <input className="input" required minLength={3} autoFocus value={title} onChange={(e) => setTitle(e.target.value)} placeholder="عنوان المقال…" />
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">التصنيف</span>
          <select className="input" value={categoryId} onChange={(e) => setCategoryId(e.target.value)} aria-label="اختيار التصنيف">
            <option value="">بدون تصنيف</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">المحتوى</span>
          <textarea className="input min-h-32 w-full" value={body} onChange={(e) => setBody(e.target.value)} placeholder="اكتب محتوى المقال هنا…" />
        </label>

        <label className="flex items-center gap-2">
          <input type="checkbox" checked={isPublished} onChange={(e) => setIsPublished(e.target.checked)} />
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

function CategoriesDialog({ categories, onClose }: { categories: KnowledgeCategory[]; onClose: () => void }) {
  const deleteCategory = useDeleteKnowledgeCategory();
  const { toast } = useToast();
  const [dialogItem, setDialogItem] = useState<KnowledgeCategory | null>(null);

  const handleDelete = async (item: KnowledgeCategory) => {
    if (!window.confirm(`حذف تصنيف «${item.name}»؟ ستبقى المقالات دون تصنيف.`)) return;
    try {
      await deleteCategory.mutateAsync(item.id);
      toast({ message: 'تم حذف التصنيف', tone: 'success' });
    } catch (err) {
      toast({ message: safeErrorMessage(err), tone: 'error' });
    }
  };

  return (
    <DialogOverlay title="إدارة التصنيفات" onClose={onClose} maxWidth="max-w-lg">
      <div className="space-y-3">
        {categories.length === 0 ? (
          <p className="muted text-sm">لا توجد تصنيفات بعد.</p>
        ) : (
          categories.map((c) => (
            <div key={c.id} className="flex items-center justify-between gap-3 rounded-xl border border-[var(--border)] p-3">
              <div className="min-w-0">
                <p className="truncate font-bold">{c.name}</p>
                {c.description ? <p className="muted text-xs">{c.description}</p> : null}
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <StatusBadge status={c.is_active ? 'active' : 'inactive'} label={c.is_active ? 'نشط' : 'معطّل'} />
                <button
                  type="button"
                  title="تعديل"
                  aria-label={`تعديل ${c.name}`}
                  className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--text-secondary)] transition hover:bg-[var(--surface-muted)]"
                  onClick={() => setDialogItem(c)}
                >
                  <BookOpen className="size-4" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  title="حذف"
                  aria-label={`حذف ${c.name}`}
                  className="grid size-8 place-items-center rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--danger)] transition hover:bg-red-50"
                  onClick={() => void handleDelete(c)}
                >
                  <Trash2 className="size-4" aria-hidden="true" />
                </button>
              </div>
            </div>
          ))
        )}
        <button type="button" className="btn-primary w-full" onClick={() => setDialogItem({} as KnowledgeCategory)}>
          <Plus className="size-4" aria-hidden="true" /> تصنيف جديد
        </button>
      </div>
      {dialogItem ? <CategoryDialog item={dialogItem} onClose={() => setDialogItem(null)} /> : null}
    </DialogOverlay>
  );
}

function CategoryDialog({ item, onClose }: { item: KnowledgeCategory; onClose: () => void }) {
  const upsert = useUpsertKnowledgeCategory();
  const { toast } = useToast();
  const isNew = !item.id;
  const [name, setName] = useState(item.name ?? '');
  const [slug, setSlug] = useState(item.slug ?? '');
  const [description, setDescription] = useState(item.description ?? '');
  const [isActive, setIsActive] = useState(item.is_active ?? true);
  const [error, setError] = useState<string | null>(null);

  const slugify = (v: string) =>
    v
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '-')
      .replace(/[^\w\u0600-\u06FF-]/g, '');

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (name.trim().length < 2) {
      setError('اسم التصنيف مطلوب (حرفان على الأقل).');
      return;
    }
    if (slug.trim().length < 2) {
      setError('المعرّف (slug) مطلوب.');
      return;
    }
    try {
      await upsert.mutateAsync({
        id: item.id ?? null,
        name,
        slug,
        description: description || null,
        is_active: isActive,
      });
      toast({ message: isNew ? 'تم إنشاء التصنيف' : 'تم تحديث التصنيف', tone: 'success' });
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title={isNew ? 'تصنيف جديد' : 'تعديل تصنيف'} onClose={onClose} maxWidth="max-w-lg">
      <form className="space-y-4" onSubmit={(e) => void handleSubmit(e)}>
        {error ? <div className="rounded-xl bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">
            الاسم <span className="text-[var(--danger)]">*</span>
          </span>
          <input
            className="input"
            required
            minLength={2}
            autoFocus
            value={name}
            onChange={(e) => {
              setName(e.target.value);
              if (isNew) setSlug(slugify(e.target.value));
            }}
            placeholder="مثلاً: إجراءات"
          />
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">
            المعرّف (slug) <span className="text-[var(--danger)]">*</span>
          </span>
          <input className="input" required minLength={2} dir="ltr" value={slug} onChange={(e) => setSlug(slugify(e.target.value))} placeholder="procedures" />
        </label>

        <label className="block space-y-1.5">
          <span className="text-sm font-bold">الوصف</span>
          <textarea className="input min-h-20 w-full" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="وصف مختصر للتصنيف…" />
        </label>

        <label className="flex items-center gap-2">
          <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
          <span className="text-sm font-bold">نشط (يظهر في القوائم)</span>
        </label>

        <div className="flex justify-end gap-3 pt-2">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={upsert.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={upsert.isPending}>
            {upsert.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : null}
            {isNew ? 'إنشاء' : 'حفظ'}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}
