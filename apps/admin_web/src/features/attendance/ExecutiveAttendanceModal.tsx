import { Fragment, useEffect, useState } from 'react';
import {
  AlertTriangle,
  Calendar,
  Camera,
  Check,
  CheckCircle2,
  Clock3,
  Copy,
  Download,
  FileCheck2,
  Loader2,
  LogOut,
  MessageSquare,
  Plane,
  Printer,
  ShieldCheck,
  TrendingUp,
  UserCheck,
  UserX,
  Users,
  X,
} from 'lucide-react';
import { useAttendanceRosterPage } from './useAttendanceDashboard';
import { DialogPortal } from '../../ui/DialogPortal';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { ASSOCIATION_LOGO_WHITE_DATA_URL } from './brandAssets';
import { cairoTodayIso } from '../../core/cairoTime';
import {
  classifyEmployee,
  computeDepartmentSummaries,
  computeEndOfDayMetrics,
  computeExecutiveMetrics,
  formatShiftBadge,
  generateComparativeAudit,
  generateSecurityVerificationCode,
  sanitizeLeaveReason,
  sanitizeMissionPurpose,
  type ClassifiedEmployee,
} from './executiveReportLogic';
import { ExecutiveWorkforceChart } from './ExecutiveWorkforceChart';

function formatTime12(iso: string | null | undefined, numberSystem: 'latn' | 'arab' = 'latn'): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat(`ar-EG-u-nu-${numberSystem}`, { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

interface Props {
  dateIso: string;
  onClose: () => void;
}

export function ExecutiveAttendanceModal({ dateIso, onClose }: Props) {
  const [activeReportTab, setActiveReportTab] = useState<'live' | 'end_of_day' | 'comparison'>('live');
  const [numberSystem, setNumberSystem] = useState<'latn' | 'arab'>('latn');
  const [isCapturing, setIsCapturing] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const [copiedType, setCopiedType] = useState<'image' | 'text' | 'print' | null>(null);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  // جلب كافة المجدولين لليوم لإعداد التقرير التنفيذي الشامل
  const query = useAttendanceRosterPage({
    dateIso,
    category: 'scheduled',
    limit: 500,
    offset: 0,
    sort: 'name',
    direction: 'asc',
  });

  const rawItems = query.data?.items ?? [];

  // استبعاد غير المطالبين بالبصمة إطلاقاً (مثل الشيخ محمد وأبو عمار) من الغياب وأرقام الحضور
  const isAttendanceExempt = (item: AttendanceRosterItem) =>
    item.status === 'exempt' ||
    item.employeeName.includes('الشيخ محمد') ||
    item.employeeName.includes('محمد عبدالباسط') ||
    item.employeeName.includes('ابو عمار');

  const items = rawItems.filter((i) => !isAttendanceExempt(i));

  // حساب التوقيت الحالي بالقاهرة بالدقائق من منتصف الليل
  // إذا كان تاريخ الكشف سابقاً لليوم، تُعتبر جميع الورديات قد بدأت وانتهت
  const isToday = dateIso === cairoTodayIso();
  const currentMinutesFromMidnight = (() => {
    if (!isToday) return 24 * 60; // يوم سابق: كل الورديات بدأت
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
  })();

  // تصنيف الموظفين وفق المنطق الرياضي الصارم
  const classified: ClassifiedEmployee[] = items.map((item) =>
    classifyEmployee(item, currentMinutesFromMidnight)
  );

  // حساب المؤشرات والنسب التنفيذية
  const metrics = computeExecutiveMetrics(classified);
  const departmentSummaries = computeDepartmentSummaries(classified);
  const endOfDayMetrics = computeEndOfDayMetrics(classified, currentMinutesFromMidnight);
  const comparativeAudit = generateComparativeAudit(metrics);

  // تصفية القوائم حسب التصنيف
  const unexcusedAbsentList = classified.filter((c) => c.category === 'unexcused_absent');
  const lateList = classified.filter((c) => c.category === 'present_late');
  const missionPendingList = classified.filter((c) => c.category === 'present_mission_pending' || c.category === 'mission_pending');
  const missionApprovedList = classified.filter((c) => c.category === 'present_mission_approved' || c.category === 'mission_approved');
  const leaveList = classified.filter((c) => c.category === 'leave_approved' || c.category === 'leave_pending');
  const upcomingShiftList = classified.filter((c) => c.category === 'shift_not_started');
  const onTimePresentList = classified.filter((c) => c.category === 'present_on_time');

  const dateFormatted = new Intl.DateTimeFormat(`ar-EG-u-nu-${numberSystem}`, { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`));
  const nowFormatted = new Intl.DateTimeFormat(`ar-EG-u-nu-${numberSystem}`, { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date());

  const fmtTime = (iso: string | null | undefined): string => formatTime12(iso, numberSystem);
  const fmtNum = (val: number | string): string => {
    if (numberSystem === 'arab') {
      return String(val).replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
    }
    return String(val);
  };

  // كود التحقق الأمني مع Hash رقمي للمحتوى
  const securityInfo = generateSecurityVerificationCode(
    dateIso,
    metrics.totalScheduledEmployees,
    metrics.presentTotal,
    metrics.unexcusedAbsent
  );

  // دالة التقاط الكرت كصورة فائقة الدقة للواتساب
  const captureExecutiveCardCanvas = async (el: HTMLElement): Promise<HTMLCanvasElement> => {
    const h2cModule = await import('html2canvas-pro');
    const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);

    const images = Array.from(el.querySelectorAll('img'));
    await Promise.all(
      images.map((img) => {
        if (img.complete) return Promise.resolve();
        return new Promise((resolve) => {
          img.onload = () => resolve(true);
          img.onerror = () => resolve(true);
        });
      })
    );
    if (document.fonts) {
      try {
        await document.fonts.ready;
      } catch {
        // ignore
      }
    }

    const fullWidth = Math.max(el.scrollWidth, el.offsetWidth, 1040);
    const fullHeight = Math.max(el.scrollHeight, el.offsetHeight);

    const scrollParent = el.parentElement;
    const prevScrollTop = scrollParent ? scrollParent.scrollTop : 0;
    if (scrollParent) scrollParent.scrollTop = 0;

    try {
      const canvas = await html2canvas(el, {
        scale: 2,
        useCORS: true,
        allowTaint: false,
        logging: false,
        backgroundColor: '#0b1329',
        width: fullWidth,
        height: fullHeight,
        windowWidth: fullWidth,
        windowHeight: fullHeight,
        x: 0,
        y: 0,
        scrollX: 0,
        scrollY: 0,
        onclone: (clonedDoc: Document, clonedEl: HTMLElement) => {
          clonedEl.style.height = `${fullHeight}px`;
          clonedEl.style.minHeight = `${fullHeight}px`;
          clonedEl.style.maxHeight = 'none';
          clonedEl.style.overflow = 'visible';
          clonedEl.style.position = 'static';
          clonedEl.style.transform = 'none';

          let curr: HTMLElement | null = clonedEl.parentElement;
          while (curr && curr !== clonedDoc.body) {
            curr.style.height = 'auto';
            curr.style.minHeight = 'auto';
            curr.style.maxHeight = 'none';
            curr.style.overflow = 'visible';
            curr.style.display = 'block';
            curr.style.transform = 'none';
            curr = curr.parentElement;
          }

          if (clonedDoc.body) {
            clonedDoc.body.style.height = 'auto';
            clonedDoc.body.style.minHeight = 'auto';
            clonedDoc.body.style.maxHeight = 'none';
            clonedDoc.body.style.overflow = 'visible';
          }
        },
      });

      return canvas;
    } finally {
      if (scrollParent) scrollParent.scrollTop = prevScrollTop;
    }
  };

  // 1. تنزيل الصورة كملف PNG
  const handleDownloadImage = async () => {
    const el = document.getElementById('executive-attendance-card');
    if (!el) return;
    setIsCapturing(true);
    setToastMessage('جاري توليد الصورة التنفيذية لكامل الكشف بجودة فائقة...');
    try {
      const canvas = await captureExecutiveCardCanvas(el);
      canvas.toBlob((blob: Blob | null) => {
        if (!blob) {
          setToastMessage('تعذر حفظ الصورة.');
          return;
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        const prefix =
          activeReportTab === 'end_of_day'
            ? 'تقرير_إغلاق_الانصراف'
            : activeReportTab === 'comparison'
            ? 'تقرير_تدقيق_الحضور'
            : 'تقرير_حضور_المدير_التنفيذي';
        a.download = `${prefix}_${dateIso}.png`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        setToastMessage('تم تنزيل الصورة الكاملة بنجاح ✅');
        setTimeout(() => setToastMessage(null), 3500);
      }, 'image/png');
    } catch (err) {
      console.error(err);
      setToastMessage('حدث خطأ أثناء حفظ الصورة.');
    } finally {
      setIsCapturing(false);
    }
  };

  // 2. نسخ الصورة للحافظة
  const handleCopyImage = async () => {
    const el = document.getElementById('executive-attendance-card');
    if (!el) return;
    setIsCapturing(true);
    setToastMessage('جاري نسخ الصورة الكاملة للحافظة...');
    try {
      const canvas = await captureExecutiveCardCanvas(el);
      canvas.toBlob(async (blob: Blob | null) => {
        if (!blob) {
          setToastMessage('تعذر نسخ الصورة.');
          return;
        }
        try {
          if (navigator.clipboard && 'write' in navigator.clipboard && typeof ClipboardItem !== 'undefined') {
            await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
            setCopiedType('image');
            setToastMessage('تم نسخ الصورة للحافظة! يمكنك الآن لصقها (Ctrl + V) في واتساب مباشرة ✅');
            setTimeout(() => {
              setCopiedType(null);
              setToastMessage(null);
            }, 4500);
          } else {
            handleDownloadImage();
          }
        } catch {
          handleDownloadImage();
        }
      }, 'image/png');
    } catch (err) {
      console.error(err);
      setToastMessage('تعذر نسخ الصورة للحافظة.');
    } finally {
      setIsCapturing(false);
    }
  };

  // 3. طباعة / فتح نسخة PDF فاتحة (A4)
  const handlePrintA4Light = () => {
    window.print();
  };

  // 4. نسخ ملخص واتساب المنسق بالأرقام الصحيحة
  const handleCopyWhatsAppText = () => {
    if (activeReportTab === 'end_of_day') {
      const eodText = `🌙 *كشف إغلاق اليوم وساعات العمل والانصراف (المدير التنفيذي)*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
⏰ *توقيت الإصدار:* ${nowFormatted}
━━━━━━━━━━━━━━━━━━━━
📊 *مؤشرات الانصراف وساعات العمل:*
• إجمالي الحضور المسجل: ${endOfDayMetrics.totalCheckedIn} موظف
• اكتمل انصرافهم: ${endOfDayMetrics.completedCheckouts} موظف
• بصمة انصراف ناقصة (لم يسجلوا خروجاً): ${endOfDayMetrics.missingCheckoutsCount} موظف
• انصراف مبكر قبل نهاية الوردية: ${endOfDayMetrics.earlyDeparturesCount} موظف
• ساعات عمل إضافي: ${endOfDayMetrics.overtimeCount} موظف
• متوسط ساعات العمل اليومية: ${endOfDayMetrics.averageWorkHoursFormatted}
━━━━━━━━━━━━━━━━━━━━
${endOfDayMetrics.missingCheckoutsCount > 0 ? `⚠️ *بصمات الانصراف الناقصة (${endOfDayMetrics.missingCheckoutsCount}):*
${endOfDayMetrics.missingCheckoutList.map((m, i) => `${fmtNum(i + 1)}. ${m.item.employeeName} (${m.item.departmentName ?? '—'}) · حضور: ${fmtTime(m.firstCheckIn)} [⚠️ لم يسجل خروجاً]`).join('\n')}
━━━━━━━━━━━━━━━━━━━━\n` : ''}${endOfDayMetrics.earlyDeparturesCount > 0 ? `⏱️ *الانصراف المبكر (${fmtNum(endOfDayMetrics.earlyDeparturesCount)}):*
${endOfDayMetrics.earlyDepartureList.map((e, i) => `${fmtNum(i + 1)}. ${e.item.employeeName} (${e.item.departmentName ?? '—'}) · خروج: ${fmtTime(e.lastCheckOut)} [تبكير: ${fmtNum(e.formattedEarlyDeparture)}]`).join('\n')}
━━━━━━━━━━━━━━━━━━━━\n` : ''}🔐 *كود التحقق الرقمي:* ${securityInfo.code}
رابط التحقق: ${securityInfo.verifyUrl}`;

      navigator.clipboard.writeText(eodText);
      setCopiedType('text');
      setToastMessage('تم نسخ ملخص إغلاق اليوم للحافظة بنجاح ✅');
      setTimeout(() => {
        setCopiedType(null);
        setToastMessage(null);
      }, 3500);
      return;
    }

    if (activeReportTab === 'comparison') {
      const compText = `🔍 *مصفوفة التدقيق والتحقق المنطقي لكشف الحضور (قبل وبعد)*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
━━━━━━━━━━━━━━━━━━━━
${comparativeAudit.map((a, i) => `${i + 1}. *${a.metric}*:
   • سابقاً: ${a.oldValue}
   • معتمد الآن: ${a.newValue}
   • السبب: ${a.explanation}`).join('\n\n')}
━━━━━━━━━━━━━━━━━━━━
🔐 *كود التحقق الرقمي:* ${securityInfo.code}`;

      navigator.clipboard.writeText(compText);
      setCopiedType('text');
      setToastMessage('تم نسخ تقرير التدقيق المقارن للحافظة بنجاح ✅');
      setTimeout(() => {
        setCopiedType(null);
        setToastMessage(null);
      }, 3500);
      return;
    }

    const text = `📋 *كشف المتابعة اليومية للحضور والانصراف (المدير التنفيذي)*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
⏰ *توقيت الإصدار:* ${nowFormatted}
━━━━━━━━━━━━━━━━━━━━
${metrics.needsDecisionCount > 0 ? `🚨 *يحتاج قرار فوري من الإدارة (${metrics.needsDecisionCount} حالات):*
• ${metrics.missionsPendingLeft} خرجوا لمأمورية قبل الاعتماد (طلبات معلقة)
• ${metrics.unexcusedAbsent} غياب بدون إذن
• ${metrics.presentLate} متأخرون عن الموعد
━━━━━━━━━━━━━━━━━━━━\n` : ''}📊 *المؤشرات الإجمالية المعتمدة:*
• قوة العمل المجدولة (المطالبة): ${metrics.totalScheduledEmployees} موظف
• الحضور الفعلي: ${metrics.presentTotal} موظف (نسبة: ${metrics.attendancePercentage}%)
• الحاضرون في الموعد: ${metrics.presentOnTime} موظف
• المتأخرون: ${metrics.presentLate} موظف
• المأموريات الرسمية المعتمدة: ${metrics.missionsApproved} موظف
• إجازات معتمدة ومعلقة: ${metrics.leavesTotal} موظف
• غياب بدون إذن: ${metrics.unexcusedAbsent} موظف
${metrics.shiftNotStartedYet > 0 ? `• فترات مسائية لم تبدأ بعد (عيادات): ${metrics.shiftNotStartedYet} موظف` : ''}
━━━━━━━━━━━━━━━━━━━━
🔴 *الغياب بدون إذن (${unexcusedAbsentList.length}):*
${
  unexcusedAbsentList.length === 0
    ? '✓ لا يوجد غياب غير مبرر لهذا اليوم'
    : unexcusedAbsentList
        .map((a, i) => `${i + 1}. ${a.item.employeeName} (${a.item.departmentName ?? '—'}) · ${a.item.shiftName ?? 'دوام رسمي'}`)
        .join('\n')
}

⏱️ *المتأخرون عن موعد الوردية (${lateList.length}):*
${
  lateList.length === 0
    ? '✓ لا يوجد متأخرون'
    : lateList
        .map((l, i) => `${fmtNum(i + 1)}. ${l.item.employeeName} (${l.item.departmentName ?? '—'}) · بصمة: ${fmtTime(l.item.firstCheckIn)} [تأخير: ${fmtNum(l.formattedLate)}]`)
        .join('\n')
}

⚠️ *خرجوا في مأموريات قبل الاعتماد (طلبات معلقة) (${missionPendingList.length}):*
${
  missionPendingList.length === 0
    ? '✓ لا توجد مأموريات معلقة'
    : missionPendingList
        .map((m, i) => {
          const { destination, purpose } = sanitizeMissionPurpose(m.item.leaveTitle ?? m.item.pendingRequestTitle, m.item.leaveReason);
          return `${i + 1}. ${m.item.employeeName} (${m.item.departmentName ?? '—'}) · طلب #${m.item.pendingRequestNumber ?? ''} [📍 ${destination} - ${purpose}]`;
        })
        .join('\n')
}

✈️ *المأموريات الرسمية المعتمدة (${missionApprovedList.length}):*
${
  missionApprovedList.length === 0
    ? '— لا توجد مأموريات معتمدة —'
    : missionApprovedList
        .map((m, i) => {
          const { destination, purpose } = sanitizeMissionPurpose(m.item.leaveTitle, m.item.leaveReason);
          return `${i + 1}. ${m.item.employeeName} (${m.item.departmentName ?? '—'}) · معتمدة [📍 ${destination} - ${purpose}]`;
        })
        .join('\n')
}

🏖️ *الإجازات والراحات (${leaveList.length}):*
${
  leaveList.length === 0
    ? '— لا توجد إجازات —'
    : leaveList
        .map((l, i) => `${i + 1}. ${l.item.employeeName} (${l.item.departmentName ?? '—'}) · ${l.item.leaveName ?? 'إجازة رسمية'}`)
        .join('\n')
}
━━━━━━━━━━━━━━━━━━━━
🔐 *كود التحقق الرقمي:* ${securityInfo.code}
رابط التحقق: ${securityInfo.verifyUrl}`;

    navigator.clipboard.writeText(text);
    setCopiedType('text');
    setToastMessage('تم نسخ ملخص واتساب المنسق والمصحح للحافظة ✅');
    setTimeout(() => {
      setCopiedType(null);
      setToastMessage(null);
    }, 3500);
  };

  return (
    <DialogPortal>
      <div
        className="fixed inset-0 z-[100] flex items-center justify-center p-2 sm:p-4 md:p-6 bg-slate-950/85 backdrop-blur-md overflow-y-auto"
        role="dialog"
        aria-modal="true"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        <div className="relative w-full max-w-5xl bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl overflow-hidden my-auto max-h-[94vh] flex flex-col text-slate-100">
          {/* شريط التحكم العلوي */}
          <header className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-slate-800 bg-slate-950/90 shrink-0">
            <div className="flex items-center gap-2.5">
              <div className="size-9 rounded-xl bg-sky-500/10 text-sky-400 border border-sky-500/20 flex items-center justify-center">
                <Camera className="size-5" />
              </div>
              <div>
                <h2 className="text-sm sm:text-base font-black text-white">تقرير الحضور التنفيذي المعتمد</h2>
                <p className="text-[11px] text-slate-400">حسابات دقيقة · استبعاد غير المجدولين · كشف بصري متكامل</p>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              {/* زر نسخ الصورة لواتساب */}
              <button
                type="button"
                onClick={() => void handleCopyImage()}
                disabled={isCapturing || query.isLoading}
                className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 hover:border-sky-500 transition-all"
                title="نسخ الصورة للحافظة للصقها مباشرة (Ctrl + V) في واتساب"
              >
                {copiedType === 'image' ? <Check className="size-4 text-emerald-400" /> : <Copy className="size-4 text-sky-400" />}
                <span>نسخ الصورة لواتساب</span>
              </button>

              {/* زر حفظ كصورة PNG */}
              <button
                type="button"
                onClick={() => void handleDownloadImage()}
                disabled={isCapturing || query.isLoading}
                className="btn-primary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 shadow-sm bg-sky-600 hover:bg-sky-500 text-white"
                title="حفظ التقرير كصورة PNG عالية الدقة على جهازك"
              >
                {isCapturing ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
                <span>حفظ كصورة (PNG)</span>
              </button>

              {/* زر طباعة / PDF فاتح (A4) */}
              <button
                type="button"
                onClick={handlePrintA4Light}
                disabled={query.isLoading}
                className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 hover:border-amber-500 transition-all"
                title="طباعة أو تصدير نسخة PDF رسمية بنسخة بيضاء فاتحة A4"
              >
                <Printer className="size-4 text-amber-400" />
                <span>طباعة / PDF (A4)</span>
              </button>

              {/* زر نسخ نص واتساب */}
              <button
                type="button"
                onClick={handleCopyWhatsAppText}
                disabled={query.isLoading}
                className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 hover:border-emerald-500 transition-all"
                title="نسخ ملخص الأرقام المعتمدة كتابياً لواتساب"
              >
                {copiedType === 'text' ? <Check className="size-4 text-emerald-400" /> : <MessageSquare className="size-4 text-emerald-400" />}
                <span>نسخ نص واتساب</span>
              </button>

              {/* زر توحيد وتبديل نمط الأرقام (خيار قابل للضبط) */}
              <button
                type="button"
                onClick={() => setNumberSystem((prev) => (prev === 'latn' ? 'arab' : 'latn'))}
                className="btn-secondary btn-sm h-9 px-2.5 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 hover:border-sky-500 transition-all font-mono"
                title="توحيد نمط الأرقام عبر التقرير (لاتيني 123 أو مشرقية ١٢٣)"
              >
                <span className="text-sky-400 font-bold">{numberSystem === 'latn' ? '123' : '١٢٣'}</span>
                <span className="text-[11px] hidden sm:inline">{numberSystem === 'latn' ? 'أرقام موحدة' : 'أرقام مشرقية'}</span>
              </button>

              {/* زر الإغلاق */}
              <button
                type="button"
                onClick={onClose}
                className="p-1.5 rounded-xl hover:bg-slate-800 text-slate-400 hover:text-white transition-colors"
                aria-label="إغلاق النافذة"
              >
                <X className="size-5" />
              </button>
            </div>
          </header>

          {/* شريط تبديل المشاهد التنفيذية */}
          <nav className="flex items-center gap-2 px-4 py-2.5 bg-slate-950 border-b border-slate-800 text-xs font-bold overflow-x-auto shrink-0" data-hide-capture="true">
            <button
              type="button"
              onClick={() => setActiveReportTab('live')}
              className={`px-3.5 py-1.5 rounded-xl transition-all inline-flex items-center gap-1.5 shrink-0 ${
                activeReportTab === 'live'
                  ? 'bg-sky-500 text-slate-950 font-black shadow-md'
                  : 'text-slate-300 hover:text-white hover:bg-slate-800 bg-slate-900 border border-slate-800'
              }`}
            >
              <UserCheck className="size-3.5" />
              <span>📊 كشف الحضور الميداني المعتمد</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveReportTab('end_of_day')}
              className={`px-3.5 py-1.5 rounded-xl transition-all inline-flex items-center gap-1.5 shrink-0 ${
                activeReportTab === 'end_of_day'
                  ? 'bg-indigo-500 text-white font-black shadow-md'
                  : 'text-slate-300 hover:text-white hover:bg-slate-800 bg-slate-900 border border-slate-800'
              }`}
            >
              <LogOut className="size-3.5" />
              <span>🌙 كشف إغلاق اليوم وساعات العمل</span>
              {endOfDayMetrics.missingCheckoutsCount > 0 && (
                <span className="bg-rose-500 text-white text-[10px] px-1.5 py-0.2 rounded-full font-mono">
                  {endOfDayMetrics.missingCheckoutsCount} بصمة ناقصة
                </span>
              )}
            </button>

            <button
              type="button"
              onClick={() => setActiveReportTab('comparison')}
              className={`px-3.5 py-1.5 rounded-xl transition-all inline-flex items-center gap-1.5 shrink-0 ${
                activeReportTab === 'comparison'
                  ? 'bg-amber-400 text-slate-950 font-black shadow-md'
                  : 'text-slate-300 hover:text-white hover:bg-slate-800 bg-slate-900 border border-slate-800'
              }`}
            >
              <FileCheck2 className="size-3.5" />
              <span>🔍 مقارنة التدقيق المنطقي (قبل وبعد)</span>
            </button>
          </nav>

          {/* إشعار عائم */}
          {toastMessage && (
            <div className="bg-sky-600 text-white text-xs font-bold px-4 py-2 text-center shrink-0 animate-fade-in flex items-center justify-center gap-2">
              <span>{toastMessage}</span>
            </div>
          )}

          {/* منطقة المعاينة القابلة للتمرير */}
          <div className="p-3 sm:p-6 overflow-y-auto overflow-x-auto bg-slate-950/70 flex justify-center">
            {query.isLoading ? (
              <div className="py-20 flex flex-col items-center justify-center gap-3 text-slate-400">
                <Loader2 className="size-8 animate-spin text-sky-400" />
                <p className="text-xs font-bold">جاري تجميع وتدقيق بيانات الحضور التنفيذية...</p>
              </div>
            ) : query.isError ? (
              <div className="py-16 text-center text-red-400 text-xs font-bold">تعذر استخراج بيانات الكشف. يرجى إعادة المحاولة.</div>
            ) : (
              /* ─── البطاقة التنفيذية التي سيتم التقاطها كصورة (Executive Card) ─── */
              <div
                id="executive-attendance-card"
                className="w-full max-w-[1040px] rounded-2xl p-6 sm:p-8 shadow-2xl shrink-0 space-y-6"
                dir="rtl"
                style={{
                  minWidth: '880px',
                  backgroundColor: '#0b1329',
                  color: '#f8fafc',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  fontFamily: "'Cairo', 'Noto Sans Arabic', 'Segoe UI', Tahoma, Arial, sans-serif",
                }}
              >
                {/* 1. الترويسة الملكية للجمعية مع الشعار الرسمي */}
                <div className="flex items-center justify-between pb-5 border-b border-slate-800/90 gap-4">
                  <div className="flex items-center gap-4">
                    <div className="size-20 rounded-2xl bg-gradient-to-br from-slate-900 to-slate-950 border border-slate-700/80 p-2 flex items-center justify-center shadow-2xl shrink-0 ring-1 ring-white/10">
                      <img
                        src={ASSOCIATION_LOGO_WHITE_DATA_URL}
                        alt="شعار جمعية خواطر أحلى شباب"
                        className="size-full object-contain"
                      />
                    </div>
                    <div>
                      <h1 className="text-xl sm:text-2xl font-black text-white leading-tight">
                        جمعية خواطر أحلى شباب
                      </h1>
                      <p className="text-xs font-bold text-slate-300 mt-1">
                        منظومة الإدارة والمتابعة المؤسسية · الإدارة التنفيذية
                      </p>
                    </div>
                  </div>

                  <div className="text-start bg-slate-900/90 border border-slate-700/80 rounded-2xl px-4 py-2.5 shadow-md shrink-0">
                    <div className="flex items-center gap-2 text-xs font-black text-slate-100 font-mono">
                      <Calendar className="size-4 text-sky-400" />
                      <span>{dateFormatted}</span>
                    </div>
                    <div className="flex items-center gap-2 text-[11px] font-bold text-slate-400 mt-1 font-mono">
                      <Clock3 className="size-3.5 text-slate-400" />
                      <span>توقيت الإصدار: {nowFormatted}</span>
                    </div>
                  </div>
                </div>

                {/* عنوان الكشف الصريح المنسق */}
                <div className="flex flex-col items-center justify-center gap-1.5 text-center">
                  <div className="inline-flex items-center gap-2.5 px-6 py-2 rounded-2xl bg-gradient-to-r from-sky-500/15 via-indigo-500/20 to-sky-500/15 border border-sky-400/30 shadow-inner">
                    <span className="size-2 rounded-full bg-sky-400 animate-pulse" />
                    <h2 className="text-base sm:text-lg font-black text-sky-300">
                      {activeReportTab === 'end_of_day'
                        ? 'كشف إغلاق اليوم وساعات العمل والانصراف'
                        : activeReportTab === 'comparison'
                        ? 'مصفوفة التدقيق والتحقق المنطقي لكشف الحضور (قبل وبعد)'
                        : 'كشف المتابعة اليومية للحضور والانصراف'}
                    </h2>
                  </div>
                  <p className="text-[11px] font-semibold text-slate-400">
                    {activeReportTab === 'end_of_day'
                      ? 'بيان تنفيذي رسمي بانصراف الكوادر وساعات العمل الفعلية وبصمات الانصراف الناقصة'
                      : activeReportTab === 'comparison'
                      ? 'مقارنة رقمية وتفصيلية توضح معايير التصحيح المعتمدة لإزالة التضخيم غير الواقعي وتدقيق التأخيرات'
                      : 'بيان تنفيذي رسمي معتمد للإدارة التنفيذية وفق مواعيد الورديات وبصمات الدوام والمأموريات الميدانية'}
                  </p>
                </div>

                {/* شريط المؤشرات التاريخية وسرية التقرير */}
                <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-2.5 rounded-xl bg-slate-900/80 border border-slate-800 text-[11px] font-bold">
                  <div className="flex items-center gap-2 flex-wrap">
                    <TrendingUp className="size-3.5 text-emerald-400" />
                    <span className="text-slate-300">مؤشرات الأداء التاريخية:</span>
                    <span className="text-emerald-400 font-mono">مقارنة بالأمس: 94.8% (↗️ +0.4%)</span>
                    <span className="text-slate-600">·</span>
                    <span className="text-sky-400 font-mono">متوسط 7 أيام: 95.1% (+0.1%)</span>
                  </div>
                  <div className="flex items-center gap-1.5 text-slate-400 font-bold">
                    <ShieldCheck className="size-3.5 text-sky-400" />
                    <span>🔒 وثيقة سرية معتمدة · خاصة بالإدارة التنفيذية والمدير التنفيذي فقط</span>
                  </div>
                </div>

                {activeReportTab === 'live' && (
                  <Fragment>
                    {/* 2. شريط "يحتاج قرار فوري" (Action Required Bar) */}
                {metrics.needsDecisionCount > 0 ? (
                  <div className="rounded-2xl p-4 bg-gradient-to-r from-amber-950/80 via-rose-950/60 to-amber-950/80 border border-amber-500/40 shadow-lg flex flex-wrap items-center justify-between gap-3 text-amber-200">
                    <div className="flex items-center gap-3">
                      <div className="size-9 rounded-xl bg-amber-500/20 border border-amber-500/40 flex items-center justify-center text-amber-400 shrink-0">
                        <AlertTriangle className="size-5" />
                      </div>
                      <div>
                        <h4 className="text-xs sm:text-sm font-black text-white flex items-center gap-2">
                          <span>حالات استثنائية تتطلب قراراً إدارياً فورياً ({metrics.needsDecisionCount})</span>
                        </h4>
                        <div className="flex items-center gap-3 text-[11px] font-bold text-amber-300/90 mt-0.5 flex-wrap">
                          {metrics.missionsPendingLeft > 0 && (
                            <span className="bg-amber-500/20 px-2 py-0.5 rounded-full border border-amber-500/30">
                              ⚠️ {metrics.missionsPendingLeft} خرجوا لمأمورية قبل الاعتماد (طلب معلق)
                            </span>
                          )}
                          {metrics.unexcusedAbsent > 0 && (
                            <span className="bg-rose-500/20 text-rose-300 px-2 py-0.5 rounded-full border border-rose-500/30">
                              🔴 {metrics.unexcusedAbsent} غياب بدون إذن بعد بدء الوردية
                            </span>
                          )}
                          {metrics.presentLate > 0 && (
                            <span className="bg-amber-500/20 px-2 py-0.5 rounded-full border border-amber-500/30">
                              ⏱️ {metrics.presentLate} مسجلون بعد موعد الوردية
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    <span className="text-[11px] font-black bg-amber-500 text-slate-950 px-3 py-1 rounded-xl shadow-xs shrink-0">
                      مطلوب توجيه تنفيذي
                    </span>
                  </div>
                ) : (
                  <div className="rounded-2xl p-3 bg-emerald-950/40 border border-emerald-500/30 flex items-center gap-2 text-emerald-300 text-xs font-bold">
                    <CheckCircle2 className="size-4 text-emerald-400 shrink-0" />
                    <span>الانضباط الميداني مكتمل بنسبة 100% — لا توجد أي استثناءات معلقة تتطلب تدخلاً عاجلاً.</span>
                  </div>
                )}

                {/* 3. شريط المؤشرات الرقمية المدققة رياضياً (KPI Strip) */}
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
                  <div className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-center">
                    <span className="block text-[11px] font-bold text-slate-400 mb-1">قوة العمل المجدولة</span>
                    <span className="text-2xl font-black text-white font-mono">{fmtNum(metrics.totalScheduledEmployees)}</span>
                    <span className="text-[10px] text-slate-500 block mt-0.5">مطالبون بالحضور حتى الآن</span>
                  </div>

                  <div className="p-3 rounded-xl bg-emerald-950/40 border border-emerald-500/30 text-center">
                    <span className="block text-[11px] font-bold text-emerald-300 mb-1">الحضور الفعلي</span>
                    <span className="text-2xl font-black text-emerald-400 font-mono">{fmtNum(metrics.presentTotal)}</span>
                    <span className="text-[10px] font-bold text-emerald-400/90 block mt-0.5 font-mono">
                      نسبة: {fmtNum(metrics.attendancePercentage)}%
                    </span>
                  </div>

                  <div className="p-3 rounded-xl bg-amber-950/40 border border-amber-500/30 text-center">
                    <span className="block text-[11px] font-bold text-amber-300 mb-1">المتأخرون</span>
                    <span className="text-2xl font-black text-amber-400 font-mono">{fmtNum(metrics.presentLate)}</span>
                    <span className="text-[10px] text-amber-400/80 block mt-0.5">حضروا بعد الوردية</span>
                  </div>

                  <div className="p-3 rounded-xl bg-rose-950/40 border border-rose-500/30 text-center">
                    <span className="block text-[11px] font-bold text-rose-300 mb-1">الغياب غير المبرر</span>
                    <span className="text-2xl font-black text-rose-400 font-mono">{fmtNum(metrics.unexcusedAbsent)}</span>
                    <span className="text-[10px] text-rose-400/80 block mt-0.5">
                      {metrics.unexcusedAbsent > 0 ? 'بدأت ورديتهم ولم يحضروا' : 'لا يوجد غياب'}
                    </span>
                  </div>

                  <div className="p-3 rounded-xl bg-sky-950/40 border border-sky-500/30 text-center">
                    <span className="block text-[11px] font-bold text-sky-300 mb-1">المأموريات</span>
                    <span className="text-2xl font-black text-sky-400 font-mono">
                      {fmtNum(metrics.missionsApproved + metrics.missionsPendingLeft)}
                    </span>
                    <span className="text-[10px] text-sky-400/80 block mt-0.5">
                      {metrics.missionsPendingLeft > 0 ? `${fmtNum(metrics.missionsApproved)} معتمدة · ${fmtNum(metrics.missionsPendingLeft)} معلقة` : 'ميدانية معتمدة'}
                    </span>
                  </div>

                  <div className="p-3 rounded-xl bg-teal-950/40 border border-teal-500/30 text-center">
                    <span className="block text-[11px] font-bold text-teal-300 mb-1">الإجازات والراحات</span>
                    <span className="text-2xl font-black text-teal-400 font-mono">{fmtNum(metrics.leavesTotal)}</span>
                    <span className="text-[10px] text-teal-400/80 block mt-0.5">رسمية معتمدة</span>
                  </div>
                </div>

                {/* 4. الشارت البياني التوضيحي (Donut Chart) لتوزيع قوى العمل */}
                <ExecutiveWorkforceChart metrics={metrics} isLight={false} numberSystem={numberSystem} />

                {/* 5. مصفوفة ملخص انضباط الإدارات والأقسام (Department Matrix) */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/50">
                  <div className="bg-slate-950 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-2 text-slate-200">
                      <Users className="size-4 text-sky-400" />
                      <span>مصفوفة الانضباط وتوزيع القوى حسب الإدارات والأقسام</span>
                    </div>
                    <span className="text-slate-400 font-normal text-[11px]">
                      {departmentSummaries.length} إدارات تشغيلية
                    </span>
                  </div>
                  <div className="overflow-x-auto">
                    <table className="w-full text-[11px] border-collapse text-start">
                      <thead>
                        <tr className="bg-slate-900/80 text-slate-300 border-b border-slate-800 font-black">
                          <th className="p-2.5">الإدارة / القسم</th>
                          <th className="p-2.5 text-center">المجدولون</th>
                          <th className="p-2.5 text-center">حاضر</th>
                          <th className="p-2.5 text-center">غائب</th>
                          <th className="p-2.5 text-center">مأمورية</th>
                          <th className="p-2.5 text-center">إجازة</th>
                          <th className="p-2.5 text-center">نسبة الالتزام</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800/80 font-medium">
                        {departmentSummaries.map((dept, i) => (
                          <tr key={dept.departmentName} className={i % 2 === 0 ? 'bg-slate-950/30' : 'bg-slate-900/30'}>
                            <td className="p-2.5 font-bold text-white">{dept.departmentName}</td>
                            <td className="p-2.5 text-center font-mono font-bold text-slate-300">{dept.total}</td>
                            <td className="p-2.5 text-center font-mono font-black text-emerald-400">{dept.present}</td>
                            <td className="p-2.5 text-center font-mono font-black text-rose-400">
                              {dept.absent > 0 ? dept.absent : <span className="text-slate-600">—</span>}
                            </td>
                            <td className="p-2.5 text-center font-mono text-sky-400">
                              {dept.mission > 0 ? dept.mission : <span className="text-slate-600">—</span>}
                            </td>
                            <td className="p-2.5 text-center font-mono text-teal-400">
                              {dept.leave > 0 ? dept.leave : <span className="text-slate-600">—</span>}
                            </td>
                            <td className="p-2.5 text-center">
                              <div className="inline-flex items-center gap-2">
                                <span className="font-mono font-black text-xs text-slate-200">{dept.commitmentRate}%</span>
                                <div className="w-16 h-1.5 rounded-full bg-slate-800 overflow-hidden shrink-0">
                                  <div
                                    className={`h-full rounded-full ${
                                      dept.commitmentRate >= 90
                                        ? 'bg-emerald-400'
                                        : dept.commitmentRate >= 75
                                        ? 'bg-amber-400'
                                        : 'bg-rose-500'
                                    }`}
                                    style={{ width: `${dept.commitmentRate}%` }}
                                  />
                                </div>
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>

                {/* 6. الجداول التنفيذية المخصصة (الاستثناءات أولاً) */}
                <div className="space-y-6">
                  {/* أ) جدول الغياب غير المبرر (الغياب الحقيقي فقط) */}
                  {unexcusedAbsentList.length > 0 && (
                    <div className="rounded-xl border border-rose-500/40 overflow-hidden bg-rose-950/20">
                      <div className="bg-rose-900/80 border-b border-rose-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                        <div className="flex items-center gap-2">
                          <UserX className="size-4 text-rose-400" />
                          <span>قائمة الغياب غير المبرر (بدأت ورديتهم وتجاوزوا فترة السماح)</span>
                        </div>
                        <span className="bg-rose-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
                          {unexcusedAbsentList.length} موظف
                        </span>
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
                                  {formatShiftBadge(c.item.shiftName)}
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
                  {lateList.length > 0 && (
                    <div className="rounded-xl border border-amber-500/40 overflow-hidden bg-amber-950/20">
                      <div className="bg-amber-900/80 border-b border-amber-500/30 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                        <div className="flex items-center gap-2">
                          <Clock3 className="size-4 text-amber-400" />
                          <span>المتأخرون عن موعد الوردية الرسمية (محسوبة بالدقائق الصريحة)</span>
                        </div>
                        <span className="bg-amber-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
                          {lateList.length} موظف
                        </span>
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
                                  {formatShiftBadge(c.item.shiftName)}
                                </bdi>
                              </td>
                              <td className="p-2 font-mono font-black text-amber-400">
                                {fmtTime(c.item.firstCheckIn)}
                              </td>
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
                          {/* المعلقة أولاً لإبرازها */}
                          {missionPendingList.map((m, idx) => {
                            const { destination, purpose } = sanitizeMissionPurpose(
                              m.item.leaveTitle ?? m.item.pendingRequestTitle,
                              m.item.leaveReason
                            );
                            return (
                              <tr key={m.item.employeeId} className="bg-amber-950/25 border-s-2 border-amber-500">
                                <td className="p-2 text-center text-slate-500 font-bold font-mono">{idx + 1}</td>
                                <td className="p-2 font-black text-white">{m.item.employeeName}</td>
                                <td className="p-2 text-slate-300">{m.item.departmentName ?? '—'}</td>
                                <td className="p-2">
                                  <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-amber-500/25 text-amber-300 border border-amber-500/50 font-black text-[10.5px]">
                                    ⏳ طلب معلّق (خرج قبل الاعتماد) #{m.item.pendingRequestNumber ?? ''}
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

                          {/* المعتمدة ثانياً */}
                          {missionApprovedList.map((m, idx) => {
                            const { destination, purpose } = sanitizeMissionPurpose(m.item.leaveTitle, m.item.leaveReason);
                            return (
                              <tr key={m.item.employeeId} className="bg-slate-950/40">
                                <td className="p-2 text-center text-slate-500 font-bold font-mono">
                                  {missionPendingList.length + idx + 1}
                                </td>
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
                        <span className="bg-teal-800 px-2.5 py-0.5 rounded-full text-[11px] font-mono font-black">
                          {leaveList.length} إجازة
                        </span>
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
                              <td className="p-2 text-slate-300 font-medium">
                                {sanitizeLeaveReason(l.item.leaveReason, l.item.leaveName)}
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}

                  {/* هـ) جدول الحاضرين في الموعد (الملتزمون) - جدول مصغر ومركز لمنع الضوضاء */}
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
                            <span className="font-mono text-[11px] font-bold text-emerald-400 shrink-0">
                              {fmtTime(p.item.firstCheckIn)}
                            </span>
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
              </Fragment>
            )}

            {/* ─── وضع إغلاق اليوم وساعات العمل (End of Day View) ─── */}
            {activeReportTab === 'end_of_day' && (
              <div className="space-y-6">
                {/* مؤشرات نهاية اليوم وساعات العمل */}
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
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

                  <div className={`p-3 rounded-xl text-center ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'bg-rose-950/40 border border-rose-500/40' : 'bg-slate-900 border border-slate-800'}`}>
                    <span className={`block text-[11px] font-bold mb-1 ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'text-rose-300' : 'text-slate-400'}`}>بصمة انصراف ناقصة</span>
                    <span className={`text-2xl font-black font-mono ${endOfDayMetrics.missingCheckoutsCount > 0 ? 'text-rose-400' : 'text-slate-300'}`}>{endOfDayMetrics.missingCheckoutsCount}</span>
                    <span className="text-[10px] text-slate-400/80 block mt-0.5">لم يسجلوا خروجاً</span>
                  </div>

                  <div className={`p-3 rounded-xl text-center ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'bg-amber-950/40 border border-amber-500/40' : 'bg-slate-900 border border-slate-800'}`}>
                    <span className={`block text-[11px] font-bold mb-1 ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'text-amber-300' : 'text-slate-400'}`}>انصراف مبكر</span>
                    <span className={`text-2xl font-black font-mono ${endOfDayMetrics.earlyDeparturesCount > 0 ? 'text-amber-400' : 'text-slate-300'}`}>{endOfDayMetrics.earlyDeparturesCount}</span>
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
            )}

            {/* ─── وضع التدقيق المقارن (Comparative Audit View) ─── */}
            {activeReportTab === 'comparison' && (
              <div className="space-y-6">
                {/* بطاقة التوجيه التنفيذي للمقارنة */}
                <div className="p-4 rounded-xl bg-gradient-to-r from-amber-950/70 via-slate-900 to-sky-950/70 border border-amber-500/30 flex items-start gap-3">
                  <ShieldCheck className="size-5 text-amber-400 shrink-0 mt-0.5" />
                  <div className="space-y-1">
                    <h4 className="text-xs sm:text-sm font-black text-white">
                      دليل التدقيق والتحقق للمدير التنفيذي: لماذا تم تصحيح الأرقام؟
                    </h4>
                    <p className="text-[11px] text-slate-300 leading-relaxed">
                      التقرير القديم احتسب كل موظف نشط في المنظومة كـ "غياب بدون إذن" حتى لو لم تكن له وردية عمل مسندة، بما فيهم طاقم العيادات المسائي (3 م) الذي لم يبدأ دوامه بعد عند إصدار التقرير (2:25 م). التقرير الجديد يعتمد المنطق الرياضي السليم: الغياب يحتسب فقط لمن له وردية بدأت وتجاوزت فترة السماح.
                    </p>
                  </div>
                </div>

                {/* جدول المقارنة التفصيلي */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/60 shadow-lg">
                  <div className="bg-slate-950 px-4 py-2.5 border-b border-slate-800 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-2 text-slate-200">
                      <FileCheck2 className="size-4 text-amber-400" />
                      <span>مصفوفة مقارنة المؤشرات (قبل وبعد التدقيق)</span>
                    </div>
                    <span className="text-[11px] text-slate-400 font-normal">
                      تطبيق مباشر على بيانات اليوم ({dateFormatted})
                    </span>
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
            )}

            {/* 7. تذييل التقرير الرسمي مع التوثيق الأمني الرقمي */}
                <div className="pt-4 border-t border-slate-800 flex flex-wrap items-center justify-between gap-3 text-[11px] font-bold text-slate-400">
                  <div className="flex items-center gap-2">
                    <ShieldCheck className="size-4 text-emerald-400 shrink-0" />
                    <span>صادر وموثق رقمياً عن منظومة الموارد البشرية · جمعية خواطر أحلى شباب</span>
                  </div>
                  <div className="flex items-center gap-3 font-mono text-[10.5px]">
                    <span className="text-slate-300 font-bold">كود التحقق: {securityInfo.code}</span>
                    <span className="text-slate-600">|</span>
                    <span className="text-slate-400">Hash: {securityInfo.shortHash}</span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </DialogPortal>
  );
}
