import { Plus } from 'lucide-react';
import { useMemo, useState } from 'react';
import { safeErrorMessage } from '../../../core/errorMapper';
import { useOrganizationAdminCatalog, useOrganizationCommands } from '../../management/useAdminOperations';

interface DeptOption {
  id: string;
  label: string;
}

export function MultiDepartmentPicker({
  baseDepartments,
  selectedDeptIds,
  primaryDeptId,
  onSelectedChange,
  onPrimaryChange,
}: {
  baseDepartments: DeptOption[];
  selectedDeptIds: string[];
  primaryDeptId: string;
  onSelectedChange: (next: string[]) => void;
  onPrimaryChange: (next: string) => void;
}) {
  const [newDeptName, setNewDeptName] = useState('');
  const [creatingDept, setCreatingDept] = useState(false);
  const [deptCreateError, setDeptCreateError] = useState<string | null>(null);
  const [locallyCreatedDepts, setLocallyCreatedDepts] = useState<DeptOption[]>([]);
  const orgCatalog = useOrganizationAdminCatalog();
  const orgCommands = useOrganizationCommands();

  const deptChipOptions = useMemo(() => {
    const seen = new Set(baseDepartments.map((d) => d.id));
    return [...baseDepartments, ...locallyCreatedDepts.filter((d) => !seen.has(d.id))];
  }, [baseDepartments, locallyCreatedDepts]);

  const createAndSelectDept = async () => {
    const name = newDeptName.trim();
    if (!name || creatingDept) return;
    setDeptCreateError(null);
    const existing = baseDepartments.find((d) => d.label.trim() === name);
    if (existing) {
      onSelectedChange(selectedDeptIds.includes(existing.id) ? selectedDeptIds : [...selectedDeptIds, existing.id]);
      if (!primaryDeptId) onPrimaryChange(existing.id);
      setNewDeptName('');
      return;
    }
    const entities = orgCatalog.data?.entities ?? [];
    const entityId = entities.find((e) => e.active)?.id ?? entities[0]?.id;
    if (!entityId) {
      setDeptCreateError('تعذّر إنشاء الإدارة: لا يوجد كيان قانوني متاح أو صلاحيتك لا تسمح بإدارة الهيكل التنظيمي.');
      return;
    }
    setCreatingDept(true);
    try {
      const code = `D${crypto.randomUUID().replace(/-/g, '').slice(0, 8).toUpperCase()}`;
      const createdId = String(await orgCommands.department.mutateAsync({ entityId, code, name, active: true }));
      setLocallyCreatedDepts((prev) => [...prev, { id: createdId, label: name }]);
      onSelectedChange(selectedDeptIds.includes(createdId) ? selectedDeptIds : [...selectedDeptIds, createdId]);
      if (!primaryDeptId) onPrimaryChange(createdId);
      setNewDeptName('');
    } catch (err) {
      setDeptCreateError(safeErrorMessage(err));
    } finally {
      setCreatingDept(false);
    }
  };

  return (
    <div className="sm:col-span-2 space-y-2.5 p-4 rounded-2xl border border-[var(--border)] bg-[var(--surface-muted)]/40">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1">
        <div>
          <span className="block text-sm font-black text-[var(--text-primary)]">الإدارات التابع لها الموظف ({selectedDeptIds.length})</span>
          <span className="block text-xs text-[var(--text-muted)] mt-0.5">
            يمكنك تحديد أكثر من إدارة للموظف (مثل: الميديا + الموارد البشرية)، وتحديد الإدارة الأساسية.
          </span>
        </div>
      </div>

      <div className="flex flex-wrap gap-2 pt-1 max-h-48 overflow-y-auto pr-1">
        {deptChipOptions.map((dept) => {
          const isSelected = selectedDeptIds.includes(dept.id);
          const isPrimary = primaryDeptId === dept.id;

          return (
            <button
              key={dept.id}
              type="button"
              onClick={() => {
                if (isSelected) {
                  const next = selectedDeptIds.filter((id) => id !== dept.id);
                  onSelectedChange(next);
                  if (isPrimary) {
                    onPrimaryChange(next[0] ?? '');
                  }
                } else {
                  const next = [...selectedDeptIds, dept.id];
                  onSelectedChange(next);
                  if (!primaryDeptId || selectedDeptIds.length === 0) {
                    onPrimaryChange(dept.id);
                  }
                }
              }}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold border transition-all cursor-pointer ${
                isSelected
                  ? isPrimary
                    ? 'bg-blue-600 text-white border-blue-600 shadow-xs'
                    : 'bg-indigo-500/15 text-indigo-700 dark:text-indigo-300 border-indigo-500/30'
                  : 'bg-[var(--surface)] text-[var(--text-secondary)] border-[var(--border)] hover:bg-[var(--surface-hover)]'
              }`}
            >
              <span>{dept.label}</span>
              {isSelected && isPrimary && <span className="inline-flex items-center text-[10px] bg-white/25 px-1.5 py-0.2 rounded-full font-black">أساسية ★</span>}
              {isSelected && !isPrimary && (
                <span
                  role="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    onPrimaryChange(dept.id);
                  }}
                  className="text-[10px] text-indigo-600 dark:text-indigo-400 hover:underline px-1"
                  title="تعيين كإدارة أساسية"
                >
                  (اجعلها أساسية)
                </span>
              )}
            </button>
          );
        })}
      </div>

      <div className="flex gap-2 pt-1">
        <input
          className="input flex-1 min-w-0"
          placeholder="اكتب اسم إدارة جديدة ثم اضغط «إضافة إدارة»…"
          aria-label="اسم إدارة جديدة"
          value={newDeptName}
          maxLength={160}
          disabled={creatingDept}
          onChange={(e) => {
            setNewDeptName(e.target.value);
            setDeptCreateError(null);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              void createAndSelectDept();
            }
          }}
        />
        <button
          type="button"
          className="btn-secondary inline-flex items-center gap-1.5 shrink-0"
          disabled={creatingDept || !newDeptName.trim()}
          onClick={() => void createAndSelectDept()}
        >
          <Plus className="size-3.5" />
          {creatingDept ? 'جارٍ الإنشاء…' : 'إضافة إدارة'}
        </button>
      </div>
      {deptCreateError ? <p className="text-xs font-bold text-red-600 dark:text-red-400">{deptCreateError}</p> : null}
    </div>
  );
}
