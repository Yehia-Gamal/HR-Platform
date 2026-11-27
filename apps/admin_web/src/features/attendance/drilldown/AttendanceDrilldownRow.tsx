import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { CheckCircle2, Clock3, MapPin, Plane } from 'lucide-react';
import { Link } from 'react-router';
import { UserAvatar } from '../../../ui/UserAvatar';
import { useHrPrefix } from '../../workspaces/access';
import { classifyEmployee, formatShiftBadge, sanitizeLeaveReason, sanitizeMissionPurpose } from '../executiveReportLogic';
import { AttendanceDrilldownStatusBadge } from './AttendanceDrilldownStatusBadge';

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

function formatTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

export function AttendanceDrilldownRow({
  item,
  focused,
  isToday,
  currentMinutesFromMidnight,
  isMissingCheckoutTab,
  isMarked,
  onUnmark,
  onGraceCheckout,
  isActionPending,
}: {
  item: AttendanceRosterItem;
  focused: boolean;
  isToday: boolean;
  currentMinutesFromMidnight: number;
  isMissingCheckoutTab: boolean;
  isMarked: boolean;
  onUnmark: (id: string) => void;
  onGraceCheckout: (id: string, name: string) => void;
  isActionPending: boolean;
}) {
  const hrPrefix = useHrPrefix();
  const classified = classifyEmployee(item, currentMinutesFromMidnight);
  const missionInfo = sanitizeMissionPurpose(item.leaveTitle ?? item.pendingRequestTitle, item.leaveReason);
  const sanitizedLeaveReason = sanitizeLeaveReason(item.leaveReason, item.leaveName);
  const hasExcuse = Boolean(item.hasApprovedLeave) || Boolean(item.hasMission) || Boolean(item.hasApprovedPermit);
  const isWorkingNow = isToday && Boolean(item.firstCheckIn) && !item.lastCheckOut && !isMarked;

  return (
    <tr data-focus-id={item.employeeId} className={focused ? 'entity-focus-highlight' : undefined}>
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
                <span
                  className="text-[10px] text-sky-400/90 font-mono font-medium truncate max-w-[160px]"
                  title={`الوردية: ${formatShiftBadge(item.shiftName)}`}
                >
                  · {formatShiftBadge(item.shiftName)}
                </span>
              ) : null}
            </div>
          </div>
        </div>
      </td>

      {/* 2. الحالة مع مؤشر العمل الحي والتصنيف المدقق */}
      <td className="min-w-[170px] whitespace-nowrap">
        <AttendanceDrilldownStatusBadge item={item} classified={classified} isWorkingNow={isWorkingNow} isMarked={isMarked} />
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
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-bold bg-amber-500/10 text-amber-500 border border-amber-500/20 font-mono whitespace-nowrap shrink-0"
            title={item.hasApprovedPermit ? `تأخير بعد استنفاد مدة الإذن المعتمد (${item.permitMinutes ?? 120} دقيقة)` : undefined}
          >
            <Clock3 className="size-3" aria-hidden="true" />
            {classified.formattedLate}
          </span>
        ) : (item.hasApprovedPermit || classified.isPendingPermit || item.pendingRequestType === 'permit') && item.firstCheckIn ? (
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-bold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 whitespace-nowrap shrink-0"
            title={
              item.hasApprovedPermit
                ? `مغطى بالكامل بالإذن المعتمد (${item.permitMinutes ?? 120} دقيقة)`
                : `مغطى بطلب إذن قيد المراجعة (${item.permitMinutes ?? 120} دقيقة)`
            }
          >
            — (مغطى بالإذن)
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
              <span
                className="inline-flex items-center gap-1 font-bold text-amber-500 text-[11px] whitespace-nowrap shrink-0"
                title="غادر مقر العمل دون تسجيل بصمة انصراف"
              >
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
                <span
                  className="inline-flex items-center gap-1 font-bold text-emerald-500 text-[11px] whitespace-nowrap shrink-0"
                  title="سجل حضور صباحاً ومتواجد حالياً في المجمع"
                >
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
          <span className="text-amber-500 text-[11px] font-bold flex items-center gap-1 whitespace-nowrap shrink-0">⚠️ مشي بدون بصمة انصراف</span>
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
            {item.hasApprovedPermit ? (
              <div className="flex flex-col gap-0.5 items-start">
                <span
                  className="status-pill status-pill--ok text-[11px] font-bold whitespace-nowrap shrink-0 bg-violet-500/15 text-violet-300 border border-violet-500/30"
                  title={item.permitTitle ? `إذن معتمد: ${item.permitTitle}` : 'إذن معتمد'}
                >
                  <Clock3 className="size-3 text-violet-400" aria-hidden="true" />
                  <span>
                    {item.permitType === 'late_permit'
                      ? 'إذن تأخير'
                      : item.permitType === 'early_permit' || item.permitType === 'early_leave_permit'
                        ? 'إذن انصراف'
                        : 'إذن عمل'}
                  </span>
                  {item.permitMinutes ? <span className="opacity-75 font-normal font-mono">({item.permitMinutes} دقيقة)</span> : null}
                  {item.leaveRequestNumber ? <span className="opacity-75 font-normal font-mono">(#{item.leaveRequestNumber})</span> : null}
                </span>

                {item.permitTitle && item.permitTitle !== item.permitReason ? (
                  <span className="text-[11px] font-semibold text-[var(--text)] line-clamp-1" title={`عنوان الإذن: ${item.permitTitle}`}>
                    📌 {item.permitTitle}
                  </span>
                ) : null}

                {item.permitReason ? (
                  <span className="text-[10.5px] text-[var(--text-muted)] line-clamp-2" title={`سبب الإذن: ${item.permitReason}`}>
                    💬 السبب: {item.permitReason}
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
              <span className="text-[10.5px] text-[var(--text-muted)]">💬 {sanitizedLeaveReason}</span>
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
            <>
              <button
                type="button"
                disabled={isActionPending}
                onClick={() => void onGraceCheckout(item.employeeId, item.employeeName)}
                className="btn-primary btn-xs text-xs font-bold rounded-lg px-2.5 py-1 whitespace-nowrap shrink-0 flex items-center gap-1 bg-emerald-600 hover:bg-emerald-500 text-white shadow-xs"
                title="اعتماد انصراف نهاية الوردية الرسمية تلقائياً وحساب ساعات العمل وإلغاء الغرامة"
              >
                <CheckCircle2 className="size-3" />
                اعتماد الوردية
              </button>
              <button
                type="button"
                disabled={isActionPending}
                onClick={() => void onUnmark(item.employeeId)}
                className="btn-ghost btn-xs text-xs font-bold text-slate-400 hover:text-rose-400 rounded-lg px-2 py-1 transition-colors whitespace-nowrap shrink-0"
                title="إلغاء وسم بصمة بلا انصراف والعودة للنظام"
              >
                تراجع
              </button>
            </>
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
