import { BriefcaseBusiness, CalendarDays, ChevronDown, Search, SlidersHorizontal, Users, WalletCards } from 'lucide-react';
import { useMemo, useState } from 'react';
import { ErrorBanner } from '../../ui/ErrorState';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';
import { hasAnyPermission } from '../workspaces/access';
import { useEmployees } from '../employees/useEmployees';
import { useAdjustLeaveBalance, useCreateBulkAssignment, useCreateLeaveForEmployee, useGrantRestCreditBulk, useLeaveTypes } from './useLeaveTools';

// ─── اختيار موظفين متعدد (بحث + تحديد الكل النشطين) ─────────────────────────

interface EmployeeOption {
  id: string;
  name: string;
  code: string | null;
  isActive: boolean;
}

function EmployeeMultiSelect({
  employees,
  selected,
  onToggle,
  onSelectAllActive,
  onClear,
  search,
  onSearch,
  placeholder,
}: {
  employees: EmployeeOption[];
  selected: Set<string>;
  onToggle: (id: string) => void;
  onSelectAllActive: () => void;
  onClear: () => void;
  search: string;
  onSearch: (value: string) => void;
  placeholder: string;
}) {
  const activeCount = employees.filter((e) => e.isActive).length;
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <input
            type="search"
            value={search}
            onChange={(e) => onSearch(e.target.value)}
            placeholder={placeholder}
            aria-label="بحث عن موظف"
            className="input-field h-9 w-full ps-9 text-sm"
          />
        </div>
        <button type="button" onClick={onSelectAllActive} className="btn-secondary shrink-0 px-3 py-1.5 text-xs" disabled={activeCount === 0}>
          تحديد الكل ({activeCount})
        </button>
        {selected.size > 0 && (
          <button type="button" onClick={onClear} className="rounded-lg px-2 py-1.5 text-xs font-semibold text-[var(--danger)] hover:bg-[var(--danger-soft)]">
            مسح ({selected.size})
          </button>
        )}
      </div>
      <div className="max-h-56 space-y-1 overflow-y-auto rounded-xl border border-[var(--border)] p-1.5">
        {employees.map((emp) => {
          const checked = selected.has(emp.id);
          return (
            <label
              key={emp.id}
              className={`flex cursor-pointer items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm transition-colors ${
                checked ? 'bg-[var(--brand-accent-soft)]' : 'hover:bg-[var(--surface-raised)]'
              } ${!emp.isActive ? 'opacity-45' : ''}`}
            >
              <input
                type="checkbox"
                checked={checked}
                onChange={() => onToggle(emp.id)}
                disabled={!emp.isActive}
                className="size-4 shrink-0 accent-[var(--brand-primary)]"
              />
              <UserAvatar displayName={emp.name} size="sm" />
              <span className="min-w-0 flex-1 truncate font-semibold">{emp.name}</span>
              {emp.code && !emp.code.match(/^\+?\d{9,}$/) && <span className="shrink-0 text-xs text-[var(--text-muted)]">{emp.code}</span>}
            </label>
          );
        })}
        {employees.length === 0 && <p className="px-2 py-3 text-center text-xs text-[var(--text-muted)]">لا يوجد موظفون مطابقون.</p>}
      </div>
    </div>
  );
}

function useEmployeeOptions(search: string) {
  const { data: employees, isLoading, isError } = useEmployees();
  const options = useMemo<EmployeeOption[]>(() => {
    const list = (employees ?? [])
      .filter((e) => (search.trim() ? (e.fullNameAr ?? '').includes(search.trim()) || (e.employeeCode ?? '').includes(search.trim()) : true))
      .map((e) => ({ id: e.id, name: e.fullNameAr, code: e.employeeCode, isActive: e.isActive }));
    list.sort((a, b) => Number(b.isActive) - Number(a.isActive));
    return list;
  }, [employees, search]);
  return { options, isLoading, isError };
}

// ─── قسم: منح بدل راحة جماعي ────────────────────────────────────────────────

