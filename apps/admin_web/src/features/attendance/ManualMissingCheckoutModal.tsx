import { useState, useMemo } from 'react';
import { Clock3, Search, X, CheckCircle2, Loader2, UserCheck } from 'lucide-react';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { UserAvatar } from '../../ui/UserAvatar';
import { parseShiftWindow } from './executiveReportLogic';

interface ManualMissingCheckoutModalProps {
  dateIso: string;
  onClose: () => void;
  onMark: (employeeIds: string[]) => Promise<void>;
  isActionPending: boolean;
  alreadyMarkedIds: Set<string>;
  presentItems: AttendanceRosterItem[];
  isLoading?: boolean;
}

function formatTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

export function ManualMissingCheckoutModal({
  dateIso: _dateIso,
  onClose,
  onMark,
  isActionPending,
  alreadyMarkedIds,
  presentItems,
  isLoading = false,
}: ManualMissingCheckoutModalProps) {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [filterType, setFilterType] = useState<'all' | 'ended' | 'ongoing'>('all');

  // حساب التوقيت الحالي بالقاهرة لدراسة انتهاء الوردية
  const currentMinutesFromMidnight = useMemo(() => {
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
  }, []);

  // الموظفون المؤهلون: سجلوا حضوراً ولم يسجلوا انصرافاً بعد وليسوا في إجازة أو مأمورية (معتمدة أو قيد المراجعة)
  const eligibleCandidates = useMemo(() => {
    return presentItems.filter((item) => {
      if (!item.firstCheckIn || item.lastCheckOut) return false;
      const isMissionOrLeave =
        item.status === 'on_leave' ||
        item.status === 'on_mission' ||
        Boolean(item.hasMission) ||
        Boolean(item.hasApprovedLeave) ||
        (Boolean(item.hasPendingRequest) && (item.pendingRequestType === 'mission' || item.pendingRequestType === 'leave'));
      if (isMissionOrLeave) {
        return false;
      }
      return true;
    });
  }, [presentItems]);

  const categorizedCandidates = useMemo(() => {
    return eligibleCandidates.map((item) => {
      const shiftWindow = parseShiftWindow(item.shiftName, item.shiftStartAt);
      const isShiftEnded = Boolean(shiftWindow && !shiftWindow.isNightShift && currentMinutesFromMidnight >= shiftWindow.endHour * 60 + shiftWindow.endMinute);
      const isMarked = alreadyMarkedIds.has(item.employeeId) || item.status === 'missing_checkout';
      return {
        ...item,
        isShiftEnded,
        isMarked,
      };
    });
  }, [eligibleCandidates, alreadyMarkedIds, currentMinutesFromMidnight]);

  const filteredCandidates = useMemo(() => {
    const q = searchTerm.trim().toLowerCase();
    return categorizedCandidates.filter((item) => {
      if (filterType === 'ended' && !item.isShiftEnded) return false;
      if (filterType === 'ongoing' && item.isShiftEnded) return false;

      if (!q) return true;
      return (
        item.employeeName.toLowerCase().includes(q) ||
        (item.employeeCode && item.employeeCode.toLowerCase().includes(q)) ||
        (item.departmentName && item.departmentName.toLowerCase().includes(q)) ||
        (item.jobTitle && item.jobTitle.toLowerCase().includes(q))
      );
    });
  }, [categorizedCandidates, searchTerm, filterType]);

  const toggleSelect = (employeeId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(employeeId)) next.delete(employeeId);
      else next.add(employeeId);
      return next;
    });
  };

  const handleSelectAll = () => {
    const unmarkedInFilter = filteredCandidates.filter((c) => !c.isMarked);
    if (selectedIds.size >= unmarkedInFilter.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(unmarkedInFilter.map((c) => c.employeeId)));
    }
  };

  const handleBulkSubmit = async () => {
    if (selectedIds.size === 0) return;
    await onMark(Array.from(selectedIds));
    setSelectedIds(new Set());
  };

  const handleSingleSubmit = async (employeeId: string) => {
    await onMark([employeeId]);
    setSelectedIds((prev) => {
      const next = new Set(prev);
      next.delete(employeeId);
      return next;
    });
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="manual-missing-checkout-title"
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-black/70 backdrop-blur-xs animate-in fade-in"
    >
      <div className="relative w-full max-w-3xl max-h-[90vh] flex flex-col rounded-2xl bg-[var(--surface,#0f172a)] border border-[var(--border,#1e293b)] text-[var(--text,#f8fafc)] shadow-2xl overflow-hidden">
        {/* ─── الترويسة ─── */}
        <div className="flex items-center justify-between p-4 sm:px-6 border-b border-[var(--border,#1e293b)] bg-[var(--surface-muted,#1e293b)]/30">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-amber-500/10 text-amber-500 border border-amber-500/20">
              <Clock3 className="size-5" />
            </span>
            <div>
              <h2 id="manual-missing-checkout-title" className="text-base sm:text-lg font-black text-white">
                تسجيل موظف «مشي بدون بصمة»
              </h2>
              <p className="text-xs text-[var(--text-muted,#94a3b8)]">
                اختر الموظف الذي غادر مقر العمل اليوم دون تسجيل بصمة انصراف لإدراجه في قائمة «بصمة بلا انصراف»
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-xl text-[var(--text-muted,#94a3b8)] hover:text-white hover:bg-[var(--surface-muted,#1e293b)] transition-colors"
            aria-label="إغلاق النافذة"
          >
            <X className="size-5" />
          </button>
        </div>

        {/* ─── شريط البحث والتصفية ─── */}
        <div className="p-4 sm:px-6 border-b border-[var(--border,#1e293b)] space-y-3 bg-[var(--surface,#0f172a)]">
          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2.5">
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute end-3.5 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted,#94a3b8)]" />
              <input
                type="search"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="ابحث بالاسم أو الرقم الوظيفي أو الإدارة..."
                className="input !h-9.5 w-full ps-9 pe-10 text-xs font-bold rounded-xl bg-[var(--surface-muted,#1e293b)]/40 border border-[var(--border,#1e293b)]"
              />
              {searchTerm ? (
                <button
                  type="button"
                  onClick={() => setSearchTerm('')}
                  className="absolute start-3 top-1/2 -translate-y-1/2 text-[var(--text-muted,#94a3b8)] hover:text-white"
                >
                  <X className="size-3.5" />
                </button>
              ) : null}
            </div>

            <div className="flex items-center gap-1 bg-[var(--surface-muted,#1e293b)]/50 p-1 rounded-xl border border-[var(--border,#1e293b)] shrink-0 text-xs">
              <button
                type="button"
                onClick={() => setFilterType('all')}
                className={`px-3 py-1 rounded-lg font-bold transition-all ${
                  filterType === 'all' ? 'bg-[var(--primary,#0284c7)] text-white shadow-xs' : 'text-[var(--text-muted,#94a3b8)] hover:text-white'
                }`}
              >
                الكل ({categorizedCandidates.length})
              </button>
              <button
                type="button"
                onClick={() => setFilterType('ended')}
                className={`px-3 py-1 rounded-lg font-bold transition-all ${
                  filterType === 'ended' ? 'bg-amber-500 text-slate-950 shadow-xs' : 'text-amber-400/80 hover:text-amber-300'
                }`}
              >
                انتهت ورديتهم ({categorizedCandidates.filter((c) => c.isShiftEnded).length})
              </button>
              <button
                type="button"
                onClick={() => setFilterType('ongoing')}
                className={`px-3 py-1 rounded-lg font-bold transition-all ${
                  filterType === 'ongoing' ? 'bg-emerald-600 text-white shadow-xs' : 'text-emerald-400/80 hover:text-emerald-300'
                }`}
              >
                مستمرة ({categorizedCandidates.filter((c) => !c.isShiftEnded).length})
              </button>
            </div>
          </div>

          <div className="flex items-center justify-between text-xs text-[var(--text-muted,#94a3b8)] font-medium">
            <span>
              عرض <strong className="text-white">{filteredCandidates.length}</strong> موظف متواجد اليوم
            </span>
            {filteredCandidates.some((c) => !c.isMarked) ? (
              <button type="button" onClick={handleSelectAll} className="text-[var(--primary,#0284c7)] hover:underline font-bold">
                {selectedIds.size >= filteredCandidates.filter((c) => !c.isMarked).length ? 'إلغاء تحديد الكل' : 'تحديد جميع المعروضين'}
              </button>
            ) : null}
          </div>
        </div>

        {/* ─── قائمة الموظفين ─── */}
        <div className="flex-1 overflow-y-auto p-4 sm:px-6 divide-y divide-[var(--border,#1e293b)]">
          {isLoading ? (
            <div className="py-12 flex flex-col items-center justify-center gap-2 text-[var(--text-muted,#94a3b8)]">
              <Loader2 className="size-6 animate-spin text-[var(--primary,#0284c7)]" />
              <span className="text-xs font-bold">جاري تحميل قائمة الحاضرين اليوم...</span>
            </div>
          ) : filteredCandidates.length === 0 ? (
            <div className="py-12 text-center text-[var(--text-muted,#94a3b8)] space-y-2">
              <UserCheck className="size-8 mx-auto text-slate-600" />
              <p className="text-sm font-bold text-white">لا يوجد موظفون متاحون للتسجيل</p>
              <p className="text-xs">{searchTerm ? 'لا توجد نتائج تطابق نص البحث الحالي.' : 'جميع الموظفين الحاضرين تم تسجيل انصرافهم أو تصنيفهم مسبقاً.'}</p>
            </div>
          ) : (
            filteredCandidates.map((item) => {
              const isSelected = selectedIds.has(item.employeeId);
              return (
                <div
                  key={item.employeeId}
                  className={`py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 transition-colors ${
                    item.isMarked ? 'opacity-60' : 'hover:bg-[var(--surface-muted,#1e293b)]/30'
                  }`}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    {!item.isMarked ? (
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => toggleSelect(item.employeeId)}
                        className="rounded accent-[var(--primary,#0284c7)] size-4 cursor-pointer shrink-0"
                        aria-label={`تحديد ${item.employeeName}`}
                      />
                    ) : (
                      <CheckCircle2 className="size-4 text-emerald-400 shrink-0" />
                    )}

                    <UserAvatar displayName={item.employeeName} photoUrl={item.photoUrl} size="sm" announceName={false} />

                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-bold text-xs sm:text-sm text-white truncate">{item.employeeName}</span>
                        {item.employeeCode ? (
                          <span className="text-[11px] text-[var(--text-muted,#94a3b8)] font-mono">
                            <bdi dir="ltr">{item.employeeCode}</bdi>
                          </span>
                        ) : null}
                        {item.isShiftEnded ? (
                          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-black bg-amber-500/15 text-amber-400 border border-amber-500/30">
                            <Clock3 className="size-2.5" />
                            انتهت الوردية
                          </span>
                        ) : null}
                      </div>

                      <div className="flex items-center gap-2 mt-0.5 text-[11px] text-[var(--text-muted,#94a3b8)] flex-wrap">
                        {item.departmentName ? (
                          <span className="truncate max-w-[140px]" title={item.departmentName}>
                            {item.departmentName}
                          </span>
                        ) : null}
                        {item.branchName ? <span>· {item.branchName}</span> : null}
                        {item.shiftName ? <span className="text-sky-400/90 font-mono">· {item.shiftName}</span> : null}
                      </div>
                    </div>
                  </div>

                  <div className="flex items-center justify-end gap-3 shrink-0 ps-7 sm:ps-0">
                    <div className="text-start sm:text-end text-xs">
                      <div className="text-[11px] text-[var(--text-muted,#94a3b8)]">وقت الحضور</div>
                      <div className="font-bold font-mono text-emerald-400">{formatTime(item.firstCheckIn)}</div>
                    </div>

                    {item.isMarked ? (
                      <span className="inline-flex items-center gap-1 px-3 py-1 rounded-xl text-xs font-bold bg-amber-500/10 text-amber-400 border border-amber-500/25">
                        <CheckCircle2 className="size-3" />
                        مسجل بلا انصراف
                      </span>
                    ) : (
                      <button
                        type="button"
                        disabled={isActionPending}
                        onClick={() => void handleSingleSubmit(item.employeeId)}
                        className="btn-primary btn-xs sm:btn-sm h-8 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-amber-600 hover:bg-amber-500 text-white shadow-xs whitespace-nowrap shrink-0"
                      >
                        {isActionPending ? <Loader2 className="size-3 animate-spin" /> : <Clock3 className="size-3" />}
                        <span>تسجيل مشي بدون بصمة</span>
                      </button>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* ─── أسفل النافذة مع الإجراء الجماعي ─── */}
        <div className="p-4 sm:px-6 border-t border-[var(--border,#1e293b)] bg-[var(--surface-muted,#1e293b)]/30 flex items-center justify-between gap-3">
          <div className="text-xs font-bold">
            {selectedIds.size > 0 ? (
              <span>
                تم تحديد <span className="text-amber-400 font-black px-1">{selectedIds.size}</span> موظف
              </span>
            ) : (
              <span className="text-[var(--text-muted,#94a3b8)]">يمكنك تحديد عدة موظفين للتسجيل دفعة واحدة</span>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={isActionPending}
              className="btn-ghost btn-sm text-xs font-bold rounded-xl text-[var(--text-muted,#94a3b8)] hover:text-white"
            >
              إلغاء
            </button>

            {selectedIds.size > 0 ? (
              <button
                type="button"
                disabled={isActionPending}
                onClick={() => void handleBulkSubmit()}
                className="btn-primary btn-sm h-9 px-4 text-xs font-black rounded-xl inline-flex items-center gap-1.5 bg-gradient-to-r from-amber-600 to-amber-500 text-white hover:from-amber-500 hover:to-amber-400 shadow-md"
              >
                {isActionPending ? <Loader2 className="size-3.5 animate-spin" /> : <Clock3 className="size-3.5" />}
                <span>تسجيل المحددين ({selectedIds.size}) كـ مشي بدون بصمة</span>
              </button>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}
