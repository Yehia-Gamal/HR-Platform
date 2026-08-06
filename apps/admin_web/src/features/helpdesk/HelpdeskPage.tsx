import { useMemo, useState } from 'react';
import { LifeBuoy, Plus, Ticket, Wrench } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { ListSkeleton } from '../../ui/Skeletons';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { useMyServicePortal, useSubmitServiceRequest } from '../governance/useGovernance';

const PRIORITY_TONE: Record<string, 'success' | 'warning' | 'info' | 'neutral' | 'danger'> = {
  urgent: 'danger', high: 'warning', normal: 'info', low: 'neutral',
};
const PRIORITY_LABELS: Record<string, string> = { urgent: 'عاجل', high: 'مرتفع', normal: 'عادي', low: 'منخفض' };
const STATUS_LABELS: Record<string, string> = { open: 'مفتوح', in_progress: 'قيد المعالجة', resolved: 'تم الحل', closed: 'مغلق', cancelled: 'ملغي' };

export function HelpdeskPage() {
  const { toast } = useToast();
  const [search, setSearch] = useState('');
  const [showNewRequest, setShowNewRequest] = useState(false);
  const portalQuery = useMyServicePortal();
  const submitRequest = useSubmitServiceRequest();

  const catalog = useMemo(() => portalQuery.data?.catalog ?? [], [portalQuery.data]);
  const requests = useMemo(() => portalQuery.data?.requests ?? [], [portalQuery.data]);

  const stats = useMemo(() => ({
    open: requests.filter((r) => r.status === 'open' || r.status === 'in_progress').length,
    resolved: requests.filter((r) => r.status === 'resolved' || r.status === 'closed').length,
    catalogItems: catalog.length,
  }), [requests, catalog]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return requests;
    return requests.filter((r) => r.title?.toLowerCase().includes(q) || r.number?.toLowerCase().includes(q) || r.serviceName?.toLowerCase().includes(q));
  }, [requests, search]);

  if (portalQuery.isLoading) return <ListSkeleton />;
  if (portalQuery.isError) return <ErrorState title="تعذّر تحميل البيانات" description={safeErrorMessage(portalQuery.error)} onRetry={() => portalQuery.refetch()} />;

  return (
    <div className="space-y-5">
      <PageHeader eyebrow="مكتب الخدمات" title="مركز الخدمات الذاتية" description="تقديم ومتابعة طلبات الخدمة المؤسسية"
        actions={<button type="button" className="btn-primary" onClick={() => setShowNewRequest(true)}><Plus className="size-4" aria-hidden="true" /> طلب خدمة</button>} />

      <section className="grid gap-3 sm:grid-cols-3">
        <MetricCard label="طلبات مفتوحة" value={stats.open} icon={Ticket} />
        <MetricCard label="طلبات محلولة" value={stats.resolved} icon={LifeBuoy} />
        <MetricCard label="خدمات متاحة" value={stats.catalogItems} icon={Wrench} />
      </section>

      <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="بحث في طلباتي…" resultText={`عرض ${filtered.length} من ${requests.length} طلب`} isDirty={Boolean(search)} onClear={() => setSearch('')} />

      {!filtered.length ? (
        <EmptyState title="لا توجد طلبات" description="لم تقم بتقديم أي طلب خدمة بعد" />
      ) : (
        <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
          <table className="w-full text-sm">
            <thead><tr className="bg-[var(--surface-muted)] text-right">
              <th className="px-4 py-3 font-semibold">الرقم</th><th className="px-4 py-3 font-semibold">الخدمة</th><th className="px-4 py-3 font-semibold">العنوان</th><th className="px-4 py-3 font-semibold">الأولوية</th><th className="px-4 py-3 font-semibold">الحالة</th><th className="px-4 py-3 font-semibold">الاستحقاق</th>
            </tr></thead>
            <tbody className="divide-y divide-[var(--border-color)]">
              {filtered.map((r) => (
                <tr key={r.id} className="hover:bg-[var(--surface-hover)]">
                  <td className="px-4 py-3 font-mono text-xs">{r.number}</td>
                  <td className="px-4 py-3 text-[var(--text-secondary)]">{r.serviceName ?? '—'}</td>
                  <td className="px-4 py-3 font-medium">{r.title}</td>
                  <td className="px-4 py-3"><StatusBadge status={PRIORITY_TONE[r.priority] ?? 'neutral'} label={PRIORITY_LABELS[r.priority] ?? r.priority} /></td>
                  <td className="px-4 py-3"><StatusBadge status={r.status === 'resolved' || r.status === 'closed' ? 'success' : r.status === 'in_progress' ? 'warning' : 'info'} label={STATUS_LABELS[r.status] ?? r.status} /></td>
                  <td className="px-4 py-3 text-xs text-[var(--text-tertiary)]">{r.dueAt ? new Date(r.dueAt).toLocaleDateString('ar-EG') : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showNewRequest && (
        <DialogOverlay title="تقديم طلب خدمة جديد" onClose={() => setShowNewRequest(false)}>
          <NewServiceRequestForm catalog={catalog} onSubmit={async (data) => {
            try { await submitRequest.mutateAsync(data); toast({ message: 'تم تقديم الطلب بنجاح', tone: 'success' }); setShowNewRequest(false); }
            catch (error) { toast({ message: safeErrorMessage(error), tone: 'error' }); }
          }} onCancel={() => setShowNewRequest(false)} isSubmitting={submitRequest.isPending} />
        </DialogOverlay>
      )}
    </div>
  );
}

function NewServiceRequestForm({ catalog, onSubmit, onCancel, isSubmitting }: {
  catalog: Array<{ id: string; name: string }>;
  onSubmit: (data: { catalogItemId: string; title: string; description: string; priority: string }) => void;
  onCancel: () => void;
  isSubmitting: boolean;
}) {
  const [form, setForm] = useState({ catalogItemId: catalog[0]?.id ?? '', title: '', description: '', priority: 'normal' });
  const canSubmit = form.catalogItemId && form.title.trim().length > 0;
  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit(form); }} className="space-y-4">
      <div>
        <label className="label-field">الخدمة *</label>
        <select value={form.catalogItemId} onChange={(e) => setForm({ ...form, catalogItemId: e.target.value })} className="form-select w-full" required>
          {catalog.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </div>
      <div>
        <label className="label-field">العنوان *</label>
        <input type="text" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="form-input w-full" placeholder="عنوان موجز للطلب" required />
      </div>
      <div>
        <label className="label-field">الوصف</label>
        <textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} className="form-textarea w-full min-h-[80px]" placeholder="تفاصيل الطلب…" />
      </div>
      <div>
        <label className="label-field">الأولوية</label>
        <select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })} className="form-select w-full">
          <option value="low">منخفض</option><option value="normal">عادي</option><option value="high">مرتفع</option><option value="urgent">عاجل</option>
        </select>
      </div>
      <div className="flex justify-end gap-2 border-t border-[var(--border-color)] pt-4">
        <button type="button" onClick={onCancel} className="btn-secondary">إلغاء</button>
        <button type="submit" disabled={!canSubmit || isSubmitting} className="btn-primary">{isSubmitting ? 'جاري الإرسال…' : 'تقديم الطلب'}</button>
      </div>
    </form>
  );
}
