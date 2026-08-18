import { useMemo, useState } from 'react';
import { FileText, FilePlus, Plus, Signature } from 'lucide-react';
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
import { useDocumentStudioCatalog, useUpsertTemplate, type TemplateInput } from './useDocumentsStudio';

const DOC_TYPE_LABELS: Record<string, string> = {
  contract: 'عقد',
  offer_letter: 'خطاب عرض',
  warning: 'إنذار',
  certificate: 'شهادة',
  experience_letter: 'شهادة خبرة',
  other: 'أخرى',
};

const DOC_STATUS_LABELS: Record<string, string> = {
  draft: 'مسودة',
  pending_signature: 'بانتظار التوقيع',
  issued: 'صادر',
  expired: 'منتهي',
  revoked: 'ملغي',
};

const DOC_STATUS_TONE: Record<string, 'success' | 'warning' | 'info' | 'neutral' | 'danger'> = {
  draft: 'neutral',
  pending_signature: 'warning',
  issued: 'success',
  expired: 'neutral',
  revoked: 'danger',
};

export function DocumentsStudioPage() {
  const { toast } = useToast();
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<'documents' | 'templates'>('documents');
  const [showEditor, setShowEditor] = useState(false);

  const catalogQuery = useDocumentStudioCatalog();
  const upsertTemplate = useUpsertTemplate();

  const templates = useMemo(() => catalogQuery.data?.templates ?? [], [catalogQuery.data]);
  const documents = useMemo(() => catalogQuery.data?.documents ?? [], [catalogQuery.data]);

  const stats = useMemo(
    () => ({
      totalDocs: documents.length,
      issued: documents.filter((d) => d.status === 'issued').length,
      pendingSig: documents.filter((d) => d.pendingSignatures > 0).length,
      activeTemplates: templates.filter((t) => t.active).length,
    }),
    [documents, templates],
  );

  const filteredDocs = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return documents;
    return documents.filter(
      (d) => d.title?.toLowerCase().includes(q) || d.referenceNumber?.toLowerCase().includes(q) || d.employeeName?.toLowerCase().includes(q),
    );
  }, [documents, search]);

  const filteredTemplates = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return templates;
    return templates.filter((t) => t.name?.toLowerCase().includes(q) || t.code?.toLowerCase().includes(q));
  }, [templates, search]);

  const handleSave = async (input: TemplateInput) => {
    try {
      await upsertTemplate.mutateAsync(input);
      toast({ message: 'تم حفظ القالب', tone: 'success' });
      setShowEditor(false);
    } catch (error) {
      toast({ message: safeErrorMessage(error), tone: 'error' });
    }
  };

  if (catalogQuery.isLoading) return <ListSkeleton />;
  if (catalogQuery.isError)
    return <ErrorState title="تعذّر التحميل" description={safeErrorMessage(catalogQuery.error)} onRetry={() => catalogQuery.refetch()} />;

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="المستندات"
        title="استوديو المستندات"
        description="إدارة قوالب المستندات والمستندات المُولّدة والتوقيعات"
        actions={
          <button type="button" className="btn-primary" onClick={() => setShowEditor(true)}>
            <Plus className="size-4" aria-hidden="true" />
            قالب جديد
          </button>
        }
      />

      <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard label="مستندات مُولّدة" value={stats.totalDocs} icon={FileText} />
        <MetricCard label="صادرة" value={stats.issued} icon={FileText} />
        <MetricCard label="بانتظار توقيع" value={stats.pendingSig} icon={Signature} />
        <MetricCard label="قوالب نشطة" value={stats.activeTemplates} icon={FilePlus} />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث بالاسم أو الرقم…"
        resultText={tab === 'documents' ? `${filteredDocs.length} مستند` : `${filteredTemplates.length} قالب`}
        isDirty={Boolean(search)}
        onClear={() => setSearch('')}
      />

      <div className="flex gap-2">
        <button className={`btn-sm ${tab === 'documents' ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setTab('documents')}>
          المستندات
        </button>
        <button className={`btn-sm ${tab === 'templates' ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setTab('templates')}>
          القوالب
        </button>
      </div>

      {tab === 'documents' &&
        (!filteredDocs.length ? (
          <EmptyState title="لا توجد مستندات" description="لم يتم توليد أي مستندات بعد" />
        ) : (
          <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-muted)] text-right">
                  <th className="px-4 py-3 font-semibold">الرقم المرجعي</th>
                  <th className="px-4 py-3 font-semibold">العنوان</th>
                  <th className="px-4 py-3 font-semibold">النوع</th>
                  <th className="px-4 py-3 font-semibold">الموظف</th>
                  <th className="px-4 py-3 font-semibold">الحالة</th>
                  <th className="px-4 py-3 font-semibold">توقيعات معلقة</th>
                  <th className="px-4 py-3 font-semibold">الإصدار</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-color)]">
                {filteredDocs.map((d) => (
                  <tr key={d.id} className="hover:bg-[var(--surface-hover)]">
                    <td className="px-4 py-3 font-mono text-xs">{d.referenceNumber ?? '—'}</td>
                    <td className="px-4 py-3 font-medium">{d.title}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{DOC_TYPE_LABELS[d.documentType] ?? d.documentType}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{d.employeeName ?? '—'}</td>
                    <td className="px-4 py-3">
                      <StatusBadge status={DOC_STATUS_TONE[d.status] ?? 'neutral'} label={DOC_STATUS_LABELS[d.status] ?? d.status} />
                    </td>
                    <td className="px-4 py-3 text-center">
                      {d.pendingSignatures > 0 ? <span className="font-bold text-[var(--warning)]">{d.pendingSignatures}</span> : '—'}
                    </td>
                    <td className="px-4 py-3 text-xs text-[var(--text-tertiary)]">{d.issuedAt ? new Date(d.issuedAt).toLocaleDateString('ar-EG') : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}

      {tab === 'templates' &&
        (!filteredTemplates.length ? (
          <EmptyState title="لا توجد قوالب" description="لم يتم إنشاء أي قوالب مستندات بعد" />
        ) : (
          <div className="overflow-x-auto rounded-xl border border-[var(--border-color)] bg-[var(--surface)]">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[var(--surface-muted)] text-right">
                  <th className="px-4 py-3 font-semibold">الرمز</th>
                  <th className="px-4 py-3 font-semibold">الاسم</th>
                  <th className="px-4 py-3 font-semibold">النوع</th>
                  <th className="px-4 py-3 font-semibold">الإصدار</th>
                  <th className="px-4 py-3 font-semibold">التوقيعات المطلوبة</th>
                  <th className="px-4 py-3 font-semibold">الحالة</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-color)]">
                {filteredTemplates.map((t) => (
                  <tr key={t.id} className="hover:bg-[var(--surface-hover)]">
                    <td className="px-4 py-3 font-mono text-xs">{t.code}</td>
                    <td className="px-4 py-3 font-medium">{t.name}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{DOC_TYPE_LABELS[t.documentType] ?? t.documentType}</td>
                    <td className="px-4 py-3 text-center">v{t.version}</td>
                    <td className="px-4 py-3 text-xs">
                      <div className="flex gap-1 flex-wrap">
                        {t.requiresEmployeeSignature && (
                          <span className="rounded bg-[var(--brand-primary-soft)] px-1.5 py-0.5 text-[var(--brand-primary)]">موظف</span>
                        )}
                        {t.requiresHrSignature && <span className="rounded bg-[var(--warning-soft)] px-1.5 py-0.5 text-[var(--warning)]">HR</span>}
                        {t.requiresExecutiveSignature && <span className="rounded bg-[var(--danger-soft)] px-1.5 py-0.5 text-[var(--danger)]">تنفيذي</span>}
                        {!t.requiresEmployeeSignature && !t.requiresManagerSignature && !t.requiresHrSignature && !t.requiresExecutiveSignature && (
                          <span className="text-[var(--text-tertiary)]">لا توجد</span>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={t.active ? 'success' : 'neutral'} label={t.active ? 'نشط' : 'معطل'} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}

      {showEditor && (
        <DialogOverlay title="إنشاء قالب مستند" onClose={() => setShowEditor(false)}>
          <TemplateForm onSubmit={handleSave} onCancel={() => setShowEditor(false)} isSaving={upsertTemplate.isPending} />
        </DialogOverlay>
      )}
    </div>
  );
}

function TemplateForm({ onSubmit, onCancel, isSaving }: { onSubmit: (data: TemplateInput) => void; onCancel: () => void; isSaving: boolean }) {
  const [form, setForm] = useState<TemplateInput>({
    code: '',
    name_ar: '',
    document_type: 'contract',
    body_template: '',
    requires_employee: true,
    requires_manager: false,
    requires_hr: true,
    requires_executive: false,
    active: true,
  });
  const canSubmit = form.code.trim() && form.name_ar.trim();
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit(form);
      }}
      className="space-y-4"
    >
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="label-field">الرمز *</label>
          <input
            type="text"
            value={form.code}
            onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })}
            className="form-input w-full"
            placeholder="DOC-001"
            required
          />
        </div>
        <div>
          <label className="label-field">النوع</label>
          <select value={form.document_type} onChange={(e) => setForm({ ...form, document_type: e.target.value })} className="form-select w-full">
            {Object.entries(DOC_TYPE_LABELS).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div>
        <label className="label-field">الاسم *</label>
        <input
          type="text"
          value={form.name_ar}
          onChange={(e) => setForm({ ...form, name_ar: e.target.value })}
          className="form-input w-full"
          placeholder="عقد عمل جديد"
          required
        />
      </div>
      <div>
        <label className="label-field">محتوى القالب</label>
        <textarea
          value={form.body_template}
          onChange={(e) => setForm({ ...form, body_template: e.target.value })}
          className="form-textarea w-full min-h-[120px]"
          placeholder="اكتب محتوى المستند هنا…"
        />
      </div>
      <div className="flex flex-wrap gap-3 rounded-lg border border-[var(--border-color)] bg-[var(--surface-muted)] p-3">
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.requires_employee}
            onChange={(e) => setForm({ ...form, requires_employee: e.target.checked })}
            className="form-checkbox"
          />{' '}
          توقيع الموظف
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.requires_manager}
            onChange={(e) => setForm({ ...form, requires_manager: e.target.checked })}
            className="form-checkbox"
          />{' '}
          توقيع المدير
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={form.requires_hr} onChange={(e) => setForm({ ...form, requires_hr: e.target.checked })} className="form-checkbox" />{' '}
          توقيع HR
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.requires_executive}
            onChange={(e) => setForm({ ...form, requires_executive: e.target.checked })}
            className="form-checkbox"
          />{' '}
          توقيع تنفيذي
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} className="form-checkbox" /> نشط
        </label>
      </div>
      <div className="flex justify-end gap-2 border-t border-[var(--border-color)] pt-4">
        <button type="button" onClick={onCancel} className="btn-secondary">
          إلغاء
        </button>
        <button type="submit" disabled={!canSubmit || isSaving} className="btn-primary">
          {isSaving ? 'جاري الحفظ…' : 'حفظ القالب'}
        </button>
      </div>
    </form>
  );
}
