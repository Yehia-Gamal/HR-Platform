import {
  ArrowRight,
  ArrowUpDown,
  Calendar,
  CalendarClock,
  CalendarX2,
  Camera,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Loader2,
  MapPin,
  Plane,
  Printer,
  RotateCcw,
  Search,
  UserCheck,
  UserX,
  Users,
  X,
} from 'lucide-react';
import { useEffect, useState } from 'react';
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

const CATEGORIES: { key: AttendanceRosterCategory; label: string; icon: typeof Users }[] = [
  { key: 'scheduled', label: 'المجدولون', icon: Users },
  { key: 'present', label: 'حاضرون', icon: UserCheck },
  { key: 'late', label: 'متأخرون', icon: Clock3 },
  { key: 'absent', label: 'غياب', icon: UserX },
  { key: 'unexcused_absent', label: 'غياب بدون إذن', icon: UserX },
  { key: 'incomplete', label: 'بصمات غير مكتملة', icon: Clock3 },
  { key: 'pending_review', label: 'تحتاج مراجعة', icon: UserCheck },
  { key: 'location_requests', label: 'طلبات الموقع', icon: MapPin },
  { key: 'location_responded', label: 'استجابات الموقع', icon: MapPin },
  { key: 'on_leave', label: 'في إجازة', icon: CalendarX2 },
  { key: 'on_mission', label: 'في مأمورية', icon: Plane },
  { key: 'missing_checkout', label: 'بصمة بلا انصراف', icon: Clock3 },
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
  return new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date(iso));
}

