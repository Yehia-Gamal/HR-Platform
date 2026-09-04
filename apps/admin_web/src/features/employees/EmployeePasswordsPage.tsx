import {
  Building2,
  Check,
  Copy,
  Download,
  Eye,
  EyeOff,
  KeyRound,
  Lock,
  Mail,
  Phone,
  RefreshCw,
  Search,
  Send,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  Users,
} from 'lucide-react';
import { useMemo, useState } from 'react';
import type { EmployeeSummary } from '@ahla/shared-contracts';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useToast } from '../../ui/Toast';
import { UserAvatar } from '../../ui/UserAvatar';
import { useEmployees, useResendInvite, useSetEmployeePassword } from './useEmployees';

/**
 * دالة توليد كلمة مرور قوية وسهلة التداول من 10 خانات
 * تضمن وجود أحرف كبيرة وصغيرة وأرقام ورموز خاصة بدون الأحرف الملتبسة (O, 0, l, 1)
 */
function generateSecurePassword(): string {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz';
  const numbers = '23456789';
  const symbols = '!@#$%&*';

  let pwd = '';
  pwd += letters[Math.floor(Math.random() * 24)]; // Uppercase
  pwd += letters[24 + Math.floor(Math.random() * 24)]; // Lowercase
  pwd += numbers[Math.floor(Math.random() * numbers.length)];
  pwd += symbols[Math.floor(Math.random() * symbols.length)];

  const allChars = letters + numbers + symbols;
  for (let i = pwd.length; i < 10; i++) {
    pwd += allChars[Math.floor(Math.random() * allChars.length)];
  }

  return pwd
    .split('')
    .sort(() => 0.5 - Math.random())
    .join('');
}

interface ResetPasswordDialogProps {
  employee: EmployeeSummary;
  onClose: () => void;
  onSuccess: (newPassword: string) => void;
}

