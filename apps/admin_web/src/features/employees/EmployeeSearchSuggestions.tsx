import { useEffect, useMemo } from 'react';
import { Link } from 'react-router';
import type { EmployeeSummary } from '@ahla/shared-contracts';
import { UserAvatar } from '../../ui/UserAvatar';

interface EmployeeSearchSuggestionsProps {
  /** النص الحالي في حقل البحث */
  query: string;
  /** قائمة الموظفين المحمّلة مسبقًا (p_limit: 500) — لا حاجة لاستدعاء API */
  employees: EmployeeSummary[];
  /** هل الحقل مُركّز عليه حاليًا */
  open: boolean;
  /** إغلاق القائمة (عند blur أو Escape) */
  onClose: () => void;
}

/**
 * قائمة اقتراحات حيّة تظهر أسفل حقل البحث أثناء الكتابة.
 * تعمل على القائمة المحمّلة مسبقًا (no API call) و تعرض حتى 5 مطابقات.
 * كل عنصر عبارة عن رابط إلى صفحة تفاصيل الموظف `/hr/employees/:id`.
 *
 * تُغلق القائمة عند:
 * - الضغط على Escape
 * - فقدان التركيز عن الحقل (يُدار من خلال `open` في الأب)
 * - اختيار أحد الاقتراحات (الملاحة تغيّر الصفحة فتفكّ المُكوّن)
 */
export function EmployeeSearchSuggestions({ query, employees, open, onClose }: EmployeeSearchSuggestionsProps) {
  const trimmed = query.trim().toLowerCase();

  const matches = useMemo<EmployeeSummary[]>(() => {
    if (!trimmed || trimmed.length < 2) return [];
    return employees
      .filter((employee) => {
        const name = employee.fullNameAr.toLowerCase();
        const code = employee.employeeCode.toLowerCase();
        const phone = employee.phoneE164 ?? '';
        return name.includes(trimmed) || code.includes(trimmed) || phone.includes(trimmed);
      })
      .slice(0, 5);
  }, [employees, trimmed]);

  /* ─── إغلاق عند الضغط على Escape ─── */
  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [open, onClose]);

  const visible = open && trimmed.length >= 2 && matches.length > 0;
  if (!visible) return null;

  return (
    <ul
      role="listbox"
      aria-label="اقتراحات الموظفين"
      className="absolute inset-inline-0 top-full z-30 mt-1 overflow-hidden rounded-xl border border-[var(--border)] bg-[var(--surface)] shadow-lg"
    >
      {matches.map((employee) => (
        <li key={employee.id} role="option" aria-selected={false}>
          <Link
            to={`/hr/employees/${employee.id}`}
            // منع blur المبكر للحقل حتى يسجّل النقر على الرابط ويتنقّح
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => onClose()}
            className="flex items-center gap-3 px-3 py-2.5 text-sm transition-colors hover:bg-[var(--surface-muted)] focus:bg-[var(--surface-muted)] focus:outline-none"
          >
            <UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} size="sm" announceName={false} />
            <div className="min-w-0 flex-1">
              <p className="truncate font-black text-[var(--text-primary)]">{employee.fullNameAr}</p>
              <p className="truncate text-xs text-[var(--text-muted)]">
                <span className="font-mono">{employee.employeeCode}</span>
                {employee.department ? <span className="mx-1.5 opacity-50">•</span> : null}
                {employee.department ?? ''}
              </p>
            </div>
            <span className="shrink-0 text-xs font-bold text-[var(--brand-primary)]">فتح الملف</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