export function AttendanceDrilldownPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const categoryParam = searchParams.get('category');
  const category: AttendanceRosterCategory = attendanceRosterCategorySchema.safeParse(categoryParam).success
    ? (categoryParam as AttendanceRosterCategory)
    : 'scheduled';
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
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const isToday = dateIso === cairoTodayIso();

  const handlePrint = async () => {
    setIsPrinting(true);
    try {
      await exportAttendancePdf({ category, dateIso, search: q, departmentId: dept || null, branchId: branch || null, sort, direction });
    } finally {
      setIsPrinting(false);
    }
  };

  const handleCaptureScreenshot = async () => {
    const element = document.getElementById('attendance-roster-view');
    if (!element) return;
    setIsCapturing(true);
    setToastMessage('جاري التقاط الشاشة بجودة فائقة...');
    try {
      const h2cModule = await import('html2canvas');
      const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);
      const canvas = await html2canvas(element, {
        scale: 2,
        useCORS: true,
        logging: false,
        backgroundColor: '#0b1329',
        windowWidth: element.scrollWidth,
      });
      canvas.toBlob((blob: Blob | null) => {
        if (!blob) {
          setToastMessage('تعذر التقاط لقطة الشاشة');
          setTimeout(() => setToastMessage(null), 3000);
          return;
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `كشف_حضور_${category}_${dateIso}.png`;
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

  const items = query.data?.items ?? [];
  const total = query.data?.total ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / limit));

  const focusedId = useEntityFocus(items.length > 0);
  const hrPrefix = useHrPrefix();
  const currentCategory = CATEGORIES.find((c) => c.key === category) ?? CATEGORIES[0];
  const isFiltered = Boolean(searchInput.trim() || branch || dept || sort !== 'name' || direction !== 'asc');

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
                  {total.toLocaleString('ar-EG')}
                </span>
              ) : null}
            </div>

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
                  <span>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`))}</span>
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
          {/* زر تقرير الصورة للمدير التنفيذي */}
          <button
            type="button"
            className="btn-primary btn-sm h-9 px-3.5 text-xs font-black rounded-xl inline-flex items-center gap-1.5 shadow-sm bg-gradient-to-r from-sky-600 to-indigo-600 text-white hover:from-sky-500 hover:to-indigo-500 transition-all ring-1 ring-sky-400/30"
            onClick={() => setShowExecutiveModal(true)}
            title="إعداد تقرير صورة تنفيذي شامل للمدير التنفيذي (من جاء ومن تغيب ومن في إجازة)"
          >
            <Camera className="size-4" />
            <span>صورة للمدير التنفيذي</span>
          </button>

          <button
            type="button"
            className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl border border-[var(--border)] inline-flex items-center gap-1.5 hover:border-[var(--primary)] transition-all"
            onClick={() => void handleCaptureScreenshot()}
            disabled={isCapturing}
            aria-busy={isCapturing}
            title="حفظ لقطة شاشة من الكشف كملف صورة PNG عالي الدقة"
          >
            {isCapturing ? <Loader2 className="size-4 animate-spin text-[var(--primary)]" /> : <Camera className="size-4 text-[var(--primary)]" />}
            لقطة شاشة
          </button>

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

      {/* ─── بطاقة المحتوى والجدول ─── */}
      <div id="attendance-roster-view" className="card space-y-4 p-3.5 sm:p-4.5 bg-[var(--surface)]">
        {/* ─── شريط البحث النظيف والمنضبط ─── */}
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
        ) : items.length === 0 ? (
          <EmptyState
            title={q ? 'لا نتائج للبحث الحالي' : 'لا عناصر في هذه الفئة'}
            description={q ? 'جرّب البحث بكلمات أخرى أو عدّل الفلاتر.' : `لا يوجد موظفون ضمن فئة «${currentCategory.label}» لهذا اليوم.`}
          />
        ) : (
          <div className="overflow-x-auto rounded-xl border border-[var(--border)] bg-[var(--surface)]">
            <table className="data-table w-full">
              <thead className="sticky top-0 z-10 bg-[var(--surface-muted)]/95 backdrop-blur-xs">
                <tr>
                  <th className="min-w-[210px]">الموظف</th>
                  <th>الحالة</th>
                  <th>الإدارة والفرع</th>
                  <th>التأخير</th>
                  <th>الحضور / الانصراف</th>
                  <th>الموقع</th>
                  <th>العذر والبيان</th>
                  <th className="text-end" aria-label="فتح الملف"></th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <Row key={item.employeeId} item={item} focused={focusedId === item.employeeId} isToday={isToday} />
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* ─── ترقيم الصفحات ─── */}
        {!query.isError && !query.isLoading && total > 0 ? (
          <Pagination
            currentPage={page}
            totalPages={totalPages}
            totalItems={total}
            pageSize={limit}
            onPageChange={(p) => updateParams({ page: String(p) })}
            onPageSizeChange={(size) => updateParams({ size: String(size) })}
          />
        ) : null}
      </div>

      {/* ─── نافذة تقرير الصورة للمدير التنفيذي ─── */}
      {showExecutiveModal && <ExecutiveAttendanceModal dateIso={dateIso} onClose={() => setShowExecutiveModal(false)} />}
    </div>
  );
}

function Row({ item, focused, isToday }: { item: AttendanceRosterItem; focused: boolean; isToday: boolean }) {
  const hrPrefix = useHrPrefix();
  const hasExcuse = Boolean(item.hasApprovedLeave) || Boolean(item.hasMission);
  const isWorkingNow = isToday && Boolean(item.firstCheckIn) && !item.lastCheckOut;

  return (
    <tr data-focus-id={item.employeeId} className={focused ? 'entity-focus-highlight' : undefined}>
      {/* 1. الموظف: الصورة والاسم ورقم الهاتف / الكود */}
      <td>
        <div className="flex items-center gap-3">
          <UserAvatar displayName={item.employeeName} photoUrl={item.photoUrl} size="sm" announceName={false} />
          <div className="min-w-0">
            <Link
              to={`${hrPrefix}/employees/${item.employeeId}`}
              className="font-bold text-xs sm:text-sm text-[var(--text)] hover:text-[var(--primary)] hover:underline block truncate"
            >
              {item.employeeName}
            </Link>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="text-[11px] text-[var(--text-muted)] font-mono">{item.employeeCode ? <bdi dir="ltr">{item.employeeCode}</bdi> : '—'}</span>
              {item.jobTitle ? (
                <span className="text-[10px] text-[var(--text-secondary)] truncate max-w-[120px]" title={item.jobTitle}>
                  · {item.jobTitle}
                </span>
              ) : null}
            </div>
          </div>
        </div>
      </td>

      {/* 2. الحالة مع مؤشر العمل الحي */}
      <td>
        {isWorkingNow && item.status === 'present' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black bg-emerald-500/10 text-emerald-500 border border-emerald-500/25">
            <span className="size-2 rounded-full bg-emerald-500 animate-pulse" />
            حاضر (في العمل)
          </span>
        ) : isWorkingNow && item.status === 'late' ? (
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black bg-amber-500/10 text-amber-500 border border-amber-500/25">
            <span className="size-2 rounded-full bg-amber-500 animate-pulse" />
            متأخر (في العمل)
          </span>
        ) : item.status === 'absent' && item.hasPendingRequest ? (
          <span
            className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-black"
            style={{
              backgroundColor: 'rgba(245, 158, 11, 0.1)',
              color: '#f59e0b',
              border: '1px solid rgba(245, 158, 11, 0.3)',
            }}
            title={item.reviewReason ?? undefined}
          >
            <span className="size-1.5 rounded-full bg-amber-500 animate-pulse" />
            غائب (طلب معلّق)
          </span>
        ) : (
          <StatusBadge status={item.status ?? undefined} />
        )}
      </td>

      {/* 3. الإدارة والفرع */}
      <td className="text-xs">
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

      {/* 4. التأخير */}
      <td>
        {item.lateMinutes != null && item.lateMinutes > 0 ? (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-bold bg-amber-500/10 text-amber-500 border border-amber-500/20">
            <Clock3 className="size-3" aria-hidden="true" />
            {formatMinutes(item.lateMinutes)}
          </span>
        ) : (
          <span className="text-[var(--text-muted)] text-xs">—</span>
        )}
      </td>

      {/* 5. الحضور / الانصراف الذكي */}
      <td className="text-xs">
        {item.firstCheckIn ? (
          <div className="flex items-center gap-1.5 font-medium">
            <span className="font-bold text-[var(--text)]">{formatTime(item.firstCheckIn)}</span>
            <span className="text-[var(--text-muted)] text-[10px]">←</span>
            {item.lastCheckOut ? (
              <span className="font-bold text-[var(--text)]">{formatTime(item.lastCheckOut)}</span>
            ) : isToday ? (
              <span className="inline-flex items-center gap-1 font-bold text-emerald-500 text-[11px]">
                <span className="size-1.5 rounded-full bg-emerald-500 animate-pulse" />
                على رأس العمل
              </span>
            ) : (
              <span className="text-[var(--text-muted)]">—</span>
            )}
          </div>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 6. الموقع */}
      <td className="text-xs">
        {item.locationRequestStatus ? (
          <span className="inline-flex items-center gap-1 text-[var(--text-secondary)]">
            <MapPin className="size-3.5 text-[var(--primary)]" aria-hidden="true" />
            {locationStatusLabel(item.locationRequestStatus)}
          </span>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 7. العذر والملاحظات */}
      <td className="text-xs">
        {hasExcuse ? (
          <div className="flex flex-wrap gap-1">
            {item.hasApprovedLeave ? (
              <span className="status-pill status-pill--ok text-[11px] font-bold" title={item.leaveName ? `إجازة: ${item.leaveName}` : 'إجازة معتمدة'}>
                <CheckCircle2 className="size-3" aria-hidden="true" />
                {item.leaveName ?? 'إجازة معتمدة'}
              </span>
            ) : null}
            {item.hasMission ? (
              <span className="status-pill status-pill--neutral text-[11px] font-bold" title="مأمورية معتمدة">
                <Plane className="size-3" aria-hidden="true" />
                مأمورية
              </span>
            ) : null}
          </div>
        ) : item.hasPendingRequest ? (
          <div className="flex flex-col gap-1 items-start">
            <span
              className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11px] font-bold"
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
                {item.pendingRequestNumber ? `(#${item.pendingRequestNumber})` : ''}
              </span>
            </span>
            {item.pendingRequestTitle ? <span className="text-[10px] text-[var(--text-muted)] truncate max-w-[180px]">{item.pendingRequestTitle}</span> : null}
          </div>
        ) : item.reviewReason ? (
          <span className="text-amber-500 text-[11px] font-bold flex items-center gap-1" title={item.reviewReason}>
            ⚠️ {item.reviewReason}
          </span>
        ) : (
          <span className="text-[var(--text-muted)]">—</span>
        )}
      </td>

      {/* 8. فتح الملف */}
      <td className="text-end">
        <Link
          to={`${hrPrefix}/employees/${item.employeeId}`}
          className="btn-ghost btn-xs whitespace-nowrap text-xs font-bold text-[var(--primary)] hover:bg-[var(--primary)]/10 rounded-lg px-2 py-1"
        >
          فتح الملف
        </Link>
      </td>
    </tr>
  );
}
