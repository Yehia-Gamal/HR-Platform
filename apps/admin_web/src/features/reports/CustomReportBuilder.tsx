import {
  Download,
  FileSpreadsheet,
  Layers,
  Printer,
  Search,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import type { EmployeeSummary } from '@ahla/shared-contracts';
import { downloadCsv, toCsv, type ExportColumn } from '../../core/exportUtils';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { useEmployees } from '../employees/useEmployees';

interface ReportField {
  id: string;
  label: string;
  category: 'أساسية' | 'وظيفية' | 'حالة الحساب';
  getValue: (emp: EmployeeSummary) => string | number;
}

const AVAILABLE_FIELDS: ReportField[] = [
  // أساسية
  { id: 'employeeCode', label: 'كود الموظف', category: 'أساسية', getValue: (e) => e.employeeCode ?? '—' },
  { id: 'fullNameAr', label: 'الاسم بالكامل (عربي)', category: 'أساسية', getValue: (e) => e.fullNameAr },
  { id: 'fullNameEn', label: 'الاسم بالإنجليزية', category: 'أساسية', getValue: (e) => e.fullNameEn ?? '—' },
  { id: 'phone', label: 'رقم الهاتف', category: 'أساسية', getValue: (e) => e.phoneE164 ?? '—' },

  // وظيفية
  { id: 'department', label: 'الإدارة / القسم', category: 'وظيفية', getValue: (e) => e.department ?? '—' },
  { id: 'jobTitle', label: 'المسمى الوظيفي', category: 'وظيفية', getValue: (e) => e.jobTitle ?? '—' },
  { id: 'branch', label: 'الفرع / الموقع', category: 'وظيفية', getValue: (e) => e.branch ?? '—' },
  { id: 'team', label: 'فريق العمل', category: 'وظيفية', getValue: (e) => e.team ?? '—' },
  {
    id: 'createdAt',
    label: 'تاريخ الإضافة / التعيين',
    category: 'وظيفية',
    getValue: (e) => (e.createdAt ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' }).format(new Date(e.createdAt)) : '—'),
  },

  // حالة الحساب
  { id: 'status', label: 'الحالة الوظيفية', category: 'حالة الحساب', getValue: (e) => e.status },
  { id: 'isActive', label: 'حالة النشاط', category: 'حالة الحساب', getValue: (e) => (e.isActive ? 'مفعل' : 'معطل') },
];

const PRESETS: { id: string; label: string; fieldIds: string[] }[] = [
  {
    id: 'comprehensive',
    label: 'الكشف الوظيفي الشامل',
    fieldIds: ['employeeCode', 'fullNameAr', 'department', 'jobTitle', 'branch', 'status'],
  },
  {
    id: 'directory',
    label: 'دليل الاتصال والمعلومات الوظيفية',
    fieldIds: ['employeeCode', 'fullNameAr', 'phone', 'department', 'jobTitle', 'branch'],
  },
  {
    id: 'organization',
    label: 'كشف التعيينات والهيكل التنظيمي',
    fieldIds: ['employeeCode', 'fullNameAr', 'department', 'team', 'jobTitle', 'createdAt', 'status'],
  },
];

export function CustomReportBuilder() {
  const { toast } = useToast();
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [selectedDept, setSelectedDept] = useState<string>('all');

  // الأعمدة المختارة افتراضياً
  const [selectedFieldIds, setSelectedFieldIds] = useState<string[]>([
    'employeeCode',
    'fullNameAr',
    'department',
    'jobTitle',
    'branch',
    'status',
  ]);

  const employeesQuery = useEmployees(searchTerm, selectedStatus);
  const rawEmployees = useMemo(() => employeesQuery.data ?? [], [employeesQuery.data]);

  // استخراج قائمة الإدارات المتاحة
  const departments = useMemo(() => {
    const set = new Set<string>();
    rawEmployees.forEach((e) => {
      if (e.department) set.add(e.department);
    });
    return Array.from(set).sort();
  }, [rawEmployees]);

  // تصفية الموظفين حسب الإدارة
  const filteredEmployees = useMemo(() => {
    if (selectedDept === 'all') return rawEmployees;
    return rawEmployees.filter((e) => e.department === selectedDept);
  }, [rawEmployees, selectedDept]);

  // الحقول المحددة حالياً
  const activeFields = useMemo(() => {
    return AVAILABLE_FIELDS.filter((f) => selectedFieldIds.includes(f.id));
  }, [selectedFieldIds]);

  const toggleField = (id: string) => {
    setSelectedFieldIds((prev) => (prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]));
  };

  const selectAll = () => {
    setSelectedFieldIds(AVAILABLE_FIELDS.map((f) => f.id));
  };

  const clearAll = () => {
    setSelectedFieldIds(['employeeCode', 'fullNameAr']);
  };

  const applyPreset = (fieldIds: string[]) => {
    setSelectedFieldIds(fieldIds);
    toast({ message: 'تم تطبيق القالب المحدد!', tone: 'success' });
  };

  const handleExportCsv = () => {
    if (activeFields.length === 0 || filteredEmployees.length === 0) {
      toast({ message: 'لا توجد بيانات أو أعمدة للتصدير.', tone: 'warning' });
      return;
    }

    const columns: ExportColumn<EmployeeSummary>[] = activeFields.map((f) => ({
      key: f.id,
      header: f.label,
      get: (emp) => f.getValue(emp),
    }));

    const csvContent = toCsv(columns, filteredEmployees);
    const dateStr = new Date().toISOString().split('T')[0];
    downloadCsv(`custom_report_${dateStr}.csv`, csvContent);
    toast({ message: `تم تصدير ${filteredEmployees.length} سجلاً بنجاح!`, tone: 'success' });
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="space-y-6">
      {/* بطاقة الترويسة والتحكم */}
      <section className="card p-6 border border-[var(--border)] bg-gradient-to-r from-[var(--surface)] via-[var(--surface-muted)] to-[var(--surface)]">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--brand-primary)] text-white shadow-xs">
              <FileSpreadsheet className="size-6" aria-hidden="true" />
            </div>
            <div>
              <h2 className="text-xl font-black text-[var(--text)]">منشئ التقارير المخصص</h2>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">
                تحديد الحقول والأعمدة بحرية، الفلترة حسب الأقسام، والمعاينة والتصدير الفوري لـ Excel
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handlePrint}
              disabled={filteredEmployees.length === 0}
              className="btn-secondary flex items-center gap-2 text-xs py-2 px-3.5"
            >
              <Printer className="size-4" aria-hidden="true" />
              طباعة
            </button>
            <button
              type="button"
              onClick={handleExportCsv}
              disabled={filteredEmployees.length === 0 || activeFields.length === 0}
              className="btn-primary flex items-center gap-2 text-xs py-2 px-4 shadow-xs"
            >
              <Download className="size-4" aria-hidden="true" />
              تصدير Excel (CSV)
            </button>
          </div>
        </div>
      </section>

      {/* القوالب السريعة ومحدد الأعمدة */}
      <section className="card p-5 border border-[var(--border)] space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] pb-3">
          <div className="flex items-center gap-2">
            <Layers className="size-4 text-[var(--brand-primary)]" aria-hidden="true" />
            <h3 className="text-sm font-black text-[var(--text)]">قوالب التقارير السريعة:</h3>
            <div className="flex flex-wrap gap-1.5">
              {PRESETS.map((preset) => (
                <button
                  key={preset.id}
                  type="button"
                  onClick={() => applyPreset(preset.fieldIds)}
                  className="rounded-lg border border-[var(--border)] bg-[var(--surface-muted)] px-3 py-1 text-xs font-bold text-[var(--text)] hover:border-[var(--brand-primary)] hover:text-[var(--brand-primary)] transition-colors"
                >
                  {preset.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={selectAll}
              className="text-xs font-bold text-[var(--brand-primary)] hover:underline"
            >
              تحديد كل الأعمدة
            </button>
            <span className="text-[var(--border)]">|</span>
            <button
              type="button"
              onClick={clearAll}
              className="text-xs font-bold text-[var(--text-muted)] hover:underline"
            >
              إلغاء التحديد
            </button>
          </div>
        </div>

        {/* شبكة الحقول حسب الفئات */}
        <div className="space-y-3">
          <span className="text-xs font-bold text-[var(--text-muted)] block">
            الأعمدة المعروضة في التقرير ({activeFields.length} من {AVAILABLE_FIELDS.length}):
          </span>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {(['أساسية', 'وظيفية', 'حالة الحساب'] as const).map((cat) => {
              const catFields = AVAILABLE_FIELDS.filter((f) => f.category === cat);
              return (
                <div key={cat} className="rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/40 p-3 space-y-2">
                  <h4 className="text-xs font-black text-[var(--brand-primary)] border-b border-[var(--border)]/70 pb-1.5">
                    {cat}
                  </h4>
                  <div className="space-y-1.5">
                    {catFields.map((field) => {
                      const isSelected = selectedFieldIds.includes(field.id);
                      return (
                        <label
                          key={field.id}
                          className="flex items-center gap-2 cursor-pointer text-xs select-none hover:text-[var(--brand-primary)] transition-colors"
                        >
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => toggleField(field.id)}
                            className="rounded border-[var(--border)] text-[var(--brand-primary)] focus:ring-[var(--brand-primary)] size-3.5"
                          />
                          <span className={isSelected ? 'font-black text-[var(--text)]' : 'text-[var(--text-muted)]'}>
                            {field.label}
                          </span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* شريط الفلاتر والبحث */}
      <section className="flex flex-wrap items-center justify-between gap-3 bg-[var(--surface)] p-4 rounded-xl border border-[var(--border)]">
        <div className="flex flex-wrap items-center gap-3 flex-1">
          {/* البحث */}
          <div className="relative min-w-[220px] flex-1 sm:max-w-xs">
            <Search className="absolute right-3 top-2.5 size-4 text-[var(--text-muted)]" aria-hidden="true" />
            <input
              type="text"
              placeholder="بحث بالاسم أو الكود..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="input w-full pr-9 text-xs"
            />
          </div>

          {/* فلتر الإدارة */}
          <select
            value={selectedDept}
            onChange={(e) => setSelectedDept(e.target.value)}
            className="input text-xs"
          >
            <option value="all">كل الإدارات والأقسام</option>
            {departments.map((dept) => (
              <option key={dept} value={dept}>
                {dept}
              </option>
            ))}
          </select>

          {/* فلتر الحالة */}
          <select
            value={selectedStatus}
            onChange={(e) => setSelectedStatus(e.target.value)}
            className="input text-xs"
          >
            <option value="all">كل الحالات الوظيفية</option>
            <option value="active">نشط (Active)</option>
            <option value="suspended">موقوف (Suspended)</option>
            <option value="archived">مؤرشف / منتهي (Archived)</option>
          </select>
        </div>

        <div className="text-xs font-bold text-[var(--text-muted)] tabular">
          النتائج: <span className="text-[var(--brand-primary)] font-black">{filteredEmployees.length}</span> موظف
        </div>
      </section>

      {/* جدول المعاينة الحية */}
      <section className="card overflow-hidden border border-[var(--border)]">
        <div className="overflow-x-auto">
          <table className="data-table">
            <thead>
              <tr>
                <th className="w-12 text-center">#</th>
                {activeFields.map((f) => (
                  <th key={f.id}>{f.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {employeesQuery.isLoading ? (
                <tr>
                  <td colSpan={activeFields.length + 1} className="p-8 text-center text-xs text-[var(--text-muted)]">
                    جاري جلب البيانات...
                  </td>
                </tr>
              ) : filteredEmployees.length === 0 ? (
                <tr>
                  <td colSpan={activeFields.length + 1} className="p-8 text-center text-xs text-[var(--text-muted)]">
                    لا توجد سجلات تطابق الفلاتر المحددة.
                  </td>
                </tr>
              ) : (
                filteredEmployees.map((emp, idx) => (
                  <tr key={emp.id}>
                    <td className="text-center text-xs text-[var(--text-muted)] tabular">{idx + 1}</td>
                    {activeFields.map((f) => {
                      const val = f.getValue(emp);
                      if (f.id === 'status') {
                        return (
                          <td key={f.id}>
                            <StatusBadge status={String(val)} />
                          </td>
                        );
                      }
                      return (
                        <td key={f.id} className="tabular">
                          {val}
                        </td>
                      );
                    })}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
