import { Pencil, Plus, Save, Trash2 } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { TextInput } from '../../ui/FormField';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { StatusBadge } from '../../ui/StatusBadge';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasAnyPermission, hasPermission } from '../workspaces/access';
import { useJobTitlesOverview, useOrganizationCommands } from './useAdminOperations';

type JobTitleDraft = { id?: string | null; code: string; name: string; nameEn: string; active: boolean };
type JobTitleRow = NonNullable<ReturnType<typeof useJobTitlesOverview>['data']>[number];

const emptyDraft: JobTitleDraft = { code: '', name: '', nameEn: '', active: true };

function autoCode(): string {
  return `JT-${crypto.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()}`;
}

export function JobTitlesSection() {
  const auth = useAuth();
  const overview = useJobTitlesOverview();
  const commands = useOrganizationCommands();
  const [filter, setFilter] = useState('');
  const [draft, setDraft] = useState<JobTitleDraft | null>(null);
  const [toDelete, setToDelete] = useState<JobTitleRow | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const canView = Boolean(
    auth.access && hasAnyPermission(auth.access, ['organization.job_title.manage', 'organization.department.manage', 'organization.position.manage']),
  );
  const canManage = Boolean(auth.access && hasPermission(auth.access, 'organization.job_title.manage'));

  const rows = useMemo(
    () => (overview.data ?? []).filter((row) => `${row.code} ${row.name}`.toLowerCase().includes(filter.toLowerCase().trim())),
    [overview.data, filter],
  );

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!draft) return;
    try {
      await commands.jobTitle.mutateAsync({
        id: draft.id ?? null,
        code: draft.code,
        name: draft.name,
        nameEn: draft.nameEn || null,
        active: draft.active,
      });
      setDraft(null);
    } catch {
      /* isError handled in dialog UI */
    }
  }

  async function confirmDelete() {
    if (!toDelete) return;
    setDeleteError(null);
    try {
      await commands.jobTitleDelete.mutateAsync(toDelete.id);
      setToDelete(null);
    } catch (err) {
      setDeleteError(safeErrorMessage(err));
    }
  }

  if (!canView) return null;

  return (
    <section className="card overflow-hidden">
      <div className="flex flex-col gap-3 border-b border-[var(--border)] p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="font-black">{'المسميات الوظيفية'}</h2>
            <p className="muted mt-1 text-sm">{'تنظيف المسميات المكررة أو غير المستخدمة — الحذف يتطلب عدم ارتباط أي موظف أو منصب.'}</p>
          </div>
          {canManage ? (
            <button className="btn-secondary" onClick={() => setDraft({ ...emptyDraft, code: autoCode() })}>
              <Plus className="size-4" aria-hidden="true" />
              {'مسمى جديد'}
            </button>
          ) : null}
        </div>
        <FilterBar
          searchValue={filter}
          onSearchChange={setFilter}
          searchPlaceholder={'بحث بالاسم أو الكود'}
          resultText={`${rows.length} مسمى`}
          isDirty={!!filter}
          onClear={() => setFilter('')}
        />
      </div>

      {overview.isError ? (
        <div className="p-5">
          <ErrorBanner message={safeErrorMessage(overview.error)} />
        </div>
      ) : null}

      {overview.isLoading && !overview.data ? (
        <div className="p-5 text-sm muted">{'جارٍ تحميل المسميات الوظيفية…'}</div>
      ) : rows.length === 0 ? (
        <EmptyState title={'لا توجد مسميات وظيفية'} description={'لم يتم إنشاء أي مسمى وظيفي بعد أو لا نتائج مطابقة للبحث.'} />
      ) : (
        <div className="overflow-x-auto">
          <table className="data-table w-full min-w-[720px] text-start text-sm">
            <thead className="bg-[var(--surface-muted)]">
              <tr>
                <th scope="col" className="p-4">
                  {'المسمى'}
                </th>
                <th scope="col" className="p-4">
                  {'الكود'}
                </th>
                <th scope="col" className="p-4">
                  {'الموظفون'}
                </th>
                <th scope="col" className="p-4">
                  {'المناصب'}
                </th>
                <th scope="col" className="p-4">
                  {'الحالة'}
                </th>
                {canManage ? (
                  <th scope="col" className="p-4">
                    {'إجراء'}
                  </th>
                ) : null}
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-t border-[var(--border)]">
                  <td className="p-4">
                    <p className="font-black">{row.name}</p>
                    {row.nameEn ? <p className="muted font-mono text-xs">{row.nameEn}</p> : null}
                  </td>
                  <td className="p-4 muted font-mono text-xs">{row.code}</td>
                  <td className="p-4">{row.employeeCount}</td>
                  <td className="p-4">{row.positionCount}</td>
                  <td className="p-4">
                    <StatusBadge value={row.active ? 'active' : 'inactive'} />
                  </td>
                  {canManage ? (
                    <td className="p-4">
                      <div className="flex items-center gap-1">
                        <button
                          className="icon-button"
                          aria-label={'تعديل المسمى الوظيفي'}
                          onClick={() => setDraft({ id: row.id, code: row.code, name: row.name, nameEn: row.nameEn ?? '', active: row.active })}
                        >
                          <Pencil className="size-4" aria-hidden="true" />
                        </button>
                        <button
                          className="icon-button text-[var(--danger)]"
                          aria-label={'حذف المسمى الوظيفي'}
                          onClick={() => {
                            setDeleteError(null);
                            setToDelete(row);
                          }}
                        >
                          <Trash2 className="size-4" aria-hidden="true" />
                        </button>
                      </div>
                    </td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {draft ? (
        <DialogOverlay title={draft.id ? 'تعديل مسمى وظيفي' : 'مسمى وظيفي جديد'} onClose={() => setDraft(null)} maxWidth="max-w-lg">
          <form className="space-y-4" onSubmit={(event) => void save(event)}>
            <div className="grid gap-4 sm:grid-cols-2">
              <TextInput label={'الكود'} required value={draft.code} onChange={(value) => setDraft({ ...draft, code: value })} />
              <TextInput label={'المسمى الوظيفي'} required value={draft.name} onChange={(value) => setDraft({ ...draft, name: value })} />
              <TextInput label={'الاسم بالإنجليزية'} value={draft.nameEn} onChange={(value) => setDraft({ ...draft, nameEn: value })} />
            </div>
            <label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">
              <input type="checkbox" checked={draft.active} onChange={(event) => setDraft({ ...draft, active: event.target.checked })} />
              {'نشط'}
            </label>
            {commands.jobTitle.isError ? <ErrorBanner message={safeErrorMessage(commands.jobTitle.error)} /> : null}
            <div className="flex justify-end gap-3 border-t border-[var(--border)] pt-4">
              <button type="button" className="btn-secondary" onClick={() => setDraft(null)}>
                إلغاء
              </button>
              <button className="btn-primary" type="submit" disabled={commands.jobTitle.isPending}>
                <Save className="size-4" aria-hidden="true" />
                {commands.jobTitle.isPending ? 'جارٍ الحفظ…' : 'حفظ'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}

      {toDelete ? (
        <DialogOverlay title={'حذف مسمى وظيفي نهائياً'} onClose={() => setToDelete(null)} maxWidth="max-w-md">
          <div className="space-y-4">
            <p className="text-sm leading-7">
              سيتم حذف «<span className="font-black">{toDelete.name}</span>» ({toDelete.code}) نهائياً.
            </p>
            <ul className="space-y-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-3 text-xs font-bold">
              <li>الموظفون الحاملون له: {toDelete.employeeCount}</li>
              <li>المناصب المرتبطة به: {toDelete.positionCount}</li>
            </ul>
            <p className="muted text-xs leading-6">إن كان المسمى مرتبطاً بأي موظف أو منصب، سيمنع الخادم الحذف وتظهر رسالة توضح السبب — أعد إسنادهم أولاً.</p>
            {deleteError ? <ErrorBanner message={deleteError} /> : null}
            <div className="flex justify-end gap-3 border-t border-[var(--border)] pt-4">
              <button className="btn-secondary" onClick={() => setToDelete(null)}>
                إلغاء
              </button>
              <button className="btn-danger" disabled={commands.jobTitleDelete.isPending} onClick={() => void confirmDelete()}>
                {commands.jobTitleDelete.isPending ? 'جارٍ الحذف…' : 'حذف نهائي'}
              </button>
            </div>
          </div>
        </DialogOverlay>
      ) : null}
    </section>
  );
}
