import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { CalendarX2, Clock3, Plane } from 'lucide-react';
import { StatusBadge } from '../../../ui/StatusBadge';
import type { ClassifiedEmployee } from '../executiveReportLogic';

export function AttendanceDrilldownStatusBadge({
  item,
  classified,
  isWorkingNow,
  isMarked,
}: {
  item: AttendanceRosterItem;
  classified: ClassifiedEmployee;
  isWorkingNow: boolean;
  isMarked: boolean;
}) {
  if (isMarked) {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/10 text-amber-500 border border-amber-500/25"
        title="سجل حضوراً ثم غادر مقر العمل دون تسجيل بصمة انصراف"
      >
        <Clock3 className="size-3 text-amber-500" />
        بصمة بلا انصراف (غادر)
      </span>
    );
  }
  if (classified.category === 'present_mission_pending') {
    return (
      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/15 text-amber-400 border border-amber-500/30">
        <Plane className="size-3 text-amber-400" />
        بصم حضور — خرج قبل الاعتماد
      </span>
    );
  }
  if (classified.category === 'present_mission_approved') {
    return (
      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-sky-500/10 text-sky-400 border border-sky-500/25">
        <Plane className="size-3 text-sky-400" />
        بصم حضور — في مأمورية
      </span>
    );
  }
  if (isWorkingNow && item.hasApprovedPermit && classified.trueLateMinutes <= 15) {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-emerald-500/10 text-emerald-400 border border-emerald-500/25"
        title={`حضر بإذن عمل معتمد: ${item.permitTitle ?? 'إذن تأخير'}${item.permitMinutes ? ` (${item.permitMinutes} دقيقة)` : ''}`}
      >
        <span className="size-2 rounded-full bg-emerald-500 animate-pulse" />
        حاضر (بإذن معتمد)
      </span>
    );
  }
  if (isWorkingNow && (classified.isPendingPermit || item.pendingRequestType === 'permit') && classified.trueLateMinutes <= 15) {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/15 text-amber-300 border border-amber-500/30"
        title={`حضر بطلب إذن تأخير قيد المراجعة: ${item.pendingRequestTitle ?? 'طلب إذن'}`}
      >
        <span className="size-2 rounded-full bg-amber-400 animate-pulse" />
        حاضر (بإذن قيد المراجعة)
      </span>
    );
  }
  if (isWorkingNow && classified.category === 'present_late') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/10 text-amber-500 border border-amber-500/25"
        title={
          item.hasApprovedPermit
            ? `تأخر بعد تجاوز مدة الإذن المعتمد بـ ${classified.trueLateMinutes} دقيقة`
            : classified.isPendingPermit
              ? `تأخر مع وجود طلب إذن قيد المراجعة`
              : undefined
        }
      >
        <span className="size-2 rounded-full bg-amber-500 animate-pulse" />
        {item.hasApprovedPermit ? 'متأخر (تجاوز الإذن)' : 'متأخر (في العمل)'}
      </span>
    );
  }
  if (isWorkingNow && classified.category === 'present_on_time') {
    return (
      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-emerald-500/10 text-emerald-500 border border-emerald-500/25">
        <span className="size-2 rounded-full bg-emerald-500 animate-pulse" />
        حاضر (في العمل)
      </span>
    );
  }
  if (!item.firstCheckIn && (item.hasApprovedPermit || item.status === 'on_permit' || classified.category === 'permit_approved')) {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-violet-500/15 text-violet-300 border border-violet-500/30"
        title={`إذن عمل معتمد: ${item.permitTitle ?? item.leaveTitle ?? 'إذن تأخير'}${item.permitMinutes ? ` (${item.permitMinutes} دقيقة)` : ''}`}
      >
        <Clock3 className="size-3 text-violet-400" />
        في إذن معتمد {item.permitMinutes ? `(${item.permitMinutes} د)` : ''}
      </span>
    );
  }
  if (!item.firstCheckIn && (item.status === 'pending_permit' || item.pendingRequestType === 'permit' || classified.category === 'permit_pending')) {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/15 text-amber-300 border border-amber-500/30"
        title={`طلب إذن قيد المراجعة: ${item.pendingRequestTitle ?? 'إذن عمل'}`}
      >
        <Clock3 className="size-3 text-amber-400" />
        إذن (قيد المراجعة)
      </span>
    );
  }
  if (classified.category === 'leave_pending') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/12 text-amber-500 border border-amber-500/30"
        title="طلب إجازة قيد المراجعة والاعتماد"
      >
        <span className="size-1.5 rounded-full bg-amber-500 animate-pulse" />
        إجازة (قيد المراجعة)
      </span>
    );
  }
  if (classified.category === 'leave_approved') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-teal-500/10 text-teal-400 border border-teal-500/25"
        title={`إجازة رسمية: ${item.leaveName ?? 'معتمدة'}`}
      >
        <CalendarX2 className="size-3 text-teal-400" />
        إجازة ({item.leaveName ?? 'معتمدة'})
      </span>
    );
  }
  if (classified.category === 'mission_pending') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-amber-500/12 text-amber-400 border border-amber-500/30"
        title="مأمورية ميدانية خرج الموظف لها بانتظار اعتماد الإدارة"
      >
        <Plane className="size-3 text-amber-400" />
        مأمورية معلقة (خرج قبل الاعتماد)
      </span>
    );
  }
  if (classified.category === 'mission_approved') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-sky-500/10 text-sky-400 border border-sky-500/25"
        title={`مأمورية رسمية معتمدة: ${item.leaveName ?? 'ميدانية'}`}
      >
        <Plane className="size-3 text-sky-400" />
        في مأمورية معتمدة
      </span>
    );
  }
  if (classified.category === 'shift_not_started') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-indigo-500/15 text-indigo-300 border border-indigo-500/30"
        title="فترة مسائية لم يبدأ موعدها بعد (العيادات الطبية 3 م – 11 م)"
      >
        <Clock3 className="size-3 text-indigo-400" />
        دوام لم يبدأ بعد
      </span>
    );
  }
  if (classified.category === 'unscheduled_rest') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-slate-700/30 text-slate-400 border border-slate-700/50"
        title="دوام مرن أو راحة أسبوعية بدون جدول زمني مقيد"
      >
        <span className="size-1.5 rounded-full bg-slate-500" />
        دوام مرن / غير مجدول
      </span>
    );
  }
  if (classified.category === 'unexcused_absent') {
    return (
      <span
        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-black whitespace-nowrap shrink-0 bg-rose-500/10 text-rose-500 border border-rose-500/25"
        title="غياب غير مبرر بعد بدء الوردية وانقضاء فترة السماح"
      >
        <span className="size-1.5 rounded-full bg-rose-500" />
        غياب بدون إذن
      </span>
    );
  }
  return <StatusBadge status={item.status ?? undefined} />;
}
