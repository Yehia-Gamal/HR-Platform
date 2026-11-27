import { AlertTriangle, Clock3, FileCheck2, ShieldCheck } from 'lucide-react';
import {
  formatShiftBadge,
  type ComparativeAuditItem,
  type EndOfDayMetrics,
} from '../executiveReportLogic';

export function ExecutiveEndOfDayView({
  endOfDayMetrics,
  fmtTime,
  fmtNum,
}: {
  endOfDayMetrics: EndOfDayMetrics;
  fmtTime: (iso: string | null | undefined) => string;
  fmtNum: (val: number | string) => string;
}) {
  return (
    <div className="space-y-6">
      {/* مؤشرات نهاية اليوم وساعات العمل */}
      <div
        className="grid gap-3"
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(6, minmax(0, 1fr))',
        }}
      >
        <div className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-center">
          <span className="block text-[11px] font-bold text-slate-400 mb-1">حضروا اليوم</span>
          <span className="text-2xl font-black text-white font-mono">{endOfDayMetrics.totalCheckedIn}</span>
          <span className="text-[10px] text-slate-500 block mt-0.5">سجلوا حضوراً فعلياً</span>
        </div>

        <div className="p-3 rounded-xl bg-emerald-950/40 border border-emerald-500/30 text-center">
          <span className="block text-[11px] font-bold text-emerald-300 mb-1">اكتمل انصرافهم</span>
          <span className="text-2xl font-black text-emerald-400 font-mono">{endOfDayMetrics.completedCheckouts}</span>
          <span className="text-[10px] text-emerald-400/80 block mt-0.5">بصمتا حضور وانصراف</span>
        </div>

        <div
          className={`p-3 rounded-xl text-center ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'bg-rose-950/40 border border-rose-500/40' : 'bg-slate-900 border border-slate-800'}`}
        >
          <span className={`block text-[11px] font-bold mb-1 ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'text-rose-300' : 'text-slate-400'}`}>
            بصمة انصراف ناقصة
          </span>
          <span className={`text-2xl font-black font-mono ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'text-rose-400' : 'text-slate-300'}`}>
            {endOfDayMetrics.missingCheckoutsCount}
          </span>
          <span className="text-[10px] text-slate-400/80 block mt-0.5">لم يسجلوا خروجاً</span>
        </div>

        <div
          className={`p-3 rounded-xl text-center ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'bg-amber-950/40 border border-amber-500/40' : 'bg-slate-900 border border-slate-800'}`}
        >
          <span className={`block text-[11px] font-bold mb-1 ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'text-amber-300' : 'text-slate-400'}`}>
            انصراف مبكر
          </span>
          <span className={`text-2xl font-black font-mono ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'text-amber-400' : 'text-slate-300'}`}>
            {endOfDayMetrics.earlyDeparturesCount}
          </span>
          <span className="text-[10px] text-slate-400/80 block mt-0.5">قبل نهاية الوردية</span>
        </div>

        <div className="p-3 rounded-xl bg-sky-950/40 border border-sky-500/30 text-center">
          <span className="block text-[11px] font-bold text-sky-300 mb-1">عمل إضافي</span>
          <span className="text-2xl font-black text-sky-400 font-mono">{endOfDayMetrics.overtimeCount}</span>
          <span className="text-[10px] text-sky-400/80 block mt-0.5">تجاوز 8.5 ساعات</span>
        </div>

        <div className="p-3 rounded-xl bg-indigo-950/40 border border-indigo-500/30 text-center">
          <span className="block text-[11px] font-bold text-indigo-300 mb-1">متوسط ساعات العمل</span>
          <span className="text-base sm:text-lg font-black text-indigo-300 font-mono">{endOfDayMetrics.averageWorkHoursFormatted}</span>
          <span className="text-[10px] text-indigo-400/80 block mt-0.5">معدل الدوام الميداني</span>
        </div>
      </div>

      {/* جدول بصمات الانصراف الناقصة */}
      {endOfDayMetrics.missingCheckoutsCount > 0 && (
        <div className="rounded-xl border border-rose-500/40 overflow-hidden bg-rose-950/20">
          <div className="bg-rose-900/80 border-b border-rose-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <AlertTriangle className="size-4 text-rose-400" />
              <span>بصمات الانصراف الناقصة (حضروا وانتهى وقت ورديتهم دون تسجيل خروج)</span>
            </div>
            <span className="bg-rose-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
              {endOfDayMetrics.missingCheckoutsCount} موظف
            </span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">الوردية المقررة</th>
                <th className="p-2">وقت الحضور</th>
                <th className="p-2">موقف الانصراف</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {endOfDayMetrics.missingCheckoutList.map((m, idx) => (
                <tr key={m.item.employeeId} className="bg-slate-950/50 hover:bg-slate-900/50">
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{m.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{m.item.departmentName ?? '—'}</td>
                  <td className="p-2 text-slate-200">
                    <bdi dir="ltr" className="font-mono text-xs font-bold text-slate-200">
                      {formatShiftBadge(m.item.shiftName)}
                    </bdi>
                  </td>
                  <td className="p-2 font-mono font-bold text-emerald-400">{fmtTime(m.firstCheckIn)}</td>
                  <td className="p-2">
                    <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-rose-500/20 text-rose-300 border border-rose-500/40 font-bold text-[10px]">
                      ⚠️ لم يسجل بصمة انصراف حتى الآن
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* جدول الانصراف المبكر */}
      {endOfDayMetrics.earlyDeparturesCount > 0 && (
        <div className="rounded-xl border border-amber-500/40 overflow-hidden bg-amber-950/20">
          <div className="bg-amber-900/80 border-b border-amber-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
            <div className="flex items-center gap-2">
              <Clock3 className="size-4 text-amber-400" />
              <span>الانصراف المبكر (سجلوا خروجاً قبل نهاية موعد الوردية)</span>
            </div>
            <span className="bg-amber-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
              {endOfDayMetrics.earlyDeparturesCount} موظف
            </span>
          </div>
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">الوردية</th>
                <th className="p-2">وقت الانصراف</th>
                <th className="p-2">مدة التبكير</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 font-medium">
              {endOfDayMetrics.earlyDepartureList.map((e, idx) => (
                <tr key={e.item.employeeId} className="bg-amber-950/20 hover:bg-amber-950/35">
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{e.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{e.item.departmentName ?? '—'}</td>
                  <td className="p-2 text-slate-200">
                    <bdi dir="ltr" className="font-mono text-xs font-bold text-slate-200">
                      {formatShiftBadge(e.item.shiftName)}
                    </bdi>
                  </td>
                  <td className="p-2 font-mono font-bold text-amber-400">{fmtTime(e.lastCheckOut)}</td>
                  <td className="p-2">
                    <span className="inline-block px-2 py-0.5 rounded bg-amber-500/25 text-amber-300 border border-amber-500/50 font-bold text-[10.5px]">
                      تبكير: {fmtNum(e.formattedEarlyDeparture)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* سجل الانصراف وساعات العمل الكامل */}
      <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/50">
        <div className="bg-slate-950 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between text-xs font-black">
          <div className="flex items-center gap-2 text-slate-200">
            <Clock3 className="size-4 text-sky-400" />
            <span>سجل الانصراف وساعات العمل الفعلية للكوادر الحاضرة ({endOfDayMetrics.allStats.length} موظف)</span>
          </div>
        </div>
        <div className="overflow-x-auto max-h-96">
          <table className="w-full text-[11px] border-collapse text-start">
            <thead className="sticky top-0 bg-slate-900 z-10">
              <tr className="text-slate-300 border-b border-slate-800 font-black">
                <th className="p-2 w-8 text-center">#</th>
                <th className="p-2">اسم الموظف</th>
                <th className="p-2">الإدارة</th>
                <th className="p-2">حضور</th>
                <th className="p-2">انصراف</th>
                <th className="p-2">ساعات العمل الفعلية</th>
                <th className="p-2">الحالة النهائية</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/80 font-medium">
              {endOfDayMetrics.allStats.map((s, idx) => (
                <tr key={s.item.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/30' : 'bg-slate-900/30'}>
                  <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                  <td className="p-2 font-black text-white">{s.item.employeeName}</td>
                  <td className="p-2 text-slate-300">{s.item.departmentName ?? '—'}</td>
                  <td className="p-2 font-mono font-bold text-emerald-400">{fmtTime(s.firstCheckIn)}</td>
                  <td className="p-2 font-mono font-bold text-sky-400">{fmtTime(s.lastCheckOut)}</td>
                  <td className="p-2 font-mono font-black text-slate-200">{fmtNum(s.formattedWorkHours)}</td>
                  <td className="p-2">
                    {s.isMissingCheckout ? (
                      <span className="text-rose-400 font-bold text-[10px] bg-rose-500/10 px-2 py-0.5 rounded border border-rose-500/30">
                        بصمة ناقصة
                      </span>
                    ) : s.isEarlyDeparture ? (
                      <span className="text-amber-400 font-bold text-[10px] bg-amber-500/10 px-2 py-0.5 rounded border border-amber-500/30">
                        انصراف مبكر
                      </span>
                    ) : s.isOvertime ? (
                      <span className="text-sky-400 font-bold text-[10px] bg-sky-500/10 px-2 py-0.5 rounded border border-sky-500/30">
                        إضافي ({s.formattedOvertime})
                      </span>
                    ) : (
                      <span className="text-emerald-400 font-bold text-[10px] bg-emerald-500/10 px-2 py-0.5 rounded border border-emerald-500/30">
                        مكتمل
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

export function ExecutiveComparativeAuditView({
  comparativeAudit,
  dateFormatted,
}: {
  comparativeAudit: ComparativeAuditItem[];
  dateFormatted: string;
}) {
  return (
    <div className="space-y-6">
      <div className="p-4 rounded-xl bg-gradient-to-r from-amber-950/70 via-slate-900 to-sky-950/70 border border-amber-500/30 flex items-start gap-3">
        <ShieldCheck className="size-5 text-amber-400 shrink-0 mt-0.5" />
        <div className="space-y-1">
          <h4 className="text-xs sm:text-sm font-black text-white">دليل التدقيق والتحقق للمدير التنفيذي: لماذا تم تصحيح الأرقام؟</h4>
          <p className="text-[11px] text-slate-300 leading-relaxed">
            التقرير القديم احتسب كل موظف نشط في المنظومة كـ &quot;غياب بدون إذن&quot; حتى لو لم تكن له وردية عمل مسندة، بما فيهم طاقم العيادات المسائي (3 م) الذي
            لم يبدأ دوامه بعد عند إصدار التقرير (2:25 م). التقرير الجديد يعتمد المنطق الرياضي السليم: الغياب يحتسب فقط لمن له وردية بدأت وتجاوزت فترة السماح.
          </p>
        </div>
      </div>

      <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/60 shadow-lg">
        <div className="bg-slate-950 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between text-xs font-black">
          <div className="flex items-center gap-2 text-slate-200">
            <FileCheck2 className="size-4 text-amber-400" />
            <span>مصفوفة مقارنة المؤشرات (قبل وبعد التدقيق)</span>
          </div>
          <span className="text-[11px] text-slate-400 font-normal">تطبيق مباشر على بيانات اليوم ({dateFormatted})</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-[11px] border-collapse text-start">
            <thead>
              <tr className="bg-slate-900 text-slate-300 border-b border-slate-800 font-black">
                <th className="p-3 w-48">المؤشر / البند</th>
                <th className="p-3 text-rose-300 bg-rose-950/20">التقرير السابق (قبل التصحيح)</th>
                <th className="p-3 text-emerald-300 bg-emerald-950/20">التقرير المعتمد (بعد التدقيق)</th>
                <th className="p-3">التفسير والأساس المنطقي للمدير التنفيذي</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/80 font-medium">
              {comparativeAudit.map((item, idx) => (
                <tr key={item.metric} className={idx % 2 === 0 ? 'bg-slate-950/30' : 'bg-slate-900/30'}>
                  <td className="p-3 font-black text-white">{item.metric}</td>
                  <td className="p-3 font-mono font-bold text-rose-300 bg-rose-950/10">{item.oldValue}</td>
                  <td className="p-3 font-mono font-black text-emerald-300 bg-emerald-950/10">{item.newValue}</td>
                  <td className="p-3 text-slate-300 leading-relaxed text-[11px]">{item.explanation}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
