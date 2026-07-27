import { FileCheck2, FilePlus2, PenLine } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton, MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useDocumentStudioCatalog, useDocumentStudioCommands } from './useEnterpriseOperations';

const SIGNATURE_ROLES = [
  { key: 'employee', label: 'الموظف' },
  { key: 'manager', label: 'المدير' },
  { key: 'hr', label: 'HR' },
  { key: 'executive', label: 'التنفيذي' },
] as const;

const DOCUMENT_TYPES = [
  { value: 'letter', label: 'خطاب' },
  { value: 'contract', label: 'عقد' },
  { value: 'certificate', label: 'شهادة' },
] as const;

export function DocumentStudioPage() {
  const query = useDocumentStudioCatalog();
  const commands = useDocumentStudioCommands();
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState({
    code: '',
    name: '',
    documentType: 'letter',
    body: 'السيد/ {{employee.full_name}}\nتحية طيبة،\n...',
    employee: false,
    manager: false,
    hr: true,
    executive: false,
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    await commands.upsertTemplate.mutateAsync(draft);
    setOpen(false);
  }

  const data = query.data;
  return <div className="space-y-6"><PageHeader title="استوديو المستندات والتوقيعات" description="قوالب Versioned، مستندات مولدة، وسلسلة توقيع متعددة الأطراف مرتبطة بنسخة المحتوى." actions={<button className="btn-primary" onClick={() => setOpen(true)}><FilePlus2 className="size-4" aria-hidden="true" />قالب جديد</button>} />
    {query.isError ? <ErrorState title="تعذر تحميل استوديو المستندات" description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} />
    : !data ? <div className="space-y-6"><MetricSkeletonRow count={3} /><ListSkeleton rows={4} /></div>
    : <><section className="grid gap-4 sm:grid-cols-3"><MetricCard label="القوالب" value={data.templates.length} icon={FilePlus2} /><MetricCard label="المستندات" value={data.documents.length} icon={FileCheck2} /><MetricCard label="توقيعات معلقة" value={data.documents.reduce((a, x) => a + x.pendingSignatures, 0)} icon={PenLine} /></section>
    <section className="grid gap-5 xl:grid-cols-2"><article className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">القوالب</h2></div><div className="divide-y divide-[var(--border)]">{data.templates.length ? data.templates.map(t => <div className="p-5" key={t.id}><div className="flex justify-between"><div><p className="font-black">{t.name}</p><p className="muted text-sm">{t.code} · الإصدار {t.version} · {t.documentType}</p></div><StatusBadge value={t.active ? 'active' : 'inactive'} /></div><p className="muted mt-2 text-sm">توقيع: {[t.requiresEmployeeSignature && 'الموظف', t.requiresManagerSignature && 'المدير', t.requiresHrSignature && 'HR', t.requiresExecutiveSignature && 'التنفيذي'].filter(Boolean).join(' ← ') || 'غير مطلوب'}</p></div>) : <EmptyState title="لا توجد قوالب" description="أنشئ قالب خطاب أو عقد أو شهادة." />}</div></article>
    <article className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">المستندات المولدة</h2></div><div className="divide-y divide-[var(--border)]">{data.documents.length ? data.documents.map(d => <div className="flex justify-between gap-4 p-5" key={d.id}><div className="flex items-center gap-3"><UserAvatar displayName={d.employeeName ?? ''} size="sm" /><div><p className="font-black">{d.title}</p><p className="muted text-sm">{d.referenceNumber} · {d.employeeName ?? 'عام'}</p></div></div><div className="text-end"><StatusBadge value={d.status} /><p className="muted mt-1 text-xs">معلق {d.pendingSignatures}</p></div></div>) : <EmptyState title="لا توجد مستندات" description="سيظهر هنا ما يتم توليده من القوالب." />}</div></article></section></>}
    {open ? (
      <DialogOverlay title="قالب جديد" onClose={() => setOpen(false)} maxWidth="max-w-3xl">
        <form className="space-y-4" onSubmit={submit}>
          {commands.upsertTemplate.error ? <ErrorBanner message={commands.upsertTemplate.error instanceof Error ? commands.upsertTemplate.error.message : 'تعذر حفظ القالب'} /> : null}
          <div className="grid gap-4 sm:grid-cols-2"><Field label="الكود"><input className="input" required value={draft.code} onChange={e => setDraft({ ...draft, code: e.target.value })} /></Field><Field label="الاسم"><input className="input" required value={draft.name} onChange={e => setDraft({ ...draft, name: e.target.value })} /></Field></div>
          <Field label="النوع"><select className="input" aria-label="النوع" value={draft.documentType} onChange={e => setDraft({ ...draft, documentType: e.target.value })}>{DOCUMENT_TYPES.map(dt => <option key={dt.value} value={dt.value}>{dt.label}</option>)}</select></Field>
          <Field label="نص القالب"><textarea className="input min-h-56 font-mono" required value={draft.body} onChange={e => setDraft({ ...draft, body: e.target.value })} /></Field>
          <div className="grid gap-3 sm:grid-cols-4">{SIGNATURE_ROLES.map(r => <label className="flex gap-2" key={r.key}><input type="checkbox" checked={draft[r.key]} onChange={e => setDraft({ ...draft, [r.key]: e.target.checked })} />{r.label}</label>)}</div>
          <button className="btn-primary">حفظ القالب</button>
        </form>
      </DialogOverlay>
    ) : null}
  </div>;
}
function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span>{children}</label>; }
