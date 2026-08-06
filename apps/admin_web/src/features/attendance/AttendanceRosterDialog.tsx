import { CalendarOff, Clock3, Loader2, MapPin, UserCheck, Users, UserX } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router';
import { type AttendanceRosterCategory, type AttendanceRosterItem } from '@ahla/shared-contracts';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAttendanceRoster } from './useAttendanceDashboard';

const CATEGORY_CONFIG: Record<
  AttendanceRosterCategory,
  { title: string; icon: typeof Users; emptyTitle: string; emptyDescription: string }
> = {
  scheduled: { title: 'المجدولون اليوم', icon: Users, emptyTitle: 'لا مجدولون اليوم', emptyDescription: 'لم يتطابق أي موظف نشط مع تقويم العمل لليوم المحدد.' },
  present: { title: 'حاضرون', icon: UserCheck, emptyTitle: 'لا حاضرون اليوم', emptyDescription: 'لم يسجل أي من الموظفين حضورًا حتى الآن.' },
  late: { title: 'متأخرون', icon: Clock3, emptyTitle: 'لا متأخرون', emptyDescription: 'لم يرد أي بصمة بعد وقت الوردية المسموح به اليوم.' },
  absent: { title: 'غياب', icon: UserX, emptyTitle: 'لا غياب', emptyDescription: 'كل الموظفين المجدولين سجلوا حضورًا أو لديهم عذر معتمد.' },
  unexcused_absent: { title: 'غياب بدون إذن', icon: UserX, emptyTitle: 'لا غياب غير مبرر', emptyDescription: 'كل الموظفين الغائبين لديهم إجازة أو مأمورية معتمدة تغطي اليوم.' },
  incomplete: { title: 'بصمات غير مكتملة', icon: Clock3, emptyTitle: 'لا بصمات غير مكتملة', emptyDescription: 'لا توجد سجلات جزئية أو معلقة حاليًا.' },
  pending_review: { title: 'تحتاج مراجعة بشرية', icon: UserCheck, emptyTitle: 'لا شيء للمراجعة', emptyDescription: 'لا توجد سجلات تتطلب تدخل بشري حاليًا.' },
  location_requests: { title: 'طلبات إرسال الموقع', icon: MapPin, emptyTitle: 'لا طلبات موقع', emptyDescription: 'لم تُرسل أي طلبات مشاركة موقع اليوم.' },
  location_responded: { title: 'استجابات الموقع', icon: MapPin, emptyTitle: 'لا استجابات', emptyDescription: 'لم يستجب أي موظف لمشاركة موقعه اليوم.' },
};

const STATUS_LABELS: Record<string, string> = {
  present: 'حاضر', late: 'متأخر', absent: 'غائب', on_leave: 'إجازة', holiday: 'عطلة', weekend: 'عطلة الأسبوع', partial: 'جزئي', pending: 'قيد الانتظار',
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

interface Props {
  category: AttendanceRosterCategory;
  dateIso: string;
  onClose: () => void;
}

export function AttendanceRosterDialog({ category, dateIso, onClose }: Props) {
  const { data, isLoading, isError, error } = useAttendanceRoster(category, true);
  const config = CATEGORY_CONFIG[category];
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim();
    if (!q) return data;
    return data.filter((item) =>
      item.employeeName.includes(q) || item.employeeCode?.includes(q) || item.departmentName?.includes(q)
    );
  }, [data, search]);

  const employeeLink = (item: AttendanceRosterItem) => `/hr/employees/${item.employeeId}`;

  const headerStats = useMemo(() => {
    if (!data) return null;
    return { total: data.length };
  }, [data]);

  return (
    <DialogOverlay title={config.title} onClose={onClose} maxWidth="max-w-4xl">
      <div className="space-y-4">
        {/* Header + search */}
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-xs text-[var(--text-muted)]">
            <CalendarOff className="size-4" aria-hidden="true" />
            <span>{new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(dateIso))}</span>
          </div>
          {headerStats ? (
            <span className="text-xs text-[var(--text-muted)]">
              إجمالي: <strong className="text-[var(--text-primary)]">{headerStats.total}</strong>
            </span>
          ) : null}
        </div>

        <input
          type="search"
          placeholder="ابحث بالاسم أو الرقم الوظيفي أو الإدارة..."
          className="input w-full text-sm"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          aria-label="بحث في القائمة"
        />

        {/* Content */}
        {isLoading ? (
          <div className="flex min-h-[200px] flex-col items-center justify-center gap-2" aria-live="polite">
            <Loader2 className="size-8 animate-spin text-brand" aria-hidden="true" />
            <span className="text-sm text-[var(--text-muted)]">جاري تحميل القائمة</span>
          </div>
        ) : isError ? (
          <EmptyState title="تعذر تحميل القائمة" description={safeErrorMessage(error)} />
        ) : filtered.length === 0 ? (
          <EmptyState
            title={search.trim() ? 'لا نتائج للبحث الحالي' : config.emptyTitle}
            description={search.trim() ? 'جرّب البحث بكلمات أخرى أو عدّل الفلاتر.' : config.emptyDescription}
          />
        ) : (
          <div className="table-container -mx-6 -mb-6 max-h-[60vh] overflow-y-auto">
            <table className="table w-full">
              <thead className="sticky top-0 z-10">
                <tr>
                  <th className="w-14">الموظف</th>
                  <th>الاسم</th>
                  <th>الحالة</th>
                  <th>الإدارة</th>
                  <th>التأخير</th>
                  <th>تسجيل الحضور/الانصراف</th>
                  <th>الموقع</th>
                  <th aria-label="فتح الملف"></th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((item) => (
                  <tr key={item.employeeId}>
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
                      <span className={`badge text-xs ${item.status === 'present' ? 'badge-success' : item.status === 'late' ? 'badge-warning' : item.status === 'absent' ? 'badge-danger' : 'badge-neutral'}`}>
                        {statusLabel(item.status)}
                      </span>
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
                    <td>
                      <Link to={employeeLink(item)} className="btn-ghost btn-xs whitespace-nowrap" onClick={onClose}>
                        فتح الملف
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </DialogOverlay>
  );
}