function BulkRestCreditSection() {
  const grant = useGrantRestCreditBulk();
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [workDate, setWorkDate] = useState(new Date().toISOString().slice(0, 10));
  const [days, setDays] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const { options, isLoading } = useEmployeeOptions(search);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };
  const selectAllActive = () => setSelected(new Set(options.filter((e) => e.isActive).map((e) => e.id)));
  const clear = () => setSelected(new Set());

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await grant.mutateAsync({ employeeIds: [...selected], workDate, days });
      setSelected(new Set());
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <form onSubmit={(e) => void submit(e)} className="card space-y-4 p-5">
      <div className="flex items-center gap-2.5">
        <span className="rounded-lg bg-[var(--brand-accent-soft)] p-2 text-[var(--brand-primary)]">
          <WalletCards className="size-5" aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-black">منح بدل راحة أسبوعي (جماعي)</h2>
          <p className="text-xs text-[var(--text-muted)]">إضافة رصيد بدل راحة لموظف واحد أو أكثر — دون خصم من رصيد الإجازات.</p>
        </div>
      </div>

      {error ? <ErrorBanner message={error} /> : null}

      <EmployeeMultiSelect
        employees={options}
        selected={selected}
        onToggle={toggle}
        onSelectAllActive={selectAllActive}
        onClear={clear}
        search={search}
        onSearch={setSearch}
        placeholder="بحث عن موظف..."
      />
      {isLoading && <p className="text-xs text-[var(--text-muted)]">جارٍ تحميل الموظفين...</p>}

      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">تاريخ بداية العمل (الجمعة)</span>
          <input
            type="date"
            className="input-field w-full text-sm"
            value={workDate}
            onChange={(e) => setWorkDate(e.target.value)}
            required
            disabled={grant.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">عدد أيام البدل</span>
          <input
            type="number"
            className="input-field w-full text-sm"
            value={days}
            min={1}
            max={365}
            onChange={(e) => setDays(Number(e.target.value))}
            required
            disabled={grant.isPending}
          />
        </label>
      </div>

      <button type="submit" className="btn-primary w-full" disabled={grant.isPending || selected.size === 0 || days < 1 || days > 365}>
        {grant.isPending ? 'جارٍ المنح...' : `منح الرصيد لـ ${selected.size} موظف`}
      </button>
    </form>
  );
}

// ─── قسم: ضبط رصيد إجازة ────────────────────────────────────────────────────

