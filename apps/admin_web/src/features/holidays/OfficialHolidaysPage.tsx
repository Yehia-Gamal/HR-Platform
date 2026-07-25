import { CalendarDays, Pencil, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { useMemo, useState } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import type { Holiday } from './useHolidays';
import { useHolidays, useCreateHoliday, useUpdateHoliday, useDeleteHoliday } from './useHolidays';

const dateFormatter = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' });
const SCOPE_LABELS: Record<string, string> = { all: 'الكل', legal_entity: 'جهة قانونية', department: 'إدارة' };
const currentYear = new Date().getFullYear();
const yearOptions = Array.from({ length: 5 }, (_, i) => currentYear + 2 - i);

export function OfficialHolidaysPage() {
  const [year, setYear] = useState(currentYear);
  const [search, setSearch] = useState('');
  const [showDialog, setShowDialog] = useState(false);
  const [editing, setEditing] = useState<Holiday | null>(null);
  const [deleting, setDeleting] = useState<Holiday | null>(null);
  const holidays = useHolidays(year);
  const deleteHoliday = useDeleteHoliday();

  const all = holidays.data ?? [];

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return all;
    return all.filter((h) => h.name.toLowerCase().includes(q) || h.name_en?.toLowerCase().includes(q));
  }, [all, search]);

  const active = all.filter((h) => h.is_active).length;
  const recurring = all.filter((h) => h.is_recurring).length;

  const onDelete = async () => {
    if (!deleting) return;
    try {
      await deleteHoliday.mutateAsync(deleting.id);
      setDeleting(null);
    } catch { /* error handled by mutation */ }
  };

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow="الوقت والخدمات"
        title="العطل الرسمية"
        description="إدارة العطل الرسمية مع دعم النطاق (الكل / جهة / إدارة) والاستثناءات — V17 §1.7."
        actions={<button type="button" className="btn-primary" onClick={() => { setEditing(null); setShowDialog(true); }}><Plus className="size-4" />إضافة عطلة</button>}
      />

      <section className="grid gap-3 sm:grid-cols-3">
        <MetricCard label="إجمالي العطل" value={all.length} icon={CalendarDays} hint={`عام ${year}`} />
        <MetricCard label="عطل فعّالة" value={active} icon={CalendarDays} hint={`${all.length ? Math.round((active / all.length) * 100) : 0}%`} />
        <MetricCard label="عطل متكررة سنويًا" value={recurring} icon={RefreshCw} />
      </section>

      <FilterBar
        searchValue={search}
        onSearchChange={setSearch}
        searchPlaceholder="بحث باسم العطلة"
        resultText={`عرض ${filtered.length} من ${all.length} عطلة`}
        isDirty={Boolean(search || year !== currentYear)}
        onClear={() => { setSearch(''); setYear(currentYear); }}
      >
        <select className="input" value={year} onChange={(e) => setYear(Number(e.target.value))} aria-label="السنة">
          {yearOptions.map((y) => <option key={y} value={y}>{y}</option>)}
        </select>
        <button type="button" onClick={() => void holidays.refetch()} className="btn-secondary" disabled={holidays.isFetching}>
          <RefreshCw className={`size-4 ${holidays.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />تحديث
        </button>
      </FilterBar>

      {holidays.isError ? (
        <ErrorState description={holidays.error instanceof Error ? holidays.error.message : undefined} onRetry={() => void holidays.refetch()} />
      ) : holidays.isLoading ? (
        <ListSkeleton rows={4} label="جارٍ تحميل العطل…" />
      ) : all.length === 0 ? (
        <EmptyState title="لا توجد عطل مسجلة" description={`لم تتم إضافة أي عطلة رسمية لعام ${year}.`} action={<button type="button" className="btn-primary" onClick={() => { setEditing(null); setShowDialog(true); }}><Plus className="size-4" />إضافة عطلة</button>} />
      ) : filtered.length === 0 ? (
        <EmptyState title="لا توجد نتائج مطابقة" description="جرّب تعديل البحث." />
      ) : (
        <section className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="data-table w-full min-w-[800px] text-right text-sm">
              <thead className="bg-[var(--surface-muted)] text-xs text-[var(--text-muted)]">
                <tr>
                  <th className="px-4 py-3.5">اسم العطلة</th>
                  <th className="px-4 py-3.5">التاريخ</th>
                  <th className="px-4 py-3.5">النهاية</th>
                  <th className="px-4 py-3.5">النطاق</th>
                  <th className="px-4 py-3.5">متكررة</th>
                  <th className="px-4 py-3.5">الحالة</th>
                  <th className="px-4 py-3.5"><span className="sr-only">إجراءات</span></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {filtered.map((h) => (
                  <tr key={h.id}>
                    <td className="px-4 py-3.5">
                      <p className="font-bold">{h.name}</p>
                      {h.name_en ? <p className="mt-0.5 text-xs text-[var(--text-muted)]" dir="ltr">{h.name_en}</p> : null}
                      {h.notes ? <p className="mt-1 text-xs text-[var(--text-muted)]">{h.notes}</p> : null}
                    </td>
                    <td className="px-4 py-3.5">{dateFormatter.format(new Date(h.holiday_date))}</td>
                    <td className="px-4 py-3.5">{h.end_date ? dateFormatter.format(new Date(h.end_date)) : '—'}</td>
                    <td className="px-4 py-3.5">{SCOPE_LABELS[h.scope] ?? h.scope}</td>
                    <td className="px-4 py-3.5">{h.is_recurring ? 'نعم' : 'لا'}</td>
                    <td className="px-4 py-3.5"><StatusBadge status={h.is_active ? 'active' : 'archived'} /></td>
                    <td className="px-4 py-3.5">
                      <div className="flex gap-2">
                        <button type="button" className="btn-secondary !px-2 !py-1.5 text-xs" onClick={() => { setEditing(h); setShowDialog(true); }} aria-label="تعديل"><Pencil className="size-3.5" /></button>
                        <button type="button" className="btn-secondary !px-2 !py-1.5 text-xs text-[var(--danger)]" onClick={() => setDeleting(h)} aria-label="حذف"><Trash2 className="size-3.5" /></button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {showDialog && (
        <HolidayFormDialog
          holiday={editing}
          onClose={() => { setShowDialog(false); setEditing(null); }}
          onSuccess={() => { setShowDialog(false); setEditing(null); void holidays.refetch(); }}
        />
      )}

      {deleting && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="card w-full max-w-sm p-6">
            <h2 className="text-lg font-black">حذف العطلة</h2>
            <p className="muted mt-2 text-sm">هل أنت متأكد من حذف «{deleting.name}»؟ لا يمكن التراجع.</p>
            <div className="mt-6 flex justify-end gap-3">
              <button type="button" className="btn-secondary" onClick={() => setDeleting(null)} disabled={deleteHoliday.isPending}>إلغاء</button>
              <button type="button" className="btn-primary bg-[var(--danger)]" onClick={() => void onDelete()} disabled={deleteHoliday.isPending}>
                {deleteHoliday.isPending ? 'جارٍ الحذف…' : 'تأكيد الحذف'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// HolidayFormDialog — Create or Edit
// ---------------------------------------------------------------------------
function HolidayFormDialog({ holiday, onClose, onSuccess }: { holiday: Holiday | null; onClose: () => void; onSuccess: () => void }) {
  const lookups = useOrganizationLookups();
  const create = useCreateHoliday();
  const update = useUpdateHoliday();
  const isEdit = Boolean(holiday);

  const [name, setName] = useState(holiday?.name ?? '');
  const [holidayDate, setHolidayDate] = useState(holiday?.holiday_date ?? '');
  const [endDate, setEndDate] = useState(holiday?.end_date ?? '');
  const [scope, setScope] = useState<'all' | 'legal_entity' | 'department'>(holiday?.scope ?? 'all');
  const [departmentId, setDepartmentId] = useState(holiday?.department_id ?? '');
  const [notes, setNotes] = useState(holiday?.notes ?? '');
  const [isRecurring, setIsRecurring] = useState(holiday?.is_recurring ?? false);
  const [error, setError] = useState<string | null>(null);

  const departments = lookups.data?.departments ?? [];
  const isPending = create.isPending || update.isPending;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      if (isEdit && holiday) {
        await update.mutateAsync({
          id: holiday.id,
          name: name.trim(),
          holiday_date: holidayDate,
          end_date: endDate || null,
          scope,
          department_id: scope === 'department' ? departmentId || null : null,
          notes: notes.trim() || null,
          is_recurring: isRecurring,
        });
      } else {
        await create.mutateAsync({
          name: name.trim(),
          holiday_date: holidayDate,
          end_date: endDate || null,
          scope,
          department_id: scope === 'department' ? departmentId || null : null,
          notes: notes.trim() || null,
          is_recurring: isRecurring,
        });
      }
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذر حفظ العطلة.');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <form onSubmit={(e) => void onSubmit(e)} className="card flex max-h-[90vh] w-full max-w-lg flex-col">
        <div className="border-b border-[var(--border)] p-6">
          <h2 className="text-lg font-black">{isEdit ? 'تعديل العطلة' : 'إضافة عطلة رسمية'}</h2>
        </div>

        <div className="flex-1 space-y-4 overflow-y-auto p-6">
          {error ? <div role="alert" className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-sm text-[var(--danger)]">{error}</div> : null}

          <label className="block">
            <span className="mb-1.5 block text-sm font-semibold">اسم العطلة <span className="text-[var(--danger)]">*</span></span>
            <input type="text" className="input w-full" required minLength={3} maxLength={200} value={name} onChange={(e) => setName(e.target.value)} disabled={isPending} />
          </label>

          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">تاريخ البداية <span className="text-[var(--danger)]">*</span></span>
              <input type="date" className="input w-full" required value={holidayDate} onChange={(e) => setHolidayDate(e.target.value)} disabled={isPending} />
            </label>
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">تاريخ النهاية</span>
              <input type="date" className="input w-full" value={endDate} onChange={(e) => setEndDate(e.target.value)} disabled={isPending} min={holidayDate} />
            </label>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1.5 block text-sm font-semibold">النطاق</span>
              <select className="input w-full" value={scope} onChange={(e) => setScope(e.target.value as typeof scope)} disabled={isPending}>
                <option value="all">الكل</option>
                <option value="legal_entity">جهة قانونية</option>
                <option value="department">إدارة</option>
              </select>
            </label>
            {scope === 'department' ? (
              <label className="block">
                <span className="mb-1.5 block text-sm font-semibold">الإدارة <span className="text-[var(--danger)]">*</span></span>
                <select className="input w-full" required value={departmentId} onChange={(e) => setDepartmentId(e.target.value)} disabled={isPending}>
                  <option value="">— اختر —</option>
                  {departments.map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
                </select>
              </label>
            ) : null}
          </div>

          <label className="block">
            <span className="mb-1.5 block text-sm font-semibold">ملاحظات</span>
            <textarea className="input min-h-16 w-full" maxLength={500} value={notes} onChange={(e) => setNotes(e.target.value)} disabled={isPending} />
          </label>

          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isRecurring} onChange={(e) => setIsRecurring(e.target.checked)} disabled={isPending} />
            <span>تتكرر سنويًا</span>
          </label>
        </div>

        <div className="flex justify-end gap-3 border-t border-[var(--border)] p-6">
          <button type="button" className="btn-secondary" onClick={onClose} disabled={isPending}>إلغاء</button>
          <button type="submit" className="btn-primary" disabled={isPending}>
            {isPending ? 'جارٍ الحفظ…' : isEdit ? 'حفظ التعديلات' : 'إضافة العطلة'}
          </button>
        </div>
      </form>
    </div>
  );
}
