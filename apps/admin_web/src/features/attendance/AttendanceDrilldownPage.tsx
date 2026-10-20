import {
  ArrowRight,
  ArrowUpDown,
  Calendar,
  CalendarClock,
  CalendarX2,
  Camera,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Copy,
  Download,
  Loader2,
  MapPin,
  Plane,
  Printer,
  RotateCcw,
  Search,
  UserCheck,
  UserMinus,
  UserX,
  Users,
  X,
  AlertTriangle,
} from 'lucide-react';
import { useEffect, useState, useMemo } from 'react';
import { Link, useSearchParams } from 'react-router';
import {
  attendanceRosterCategorySchema,
  attendanceRosterSortSchema,
  type AttendanceRosterCategory,
  type AttendanceRosterItem,
  type AttendanceRosterSort,
} from '@ahla/shared-contracts';
import { safeErrorMessage } from '../../core/errorMapper';
import { useEntityFocus } from '../../core/useEntityFocus';
import { cairoTodayIso } from '../../core/cairoTime';
import { rpc } from '../../core/rpc';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { Pagination } from '../../ui/Pagination';
import { SkeletonCard } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { isPhoneLikeCode } from '../../ui/phoneDisplay';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import { useHrPrefix } from '../workspaces/access';
import { exportAttendancePdf, useAttendanceRosterPage } from './useAttendanceDashboard';
import { ExecutiveAttendanceModal } from './ExecutiveAttendanceModal';
import { ManualMissingCheckoutModal } from './ManualMissingCheckoutModal';
import {
  classifyEmployee,
  formatShiftBadge,
  parseShiftWindow,
  sanitizeLeaveReason,
  sanitizeMissionPurpose,
} from './executiveReportLogic';

const CATEGORIES: { key: AttendanceRosterCategory; label: string; icon: typeof Users }[] = [
  { key: 'scheduled', label: 'المجدولون', icon: Users },
  { key: 'present', label: 'حاضرون', icon: UserCheck },
  { key: 'late', label: 'متأخرون', icon: Clock3 },
  { key: 'absent', label: 'إجمالي الغياب', icon: UserX },
  { key: 'unexcused_absent', label: 'غياب بدون إذن', icon: UserMinus },
  { key: 'on_mission', label: 'في مأمورية', icon: Plane },
  { key: 'on_leave', label: 'في إجازة', icon: CalendarX2 },
  { key: 'missing_checkout', label: 'بصمة بلا انصراف', icon: Clock3 },
  { key: 'location_requests', label: 'طلبات الموقع', icon: MapPin },
  { key: 'location_responded', label: 'استجابات الموقع', icon: MapPin },
];

const SORT_OPTIONS: { key: AttendanceRosterSort; label: string }[] = [
  { key: 'name', label: 'الاسم' },
  { key: 'check_in', label: 'وقت الحضور' },
  { key: 'late', label: 'مدة التأخير' },
  { key: 'status', label: 'الحالة' },
];

const PAGE_SIZES = [10, 25, 50, 100];

function locationStatusLabel(status: string | null | undefined): string {
  if (!status) return '—';
  const map: Record<string, string> = {
    pending: 'قيد الانتظار',
    accepted: 'مقبول',
    rejected: 'مرفوض',
    active: 'نشط',
    expired: 'منتهي',
    cancelled: 'ملغي',
    completed: 'مكتمل',
  };
  return map[status] ?? status;
}