function ResetPasswordDialog({ employee, onClose, onSuccess }: ResetPasswordDialogProps) {
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPwd, setShowPwd] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const setPasswordMutation = useSetEmployeePassword();

  const handleAutoGenerate = () => {
    const generated = generateSecurePassword();
    setPassword(generated);
    setConfirmPassword(generated);
    setShowPwd(true);
    setError(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (password.length < 6) {
      setError('كلمة المرور يجب ألا تقل عن 6 أحرف طبقاً للائحة النظام.');
      return;
    }
    if (password.length > 72) {
      setError('كلمة المرور يجب ألا تتجاوز 72 حرفاً.');
      return;
    }
    if (password !== confirmPassword) {
      setError('كلمتا المرور غير متطابقتين.');
      return;
    }

    try {
      await setPasswordMutation.mutateAsync({ employeeId: employee.id, password });
      onSuccess(password);
      onClose();
    } catch (err) {
      setError(safeErrorMessage(err));
    }
  };

  return (
    <DialogOverlay title="إعادة تعيين كلمة مرور الموظف" onClose={onClose} maxWidth="max-w-md">
      <form onSubmit={handleSubmit} className="space-y-4 text-right">
        <div className="flex items-center gap-3 rounded-xl border border-[var(--border)] bg-[var(--surface-subtle)] p-3">
          <UserAvatar displayName={employee.fullNameAr} photoUrl={employee.photoUrl} size="md" />
          <div className="min-w-0 flex-1">
            <h4 className="text-sm font-black text-[var(--text)]">{employee.fullNameAr}</h4>
            <p className="text-xs text-[var(--muted)]">
              كود: <span className="font-mono font-bold text-[var(--primary)]">{employee.employeeCode}</span>
              {employee.jobTitle ? ` • ${employee.jobTitle}` : ''}
            </p>
          </div>
        </div>

        {error ? (
          <div className="flex items-center gap-2 rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] p-3 text-xs font-bold text-[var(--danger)]">
            <ShieldAlert className="size-4 shrink-0" aria-hidden="true" />
            <span>{error}</span>
          </div>
        ) : null}

        <div>
          <div className="mb-1 flex items-center justify-between">
            <label htmlFor="new-pwd-input" className="text-xs font-bold text-[var(--text)]">
              كلمة المرور الجديدة
            </label>
            <button
              type="button"
              onClick={handleAutoGenerate}
              className="flex items-center gap-1 text-xs font-bold text-[var(--primary)] hover:underline"
            >
              <Sparkles className="size-3.5" aria-hidden="true" />
              توليد كلمة مرور قوية
            </button>
          </div>

          <div className="relative">
            <input
              id="new-pwd-input"
              type={showPwd ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="6 أحرف على الأقل..."
              className="input pr-3 pl-10 font-mono text-sm"
              dir="ltr"
              autoFocus
              required
            />
            <button
              type="button"
              onClick={() => setShowPwd(!showPwd)}
              className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)] hover:text-[var(--text)]"
              aria-label={showPwd ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
            >
              {showPwd ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </button>
          </div>
        </div>

        <div>
          <label htmlFor="confirm-pwd-input" className="mb-1 block text-xs font-bold text-[var(--text)]">
            تأكيد كلمة المرور الجديدة
          </label>
          <input
            id="confirm-pwd-input"
            type={showPwd ? 'text' : 'password'}
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            placeholder="أعد كتابة كلمة المرور..."
            className="input font-mono text-sm"
            dir="ltr"
            required
          />
        </div>

        <div className="rounded-lg bg-blue-500/10 p-3 text-[11px] leading-relaxed text-blue-600 dark:text-blue-400">
          <p className="font-bold">ملاحظة أمنية هامة:</p>
          <p>
            سيتم إلزام الموظف بتغيير كلمة المرور التي تعينها له فور تسجيل دخوله الأول لضمان الخصوصية وسرية الحساب.
          </p>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button type="button" onClick={onClose} className="btn-secondary" disabled={setPasswordMutation.isPending}>
            إلغاء
          </button>
          <button type="submit" className="btn-primary" disabled={setPasswordMutation.isPending}>
            {setPasswordMutation.isPending ? (
              <>
                <RefreshCw className="size-4 animate-spin" aria-hidden="true" />
                جاري التعيين...
              </>
            ) : (
              <>
                <Check className="size-4" aria-hidden="true" />
                حفظ وتعيين كلمة المرور
              </>
            )}
          </button>
        </div>
      </form>
    </DialogOverlay>
  );
}

export function EmployeePasswordsPage() {
  const { toast } = useToast();
  const { data: employees = [], isLoading, isError, error, refetch } = useEmployees();
  const resendInviteMutation = useResendInvite();
  const setPasswordMutation = useSetEmployeePassword();

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [departmentFilter, setDepartmentFilter] = useState<string>('all');

  // سجل كلمات المرور المؤقتة المعينة في الجلسة للمسؤول [employeeId: password]
  const [sessionPasswords, setSessionPasswords] = useState<Record<string, string>>({});
  // حالة كشف/إخفاء كلمة المرور لكل موظف [employeeId: boolean]
  const [visiblePasswords, setVisiblePasswords] = useState<Record<string, boolean>>({});
  // حالة الموظف المنسوخ مؤخراً
  const [copiedId, setCopiedId] = useState<string | null>(null);

  // حوار إعادة التعيين
  const [selectedEmployeeForReset, setSelectedEmployeeForReset] = useState<EmployeeSummary | null>(null);
  // معرف الموظف الجاري إرسال الرابط له
  const [sendingEmailId, setSendingEmailId] = useState<string | null>(null);

  // استخراج قائمة الإدارات الفريدة للفلترة
  const departments = useMemo(() => {
    const set = new Set<string>();
    employees.forEach((emp) => {
      if (emp.department) set.add(emp.department);
    });
    return Array.from(set).sort();
  }, [employees]);

  // تصفية الموظفين
  const filteredEmployees = useMemo(() => {
    return employees.filter((emp) => {
      const matchSearch =
        !searchQuery.trim() ||
        emp.fullNameAr.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (emp.fullNameEn && emp.fullNameEn.toLowerCase().includes(searchQuery.toLowerCase())) ||
        emp.employeeCode.toLowerCase().includes(searchQuery.toLowerCase()) ||
        (emp.phoneE164 && emp.phoneE164.includes(searchQuery));

      const matchStatus =
        statusFilter === 'all' ||
        (statusFilter === 'active' && emp.status === 'active') ||
        (statusFilter === 'pending' && ['invited', 'onboarding', 'draft'].includes(emp.status)) ||
        (statusFilter === 'other' && !['active', 'invited', 'onboarding', 'draft'].includes(emp.status));

      const matchDept = departmentFilter === 'all' || emp.department === departmentFilter;

      return matchSearch && matchStatus && matchDept;
    });
  }, [employees, searchQuery, statusFilter, departmentFilter]);

  // إحصائيات سريعة
  const stats = useMemo(() => {
    const total = employees.length;
    const active = employees.filter((e) => e.status === 'active').length;
    const pending = employees.filter((e) => ['invited', 'onboarding', 'draft'].includes(e.status)).length;
    const inSession = Object.keys(sessionPasswords).length;
    return { total, active, pending, inSession };
  }, [employees, sessionPasswords]);

  // نسخ كلمة المرور إلى الحافظة
  const copyPassword = async (employeeId: string, pwdText: string) => {
    try {
      await navigator.clipboard.writeText(pwdText);
      setCopiedId(employeeId);
      toast({ message: 'تم نسخ كلمة المرور إلى الحافظة بنجاح', tone: 'success' });
      setTimeout(() => setCopiedId(null), 2500);
    } catch {
      toast({ message: 'تعذر النسخ التلقائي. يرجى النسخ يدوياً.', tone: 'error' });
    }
  };

  // تبديل إظهار كلمة المرور
  const toggleVisibility = (employeeId: string) => {
    setVisiblePasswords((prev) => ({ ...prev, [employeeId]: !prev[employeeId] }));
  };

  // إرسال رابط إعادة تعيين / تفعيل لكلمة المرور عبر البريد الإلكتروني
  const handleSendResetLink = async (employee: EmployeeSummary) => {
    setSendingEmailId(employee.id);
    try {
      const msg = await resendInviteMutation.mutateAsync(employee.id);
      toast({
        message: msg || `تم إرسال رابط ضبط كلمة المرور إلى البريد الرسمي للموظف ${employee.fullNameAr}`,
        tone: 'success',
      });
    } catch (err) {
      toast({
        message: safeErrorMessage(err) || 'تعذر إرسال رابط ضبط كلمة المرور. تأكد من وجود بريد مسجل.',
        tone: 'error',
      });
    } finally {
      setSendingEmailId(null);
    }
  };

  // توليد كلمة مرور فورية وتعيينها للموظف
  const handleInstantGenerateAndSet = async (employee: EmployeeSummary) => {
    const newPwd = generateSecurePassword();
    try {
      await setPasswordMutation.mutateAsync({ employeeId: employee.id, password: newPwd });
      setSessionPasswords((prev) => ({ ...prev, [employee.id]: newPwd }));
      setVisiblePasswords((prev) => ({ ...prev, [employee.id]: true }));
      toast({
        message: `تم توليد وتعيين كلمة المرور للموظف ${employee.fullNameAr}: (${newPwd})`,
        tone: 'success',
      });
    } catch (err) {
      toast({ message: safeErrorMessage(err) || 'تعذر تعيين كلمة المرور.', tone: 'error' });
    }
  };

  // تصدير كشف بيانات الحسابات وحالات كلمة المرور
  const handleExport = () => {
    const headers = ['كود الموظف', 'الاسم', 'الإدارة', 'المسمى الوظيفي', 'الهاتف', 'حالة الحساب', 'كلمة المرور المؤقتة المحددة'];
    const rows = filteredEmployees.map((emp) => [
      emp.employeeCode,
      emp.fullNameAr,
      emp.department ?? '—',
      emp.jobTitle ?? '—',
      emp.phoneE164 ?? '—',
      emp.status,
      sessionPasswords[emp.id] ?? 'مشفرة في الخادم',
    ]);

    const csvContent =
      '\uFEFF' +
      [headers.join(','), ...rows.map((r) => r.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(','))].join(
        '\n'
      );

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `employee-passwords-audit-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    toast({ message: 'تم تصدير كشف الحسابات بنجاح', tone: 'success' });
  };

  if (isLoading) {
    return (
      <div className="space-y-6">
        <SkeletonCard className="h-28" />
        <div className="grid gap-4 sm:grid-cols-4">
          <SkeletonCard className="h-24" />
          <SkeletonCard className="h-24" />
          <SkeletonCard className="h-24" />
          <SkeletonCard className="h-24" />
        </div>
        <SkeletonCard className="h-96" />
      </div>
    );
  }

  if (isError) {
    return (
      <ErrorState
        title="تعذر تحميل بيانات حسابات وكلمات مرور الموظفين"
        description={safeErrorMessage(error)}
        onRetry={() => void refetch()}
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* رأس الصفحة */}
      <PageHeader
        title="إدارة كلمات المرور وحسابات الموظفين"
        description="لوحة مركزية موحدة لتعيين كلمات المرور، استعراض بيانات الدخول المؤقتة، وإرسال روابط إعادة التعيين المعتمدة"
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" onClick={handleExport} className="btn-secondary">
              <Download className="size-4" aria-hidden="true" />
              تصدير كشف الحسابات
            </button>
          </div>
        }
      />

      {/* بطاقات المؤشرات الإحصائية */}
      <section aria-label="إحصائيات حسابات وكلمات المرور" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard label="إجمالي الموظفين" value={stats.total} icon={Users} />
        <MetricCard label="حسابات مفعلة" value={stats.active} icon={ShieldCheck} />
        <MetricCard label="بانتظار تفعيل كلمة المرور" value={stats.pending} icon={Mail} />
        <MetricCard
          label="كلمات مرور معينة بالجلسة"
          value={stats.inSession}
          icon={KeyRound}
        />
      </section>

      {/* تنبيه الإرشادات الأمنية */}
      <div className="flex items-start gap-3 rounded-2xl border border-blue-500/20 bg-blue-500/5 p-4 text-xs leading-relaxed text-blue-700 dark:text-blue-300">
        <ShieldAlert className="size-5 shrink-0 text-blue-600 dark:text-blue-400 mt-0.5" aria-hidden="true" />
        <div>
          <h4 className="font-bold mb-1">السياسة الأمنية لإدارة كلمات المرور:</h4>
          <p className="text-[11px] text-[var(--muted)] leading-normal">
            تُخزن كلمات المرور الحقيقية في قاعدة البيانات بتشفير أحادي الاتجاه غير قابل للاسترجاع. عند قيامك بتعيين كلمة مرور هنا أو توليدها، يمكنك نسخها للموظف فوراً مع إلزامه آلياً بتغييرها عند أول تسجيل دخول لحماية حسابه. يمكنك أيضاً إرسال رابط آمن ومباشر لإعادة التعيين عبر بريده الرسمي.
          </p>
        </div>
      </div>

      {/* شريط الفلاتر والبحث السريع */}
      <div className="card p-4">
        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="relative flex-1">
            <Search className="absolute right-3.5 top-1/2 size-4 -translate-y-1/2 text-[var(--muted)]" aria-hidden="true" />
            <input
              type="search"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="البحث بالاسم، الكود الوظيفي، الهاتف..."
              className="input pr-10 text-sm"
              aria-label="البحث عن موظف"
            />
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="select text-xs font-bold"
              aria-label="تصفية بحسب حالة الحساب"
            >
              <option value="all">كافة الحالات</option>
              <option value="active">الحسابات المفعلة فقط</option>
              <option value="pending">بانتظار ضبط كلمة المرور / تفعيل</option>
              <option value="other">حالات أخرى (معلق / مؤرشف)</option>
            </select>

            {departments.length > 0 ? (
              <select
                value={departmentFilter}
                onChange={(e) => setDepartmentFilter(e.target.value)}
                className="select text-xs font-bold"
                aria-label="تصفية بحسب الإدارة"
              >
                <option value="all">كافة الإدارات</option>
                {departments.map((dept) => (
                  <option key={dept} value={dept}>
                    {dept}
                  </option>
                ))}
              </select>
            ) : null}
          </div>
        </div>
      </div>

      {/* جدول كلمات المرور والحسابات */}
      <section className="card overflow-hidden" aria-label="جدول كلمات مرور الموظفين">
        {filteredEmployees.length === 0 ? (
          <EmptyState
            title="لا توجد نتائج مطابقة"
            description="لم يتم العثور على موظفين يطابقون معايير البحث والفلترة المحددة."
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-xs">
              <thead className="border-b border-[var(--border)] bg-[var(--surface-subtle)] text-[var(--muted)]">
                <tr>
                  <th scope="col" className="p-4 font-bold">الموظف والكود</th>
                  <th scope="col" className="p-4 font-bold">الإدارة والمسمى</th>
                  <th scope="col" className="p-4 font-bold">الهاتف</th>
                  <th scope="col" className="p-4 font-bold">حالة الحساب</th>
                  <th scope="col" className="p-4 font-bold">كلمة المرور المؤقتة / المعينة</th>
                  <th scope="col" className="p-4 text-center font-bold">إجراءات التحكم</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {filteredEmployees.map((emp) => {
                  const sessionPwd = sessionPasswords[emp.id];
                  const isVisible = visiblePasswords[emp.id];
                  const isCopied = copiedId === emp.id;
                  const isSendingEmail = sendingEmailId === emp.id;

                  return (
                    <tr key={emp.id} className="transition-colors hover:bg-[var(--surface-subtle)]/50">
                      {/* الموظف */}
                      <td className="p-4">
                        <div className="flex items-center gap-3">
                          <UserAvatar displayName={emp.fullNameAr} photoUrl={emp.photoUrl} size="md" />
                          <div>
                            <span className="block font-bold text-[var(--text)]">{emp.fullNameAr}</span>
                            {emp.fullNameEn ? <span className="block text-[11px] text-[var(--muted)]">{emp.fullNameEn}</span> : null}
                            <span className="mt-0.5 inline-block rounded bg-[var(--surface-subtle)] px-2 py-0.5 font-mono text-[11px] font-black text-[var(--primary)] border border-[var(--border)]">
                              {emp.employeeCode}
                            </span>
                          </div>
                        </div>
                      </td>

                      {/* الإدارة والمسمى */}
                      <td className="p-4">
                        <div className="space-y-1">
                          <div className="flex items-center gap-1.5 font-bold text-[var(--text)]">
                            <Building2 className="size-3.5 text-[var(--muted)]" aria-hidden="true" />
                            <span>{emp.department ?? 'الإدارة العامة'}</span>
                          </div>
                          <span className="block text-[11px] text-[var(--muted)]">{emp.jobTitle ?? 'موظف'}</span>
                        </div>
                      </td>

                      {/* الهاتف */}
                      <td className="p-4">
                        <span className="flex items-center gap-1.5 font-mono text-xs text-[var(--muted)]">
                          <Phone className="size-3.5 text-[var(--muted)]" aria-hidden="true" />
                          <span dir="ltr">{emp.phoneE164 ?? '—'}</span>
                        </span>
                      </td>

                      {/* حالة الحساب */}
                      <td className="p-4">
                        <StatusBadge value={emp.status} />
                      </td>

                      {/* كلمة المرور المؤقتة / المعينة */}
                      <td className="p-4">
                        {sessionPwd ? (
                          <div className="inline-flex items-center gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-1.5">
                            <KeyRound className="size-3.5 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
                            <span className="font-mono text-xs font-black text-emerald-700 dark:text-emerald-300" dir="ltr">
                              {isVisible ? sessionPwd : '••••••••••'}
                            </span>
                            <div className="flex items-center gap-1 border-r border-emerald-500/20 pr-2 mr-1">
                              <button
                                type="button"
                                onClick={() => toggleVisibility(emp.id)}
                                className="rounded p-1 text-emerald-700 hover:bg-emerald-500/20 dark:text-emerald-300"
                                aria-label={isVisible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'}
                              >
                                {isVisible ? <EyeOff className="size-3.5" /> : <Eye className="size-3.5" />}
                              </button>
                              <button
                                type="button"
                                onClick={() => copyPassword(emp.id, sessionPwd)}
                                className="rounded p-1 text-emerald-700 hover:bg-emerald-500/20 dark:text-emerald-300"
                                aria-label="نسخ كلمة المرور"
                              >
                                {isCopied ? <Check className="size-3.5 text-emerald-600" /> : <Copy className="size-3.5" />}
                              </button>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-center gap-2">
                            <span className="flex items-center gap-1.5 rounded-lg bg-[var(--surface-subtle)] px-2.5 py-1 text-[11px] font-bold text-[var(--muted)] border border-[var(--border)]">
                              <Lock className="size-3" aria-hidden="true" />
                              مشفرة في الخادم
                            </span>
                            <button
                              type="button"
                              onClick={() => handleInstantGenerateAndSet(emp)}
                              className="flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-bold text-[var(--primary)] hover:bg-[var(--primary)]/10 transition-colors"
                              title="توليد وتعيين كلمة مرور فورية"
                            >
                              <Sparkles className="size-3" aria-hidden="true" />
                              توليد فوري
                            </button>
                          </div>
                        )}
                      </td>

                      {/* الإجراءات */}
                      <td className="p-4 text-center">
                        <div className="flex items-center justify-center gap-2">
                          <button
                            type="button"
                            onClick={() => setSelectedEmployeeForReset(emp)}
                            className="btn-secondary !px-2.5 !py-1 text-xs"
                            title="إعادة ضبط وتعيين كلمة المرور"
                          >
                            <KeyRound className="size-3.5 text-[var(--primary)]" aria-hidden="true" />
                            تغيير كلمة المرور
                          </button>

                          <button
                            type="button"
                            onClick={() => handleSendResetLink(emp)}
                            disabled={isSendingEmail}
                            className="btn-secondary !px-2.5 !py-1 text-xs"
                            title="إرسال رابط إعادة التعيين بالبريد الرسمي"
                          >
                            {isSendingEmail ? (
                              <RefreshCw className="size-3.5 animate-spin" aria-hidden="true" />
                            ) : (
                              <Send className="size-3.5 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
                            )}
                            إرسال الرابط
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* حوار إعادة ضبط كلمة المرور */}
      {selectedEmployeeForReset ? (
        <ResetPasswordDialog
          employee={selectedEmployeeForReset}
          onClose={() => setSelectedEmployeeForReset(null)}
          onSuccess={(newPwd) => {
            setSessionPasswords((prev) => ({ ...prev, [selectedEmployeeForReset.id]: newPwd }));
            setVisiblePasswords((prev) => ({ ...prev, [selectedEmployeeForReset.id]: true }));
            toast({
              message: `تم تعيين كلمة المرور بنجاح للموظف ${selectedEmployeeForReset.fullNameAr}`,
              tone: 'success',
            });
          }}
        />
      ) : null}
    </div>
  );
}
