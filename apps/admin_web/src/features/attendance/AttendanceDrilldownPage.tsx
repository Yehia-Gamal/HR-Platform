import {
  ArrowLeft,
  CalendarOff,
  CalendarX2,
  CheckCircle2,
  Clock3,
  Loader2,
  MapPin,
  Plane,
  Printer,
  Search,
  UserCheck,
  UserX,
  Users,
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
import { cairoTodayIso } from '../../core/cairoTime';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { Pagination } from '../../ui/Pagination';
import { SkeletonCard } from '../../ui/Skeletons';
import { UserAvatar } from '../../ui/UserAvatar';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import { useHrPrefix } from '../workspaces/access';
import { exportAttendancePdf, useAttendanceRosterPage } from './useAttendanceDashboard';

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

const STATUS_LABELS: Record<string, string> = {
  present: 'حاضر', late: 'متأخر', absent: 'غائب', on_leave: 'إجازة', holiday: 'عطلة', weekend: 'عطلة الأسبوع', partial: 'جزئي', pending: 'قيد الانتظار', on_mission: 'مأمورية', missing_checkout: 'بصمة بلا انصراف',
};

function statusLabel(status: string | null): string {
  if (!status) return '—';
  return STATUS_LABELS[status] ?? status;
}

function locationStatusLabel(status: string | null | undefined): string {
  if (!status) return '—';
  const map: Record<string, string> = {
    pending: 'قيد الانتظار', accepted: 'مقبول', rejected: 'مرفوض', active: 'نشط', expired: 'منتهي', cancelled: 'ملغي', completed: 'مكتمل',
  };
  return map[status] ?? status;
}

function formatMinutes(minutes: number | null | undefined): string {
  if (minutes == null || minutes === 0) return '—';
  return `${minutes} د`;
}

function formatTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date(iso));
}

function statusBadgeClass(status: string | null): string {
  if (status === 'present') return 'status-pill--ok';
  if (status === 'late') return 'status-pill--warn';
  if (status === 'absent') return 'status-pill--danger';
  if (status === 'missing_checkout') return 'status-pill--warn';
  if (status === 'on_leave') return 'status-pill--ok';
  return 'status-pill--neutral';
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
  const sort: AttendanceRosterSort = attendanceRosterSortSchema.safeParse(sortParam).success
    ? (sortParam as AttendanceRosterSort)
    : 'name';
  const direction = searchParams.get('dir') === 'desc' ? ('desc' as const) : ('asc' as const);
  const page = Math.max(1, Number(searchParams.get('page') ?? '1') || 1);
  const sizeParam = Number(searchParams.get('size') ?? '25');
  const limit = PAGE_SIZES.includes(sizeParam) ? sizeParam : 25;
  const offset = (page - 1) * limit;

  const [searchInput, setSearchInput] = useState(q);
  const [isPrinting, setIsPrinting] = useState(false);

  const handlePrint = async () => {
    setIsPrinting(true);
    try {
      await exportAttendancePdf({ category, dateIso, search: q, departmentId: dept || null, branchId: branch || null, sort, direction });
    } finally {
      setIsPrinting(false);
    }
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

  const currentCategory = CATEGORIES.find((c) => c.key === category) ?? CATEGORIES[0];

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link to="/hr/attendance" className="btn-ghost btn-sm" aria-label="العودة إلى لوحة الحضور">
            <ArrowLeft className="size-4" aria-hidden="true" />
            عودة
          </Link>
          <div>
            <h1 className="text-lg font-black">قائمة «{currentCategory.label}»</h1>
            <p className="mt-0.5 flex items-center gap-1.5 text-xs text-[var(--text-muted)]">
              <CalendarOff className="size-3.5" aria-hidden="true" />
              {new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(dateIso))}
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <button className="btn-secondary btn-sm" onClick={() => void handlePrint()} disabled={isPrinting} aria-busy={isPrinting} aria-label="تصدير القائمة كـ PDF">
            {isPrinting ? <Loader2 className="size-4 animate-spin" aria-hidden="true" /> : <Printer className="size-4" aria-hidden="true" />}
            طباعة / PDF
          </button>
          <button className="btn-secondary btn-sm" onClick={() => void query.refetch()} disabled={query.isFetching} aria-busy={query.isFetching}>
            <Loader2 className={`size-4 ${query.isFetching ? 'animate-spin' : ''}`} aria-hidden="true" />
            تحديث
          </button>
        </div>
      </header>

      {/* ─── تبويبات الفئات ─── */}
      <div className="flex flex-wrap gap-2" aria-label="فئات الحضور">
        {CATEGORIES.map((c) => {
          const active = c.key === category;
          const Icon = c.icon;
          return (
            <button
              key={c.key}
              type="button"
              aria-pressed={active}
              className={`filter-chip ${active ? 'is-active' : ''}`}
              onClick={() => updateParams({ category: c.key })}
            >
              <Icon className="size-4" aria-hidden="true" />
              {c.label}
            </button>
          );
        })}
      </div>

      <div className="card space-y-4 p-4">
        {/* ─── البحث (صف مستقل) ─── */}
        <label className="relative block">
          <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <input
            type="search"
            className="input w-full ps-3 pe-9 text-sm"
            placeholder="ابحث بالاسم أو الرقم الوظيفي أو الإدارة..."
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            aria-label="بحث في القائمة"
          />
        </label>

        {/* ─── الفلاتر (صف ثانٍ) ─── */}
        <div className="flex flex-wrap items-center gap-2">
          <select
            className="input min-w-36 text-sm"
            value={branch}
            onChange={(e) => updateParams({ branch: e.target.value })}
            aria-label="تصفية حسب الفرع"
          >
            <option value="">كل الفروع</option>
            {(lookups.data?.branches ?? []).map((b) => (
              <option key={b.id} value={b.id}>{b.label}</option>
            ))}
          </select>
          <select
            className="input min-w-36 text-sm"
            value={dept}
            onChange={(e) => updateParams({ dept: e.target.value })}
            aria-label="تصفية حسب الإدارة"
          >
            <option value="">كل الإدارات</option>
            {(lookups.data?.departments ?? []).map((d) => (
              <option key={d.id} value={d.id}>{d.label}</option>
            ))}
          </select>
          <select
            className="input min-w-32 text-sm"
            value={sort}
            onChange={(e) => updateParams({ sort: e.target.value })}
            aria-label="ترتيب القائمة"
          >
            {SORT_OPTIONS.map((s) => (
              <option key={s.key} value={s.key}>{s.label}</option>
            ))}
          </select>
          <button
            type="button"
            className="btn-secondary btn-sm"
            onClick={() => updateParams({ dir: direction === 'asc' ? 'desc' : 'asc' })}
            aria-label={`ترتيب ${direction === 'asc' ? 'تنازلي' : 'تصاعدي'}`}
          >
            {direction === 'asc' ? 'تصاعدي ↑' : 'تنازلي ↓'}
          </button>
        </div>

        {query.isError ? (
          <ErrorState
            title="تعذر تحميل القائمة"
            description={safeErrorMessage(query.error)}
            onRetry={() => void query.refetch()}
          />
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
          <div className="-m-4 max-h-[65vh] overflow-auto">
            <table className="data-table w-full">
              <thead className="sticky top-0 z-10">
                <tr>
                  <th className="w-14">الموظف</th>
                  <th>الاسم</th>
                  <th>الحالة</th>
                  <th>الإدارة</th>
                  <th>التأخير</th>
                  <th>الحضور/الانصراف</th>
                  <th>الموقع</th>
                  <th>العذر</th>
                  <th aria-label="فتح الملف"></th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <Row key={item.employeeId} item={item} />
                ))}
              </tbody>
            </table>
          </div>
        )}

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
    </div>
  );
}