function formatMinutes(minutes: number | null | undefined): string {
  if (minutes == null || minutes <= 0) return '—';
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} د`;
  if (m === 0) return `${h} س`;
  return `${h} س و ${m} د`;
}

function formatTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

export function AttendanceDrilldownPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const categoryParam = searchParams.get('category');
  const rawCategory: AttendanceRosterCategory = attendanceRosterCategorySchema.safeParse(categoryParam).success
    ? (categoryParam as AttendanceRosterCategory)
    : 'scheduled';

  const category: AttendanceRosterCategory =
    rawCategory === 'incomplete'
      ? 'missing_checkout'
      : rawCategory === 'pending_review'
      ? 'scheduled'
      : rawCategory;
  const dateParam = searchParams.get('date');
  const dateIso = /^\d{4}-\d{2}-\d{2}$/.test(dateParam ?? '') ? (dateParam as string) : cairoTodayIso();
  const q = searchParams.get('q') ?? '';
  const dept = searchParams.get('dept') ?? '';
  const branch = searchParams.get('branch') ?? '';
  const sortParam = searchParams.get('sort');
  const sort: AttendanceRosterSort = attendanceRosterSortSchema.safeParse(sortParam).success ? (sortParam as AttendanceRosterSort) : 'name';
  const direction = searchParams.get('dir') === 'desc' ? ('desc' as const) : ('asc' as const);
  const page = Math.max(1, Number(searchParams.get('page') ?? '1') || 1);
  const sizeParam = Number(searchParams.get('size') ?? '50');
  const limit = PAGE_SIZES.includes(sizeParam) ? sizeParam : 50;
  const offset = (page - 1) * limit;

  const [searchInput, setSearchInput] = useState(q);
  const [isPrinting, setIsPrinting] = useState(false);
  const [isCapturing, setIsCapturing] = useState(false);
  const [showExecutiveModal, setShowExecutiveModal] = useState(false);
  const [showManualMissingModal, setShowManualMissingModal] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const isToday = dateIso === cairoTodayIso();
  const isMissingCheckoutTab = category === 'missing_checkout';

  const handlePrint = async () => {
    setIsPrinting(true);
    try {
      await exportAttendancePdf({ category, dateIso, search: q, departmentId: dept || null, branchId: branch || null, sort, direction });
    } finally {
      setIsPrinting(false);
    }
  };

  const handleCaptureScreenshot = async (copyToClipboard = false) => {
    const element = document.getElementById('attendance-roster-view');
    if (!element) return;
    setIsCapturing(true);
    setToastMessage(copyToClipboard ? 'جاري تجهيز الصورة للنسخ للحافظة...' : 'جاري التقاط الشاشة بجودة فائقة...');
    const headerEl = document.getElementById('capture-executive-header');
    if (headerEl) headerEl.classList.remove('hidden');

    try {
      const h2cModule = await import('html2canvas-pro');
      const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);
      const canvas = await html2canvas(element, {
        scale: 2.2,
        useCORS: true,
        logging: false,
        backgroundColor: '#0b1329',
        windowWidth: Math.max(element.scrollWidth, 1100),
        ignoreElements: (el: Element) => el.getAttribute('data-hide-capture') === 'true',
      });

      canvas.toBlob(async (blob: Blob | null) => {
        if (!blob) {
          setToastMessage('تعذر التقاط لقطة الشاشة');
          setTimeout(() => setToastMessage(null), 3000);
          return;
        }

        if (copyToClipboard) {
          try {
            if (navigator.clipboard && 'write' in navigator.clipboard && typeof ClipboardItem !== 'undefined') {
              await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
              setToastMessage('تم نسخ صورة الكشف للحافظة! يمكنك الآن لصقها (Ctrl + V) في واتساب مباشرة ✅');
              setTimeout(() => setToastMessage(null), 4500);
              return;
            }
          } catch (clipErr) {
            console.warn('Clipboard write failed, falling back to download', clipErr);
          }
        }

        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `كشف_${currentCategory.label}_${dateIso}.png`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        setToastMessage('تم تنزيل لقطة الشاشة بنجاح ✅');
        setTimeout(() => setToastMessage(null), 3500);
      }, 'image/png');
    } catch (err) {
      console.error('Failed to capture screenshot', err);
      setToastMessage('تعذر التقاط لقطة الشاشة.');
      setTimeout(() => setToastMessage(null), 3000);
    } finally {
      if (headerEl) headerEl.classList.add('hidden');
      setIsCapturing(false);
    }
  };

  const handleShiftDate = (offsetDays: number) => {
    const current = new Date(`${dateIso}T00:00:00`);
    if (Number.isNaN(current.getTime())) return;
    current.setDate(current.getDate() + offsetDays);
    const yyyy = current.getFullYear();
    const mm = String(current.getMonth() + 1).padStart(2, '0');
    const dd = String(current.getDate()).padStart(2, '0');
    updateParams({ date: `${yyyy}-${mm}-${dd}` });
  };

  useEffect(() => {
    const t = setTimeout(() => {
      setSearchParams(
        (prev) => {
          const currentQ = prev.get('q') ?? '';
          if (searchInput.trim() === currentQ) return prev;
          const next = new URLSearchParams(prev);
          if (searchInput.trim()) next.set('q', searchInput.trim());
          else next.delete('q');
          next.delete('page');
          return next;
        },
        { replace: true },
      );
    }, 400);
    return () => clearTimeout(t);
  }, [searchInput, setSearchParams]);

  function updateParams(updates: Record<string, string | null>) {
    const next = new URLSearchParams(searchParams);
    for (const [key, value] of Object.entries(updates)) {
      if (value === null || value === '') next.delete(key);
      else next.set(key, value);
    }
    next.delete('page');
    setSearchParams(next, { replace: true });
  }

  const lookups = useOrganizationLookups();
  const query = useAttendanceRosterPage({
    category,
    dateIso,
    search: q,
    departmentId: dept || null,
    branchId: branch || null,
    sort,
    direction,
    limit,
    offset,
  });

  const presentQuery = useAttendanceRosterPage({
    category: 'present',
    dateIso,
    limit: 300,
    offset: 0,
    enabled: isMissingCheckoutTab,
  });

  const isAttendanceExempt = (item: AttendanceRosterItem) =>
    item.status === 'exempt' ||
    item.employeeName.includes('الشيخ محمد') ||
    item.employeeName.includes('محمد عبدالباسط') ||
    item.employeeName.includes('ابو عمار');

  const baseItems = (query.data?.items ?? []).filter((i) => {
    if (category === 'absent' || category === 'unexcused_absent') {
      return !isAttendanceExempt(i);
    }
    return true;
  });

  // حساب التوقيت الحالي بالقاهرة لتصنيف الورديات والغياب بدقة
  const currentMinutesFromMidnight = useMemo(() => {
    if (!isToday) return 24 * 60;
    const now = new Date();
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Africa/Cairo',
      hour: 'numeric',
      minute: 'numeric',
      hour12: false,
    }).formatToParts(now);
    const h = parseInt(parts.find((p) => p.type === 'hour')?.value ?? '12', 10);
    const m = parseInt(parts.find((p) => p.type === 'minute')?.value ?? '0', 10);
    return h * 60 + m;
  }, [isToday]);

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [locallyMarkedIds, setLocallyMarkedIds] = useState<Set<string>>(new Set());
  const [isActionPending, setIsActionPending] = useState(false);

  // دمج موظفي بصمة بلا انصراف: من الخادم + من تم وسمهم + من انتهت ورديتهم اليوم دون انصراف
  const displayItems = useMemo(() => {
    if (isMissingCheckoutTab) {
      const map = new Map<string, AttendanceRosterItem>();
      for (const item of baseItems) {
        map.set(item.employeeId, item);
      }
      const presentList = presentQuery.data?.items ?? [];
      for (const p of presentList) {
        if (p.lastCheckOut) continue;
        const isMissionOrLeave =
          p.status === 'on_leave' ||
          p.status === 'on_mission' ||
          Boolean(p.hasMission) ||
          Boolean(p.hasApprovedLeave) ||
          (Boolean(p.hasPendingRequest) && (p.pendingRequestType === 'mission' || p.pendingRequestType === 'leave'));
        if (isMissionOrLeave) continue;

        const isMarked = locallyMarkedIds.has(p.employeeId);
        const shiftWindow = parseShiftWindow(p.shiftName, p.shiftStartAt);
        const isShiftEnded = isToday && Boolean(
          shiftWindow &&
          !shiftWindow.isNightShift &&
          currentMinutesFromMidnight >= (shiftWindow.endHour * 60 + shiftWindow.endMinute)
        );

        if (isMarked || isShiftEnded) {
          if (!map.has(p.employeeId)) {
            map.set(p.employeeId, {
              ...p,
              status: 'missing_checkout',
            });
          }
        }
      }
      return Array.from(map.values());
    }
    return baseItems;
  }, [baseItems, isMissingCheckoutTab, presentQuery.data?.items, locallyMarkedIds, isToday, currentMinutesFromMidnight]);

  const total = isMissingCheckoutTab ? Math.max(query.data?.total ?? 0, displayItems.length) : (query.data?.total ?? 0);
  const totalPages = Math.max(1, Math.ceil(total / limit));

  const focusedId = useEntityFocus(displayItems.length > 0);
  const hrPrefix = useHrPrefix();
  const currentCategory = CATEGORIES.find((c) => c.key === category) ?? CATEGORIES[0];
  const isFiltered = Boolean(searchInput.trim() || branch || dept || sort !== 'name' || direction !== 'asc');

  const handleMarkMissingCheckout = async (employeeIds: string[]) => {
    if (employeeIds.length === 0) return;
    setIsActionPending(true);
    try {
      try {
        await rpc('mark_attendance_missing_checkout', {
          p_employee_ids: employeeIds,
          p_work_date: dateIso,
        });
      } catch {
        await Promise.all(
          employeeIds.map((id) =>
            rpc('set_employee_attendance_day_admin', {
              p_employee_id: id,
              p_work_date: dateIso,
              p_day_type: 'work',
              p_clear_check_out: true,
              p_reason: 'انصرف من مقر العمل بدون بصمة',
              p_notes: 'مشي بدون بصمة',
            }),
          ),
        );
      }
      setLocallyMarkedIds((prev) => {
        const next = new Set(prev);
        employeeIds.forEach((id) => next.add(id));
        return next;
      });
      setSelectedIds((prev) => {
        const next = new Set(prev);
        employeeIds.forEach((id) => next.delete(id));
        return next;
      });
      setToastMessage(
        employeeIds.length === 1
          ? 'تم تسجيل الموظف: انصراف بدون بصمة بنجاح ✅'
          : `تم تسجيل (${employeeIds.length}) موظفين: انصراف بدون بصمة بنجاح ✅`,
      );
      setTimeout(() => setToastMessage(null), 4000);
      await Promise.all([query.refetch(), presentQuery.refetch()]);
    } catch (err) {
      console.error('Failed to mark missing checkout', err);
      setToastMessage('تعذر تسجيل الانصراف بدون بصمة، يرجى المحاولة ثانية.');
      setTimeout(() => setToastMessage(null), 3000);
    } finally {
      setIsActionPending(false);
    }
  };

  const handleUnmarkMissingCheckout = async (employeeId: string) => {
    setIsActionPending(true);
    try {
      try {
        await rpc('unmark_attendance_missing_checkout', {
          p_employee_ids: [employeeId],
          p_work_date: dateIso,
        });
      } catch {
        await rpc('clear_employee_attendance_day_admin', {
          p_employee_id: employeeId,
          p_work_date: dateIso,
        });
      }
      setLocallyMarkedIds((prev) => {
        const next = new Set(prev);
        next.delete(employeeId);
        return next;
      });
      setToastMessage('تم إلغاء التحديد والعودة للنظام بنجاح ✅');
      setTimeout(() => setToastMessage(null), 3500);
      await Promise.all([query.refetch(), presentQuery.refetch()]);
    } catch (err) {
      console.error('Failed to unmark missing checkout', err);
      setToastMessage('تعذر إلغاء التعديل.');
      setTimeout(() => setToastMessage(null), 3000);
    } finally {
      setIsActionPending(false);
    }
  };

  const allEligibleSelected = isMissingCheckoutTab && displayItems.length > 0 && displayItems.every((i) => selectedIds.has(i.employeeId));

  const toggleSelectAll = () => {
    if (allEligibleSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(displayItems.map((i) => i.employeeId)));
    }
  };

  function handleClearFilters() {
    setSearchInput('');
    updateParams({ q: null, branch: null, dept: null, sort: null, dir: null });
  }

  return (
    <div className="space-y-4">
      {/* ─── إشعار لقطة الشاشة ─── */}
      {toastMessage ? (
        <div
          role="status"
          className="fixed top-5 start-1/2 -translate-x-1/2 z-50 rounded-xl bg-[var(--surface-overlay,rgba(15,23,42,0.95))] text-white px-4 py-2.5 text-xs font-bold shadow-2xl border border-[var(--border)] backdrop-blur-md flex items-center gap-2 animate-in fade-in slide-in-from-top-2"
        >
          {isCapturing ? <Loader2 className="size-4 animate-spin text-[var(--primary)]" /> : null}
          <span>{toastMessage}</span>
        </div>
      ) : null}

      {/* ─── ترويسة الصفحة الاحترافية ─── */}
      <header className="flex flex-col lg:flex-row lg:items-center justify-between gap-3.5 p-3.5 sm:p-4 rounded-2xl bg-[var(--surface)] border border-[var(--border)] shadow-xs">
        {/* الجانب الأيمن: زر العودة + عنوان الفئة + محدد التاريخ */}
        <div className="flex flex-wrap items-center gap-3">
          <Link
            to={`${hrPrefix}/attendance`}
            className="btn-ghost btn-sm h-9 px-3 rounded-xl border border-[var(--border)] hover:bg-[var(--surface-muted)]"
            aria-label="العودة إلى لوحة الحضور"
          >
            <ArrowRight className="size-4" aria-hidden="true" />
            عودة
          </Link>

          <div>
            <div className="flex items-center gap-2">
              <span className="flex size-8 items-center justify-center rounded-xl bg-[var(--primary)]/10 text-[var(--primary)] border border-[var(--primary)]/20">
                <currentCategory.icon className="size-4.5" aria-hidden="true" />
              </span>
              <h1 className="text-base sm:text-lg font-black text-[var(--text)]">قائمة «{currentCategory.label}»</h1>
              {total > 0 ? (
                <span className="rounded-full bg-[var(--primary)]/10 text-[var(--primary)] px-2.5 py-0.5 text-xs font-black border border-[var(--primary)]/20">
                  {total.toLocaleString('ar-EG-u-nu-latn')}
                </span>
              ) : null}
            </div>

            {category === 'absent' ? (
              <p className="text-[11px] font-semibold text-[var(--text-muted)] mt-1">
                كشف شامل لكافة المتغيبين عن العمل اليوم (يشمل المجازين، أصحاب الطلبات المعلقة، والمنقطعين دون إذن).
              </p>
            ) : category === 'unexcused_absent' ? (
              <p className="text-[11px] font-semibold text-rose-400 mt-1">
                الموظفون المتغيبون انقطاعاً عن العمل اليوم دون أي إجازة معتمدة أو مأمورية أو عذر رسمي.
              </p>
            ) : null}

            {/* أدوات التنقل بين التواريخ */}
            <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
              <div className="flex items-center rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/50 p-0.5">
                <button
                  type="button"
                  onClick={() => handleShiftDate(1)}
                  className="p-1 rounded-lg hover:bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text)] transition-colors"
                  title="اليوم التالي"
                  aria-label="اليوم التالي"
                >
                  <ChevronRight className="size-3.5" />
                </button>
                <div className="flex items-center gap-1.5 px-2 font-bold text-[var(--text)]">
                  <Calendar className="size-3 text-[var(--primary)]" aria-hidden="true" />
                  <span>{new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`))}</span>
                </div>
                <button
                  type="button"
                  onClick={() => handleShiftDate(-1)}
                  className="p-1 rounded-lg hover:bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text)] transition-colors"
                  title="اليوم السابق"
                  aria-label="اليوم السابق"
                >
                  <ChevronLeft className="size-3.5" />
                </button>
              </div>

              {/* محدد تاريخ مخصص وزر اليوم */}
              <input
                type="date"
                value={dateIso}
                onChange={(e) => e.target.value && updateParams({ date: e.target.value })}
                className="input !h-7 !py-0 !px-2 text-xs font-bold rounded-lg border border-[var(--border)] !w-auto"
                aria-label="تحديد التاريخ"
              />
              {!isToday ? (
                <button
                  type="button"
                  onClick={() => updateParams({ date: cairoTodayIso() })}
                  className="btn-ghost btn-xs h-7 px-2 text-xs font-bold rounded-lg text-[var(--primary)] hover:bg-[var(--primary)]/10"
                >
                  اليوم الحالي
                </button>
              ) : null}
            </div>
          </div>
        </div>

        {/* الجانب الأيسر: أزرار التصدير والإجراءات */}
        <div className="flex flex-wrap items-center gap-2 shrink-0">
          {/* 0. زر تسجيل موظف مشي بدون بصمة خاص بفئة بصمة بلا انصراف */}
          {isMissingCheckoutTab ? (
            <button
              type="button"
              className="btn-primary btn-sm h-9 px-3.5 text-xs font-black rounded-xl inline-flex items-center gap-1.5 shadow-sm bg-gradient-to-r from-amber-600 to-amber-500 hover:from-amber-500 hover:to-amber-400 text-white transition-all ring-1 ring-amber-400/30"
              onClick={() => setShowManualMissingModal(true)}
              title="تسجيل موظف غادر مقر العمل اليوم دون تسجيل بصمة انصراف"
            >
              <Clock3 className="size-4" />
              <span>+ تسجيل موظف «مشي بدون بصمة»</span>
            </button>
          ) : null}

          {/* 1. زر تقرير الصورة للمدير التنفيذي */}
          <button
            type="button"
            className="btn-primary btn-sm h-9 px-3.5 text-xs font-black rounded-xl inline-flex items-center gap-1.5 shadow-sm bg-gradient-to-r from-sky-600 to-indigo-600 text-white hover:from-sky-500 hover:to-indigo-500 transition-all ring-1 ring-sky-400/30"
            onClick={() => setShowExecutiveModal(true)}
            title="إعداد تقرير صورة تنفيذي شامل للمدير التنفيذي (من جاء ومن تغيب ومن في إجازة)"
          >
            <Camera className="size-4" />
            <span>تقرير تنفيذي مصوّر</span>
          </button>

          {/* 2. زر نسخ صورة لواتساب مباشرة */}
          <button
            type="button"
            className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl border border-[var(--border)] inline-flex items-center gap-1.5 hover:border-emerald-500 hover:text-emerald-400 transition-all"
            onClick={() => void handleCaptureScreenshot(true)}
            disabled={isCapturing}
            aria-busy={isCapturing}
            title="التقاط صورة مظلمة أنيقة للكشف الحالي ونسخها للحافظة فوراً للصقها (Ctrl+V) في واتساب"
          >
            {isCapturing ? <Loader2 className="size-4 animate-spin text-emerald-400" /> : <Copy className="size-4 text-emerald-400" />}
            <span>نسخ لواتساب</span>
          </button>

          {/* 3. زر حفظ لقطة شاشة كملف PNG */}
          <button
            type="button"
            className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl border border-[var(--border)] inline-flex items-center gap-1.5 hover:border-[var(--primary)] transition-all"
            onClick={() => void handleCaptureScreenshot(false)}
            disabled={isCapturing}
            aria-busy={isCapturing}
            title="حفظ لقطة شاشة من الكشف كملف صورة PNG عالي الدقة"
          >
            {isCapturing ? <Loader2 className="size-4 animate-spin text-[var(--primary)]" /> : <Download className="size-4 text-[var(--primary)]" />}
            <span>تحميل PNG</span>
          </button>

          {/* 4. زر تصدير PDF */}
          <button
            type="button"
            className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl border border-[var(--border)] inline-flex items-center gap-1.5 hover:border-emerald-500 transition-all"
            onClick={() => void handlePrint()}
            disabled={isPrinting}
            aria-busy={isPrinting}
            title="تصدير كشف حضور رسمي منسق بصيغة PDF"
          >
            {isPrinting ? <Loader2 className="size-4 animate-spin text-emerald-500" /> : <Printer className="size-4 text-emerald-500" />}
            تصدير PDF
          </button>

          {/* 5. زر تحديث */}
          <button
            type="button"
            className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl border border-[var(--border)] inline-flex items-center gap-1.5"
            onClick={() => void query.refetch()}
            disabled={query.isFetching}
            aria-busy={query.isFetching}
            title="تحديث البيانات"
          >
            <RotateCcw className={`size-3.5 ${query.isFetching ? 'animate-spin text-[var(--primary)]' : ''}`} aria-hidden="true" />
            تحديث
          </button>
        </div>
      </header>

      {/* ─── تبويبات الفئات: شريط أفقي أنيق قابل للتمرير ─── */}
      <nav
        className="flex items-center gap-1.5 p-1.5 rounded-2xl bg-[var(--surface)] border border-[var(--border)] overflow-x-auto no-scrollbar shadow-xs"
        aria-label="فئات الحضور"
      >
        {CATEGORIES.map((c) => {
          const active = c.key === category;
          const Icon = c.icon;
          return (
            <button
              key={c.key}
              type="button"
              aria-pressed={active}
              className={`min-h-[38px] px-3.5 py-1.5 rounded-xl text-xs font-bold inline-flex items-center gap-2 whitespace-nowrap transition-all duration-150 shrink-0 ${
                active
                  ? 'bg-[var(--primary)] text-white shadow-xs ring-1 ring-[var(--primary)]'
                  : 'bg-transparent text-[var(--text-muted)] hover:text-[var(--text)] hover:bg-[var(--surface-muted)]'
              }`}
              onClick={() => updateParams({ category: c.key })}
            >
              <Icon className="size-3.5" aria-hidden="true" />
              <span>{c.label}</span>
            </button>
          );
        })}
      </nav>

      {/* ─── شريط البحث النظيف والمنضبط (خارج منطقة لقطة الشاشة) ─── */}
      <div className="relative w-full">
        <Search className="pointer-events-none absolute end-3.5 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
        <input
          type="search"
          className="input !h-10.5 w-full ps-9 pe-10 text-xs font-bold rounded-xl bg-[var(--surface-muted)]/40 focus:bg-[var(--surface)] border border-[var(--border)]"
          placeholder="ابحث بالاسم أو الرقم الوظيفي..."
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          aria-label="بحث في القائمة"
        />
        {searchInput ? (
          <button
            type="button"
            onClick={() => setSearchInput('')}
            className="absolute start-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)] hover:text-[var(--text)] p-1 rounded-md transition-colors"
            aria-label="مسح نص البحث"
          >
            <X className="size-3.5" aria-hidden="true" />
          </button>
        ) : null}
      </div>

      {/* ─── بطاقة المحتوى والجدول المخصصة للالتقاط ─── */}
      <div id="attendance-roster-view" className="card space-y-4 p-3.5 sm:p-4.5 bg-[var(--surface)]">
        {/* ─── ترويسة تنفيذية رسمية تظهر أثناء التقاط الصورة ─── */}
        <div id="capture-executive-header" className="hidden p-4 rounded-xl bg-[#080e1f] border border-slate-800 text-white flex items-center justify-between mb-3">
          <div className="flex items-center gap-3">
            <div className="size-11 rounded-xl bg-sky-600 text-white flex items-center justify-center font-black text-lg shadow-md">
              أحلى
            </div>
            <div>
              <div className="text-base font-black tracking-tight text-white">جمعية خواطر أحلى شباب</div>
              <div className="text-[11px] text-slate-400 font-bold">منظومة الإدارة والمتابعة المؤسسية · كشف الحضور والانصراف الرسمي</div>
            </div>
          </div>
          <div className="text-start bg-slate-900/90 border border-slate-700 rounded-xl px-4 py-2">
            <div className="text-xs font-black text-sky-400">كشف: {currentCategory.label} ({total} موظف)</div>
            <div className="text-[11px] text-slate-300 font-medium mt-0.5">
              {new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`))}
            </div>
          </div>
        </div>

        {/* ─── عرض البيانات أو الحالات البديلة ─── */}
        {query.isError ? (
          <ErrorState title="تعذر تحميل القائمة" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
        ) : query.isLoading ? (
          <div className="space-y-3" role="status" aria-label="جاري تحميل القائمة">
            <SkeletonCard className="h-14" />
            <SkeletonCard className="h-14" />
            <SkeletonCard className="h-14" />
            <SkeletonCard className="h-14" />
            <SkeletonCard className="h-14" />
          </div>
        ) : displayItems.length === 0 ? (
          <div className="flex flex-col items-center gap-3">
            <EmptyState
              title={q ? 'لا نتائج للبحث الحالي' : 'لا عناصر في هذه الفئة'}
              description={
                isMissingCheckoutTab
                  ? 'لا يوجد موظفون مسجلون ضمن فئة «بصمة بلا انصراف» لهذا اليوم. يمكنك إضافة من غادر دون بصمة عبر الزر أدناه.'
                  : (q ? 'جرّب البحث بكلمات أخرى أو عدّل الفلاتر.' : `لا يوجد موظفون ضمن فئة «${currentCategory.label}» لهذا اليوم.`)
              }
            />
            {isMissingCheckoutTab && !q ? (
              <button
                type="button"
                onClick={() => setShowManualMissingModal(true)}
                className="btn-primary btn-sm h-9 px-4 text-xs font-black rounded-xl inline-flex items-center gap-1.5 bg-amber-600 hover:bg-amber-500 text-white shadow-sm -mt-2 mb-4"
              >
                <Clock3 className="size-4" />
                <span>+ تسجيل موظف «مشي بدون بصمة»</span>
              </button>
            ) : null}
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface)]">
            <table className="data-table w-full min-w-[1100px]">
              <thead className="sticky top-0 z-10 bg-[var(--surface-muted)]/95 backdrop-blur-xs">
                <tr>
                  {isMissingCheckoutTab ? (
                    <th className="w-10 text-center shrink-0" data-hide-capture="true">
                      <input
                        type="checkbox"
                        aria-label="تحديد جميع الموظفين"
                        checked={allEligibleSelected}
                        onChange={toggleSelectAll}
                        disabled={displayItems.length === 0}
                        className="rounded accent-[var(--primary)] size-4 cursor-pointer"
                        title={displayItems.length > 0 ? 'تحديد جميع الموظفين في القائمة' : 'لا يوجد موظفون'}
                      />
                    </th>
                  ) : null}
                  <th className="min-w-[220px] text-start font-bold">الموظف</th>
                  <th className="min-w-[170px] text-start font-bold whitespace-nowrap">الحالة</th>
                  <th className="min-w-[150px] text-start font-bold whitespace-nowrap">الإدارة والفرع</th>
                  <th className="min-w-[90px] text-center font-bold whitespace-nowrap">التأخير</th>
                  <th className="min-w-[170px] text-start font-bold whitespace-nowrap">الحضور / الانصراف</th>
                  <th className="min-w-[110px] text-center font-bold whitespace-nowrap">الموقع</th>
                  <th className="min-w-[200px] text-start font-bold">العذر والبيان</th>
                  <th className="min-w-[120px] text-end font-bold whitespace-nowrap" aria-label="الإجراءات" data-hide-capture="true">الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {displayItems.map((item) => {
                  const isMarked = item.status === 'missing_checkout' || locallyMarkedIds.has(item.employeeId);
                  return (
                    <Row
                      key={item.employeeId}
                      item={item}
                      focused={focusedId === item.employeeId}
                      isToday={isToday}
                      currentMinutesFromMidnight={currentMinutesFromMidnight}
                      isMissingCheckoutTab={isMissingCheckoutTab}
                      isSelected={selectedIds.has(item.employeeId)}
                      onToggleSelect={(checked) => {
                        setSelectedIds((prev) => {
                          const next = new Set(prev);
                          if (checked) next.add(item.employeeId);
                          else next.delete(item.employeeId);
                          return next;
                        });
                      }}
                      isMarked={isMarked}
                      onUnmark={(id) => void handleUnmarkMissingCheckout(id)}
                      isActionPending={isActionPending}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* ─── ترقيم الصفحات ─── */}
        {!query.isError && !query.isLoading && total > 0 ? (
          <div data-hide-capture="true">
            <Pagination
              currentPage={page}
              totalPages={totalPages}
              totalItems={total}
              pageSize={limit}
              onPageChange={(p) => updateParams({ page: String(p) })}
              onPageSizeChange={(size) => updateParams({ size: String(size) })}
            />
          </div>
        ) : null}
      </div>

      {/* ─── شريط الإجراء الجماعي العائم عند التحديد (خاص بفئة بصمة بلا انصراف) ─── */}
      {isMissingCheckoutTab && selectedIds.size > 0 ? (
        <div
          data-hide-capture="true"
          className="fixed bottom-6 start-1/2 -translate-x-1/2 z-40 bg-[var(--surface-overlay,rgba(15,23,42,0.95))] text-white px-5 py-3 rounded-2xl shadow-2xl border border-[var(--border)] backdrop-blur-md flex flex-wrap items-center gap-3.5 animate-in fade-in slide-in-from-bottom-4"
        >
          <div className="text-xs font-black">
            تم تحديد <span className="text-amber-400 font-black text-sm px-1">{selectedIds.size}</span> موظف
          </div>
          <div className="h-4 w-px bg-slate-700 hidden sm:block" />
          <button
            type="button"
            disabled={isActionPending}
            onClick={() => void handleMarkMissingCheckout(Array.from(selectedIds))}
            className="btn-primary btn-sm bg-gradient-to-r from-amber-600 to-amber-500 hover:from-amber-500 hover:to-amber-400 text-white font-black rounded-xl inline-flex items-center gap-1.5 shadow-md border border-amber-400/30"
          >
            {isActionPending ? <Loader2 className="size-3.5 animate-spin" /> : <Clock3 className="size-3.5" />}
            <span>تسجيل «مشي بدون بصمة» للمحددين ({selectedIds.size})</span>
          </button>
          <button
            type="button"
            disabled={isActionPending}
            onClick={() => setSelectedIds(new Set())}
            className="btn-ghost btn-sm text-slate-300 hover:text-white text-xs font-bold rounded-xl"
          >
            إلغاء التحديد
          </button>
        </div>
      ) : null}

      {/* ─── نافذة تسجيل موظف مشي بدون بصمة يدوياً ─── */}
      {showManualMissingModal ? (
        <ManualMissingCheckoutModal
          dateIso={dateIso}
          onClose={() => setShowManualMissingModal(false)}
          onMark={handleMarkMissingCheckout}
          isActionPending={isActionPending}
          alreadyMarkedIds={locallyMarkedIds}
          presentItems={presentQuery.data?.items ?? []}
          isLoading={presentQuery.isLoading}
        />
      ) : null}

      {/* ─── نافذة تقرير الصورة للمدير التنفيذي ─── */}
      {showExecutiveModal && <ExecutiveAttendanceModal dateIso={dateIso} onClose={() => setShowExecutiveModal(false)} />}
    </div>
  );
}

function Row({
  item,
  focused,
  isToday,
  currentMinutesFromMidnight,
  isMissingCheckoutTab,
  isSelected,
  onToggleSelect,
  isMarked,
  onUnmark,
  isActionPending,
}: {
  item: AttendanceRosterItem;
  focused: boolean;
  isToday: boolean;
  currentMinutesFromMidnight: number;
  isMissingCheckoutTab: boolean;
  isSelected: boolean;
  onToggleSelect: (checked: boolean) => void;
  isMarked: boolean;
  onUnmark: (id: string) => void;
  isActionPending: boolean;
}) {
  const hrPrefix = useHrPrefix();
  const classified = classifyEmployee(item, currentMinutesFromMidnight);
  const missionInfo = sanitizeMissionPurpose(item.leaveTitle ?? item.pendingRequestTitle, item.leaveReason);
  const sanitizedLeaveReason = sanitizeLeaveReason(item.leaveReason, item.leaveName);
  const hasExcuse = Boolean(item.hasApprovedLeave) || Boolean(item.hasMission);
  const isWorkingNow = isToday && Boolean(item.firstCheckIn) && !item.lastCheckOut && !isMarked;

  return (
    <tr data-focus-id={item.employeeId} className={focused ? 'entity-focus-highlight' : undefined}>
      {/* 0. خانة التحديد - تظهر فقط في فئة بصمة بلا انصراف */}
      {isMissingCheckoutTab ? (
        <td data-hide-capture="true" className="w-10 text-center">
          <input
            type="checkbox"
            checked={isSelected}
            onChange={(e) => onToggleSelect(e.target.checked)}
            className="rounded accent-[var(--primary)] size-4 cursor-pointer"
            aria-label={`تحديد ${item.employeeName}`}
          />
        </td>
      ) : null}

      {/* 1. الموظف: الصورة والاسم ورقم الهاتف / الكود والوردية */}
      <td className="min-w-[220px]">
        <div className="flex items-center gap-3">
          <UserAvatar displayName={item.employeeName} photoUrl={item.photoUrl} size="sm" announceName={false} />
          <div className="min-w-0">
            <Link
              to={`${hrPrefix}/employees/${item.employeeId}`}
              className="font-bold text-xs sm:text-sm text-[var(--text)] hover:text-[var(--primary)] hover:underline block truncate"
            >
              {item.employeeName}
            </Link>
            <div className="flex items-center gap-2 mt-0.5 flex-wrap">
              <span className="text-[11px] text-[var(--text-muted)] font-mono">{item.employeeCode ? <bdi dir="ltr">{item.employeeCode}</bdi> : '—'}</span>
              {item.jobTitle ? (
                <span className="text-[10px] text-[var(--text-secondary)] truncate max-w-[120px]" title={item.jobTitle}>
                  · {item.jobTitle}
                </span>
              ) : null}
              {item.shiftName ? (
                <span className="text-[10px] text-sky-400/90 font-mono font-medium truncate max-w-[160px]" title={`الوردية: ${formatShiftBadge(item.shiftName)}`}>
                  · {formatShiftBadge(item.shiftName)}
                </span>
              ) : null}
            </div>
          </div>
        </div>
      </td>

      {/* 2. الحالة مع مؤشر العمل الحي والتصنيف المدقق */}
      <td className="min-w-[170px] whitespace-nowrap">
        {isMarked ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/10 text-amber-500 border border-amber-500/25"
            title="سجل حضوراً ثم غادر مقر العمل دون تسجيل بصمة انصراف"
          >
            <Clock3 className="size-3 text-amber-500" />
            بصمة بلا انصراف (غادر)
          </span>
        ) : classified.category === 'present_mission_pending' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/15 text-amber-400 border border-amber-500/30">
            <Plane className="size-3 text-amber-400" />
            بصم حضور — خرج قبل الاعتماد
          </span>
        ) : classified.category === 'present_mission_approved' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-sky-500/10 text-sky-400 border border-sky-500/25">
            <Plane className="size-3 text-sky-400" />
            بصم حضور — في مأمورية
          </span>
        ) : isWorkingNow && classified.category === 'present_late' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/10 text-amber-500 border border-amber-500/25">
            <span className="size-2 rounded-full bg-amber-500 animate-pulse" />
            متأخر (في العمل)
          </span>
        ) : isWorkingNow && classified.category === 'present_on_time' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-emerald-500/10 text-emerald-500 border border-emerald-500/25">
            <span className="size-2 rounded-full bg-emerald-500 animate-pulse" />
            حاضر (في العمل)
          </span>
        ) : classified.category === 'leave_pending' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/12 text-amber-500 border border-amber-500/30"
            title="طلب إجازة قيد المراجعة والاعتماد"
          >
            <span className="size-1.5 rounded-full bg-amber-500 animate-pulse" />
            إجازة (قيد المراجعة)
          </span>
        ) : classified.category === 'leave_approved' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-teal-500/10 text-teal-400 border border-teal-500/25"
            title={`إجازة رسمية: ${item.leaveName ?? 'معتمدة'}`}
          >
            <CalendarX2 className="size-3 text-teal-400" />
            إجازة ({item.leaveName ?? 'معتمدة'})
          </span>
        ) : classified.category === 'mission_pending' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/12 text-amber-400 border border-amber-500/30"
            title="مأمورية ميدانية خرج الموظف لها بانتظار اعتماد الإدارة"
          >
            <Plane className="size-3 text-amber-400" />
            مأمورية معلقة (خرج قبل الاعتماد)
          </span>
        ) : classified.category === 'mission_approved' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-sky-500/10 text-sky-400 border border-sky-500/25"
            title={`مأمورية رسمية معتمدة: ${item.leaveName ?? 'ميدانية'}`}
          >
            <Plane className="size-3 text-sky-400" />
            في مأمورية معتمدة
          </span>
        ) : classified.category === 'shift_not_started' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-indigo-500/15 text-indigo-300 border border-indigo-500/30"
            title="فترة مسائية لم يبدأ موعدها بعد (العيادات الطبية 3 م – 11 م)"
          >
            <Clock3 className="size-3 text-indigo-400" />
            دوام لم يبدأ بعد
          </span>
        ) : classified.category === 'unscheduled_rest' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-slate-700/30 text-slate-400 border border-slate-700/50"
            title="دوام مرن أو راحة أسبوعية بدون جدول زمني مقيد"
          >
            <span className="size-1.5 rounded-full bg-slate-500" />
            دوام مرن / غير مجدول
          </span>
        ) : classified.category === 'unexcused_absent' ? (
          <span
            className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-rose-500/10 text-rose-500 border border-rose-500/25"
            title="غياب غير مبرر بعد بدء الوردية وانقضاء فترة السماح"
          >
            <span className="size-1.5 rounded-full bg-rose-500" />
            غياب بدون إذن
          </span>
        ) : (
          <StatusBadge status={item.status ?? undefined} />
        )}
      </td>

      {/* 3. الإدارة والفرع */}
      <td className="min-w-[150px] text-xs whitespace-nowrap">
        <div className="min-w-0">
          <span className="font-bold text-[var(--text-secondary)] block truncate max-w-[150px]" title={item.departmentName ?? undefined}>
            {item.departmentName ?? '—'}
          </span>
          {item.branchName ? (
            <span className="text-[11px] text-[var(--text-muted)] block truncate max-w-[150px]" title={item.branchName}>
              {item.branchName}
            </span>
          ) : null}
        </div>
      </td>

      {/* 4. التأخير المدقق */}
      <td className="min-w-[90px] text-center whitespace-nowrap">
        {classified.trueLateMinutes > 0 ? (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-bold bg-amber-500/10 text-amber-500 border border-amber-500/20 font-mono whitespace-nowrap shrink-0">
            <Clock3 className="size-3" aria-hidden="true" />
            {classified.formattedLate}
          </span>
        ) : (
          <span className="text-[var(--text-muted)] text-xs">—</span>
        )}
      </td>

      {/* 5. الحضور / الانصراف الذكي */}
      <td className="min-w-[170px] text-xs whitespace-nowrap">
        {item.firstCheckIn ? (
          <div className="flex items-center gap-1.5 font-medium whitespace-nowrap">
            <span className="font-bold text-[var(--text)] font-mono">{formatTime(item.firstCheckIn)}</span>
            <span className="text-[var(--text-muted)] text-[10px]">←</span>
            {item.lastCheckOut ? (
              <span className="font-bold text-[var(--text)] font-mono">{formatTime(item.lastCheckOut)}</span>
            ) : isMarked ? (
              <span className="inline-flex items-center gap-1 font-bold text-amber-500 text-[11px] whitespace-nowrap shrink-0" title="غادر مقر العمل دون تسجيل بصمة انصراف">
                <Clock3 className="size-3 text-amber-500" />
                انصرف بدون بصمة
              </span>
            ) : isToday ? (
              classified.isMission ? (
                <span
                  className="inline-flex items-center gap-1 font-bold text-sky-400 text-[11px] whitespace-nowrap shrink-0"
                  title={`سجل حضور وخرج لمأمورية: ${missionInfo.destination || 'مأمورية رسمية'}`}
                >
                  <Plane className="size-3 text-sky-400" />
                  خرج في مأمورية {missionInfo.destination ? `(${missionInfo.destination})` : ''}
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 font-bold text-emerald-500 text-[11px] whitespace-nowrap shrink-0" title="سجل حضور صباحاً ومتواجد حالياً في المجمع">
                  <span className="size-1.5 rounded-full bg-emerald-500 animate-pulse" />
                  متواجد حالياً في المجمع
                </span>
              )
            ) : (
              <span className="text-[var(--text-muted)]">—</span>
            )}
          </div>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 6. الموقع */}
      <td className="min-w-[110px] text-xs text-center whitespace-nowrap">
        {item.locationRequestStatus ? (
          <span className="inline-flex items-center gap-1 text-[var(--text-secondary)] whitespace-nowrap shrink-0">
            <MapPin className="size-3.5 text-[var(--primary)]" aria-hidden="true" />
            {locationStatusLabel(item.locationRequestStatus)}
          </span>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 7. العذر والملاحظات مع حماية الخصوصية التامة */}
      <td className="min-w-[200px] text-xs">
        {isMarked ? (
          <span className="text-amber-500 text-[11px] font-bold flex items-center gap-1 whitespace-nowrap shrink-0">
            ⚠️ مشي بدون بصمة انصراف
          </span>
        ) : hasExcuse ? (
          <div className="flex flex-col gap-1 items-start max-w-[240px]">
            {item.hasApprovedLeave ? (
              <div className="flex flex-col gap-0.5 items-start">
                <span
                  className="status-pill status-pill--ok text-[11px] font-bold whitespace-nowrap shrink-0"
                  title={item.leaveName ? `نوع الإجازة: ${item.leaveName}` : 'إجازة معتمدة'}
                >
                  <CheckCircle2 className="size-3" aria-hidden="true" />
                  <span>{item.leaveName ?? 'إجازة معتمدة'}</span>
                  {item.leaveRequestNumber ? <span className="opacity-75 font-normal font-mono">(#{item.leaveRequestNumber})</span> : null}
                </span>

                {item.leaveTitle && item.leaveTitle !== item.leaveName && item.leaveTitle !== item.leaveReason ? (
                  <span className="text-[11px] font-semibold text-[var(--text)] line-clamp-1" title={`عنوان الإجازة: ${item.leaveTitle}`}>
                    📌 {item.leaveTitle}
                  </span>
                ) : null}

                {sanitizedLeaveReason ? (
                  <span className="text-[10.5px] text-[var(--text-muted)] line-clamp-2" title={`سبب الإجازة: ${sanitizedLeaveReason}`}>
                    💬 السبب: {sanitizedLeaveReason}
                  </span>
                ) : null}
              </div>
            ) : null}
            {item.hasMission ? (
              <div className="flex flex-col gap-0.5 items-start">
                <span className="status-pill status-pill--neutral text-[11px] font-bold whitespace-nowrap shrink-0" title="مأمورية رسمية معتمدة">
                  <Plane className="size-3" aria-hidden="true" />
                  <span>{item.leaveName && item.leaveName !== item.leaveTitle ? item.leaveName : 'مأمورية رسمية'}</span>
                  {item.leaveRequestNumber ? <span className="opacity-75 font-normal font-mono">(#{item.leaveRequestNumber})</span> : null}
                </span>

                {missionInfo.destination ? (
                  <span className="text-[11px] font-semibold text-[var(--text)] line-clamp-1" title={`وجهة / موضوع المأمورية: ${missionInfo.destination}`}>
                    📍 {missionInfo.destination}
                  </span>
                ) : null}

                {missionInfo.purpose ? (
                  <span className="text-[10.5px] text-[var(--text-muted)] line-clamp-2" title={`الغرض: ${missionInfo.purpose}`}>
                    💬 الغرض: {missionInfo.purpose}
                  </span>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : item.hasPendingRequest ? (
          <div className="flex flex-col gap-1 items-start">
            <span
              className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-bold whitespace-nowrap shrink-0"
              style={{
                backgroundColor: 'rgba(245, 158, 11, 0.12)',
                color: '#f59e0b',
                border: '1px solid rgba(245, 158, 11, 0.3)',
              }}
              title={item.reviewReason ?? item.pendingRequestTitle ?? undefined}
            >
              <Clock3 className="size-3" aria-hidden="true" />
              <span>
                {item.pendingRequestType === 'leave' ? 'طلب إجازة معلّق' : item.pendingRequestType === 'mission' ? 'طلب مأمورية معلّق' : 'طلب معلّق'}{' '}
                {item.pendingRequestNumber ? <bdi dir="ltr">(#{item.pendingRequestNumber})</bdi> : ''}
              </span>
            </span>
            {item.pendingRequestType === 'mission' ? (
              <div className="flex flex-col gap-0.5 text-[10.5px] text-[var(--text-muted)]">
                {missionInfo.destination ? <span className="font-semibold text-slate-200">📍 {missionInfo.destination}</span> : null}
                {missionInfo.purpose ? <span>💬 {missionInfo.purpose}</span> : null}
              </div>
            ) : item.pendingRequestType === 'leave' ? (
              <span className="text-[10.5px] text-[var(--text-muted)]">
                💬 {sanitizedLeaveReason}
              </span>
            ) : item.pendingRequestTitle ? (
              <span className="text-[10px] text-[var(--text-muted)] truncate max-w-[180px]">{item.pendingRequestTitle}</span>
            ) : null}
          </div>
        ) : item.reviewReason ? (
          <span className="text-amber-500 text-[11px] font-bold flex items-center gap-1 whitespace-nowrap shrink-0" title={item.reviewReason}>
            ⚠️ {item.reviewReason}
          </span>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 8. الإجراءات وفتح الملف */}
      <td className="min-w-[120px] text-end whitespace-nowrap" data-hide-capture="true">
        <div className="flex items-center justify-end gap-1.5 whitespace-nowrap">
          {isMissingCheckoutTab && isMarked ? (
            <button
              type="button"
              disabled={isActionPending}
              onClick={() => void onUnmark(item.employeeId)}
              className="btn-ghost btn-xs text-xs font-bold text-slate-400 hover:text-rose-400 rounded-lg px-2 py-1 transition-colors whitespace-nowrap shrink-0"
              title="إلغاء وسم بصمة بلا انصراف والعودة للنظام"
            >
              تراجع
            </button>
          ) : null}
          <Link
            to={`${hrPrefix}/employees/${item.employeeId}`}
            className="btn-ghost btn-xs whitespace-nowrap shrink-0 text-xs font-bold text-[var(--primary)] hover:bg-[var(--primary)]/10 rounded-lg px-2.5 py-1"
          >
            فتح الملف
          </Link>
        </div>
      </td>
    </tr>
  );
}