function AdjustBalanceSection() {
  const adjust = useAdjustLeaveBalance();
  const { data: leaveTypes } = useLeaveTypes();
  const [search, setSearch] = useState('');
  const [selectedEmployee, setSelectedEmployee] = useState<string>('');
  const [leaveTypeId, setLeaveTypeId] = useState('');
  const [year, setYear] = useState(new Date().getFullYear());
  const [units, setUnits] = useState(1);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { options } = useEmployeeOptions(search);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await adjust.mutateAsync({ employeeId: selectedEmployee, leaveTypeId, year, units, reason: reason.trim() });
      setReason('');
      setSelectedEmployee('');
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <form onSubmit={(e) => void submit(e)} className="card space-y-4 p-5">
      <div className="flex items-center gap-2.5">
        <span className="rounded-lg bg-[var(--brand-accent-soft)] p-2 text-[var(--brand-primary)]">
          <SlidersHorizontal className="size-5" aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-black">ضبط رصيد إجازة</h2>
          <p className="text-xs text-[var(--text-muted)]">زيادة أو خصم من رصيد الإجازات السنوية لموظف (تعديل إداري مسجّل في السجل).</p>
        </div>
      </div>

      {error ? <ErrorBanner message={error} /> : null}

      <div className="space-y-1.5">
        <span className="block text-xs font-semibold text-[var(--text-muted)]">الموظف</span>
        <div className="relative">
          <Search className="absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="ابحث عن موظف..."
            aria-label="بحث عن موظف"
            className="input-field h-9 w-full ps-9 text-sm"
          />
        </div>
        <select value={selectedEmployee} onChange={(e) => setSelectedEmployee(e.target.value)} className="input-field w-full text-sm" required>
          <option value="">— اختر موظفاً —</option>
          {options.map((emp) => (
            <option key={emp.id} value={emp.id} disabled={!emp.isActive}>
              {emp.name}
              {emp.code && !emp.code.match(/^\+?\d{9,}$/) ? ` (${emp.code})` : ''}
            </option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">نوع الإجازة</span>
          <select value={leaveTypeId} onChange={(e) => setLeaveTypeId(e.target.value)} className="input-field w-full text-sm" required>
            <option value="">— اختر النوع —</option>
            {(leaveTypes ?? []).map((lt) => (
              <option key={lt.id} value={lt.id}>
                {lt.nameAr}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">السنة</span>
          <input
            type="number"
            className="input-field w-full text-sm"
            value={year}
            min={2020}
            max={2100}
            onChange={(e) => setYear(Number(e.target.value))}
            required
            disabled={adjust.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">الكمية (بالأيام، +/−)</span>
          <input
            type="number"
            className="input-field w-full text-sm"
            value={units}
            onChange={(e) => setUnits(Number(e.target.value))}
            required
            disabled={adjust.isPending}
            step="0.5"
          />
        </label>
        <div className="flex items-end">
          <p className="text-xs text-[var(--text-muted)]">استخدم قيماً سالبة للخصم، موجبة للإضافة.</p>
        </div>
      </div>

      <label className="block">
        <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">سبب التعديل (يُسجّل في سجل التدقيق)</span>
        <textarea
          className="input-field w-full resize-none text-sm"
          rows={2}
          minLength={5}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="سبب التعديل..."
          required
          disabled={adjust.isPending}
        />
      </label>

      <button type="submit" className="btn-primary w-full" disabled={adjust.isPending || !selectedEmployee || !leaveTypeId || reason.trim().length < 5}>
        {adjust.isPending ? 'جارٍ الحفظ...' : 'حفظ التعديل'}
      </button>
    </form>
  );
}

// ─── قسم: إنشاء إجازة بدل الموظف ────────────────────────────────────────────

function CreateLeaveForEmployeeSection() {
  const create = useCreateLeaveForEmployee();
  const { data: leaveTypes } = useLeaveTypes();
  const [search, setSearch] = useState('');
  const [selectedEmployee, setSelectedEmployee] = useState<string>('');
  const [leaveType, setLeaveType] = useState('annual');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [reason, setReason] = useState('');
  const [handoverNotes, setHandoverNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { options } = useEmployeeOptions(search);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      await create.mutateAsync({
        employeeId: selectedEmployee,
        leaveType,
        startDate,
        endDate,
        reason: reason.trim(),
        handoverNotes: handoverNotes.trim() || undefined,
      });
      setReason('');
      setHandoverNotes('');
      setStartDate('');
      setEndDate('');
      setSelectedEmployee('');
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <form onSubmit={(e) => void submit(e)} className="card space-y-4 p-5">
      <div className="flex items-center gap-2.5">
        <span className="rounded-lg bg-[var(--brand-accent-soft)] p-2 text-[var(--brand-primary)]">
          <CalendarDays className="size-5" aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-black">إنشاء إجازة بدل الموظف</h2>
          <p className="text-xs text-[var(--text-muted)]">تسجيل طلب إجازة نيابة عن موظف — يسير في مسار الموافقة المعتاد (مدير مباشر ثم عمليات).</p>
        </div>
      </div>

      {error ? <ErrorBanner message={error} /> : null}

      <div className="space-y-1.5">
        <span className="block text-xs font-semibold text-[var(--text-muted)]">الموظف</span>
        <div className="relative">
          <Search className="absolute start-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="ابحث عن موظف..."
            aria-label="بحث عن موظف"
            className="input-field h-9 w-full ps-9 text-sm"
          />
        </div>
        <select value={selectedEmployee} onChange={(e) => setSelectedEmployee(e.target.value)} className="input-field w-full text-sm" required>
          <option value="">— اختر موظفاً —</option>
          {options.map((emp) => (
            <option key={emp.id} value={emp.id} disabled={!emp.isActive}>
              {emp.name}
              {emp.code && !emp.code.match(/^\+?\d{9,}$/) ? ` (${emp.code})` : ''}
            </option>
          ))}
        </select>
      </div>

      <label className="block">
        <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">نوع الإجازة</span>
        <select value={leaveType} onChange={(e) => setLeaveType(e.target.value)} className="input-field w-full text-sm">
          {(leaveTypes ?? []).map((lt) => (
            <option key={lt.code} value={lt.code}>
              {lt.nameAr}
              {!lt.affectsBalance ? ' — بدون رصيد (مفتوحة)' : ''}
            </option>
          ))}
        </select>
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">من تاريخ</span>
          <input
            type="date"
            className="input-field w-full text-sm"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            required
            disabled={create.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">إلى تاريخ</span>
          <input
            type="date"
            className="input-field w-full text-sm"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
            required
            disabled={create.isPending}
          />
        </label>
      </div>

      <label className="block">
        <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">السبب</span>
        <textarea
          className="input-field w-full resize-none text-sm"
          rows={2}
          minLength={3}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="سبب الإجازة..."
          required
          disabled={create.isPending}
        />
      </label>

      <label className="block">
        <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">ملاحظات التسليم (اختياري)</span>
        <input
          className="input-field w-full text-sm"
          value={handoverNotes}
          onChange={(e) => setHandoverNotes(e.target.value)}
          placeholder="من سيغطي العمل أثناء الإجازة؟"
          disabled={create.isPending}
        />
      </label>

      <button
        type="submit"
        className="btn-primary w-full"
        disabled={create.isPending || !selectedEmployee || !startDate || !endDate || reason.trim().length < 3}
      >
        {create.isPending ? 'جارٍ الإنشاء...' : 'إنشاء الطلب'}
      </button>
    </form>
  );
}

// ─── قسم: قافلة / فاندي جماعية ──────────────────────────────────────────────

function BulkAssignmentSection() {
  const create = useCreateBulkAssignment();
  const [search, setSearch] = useState('');
  const [assignmentType, setAssignmentType] = useState<'MISSION' | 'CONVOY' | 'FUNDRAISING'>('CONVOY');
  const [title, setTitle] = useState('');
  const [startAt, setStartAt] = useState('');
  const [endAt, setEndAt] = useState('');
  const [location, setLocation] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [useAllActive, setUseAllActive] = useState(true);
  const [targetAmount, setTargetAmount] = useState('');
  const [needsReport, setNeedsReport] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { options, isLoading } = useEmployeeOptions(search);
  const activeIds = useMemo(() => options.filter((e) => e.isActive).map((e) => e.id), [options]);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };
  const selectAllActive = () => setSelected(new Set(activeIds));
  const clear = () => setSelected(new Set());

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const participantIds = useAllActive ? activeIds : [...selected];
    if (participantIds.length === 0) {
      setError('اختر موظفاً واحداً على الأقل.');
      return;
    }
    try {
      await create.mutateAsync({
        assignmentType,
        title: title.trim(),
        startAt,
        endAt,
        participantIds,
        location: location.trim() || undefined,
        targetAmount: assignmentType === 'FUNDRAISING' && targetAmount ? Number(targetAmount) : null,
      });
      setTitle('');
      setStartAt('');
      setEndAt('');
      setLocation('');
      setTargetAmount('');
      setNeedsReport(false);
      setSelected(new Set());
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <form onSubmit={(e) => void submit(e)} className="card space-y-4 p-5">
      <div className="flex items-center gap-2.5">
        <span className="rounded-lg bg-[var(--brand-accent-soft)] p-2 text-[var(--brand-primary)]">
          <BriefcaseBusiness className="size-5" aria-hidden="true" />
        </span>
        <div>
          <h2 className="text-sm font-black">إضافة مأمورية / قافلة / فاندي</h2>
          <p className="text-xs text-[var(--text-muted)]">تكليف كل الموظفين أو مجموعة محددة — يوم عمل معتمد لا يُبصمون فيه.</p>
        </div>
      </div>

      {error ? <ErrorBanner message={error} /> : null}

      <div className="grid grid-cols-2 gap-3">
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">نوع التكليف</span>
          <div className="relative">
            <select
              value={assignmentType}
              onChange={(e) => setAssignmentType(e.target.value as 'MISSION' | 'CONVOY' | 'FUNDRAISING')}
              className="input-field w-full appearance-none text-sm"
            >
              <option value="MISSION">مأمورية</option>
              <option value="CONVOY">قافلة</option>
              <option value="FUNDRAISING">فاندي (جمع تبرعات)</option>
            </select>
            <ChevronDown className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          </div>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">العنوان</span>
          <input
            className="input-field w-full text-sm"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            minLength={3}
            placeholder="مثال: قافلة رمضان — حي الأمل"
            required
            disabled={create.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">من</span>
          <input
            type="datetime-local"
            className="input-field w-full text-sm"
            value={startAt}
            onChange={(e) => setStartAt(e.target.value)}
            required
            disabled={create.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">إلى</span>
          <input
            type="datetime-local"
            className="input-field w-full text-sm"
            value={endAt}
            onChange={(e) => setEndAt(e.target.value)}
            required
            disabled={create.isPending}
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">الموقع (اختياري)</span>
          <input
            className="input-field w-full text-sm"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            placeholder="مثال: شارع المدارس"
            disabled={create.isPending}
          />
        </label>
        {assignmentType === 'FUNDRAISING' && (
          <label className="block">
            <span className="mb-1.5 block text-xs font-semibold text-[var(--text-muted)]">الهدف (جنيه، اختياري)</span>
            <input
              type="number"
              className="input-field w-full text-sm"
              value={targetAmount}
              min={0}
              onChange={(e) => setTargetAmount(e.target.value)}
              placeholder="مثال: 50000"
              disabled={create.isPending}
            />
          </label>
        )}
        <div className="flex items-center gap-3 rounded-xl border border-[var(--border)] p-3">
          <input
            type="checkbox"
            id="needs-report"
            className="size-4 accent-[var(--brand-primary)]"
            checked={needsReport}
            onChange={(e) => setNeedsReport(e.target.checked)}
          />
          <label htmlFor="needs-report" className="flex-1 text-sm font-semibold">
            طلب تقرير من الموظف بعد التنفيذ
          </label>
        </div>
      </div>

      <div className="flex items-center gap-3 rounded-xl border border-[var(--border)] p-3">
        <input
          type="checkbox"
          id="use-all-active"
          className="size-4 accent-[var(--brand-primary)]"
          checked={useAllActive}
          onChange={(e) => setUseAllActive(e.target.checked)}
        />
        <label htmlFor="use-all-active" className="flex-1 text-sm font-semibold">
          جميع الموظفين النشطين ({activeIds.length})
        </label>
        {!useAllActive && (
          <span className="text-xs text-[var(--text-muted)]">
            {selected.size} مختار
            {selected.size > 0 ? (
              <button type="button" onClick={clear} className="ms-2 font-bold text-[var(--danger)] hover:underline">
                مسح
              </button>
            ) : null}
          </span>
        )}
      </div>

      {!useAllActive && (
        <EmployeeMultiSelect
          employees={options}
          selected={selected}
          onToggle={toggle}
          onSelectAllActive={selectAllActive}
          onClear={clear}
          search={search}
          onSearch={setSearch}
          placeholder="بحث عن موظف..."
        />
      )}
      {isLoading && <p className="text-xs text-[var(--text-muted)]">جارٍ تحميل الموظفين...</p>}

      <button
        type="submit"
        className="btn-primary w-full"
        disabled={create.isPending || title.trim().length < 3 || !startAt || !endAt || (useAllActive ? activeIds.length === 0 : selected.size === 0)}
      >
        {create.isPending
          ? 'جارٍ الإنشاء...'
          : `إنشاء ${assignmentType === 'MISSION' ? 'المأمورية' : assignmentType === 'CONVOY' ? 'القافلة' : 'الفاندي'} لـ ${useAllActive ? activeIds.length : selected.size} موظف`}
      </button>
    </form>
  );
}

// ─── الصفحة ─────────────────────────────────────────────────────────────────

export function LeaveToolsPage() {
  const auth = useAuth();
  const canManageAssignments =
    auth.access != null &&
    hasAnyPermission(auth.access, ['assignments.mission.manage', 'assignments.convoy.manage', 'operations.convoy.manage', 'assignments.fundraising.manage']);

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="الموارد البشرية"
        title="أدوات الإجازات والتكليفات"
        description="منح بدل الراحة، ضبط أرصدة الإجازات، إنشاء إجازة بدل الموظف، وتكليف المأموريات والقوافل والفاندي"
      />

      <div className="flex items-start gap-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-4 text-sm">
        <Users className="mt-0.5 size-4 shrink-0 text-[var(--brand-primary)]" aria-hidden="true" />
        <p className="text-[var(--text-muted)]">
          الإجازة المرضية <strong className="text-[var(--text)]">مفتوحة بلا رصيد</strong> — يُترك القرار للمدير المباشر ثم عمليات 1 (أبو عمار) للموافقة أو
          الرفض.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <BulkRestCreditSection />
        <AdjustBalanceSection />
        <CreateLeaveForEmployeeSection />
        {canManageAssignments ? <BulkAssignmentSection /> : null}
      </div>
    </div>
  );
}