function Row({ item }: { item: AttendanceRosterItem }) {
  const hrPrefix = useHrPrefix();
  const hasExcuse = Boolean(item.hasApprovedLeave) || Boolean(item.hasMission);
  return (
    <tr>
      <td>
        <UserAvatar displayName={item.employeeName} photoUrl={item.photoUrl} size="sm" announceName={false} />
      </td>
      <td>
        <div className="min-w-0">
          <p className="truncate font-semibold">{item.employeeName}</p>
          <p className="text-xs text-[var(--text-muted)]">{item.employeeCode ?? '—'}</p>
        </div>
      </td>
      <td>
        <span className={`status-pill ${statusBadgeClass(item.status)}`}>{statusLabel(item.status)}</span>
      </td>
      <td className="text-xs text-[var(--text-muted)]">{item.departmentName ?? '—'}</td>
      <td>
        {item.lateMinutes != null && item.lateMinutes > 0 ? (
          <span className="text-xs font-semibold text-[var(--warning)]">{formatMinutes(item.lateMinutes)}</span>
        ) : '—'}
      </td>
      <td className="text-xs">
        <span>{formatTime(item.firstCheckIn)}</span>
        <span className="text-[var(--text-muted)]"> → </span>
        <span>{formatTime(item.lastCheckOut)}</span>
      </td>
      <td className="text-xs">
        {item.locationRequestStatus ? (
          <span className="inline-flex items-center gap-1">
            <MapPin className="size-3.5" aria-hidden="true" />
            {locationStatusLabel(item.locationRequestStatus)}
          </span>
        ) : '—'}
      </td>
      <td className="text-xs">
        {hasExcuse ? (
          <span className="flex flex-wrap gap-1">
            {item.hasApprovedLeave ? (
              <span className="status-pill status-pill--ok" title={`إجازة${item.leaveIsPaid ? ' مدفوعة' : ''}`}>
                <CheckCircle2 className="size-3" aria-hidden="true" />
                إجازة
              </span>
            ) : null}
            {item.hasMission ? (
              <span className="status-pill status-pill--neutral" title="مأمورية معتمدة">
                <Plane className="size-3" aria-hidden="true" />
                مأمورية
              </span>
            ) : null}
          </span>
        ) : '—'}
      </td>
      <td>
        <Link to={`${hrPrefix}/employees/${item.employeeId}`} className="btn-ghost btn-xs whitespace-nowrap">
          فتح الملف
        </Link>
      </td>
    </tr>
  );
}
