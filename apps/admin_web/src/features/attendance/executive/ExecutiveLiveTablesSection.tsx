import { Calendar, CheckCircle2, Clock3, Plane, UserCheck, UserX } from 'lucide-react';
import {
  formatShiftBadge,
  sanitizeLeaveReason,
  sanitizeMissionPurpose,
  type ClassifiedEmployee,
} from '../executiveReportLogic';

interface ExecutiveLiveTablesSectionProps {
  unexcusedAbsentList: ClassifiedEmployee[];
  lateList: ClassifiedEmployee[];
  missionPendingList: ClassifiedEmployee[];
  missionApprovedList: ClassifiedEmployee[];
  leaveList: ClassifiedEmployee[];
  permitList: ClassifiedEmployee[];
  upcomingShiftList: ClassifiedEmployee[];
  onTimePresentList: ClassifiedEmployee[];
  fmtTime: (iso: string | null | undefined) => string;
  fmtNum: (val: number | string) => string;
}

export function ExecutiveLiveTablesSection({
  unexcusedAbsentList,
  lateList,
  missionPendingList,
  missionApprovedList,
  leaveList,
  permitList,
  upcomingShiftList,
  onTimePresentList,
  fmtTime,
  fmtNum,
}: ExecutiveLiveTablesSectionProps) {
  return (
    <div className="space-y-6">
      {/* أ) جدول الغياب غير المبرر (الغياب الحقيقي فقط) */}
      {unexcusedAbsentList.length > 0 && (
        <div className="rounded-xl border border-rose-500/40 overflow-hidden bg-rose-950/20">
          <div className="bg-rose-900/80 border-b border-rose-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <UserX className="size-4 text-rose-400" />
              <span>قائمة الغياب غير المبرر (بدأت ورديتهم وتجاوزوا فترة السماح)</span>
            </div>
            <span className="bg-rose-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">{unexcusedAbsentList.length} موظف</span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">الوردية المقررة</th>
                <th className="p-2">موقف المتابعة والاتصال</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {unexcusedAbsentList.map((c, idx) => (
                <tr key={c.item.employeeId} className="bg-slate-950/50 hover:bg-slate-900/50">
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{c.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{c.item.departmentName ?? '—'}</td>
                  <td className="p-2 text-slate-200">
                    <bdi dir="ltr" className="font-mono text-xs font-bold text-slate-200">
                      {formatShiftBadge(c.item.shiftName, c.isPartTime)}
                    </bdi>
                  </td>
                  <td className="p-2">
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-rose-500/20 text-rose-300 border border-rose-500/40 font-bold text-[10px]">
                      ⚠️ غياب بلا إذن — جاري المتابعة الهاتفية
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* ب) جدول المتأخرين عن موعد الوردية */}
      {lateList.length > 0 ? (
        <div className="rounded-xl border border-amber-500/40 overflow-hidden bg-amber-950/20">
          <div className="bg-amber-900/80 border-b border-amber-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <Clock3 className="size-4 text-amber-400" />
              <span>المتأخرون عن موعد الوردية الرسمية (محسوبة بالدقائق الصريحة)</span>
            </div>
            <span className="bg-amber-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">{lateList.length} موظف</span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">الوردية المقررة</th>
                <th className="p-2">وقت البصمة</th>
                <th className="p-2">مدة التأخير الفعلية</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {lateList.map((c, idx) => (
                <tr key={c.item.employeeId} className="bg-amber-950/20 hover:bg-amber-950/35">
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{c.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{c.item.departmentName ?? '—'}</td>
                  <td className="p-2 text-slate-200">
                    <bdi dir="ltr" className="font-mono text-xs font-bold text-slate-200">
                      {formatShiftBadge(c.item.shiftName, c.isPartTime)}
                    </bdi>
                  </td>
                  <td className="p-2 font-mono font-black text-amber-400">{fmtTime(c.item.firstCheckIn)}</td>
                  <td className="p-2">
                    <span className="inline-block px-2.5 py-1 rounded-lg bg-amber-500/25 text-amber-300 border border-amber-500/50 font-black text-xs font-mono shadow-xs">
                      ⚠️ تأخير {fmtNum(c.formattedLate)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-950/20 px-4 py-3 flex items-center justify-between text-xs">
          <div className="flex items-center gap-2 text-emerald-300 font-bold">
            <CheckCircle2 className="size-4 text-emerald-400 shrink-0" />
            <span>المتأخرون عن موعد الوردية الرسمية: لا يوجد أي متأخرين بدون عذر مسبق لهذا اليوم (انضباط كامل)</span>
          </div>
          <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-mono font-black text-[11px]">
            0 متأخر
          </span>
        </div>
      )}

      {/* ج) جدول المأموريات (فصل المعلق عن المعتمد) */}
      {(missionPendingList.length > 0 || missionApprovedList.length > 0) && (
        <div className="rounded-xl border border-sky-500/30 overflow-hidden bg-slate-900/40">
          <div className="bg-sky-900/80 border-b border-sky-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <Plane className="size-4 text-sky-400" />
              <span>قائمة المأموريات والتكليفات الميدانية الرسمية</span>
            </div>
            <span className="bg-sky-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
              {missionPendingList.length + missionApprovedList.length} مأمورية
            </span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">حالة المأمورية</th>
                <th className="p-2">الوجهة والغرض الميداني الرسمي</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {missionPendingList.map((m, idx) => {
                const { destination, purpose } = sanitizeMissionPurpose(m.item.leaveTitle ?? m.item.pendingRequestTitle, m.item.leaveReason);
                return (
                  <tr key={m.item.employeeId} className="bg-amber-950/25 border-s-2 border-amber-500">
                    <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                    <td className="p-2 font-black text-white">{m.item.employeeName}</td>
                    <td className="p-2 text-slate-300">{m.item.departmentName ?? '—'}</td>
                    <td className="p-2">
                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-amber-500/25 text-amber-300 border border-amber-500/50 font-black text-[10.5px]">
                        {m.item.firstCheckIn ? '⏳ خرج لمأمورية قبل الاعتماد' : '⏳ مأمورية ميدانية قيد الاعتماد'} #
                        {m.item.pendingRequestNumber ?? ''}
                      </span>
                    </td>
                    <td className="p-2 text-slate-200">
                      <div className="flex flex-col gap-0.5">
                        <span className="text-white font-bold text-xs">📍 {destination}</span>
                        <span className="text-slate-300 text-[10.5px]">💬 الغرض: {purpose}</span>
                      </div>
                    </td>
                  </tr>
                );
              })}

              {missionApprovedList.map((m, idx) => {
                const { destination, purpose } = sanitizeMissionPurpose(m.item.leaveTitle, m.item.leaveReason);
                return (
                  <tr key={m.item.employeeId} className="bg-slate-950/40">
                    <td className="p-2 text-center text-slate-500 font-bold font-mono">{missionPendingList.length + idx + 1}</td>
                    <td className="p-2 font-black text-white">{m.item.employeeName}</td>
                    <td className="p-2 text-slate-300">{m.item.departmentName ?? '—'}</td>
                    <td className="p-2">
                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-sky-500/20 text-sky-300 border border-sky-500/30 font-bold text-[10.5px]">
                        ✈️ مأمورية رسمية معتمدة
                      </span>
                    </td>
                    <td className="p-2 text-slate-200">
                      <div className="flex flex-col gap-0.5">
                        <span className="text-white font-bold text-xs">📍 {destination}</span>
                        <span className="text-slate-300 text-[10.5px]">💬 الغرض: {purpose}</span>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* د) جدول الإجازات والراحات الرسمية مع حجب التفاصيل الطبية */}
      {leaveList.length > 0 && (
        <div className="rounded-xl border border-teal-500/30 overflow-hidden bg-slate-900/40">
          <div className="bg-teal-900/80 border-b border-teal-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <Calendar className="size-4 text-teal-400" />
              <span>قائمة الإجازات والراحات الرسمية المسجلة</span>
            </div>
            <span className="bg-teal-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">{leaveList.length} إجازة</span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">نوع الإجازة والمعاملة</th>
                <th className="p-2">البيان الرسمي</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {leaveList.map((l, idx) => (
                <tr key={l.item.employeeId} className="bg-slate-950/40">
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{l.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{l.item.departmentName ?? '—'}</td>
                  <td className="p-2">
                    <span className="inline-block px-2 py-0.5 rounded font-black text-[10.5px] bg-teal-500/20 text-teal-300 border border-teal-500/30">
                      {l.isPendingLeave ? '⏳ طلب إجازة معلّق' : `${l.item.leaveName ?? 'إجازة اعتيادية'} (معتمدة)`}
                    </span>
                  </td>
                  <td className="p-2 text-slate-300 font-medium">{sanitizeLeaveReason(l.item.leaveReason, l.item.leaveName)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* هـ) جدول أذونات وتصاريح العمل الرسمية */}
      {permitList.length > 0 && (
        <div className="rounded-xl border border-violet-500/30 overflow-hidden bg-slate-900/40">
          <div className="bg-violet-900/80 border-b border-violet-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <Clock3 className="size-4 text-violet-400" />
              <span>قائمة أذونات وتصاريح العمل الرسمية (تأخير / انصراف)</span>
            </div>
            <span className="bg-violet-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">{permitList.length} إذن</span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">حالة ونوع الإذن</th>
                <th className="p-2">المدة والبيان</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {permitList.map((pm, idx) => {
                const isPending = pm.category === 'permit_pending' || pm.category === 'present_permit_pending';
                return (
                  <tr key={pm.item.employeeId} className="bg-slate-950/40">
                    <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                    <td className="p-2 font-black text-white">{pm.item.employeeName}</td>
                    <td className="p-2 text-slate-300">{pm.item.departmentName ?? '—'}</td>
                    <td className="p-2">
                      <span
                        className={`inline-block px-2 py-0.5 rounded font-black text-[10.5px] ${
                          isPending
                            ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                            : 'bg-violet-500/20 text-violet-300 border border-violet-500/30'
                        }`}
                      >
                        {isPending ? `⏳ طلب إذن معلّق #${pm.item.pendingRequestNumber ?? ''}` : `⏱️ ${pm.item.permitTitle ?? 'إذن معتمد'}`}
                      </span>
                    </td>
                    <td className="p-2 text-slate-300 font-medium">
                      <div className="flex flex-col gap-0.5">
                        <div>
                          {pm.item.permitMinutes ? `${pm.item.permitMinutes} دقيقة — ` : ''}
                          {pm.item.permitReason ?? pm.item.leaveReason ?? 'ظرف طارئ'}
                        </div>
                        {pm.item.firstCheckIn ? (
                          <div className="text-[10px] font-mono text-slate-400">
                            بصمة الحضور: <span className="text-white font-bold">{fmtTime(pm.item.firstCheckIn)}</span>
                            {pm.trueLateMinutes === 0 ? (
                              <span className="text-emerald-400 ms-2 font-bold">✓ حضور منضبط ضمن فترة الإذن</span>
                            ) : (
                              <span className="text-amber-400 ms-2 font-bold">
                                ⚠️ تجاوز الإذن بـ {fmtNum(pm.formattedLate)} (مخصوم {pm.item.permitMinutes || 120} د)
                              </span>
                            )}
                          </div>
                        ) : (
                          <div className="text-[10px] font-mono text-slate-500">لم يسجل بصمة حضور بعد</div>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* هـ) جدول الحاضرين في الموعد (الملتزمون) */}
      <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
        <div className="bg-emerald-950/80 border-b border-emerald-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
          <div className="flex items-center gap-2 text-emerald-300">
            <UserCheck className="size-4 text-emerald-400" />
            <span>قائمة الحاضرين الملتزمين في الموعد ({onTimePresentList.length} موظف متواجد بالمجمع)</span>
          </div>
          <span className="text-[11px] text-emerald-400/90 font-mono">100% التزام بالوردية</span>
        </div>
        <div className="p-3 bg-slate-950/40">
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
            {onTimePresentList.map((p, idx) => (
              <div
                key={p.item.employeeId}
                className="flex items-center justify-between p-2 rounded-lg bg-slate-900/70 border border-slate-800/80 text-xs"
              >
                <div className="flex items-center gap-2 truncate">
                  <span className="text-slate-500 font-mono text-[10px] w-4">{idx + 1}</span>
                  <span className="font-bold text-white truncate">{p.item.employeeName}</span>
                </div>
                <span className="font-mono text-[11px] font-bold text-emerald-400 shrink-0">{fmtTime(p.item.firstCheckIn)}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* و) فترات مسائية تبدأ لاحقاً (لتأكيد عدم غيابهم) */}
      {upcomingShiftList.length > 0 && (
        <div className="rounded-xl border border-indigo-500/30 overflow-hidden bg-indigo-950/20">
          <div className="bg-indigo-900/70 border-b border-indigo-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2 text-indigo-300">
              <Clock3 className="size-4 text-indigo-400" />
              <span>دوام مسائي لم يبدأ بعد ({upcomingShiftList.length} موظف - يبدأ دوامهم في موعده)</span>
            </div>
            <span className="bg-indigo-800/80 px-2 py-0.5 rounded-full text-[10.5px]">غير محسوبين غياباً</span>
          </div>
          <div className="p-3 bg-slate-950/30 flex flex-wrap gap-2 text-xs">
            {upcomingShiftList.map((u) => (
              <span
                key={u.item.employeeId}
                className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-900 border border-slate-800 text-slate-300"
              >
                <span className="font-bold text-white">{u.item.employeeName}</span>
                <span className="text-slate-500">·</span>
                <bdi dir="ltr" className="font-mono text-[11px] text-indigo-300">
                  {formatShiftBadge(u.item.shiftName)}
                </bdi>
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
