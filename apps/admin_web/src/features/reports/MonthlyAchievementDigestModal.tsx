import React, { useMemo, useState } from 'react';
import {
  AlertCircle,
  Award,
  Calendar,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Copy,
  Layers,
  Printer,
  Share2,
  Sparkles,
  TrendingUp,
  X,
} from 'lucide-react';
import { shareMonthlyAchievementReport } from '../../core/whatsappShare';
import { useEmployees } from '../employees/useEmployees';
import { useEmployeeDailyReports } from '../employees/useEmployeeDossier';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useToast } from '../../ui/Toast';
import { UserAvatar } from '../../ui/UserAvatar';

const ARABIC_MONTHS = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

interface MonthlyAchievementDigestModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialEmployeeId?: string;
  initialYear?: number;
  initialMonth?: number; // 1-12
}

export function MonthlyAchievementDigestModal({
  isOpen,
  onClose,
  initialEmployeeId,
  initialYear,
  initialMonth,
}: MonthlyAchievementDigestModalProps) {
  const { toast } = useToast();
  const currentDate = new Date();
  const currentYear = initialYear ?? currentDate.getFullYear();
  const currentMonth = initialMonth ?? currentDate.getMonth() + 1;

  const [selectedYear, setSelectedYear] = useState<number>(currentYear);
  const [selectedMonth, setSelectedMonth] = useState<number>(currentMonth);
  const [employeeId, setEmployeeId] = useState<string>(initialEmployeeId ?? '');
  const [copied, setCopied] = useState<boolean>(false);

  const { data: employees = [], isLoading: loadingEmployees } = useEmployees();

  // الموظف المختار
  const selectedEmployee = useMemo(() => {
    if (employeeId) {
      return employees.find((e) => e.id === employeeId) ?? employees[0];
    }
    return employees[0];
  }, [employees, employeeId]);

  const activeEmpId = selectedEmployee?.id;

  // جلب تقارير الموظف
  const { data: dailyReports = [], isLoading: loadingReports } = useEmployeeDailyReports(activeEmpId);

  // فلترة تقارير الشهر والسنة المحددة
  const monthPrefix = `${selectedYear}-${String(selectedMonth).padStart(2, '0')}`;
  const monthReports = useMemo(() => {
    return dailyReports
      .filter((r) => r.reportDate.startsWith(monthPrefix))
      .sort((a, b) => a.reportDate.localeCompare(b.reportDate));
  }, [dailyReports, monthPrefix]);

  // إحصائيات الشهر
  const stats = useMemo(() => {
    const totalDays = monthReports.length;

    // استخلاص الإنجازات غير الفارغة
    const achievements: { date: string; text: string }[] = [];
    const blockers: { date: string; text: string }[] = [];
    const tomorrowPlans: { date: string; text: string }[] = [];
    const managerNotes: { date: string; text: string; reviewer: string }[] = [];

    monthReports.forEach((r) => {
      if (r.achievements?.trim()) {
        const lines = r.achievements
          .split('\n')
          .map((l) => l.trim())
          .filter((l) => l.length > 2);
        lines.forEach((line) => achievements.push({ date: r.reportDate, text: line }));
      }
      if (r.blockers?.trim() && !['لا يوجد', 'لا توجد', 'لا', 'none', '-'].includes(r.blockers.trim())) {
        blockers.push({ date: r.reportDate, text: r.blockers.trim() });
      }
      if (r.tomorrowPlan?.trim()) {
        tomorrowPlans.push({ date: r.reportDate, text: r.tomorrowPlan.trim() });
      }
      if (r.managerComment?.trim()) {
        managerNotes.push({
          date: r.reportDate,
          text: r.managerComment.trim(),
          reviewer: r.reviewerName || 'الإدارة المباشرة',
        });
      }
    });

    return {
      totalDays,
      achievements,
      blockers,
      tomorrowPlans,
      managerNotes,
    };
  }, [monthReports]);

  const monthName = ARABIC_MONTHS[selectedMonth - 1] ?? `شهر ${selectedMonth}`;

  // التنقل بين الشهور
  const handlePrevMonth = () => {
    if (selectedMonth === 1) {
      setSelectedMonth(12);
      setSelectedYear((y) => y - 1);
    } else {
      setSelectedMonth((m) => m - 1);
    }
  };

  const handleNextMonth = () => {
    if (selectedMonth === 12) {
      setSelectedMonth(1);
      setSelectedYear((y) => y + 1);
    } else {
      setSelectedMonth((m) => m + 1);
    }
  };

  // توليد النص الرسمي المنسق
  const buildFormattedDigestText = () => {
    const empName = selectedEmployee?.fullNameAr || 'الموظف';
    const dept = selectedEmployee?.department || '';
    const lines: string[] = [
      `📋 تقرير إنجازات شهر (${monthName} ${selectedYear})`,
      `الموظف: ${empName} | القسم: ${dept}`,
      '──────────────────────────',
      `• عدد أيام العمل الموثقة: ${stats.totalDays} يوماً`,
      `• إجمالي المهام والمنجزات: ${stats.achievements.length} إنجازاً`,
      `• معوقات وتحديات تم التغلب عليها: ${stats.blockers.length}`,
      '──────────────────────────',
      '🌟 أبرز الإنجازات الموثقة:',
    ];

    if (stats.achievements.length === 0) {
      lines.push('لم يتم تسجيل إنجازات مفصلة في هذا الشهر.');
    } else {
      stats.achievements.slice(0, 15).forEach((a, i) => {
        lines.push(`${i + 1}) [${a.date}] ${a.text}`);
      });
      if (stats.achievements.length > 15) {
        lines.push(`... بالإضافة إلى ${stats.achievements.length - 15} مهام إضافية مسجلة.`);
      }
    }

    if (stats.blockers.length > 0) {
      lines.push('──────────────────────────');
      lines.push('🛡️ التحديات التشغيلية المعالجة:');
      stats.blockers.forEach((b, i) => {
        lines.push(`• [${b.date}] ${b.text}`);
      });
    }

    lines.push('──────────────────────────');
    lines.push('صادر من منظومة إدارة جمعية أحلى شباب');
    return lines.join('\n');
  };

  // نسخ التقرير
  const handleCopy = async () => {
    const text = buildFormattedDigestText();
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      toast({ message: 'تم نسخ تقرير الإنجاز بنجاح إلى الحافظة', tone: 'success' });
      setTimeout(() => setCopied(false), 2500);
    } catch {
      toast({ message: 'تعذر النسخ التلقائي للحافظة', tone: 'error' });
    }
  };

  // مشاركة عبر واتساب
  const handleWhatsApp = () => {
    const empName = selectedEmployee?.fullNameAr || 'الموظف';
    const dept = selectedEmployee?.department || null;
    const topAchs = stats.achievements.map((a) => a.text);

    shareMonthlyAchievementReport({
      employeeName: empName,
      department: dept,
      monthName,
      year: selectedYear,
      reportedDaysCount: stats.totalDays,
      achievementsCount: stats.achievements.length,
      topAchievements: topAchs,
      phone: selectedEmployee?.phoneE164,
    });
  };

  // طباعة / تصدير PDF
  const handlePrint = () => {
    window.print();
  };

  if (!isOpen) return null;

  return (
    <DialogOverlay onClose={onClose} title="مُولّد تقرير الإنجاز الشهري الذكي" maxWidth="max-w-3xl">
      <div className="space-y-5 text-end font-sans max-h-[82vh] overflow-y-auto px-1">
        {/* شريط الإعدادات السريعة: الموظف والشهر */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-[var(--border)] bg-[var(--surface-raised)] p-3.5">
          {/* اختيار الموظف */}
          <div className="flex items-center gap-2.5 min-w-[240px]">
            <UserAvatar
              photoUrl={selectedEmployee?.photoUrl}
              displayName={selectedEmployee?.fullNameAr || 'موظف'}
              size="md"
            />
            <div className="flex-1">
              <label htmlFor="digest-employee-select" className="block text-[11px] font-bold text-[var(--text-muted)]">
                الموظف المعني:
              </label>
              <select
                id="digest-employee-select"
                value={employeeId || selectedEmployee?.id || ''}
                onChange={(e) => setEmployeeId(e.target.value)}
                disabled={loadingEmployees}
                className="w-full mt-0.5 rounded-lg border border-[var(--border)] bg-[var(--surface)] px-2.5 py-1 text-xs font-black text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-brand/30"
              >
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.fullNameAr} ({emp.employeeCode}) {emp.department ? `- ${emp.department}` : ''}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* محدد الشهر والسنة */}
          <div className="flex items-center gap-1.5 bg-[var(--surface)] border border-[var(--border)] rounded-xl px-2 py-1">
            <button
              type="button"
              onClick={handlePrevMonth}
              title="الشهر السابق"
              className="p-1 rounded-lg hover:bg-[var(--surface-raised)] text-[var(--text-muted)] transition"
            >
              <ChevronRight className="size-4" />
            </button>
            <div className="flex items-center gap-1 px-2 text-xs font-black text-[var(--text-primary)]">
              <Calendar className="size-3.5 text-brand" />
              <span>{monthName} {selectedYear}</span>
            </div>
            <button
              type="button"
              onClick={handleNextMonth}
              title="الشهر التالي"
              className="p-1 rounded-lg hover:bg-[var(--surface-raised)] text-[var(--text-muted)] transition"
            >
              <ChevronLeft className="size-4" />
            </button>
          </div>
        </div>

        {/* بطاقات الإحصائيات الذكية المستخلصة */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 text-center">
          <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-3">
            <span className="flex items-center justify-center gap-1 text-[11px] font-bold text-[var(--text-muted)]">
              <Calendar className="size-3 text-brand" />
              أيام التوثيق
            </span>
            <strong className="block text-xl font-black text-brand mt-1">
              {loadingReports ? '...' : stats.totalDays} <span className="text-xs font-normal text-[var(--text-muted)]">يوماً</span>
            </strong>
          </div>

          <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-3">
            <span className="flex items-center justify-center gap-1 text-[11px] font-bold text-[var(--text-muted)]">
              <TrendingUp className="size-3 text-emerald-500" />
              إجمالي المهام
            </span>
            <strong className="block text-xl font-black text-emerald-600 dark:text-emerald-400 mt-1">
              {loadingReports ? '...' : stats.achievements.length} <span className="text-xs font-normal text-[var(--text-muted)]">مهمة</span>
            </strong>
          </div>

          <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-3">
            <span className="flex items-center justify-center gap-1 text-[11px] font-bold text-[var(--text-muted)]">
              <AlertCircle className="size-3 text-amber-500" />
              تحديات عولجت
            </span>
            <strong className="block text-xl font-black text-amber-600 dark:text-amber-400 mt-1">
              {loadingReports ? '...' : stats.blockers.length}
            </strong>
          </div>

          <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-3">
            <span className="flex items-center justify-center gap-1 text-[11px] font-bold text-[var(--text-muted)]">
              <Award className="size-3 text-purple-500" />
              توجيهات الإدارة
            </span>
            <strong className="block text-xl font-black text-purple-600 dark:text-purple-400 mt-1">
              {loadingReports ? '...' : stats.managerNotes.length}
            </strong>
          </div>
        </div>

        {/* جسم التقرير وسجل الإنجازات */}
        {loadingReports ? (
          <div className="py-12 text-center text-xs text-[var(--text-muted)]">
            جاري استخلاص وتجميع تقارير الموظف من السجلات اليومية...
          </div>
        ) : stats.totalDays === 0 ? (
          <div className="rounded-2xl border border-dashed border-[var(--border)] p-8 text-center space-y-2">
            <Sparkles className="size-8 text-[var(--text-muted)] mx-auto opacity-40" />
            <p className="text-xs font-bold text-[var(--text-muted)]">
              لا توجد تقارير يومية مسجلة للموظف {selectedEmployee?.fullNameAr} في شهر {monthName} {selectedYear}.
            </p>
            <p className="text-[11px] text-[var(--text-muted)] opacity-80">
              يمكنك اختيار شهر آخر من الأعلى أو تشجيع الموظف على تدوين تقارير العمل اليومية بانتظام.
            </p>
          </div>
        ) : (
          <div className="space-y-4">
            {/* قسم الإنجازات اليومية المجمعة */}
            <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 space-y-3">
              <div className="flex items-center justify-between border-b border-[var(--border)] pb-2">
                <span className="flex items-center gap-1.5 text-xs font-black text-[var(--text-primary)]">
                  <CheckCircle2 className="size-4 text-emerald-500" />
                  سجل الإنجازات المجمعة ({stats.achievements.length} مهمة)
                </span>
                <span className="text-[10px] text-[var(--text-muted)]">مرتبة زمنياً</span>
              </div>

              <div className="space-y-2 max-h-56 overflow-y-auto pr-1">
                {stats.achievements.map((ach, idx) => (
                  <div
                    key={`${ach.date}-${idx}`}
                    className="flex items-start gap-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface)] p-2.5 text-xs"
                  >
                    <span className="shrink-0 rounded-md bg-brand/10 px-1.5 py-0.5 text-[10px] font-bold text-brand">
                      {ach.date}
                    </span>
                    <p className="text-[var(--text-primary)] font-medium leading-relaxed">{ach.text}</p>
                  </div>
                ))}
              </div>
            </div>

            {/* المعوقات المعالجة إن وجدت */}
            {stats.blockers.length > 0 && (
              <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-4 space-y-2.5">
                <div className="flex items-center gap-1.5 text-xs font-black text-amber-700 dark:text-amber-300">
                  <AlertCircle className="size-4 text-amber-500" />
                  التحديات والمعوقات التشغيلية التي تم رصدها ومعالجتها ({stats.blockers.length})
                </div>
                <div className="space-y-1.5 max-h-36 overflow-y-auto pr-1">
                  {stats.blockers.map((b, idx) => (
                    <div
                      key={`blk-${idx}`}
                      className="rounded-lg bg-[var(--surface)] border border-amber-500/20 p-2 text-xs text-amber-800 dark:text-amber-200"
                    >
                      <span className="font-bold text-[10px] text-amber-600 block mb-0.5">{b.date}</span>
                      {b.text}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* توجيهات الإدارة */}
            {stats.managerNotes.length > 0 && (
              <div className="rounded-2xl border border-purple-500/20 bg-purple-500/5 p-4 space-y-2">
                <div className="flex items-center gap-1.5 text-xs font-black text-purple-700 dark:text-purple-300">
                  <Award className="size-4 text-purple-500" />
                  ملاحظات وتوجيهات الإدارة أثناء الشهر ({stats.managerNotes.length})
                </div>
                <div className="space-y-1.5">
                  {stats.managerNotes.map((note, idx) => (
                    <div
                      key={`mgr-${idx}`}
                      className="rounded-lg bg-[var(--surface)] border border-purple-500/20 p-2 text-xs text-[var(--text-primary)]"
                    >
                      <div className="flex items-center justify-between text-[10px] text-[var(--text-muted)] mb-1">
                        <span>بواسطة: {note.reviewer}</span>
                        <span>{note.date}</span>
                      </div>
                      <p className="font-medium">{note.text}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* شريط الإجراءات السفلي */}
        <div className="flex flex-wrap items-center justify-between gap-2.5 pt-3 border-t border-[var(--border)]">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleWhatsApp}
              disabled={stats.totalDays === 0}
              className="rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white px-3.5 py-2 text-xs font-black flex items-center gap-1.5 shadow-sm transition disabled:opacity-50"
            >
              <Share2 className="size-3.5" />
              <span>مشاركة واتساب كتقرير رسمي</span>
            </button>

            <button
              type="button"
              onClick={handleCopy}
              disabled={stats.totalDays === 0}
              className="rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-raised)] text-[var(--text-primary)] px-3 py-2 text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
            >
              {copied ? <CheckCircle2 className="size-3.5 text-emerald-500" /> : <Copy className="size-3.5" />}
              <span>{copied ? 'تم النسخ!' : 'نسخ التقرير'}</span>
            </button>

            <button
              type="button"
              onClick={handlePrint}
              disabled={stats.totalDays === 0}
              className="rounded-xl border border-[var(--border)] bg-[var(--surface)] hover:bg-[var(--surface-raised)] text-[var(--text-primary)] px-3 py-2 text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
            >
              <Printer className="size-3.5" />
              <span>طباعة / PDF</span>
            </button>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-[var(--border)] px-4 py-2 text-xs font-bold text-[var(--text-muted)] hover:bg-[var(--surface-raised)] transition"
          >
            إغلاق
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}
