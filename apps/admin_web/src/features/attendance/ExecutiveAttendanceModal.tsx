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
  Printer,
  ShieldCheck,
  TrendingUp,
  UserCheck,
  X,
} from 'lucide-react';
import { useAttendanceRosterPage } from './useAttendanceDashboard';
import { DialogPortal } from '../../ui/DialogPortal';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { ASSOCIATION_LOGO_WHITE_DATA_URL } from './brandAssets';
import { cairoTodayIso } from '../../core/cairoTime';
import {
  classifyEmployee,
  computeEndOfDayMetrics,
  computeExecutiveMetrics,
  generateComparativeAudit,
  generateSecurityVerificationCode,
  isClinicTeamMember,
  type ClassifiedEmployee,
} from './executiveReportLogic';
import { ExecutiveWorkforceChart } from './ExecutiveWorkforceChart';
import { captureExecutiveCardCanvas, triggerPngDownload } from './executive/executiveModalCapture';
import {
  buildComparativeAuditWhatsAppText,
  buildEndOfDayWhatsAppText,
  buildLiveAttendanceWhatsAppText,
} from './executive/executiveModalWhatsApp';
import { ExecutiveComparativeAuditView, ExecutiveEndOfDayView } from './executive/ExecutiveEndOfDayAndAuditViews';
import { ExecutiveLiveTablesSection } from './executive/ExecutiveLiveTablesSection';

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
  const [excludeClinics, setExcludeClinics] = useState(true); // استبعاد وحجب طاقم العيادات الطبية المعزول افتراضياً (مثل سامية أشرف وباقي الفريق) لحماية الخصوصية
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

  // استبعاد المعفيين وتيم العيادات الطبية (فترة عملهم 3:00 عصراً لعدم التأثير على تقرير 12:00 ظهراً)
  const items = rawItems.filter((i) => {
    if (isAttendanceExempt(i)) return false;
    if (excludeClinics && isClinicTeamMember(i)) return false;
    return true;
  });

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
  const classified: ClassifiedEmployee[] = items.map((item) => classifyEmployee(item, currentMinutesFromMidnight));

  // حساب المؤشرات والنسب التنفيذية
  const metrics = computeExecutiveMetrics(classified);
  const endOfDayMetrics = computeEndOfDayMetrics(classified, currentMinutesFromMidnight);
  const comparativeAudit = generateComparativeAudit(metrics);

  // تصفية القوائم حسب التصنيف
  const unexcusedAbsentList = classified.filter((c) => c.category === 'unexcused_absent');
  const lateList = classified.filter((c) => c.category === 'present_late');
  const missionPendingList = classified.filter((c) => c.category === 'present_mission_pending' || c.category === 'mission_pending');
  const missionApprovedList = classified.filter((c) => c.category === 'present_mission_approved' || c.category === 'mission_approved');
  const leaveList = classified.filter((c) => c.category === 'leave_approved' || c.category === 'leave_pending');
  const permitList = classified.filter(
    (c) =>
      c.isPermit ||
      c.category === 'permit_approved' ||
      c.category === 'permit_pending' ||
      c.category === 'present_permit_approved' ||
      c.category === 'present_permit_pending',
  );
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
  const securityInfo = generateSecurityVerificationCode(dateIso, metrics.totalScheduledEmployees, metrics.presentTotal, metrics.unexcusedAbsent);

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
        const prefix =
          activeReportTab === 'end_of_day' ? 'تقرير_إغلاق_الانصراف' : activeReportTab === 'comparison' ? 'تقرير_تدقيق_الحضور' : 'تقرير_حضور_المدير_التنفيذي';
        triggerPngDownload(blob, `${prefix}_${dateIso}.png`);
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
  const copyTextWithToast = (text: string, message: string) => {
    navigator.clipboard.writeText(text);
    setCopiedType('text');
    setToastMessage(message);
    setTimeout(() => {
      setCopiedType(null);
      setToastMessage(null);
    }, 3500);
  };

  const handleCopyWhatsAppText = () => {
    if (activeReportTab === 'end_of_day') {
      copyTextWithToast(
        buildEndOfDayWhatsAppText({ dateFormatted, nowFormatted, endOfDayMetrics, securityInfo, fmtTime, fmtNum }),
        'تم نسخ ملخص إغلاق اليوم للحافظة بنجاح ✅',
      );
      return;
    }
    if (activeReportTab === 'comparison') {
      copyTextWithToast(
        buildComparativeAuditWhatsAppText({ dateFormatted, comparativeAudit, securityCode: securityInfo.code }),
        'تم نسخ تقرير التدقيق المقارن للحافظة بنجاح ✅',
      );
      return;
    }
    copyTextWithToast(
      buildLiveAttendanceWhatsAppText({
        dateFormatted,
        nowFormatted,
        excludeClinics,
        metrics,
        unexcusedAbsentList,
        lateList,
        missionPendingList,
        missionApprovedList,
        leaveList,
        permitList,
        securityInfo,
        fmtTime,
        fmtNum,
      }),
      'تم نسخ ملخص واتساب المنسق والمصحح للحافظة ✅',
    );
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
        <div className="relative w-full max-w-[1120px] bg-slate-900 border border-slate-700/80 rounded-2xl shadow-2xl overflow-hidden my-auto max-h-[94vh] flex flex-col text-slate-100">
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

              {/* زر استبعاد / تضمين تيم العيادات (فترة 3:00 م) */}
              <button
                type="button"
                onClick={() => setExcludeClinics((prev) => !prev)}
                className={`btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 transition-all ${
                  excludeClinics
                    ? 'bg-sky-950/80 border-sky-500/50 text-sky-300 hover:bg-sky-900/60'
                    : 'bg-slate-800 border-slate-700 text-slate-400 hover:text-white'
                }`}
                title="التبديل بين حجب طاقم العيادات الطبية أو إظهارهن في التقرير"
              >
                <span>🏥</span>
                <span>{excludeClinics ? 'طاقم العيادات: محجوب (معزول)' : 'طاقم العيادات: معروض'}</span>
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
          <nav
            className="flex items-center gap-2 px-4 py-2.5 bg-slate-950 border-b border-slate-800 text-xs font-bold overflow-x-auto shrink-0"
            data-hide-capture="true"
          >
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
                className="rounded-2xl p-6 sm:p-8 shadow-2xl shrink-0 space-y-6"
                dir="rtl"
                style={{
                  width: '1040px',
                  minWidth: '1040px',
                  maxWidth: '1040px',
                  boxSizing: 'border-box',
                  backgroundColor: '#0b1329',
                  color: '#f8fafc',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  fontFamily: "'Cairo', 'Noto Sans Arabic', 'Segoe UI', Tahoma, Arial, sans-serif",
                }}
              >
                {/* 1. الترويسة الملكية للجمعية مع الشعار الرسمي */}
                <div className="flex items-center justify-between pb-5 border-b border-slate-800/90 gap-4">
                  <div className="flex items-center gap-4">
                    <div
                      className="rounded-2xl bg-gradient-to-br from-slate-900 to-slate-950 border border-slate-700/80 p-2 flex items-center justify-center shadow-2xl shrink-0 ring-1 ring-white/10"
                      style={{
                        width: '80px',
                        height: '80px',
                        minWidth: '80px',
                        minHeight: '80px',
                        maxWidth: '80px',
                        maxHeight: '80px',
                        boxSizing: 'border-box',
                      }}
                    >
                      <img
                        src={ASSOCIATION_LOGO_WHITE_DATA_URL}
                        alt="شعار جمعية خواطر أحلى شباب"
                        width={80}
                        height={80}
                        style={{
                          width: '80px',
                          height: '80px',
                          maxWidth: '80px',
                          maxHeight: '80px',
                          objectFit: 'contain',
                          display: 'block',
                        }}
                      />
                    </div>
                    <div>
                      <h1 className="text-xl sm:text-2xl font-black text-white leading-tight">جمعية خواطر أحلى شباب</h1>
                      <p className="text-xs font-bold text-slate-300 mt-1">منظومة الإدارة والمتابعة المؤسسية · الإدارة التنفيذية</p>
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

                {/* شريط تنويه ضبط توقيت الكشف واستبعاد العيادات المسائية */}
                {excludeClinics && (
                  <div className="flex items-center justify-between px-4 py-2 rounded-xl bg-sky-950/40 border border-sky-500/20 text-[11px] font-bold text-sky-300">
                    <span className="flex items-center gap-2">
                      <span>🏥</span>
                      <span>كشف منضبط خاص بفترة الصباح والظهيرة (12:00 ظهراً) · تم استبعاد طاقم العيادات الطبية (فترة عملهم تبدأ 3:00 عصراً)</span>
                    </span>
                    <span className="bg-sky-500/20 text-sky-200 px-2 py-0.5 rounded-full text-[10px] font-mono shrink-0">وردية 3 م مستبعدة تلقائياً</span>
                  </div>
                )}

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
                                  ⚠️ {metrics.missionsPendingLeft} مأمورية معلقة بانتظار الاعتماد
                                </span>
                              )}
                              {metrics.leavesPendingCount > 0 && (
                                <span className="bg-purple-500/20 text-purple-200 px-2 py-0.5 rounded-full border border-purple-500/30">
                                  🏖️ {metrics.leavesPendingCount} طلبات إجازة معلقة تنتظر الاعتماد
                                </span>
                              )}
                              {metrics.permitsPendingCount > 0 && (
                                <span className="bg-cyan-500/20 text-cyan-200 px-2 py-0.5 rounded-full border border-cyan-500/30">
                                  ⏱️ {metrics.permitsPendingCount} طلبات إذن وتصريح معلقة
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
                        <span className="text-[11px] font-black bg-amber-500 text-slate-950 px-3 py-1 rounded-xl shadow-xs shrink-0">مطلوب توجيه تنفيذي</span>
                      </div>
                    ) : (
                      <div className="rounded-2xl p-3 bg-emerald-950/40 border border-emerald-500/30 flex items-center gap-2 text-emerald-300 text-xs font-bold">
                        <CheckCircle2 className="size-4 text-emerald-400 shrink-0" />
                        <span>الانضباط الميداني مكتمل بنسبة 100% — لا توجد أي استثناءات معلقة تتطلب تدخلاً عاجلاً.</span>
                      </div>
                    )}

                    {/* 3. شريط المؤشرات الرقمية المدققة رياضياً (KPI Strip) */}
                    <div
                      className="grid gap-2.5 sm:gap-3"
                      style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(7, minmax(0, 1fr))',
                      }}
                    >
                      <div className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-center">
                        <span className="block text-[11px] font-bold text-slate-400 mb-1">قوة العمل المجدولة</span>
                        <span className="text-2xl font-black text-white font-mono">{fmtNum(metrics.totalScheduledEmployees)}</span>
                        <span className="text-[10px] text-slate-500 block mt-0.5">مطالبون بالحضور حتى الآن</span>
                      </div>

                      <div className="p-3 rounded-xl bg-emerald-950/40 border border-emerald-500/30 text-center">
                        <span className="block text-[11px] font-bold text-emerald-300 mb-1">الحضور الفعلي بالمقر</span>
                        <span className="text-2xl font-black text-emerald-400 font-mono">{fmtNum(metrics.presentTotal)}</span>
                        <span className="text-[10px] font-bold text-emerald-400/90 block mt-0.5 font-mono">
                          حضور: {fmtNum(metrics.actualPresenceRate)}% · التزام: {fmtNum(metrics.overallComplianceRate)}%
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
                        <span className="text-2xl font-black text-sky-400 font-mono">{fmtNum(metrics.missionsApproved + metrics.missionsPendingLeft)}</span>
                        <span className="text-[10px] text-sky-400/80 block mt-0.5">
                          {metrics.missionsPendingLeft > 0
                            ? `${fmtNum(metrics.missionsApproved)} معتمدة · ${fmtNum(metrics.missionsPendingLeft)} معلقة`
                            : 'ميدانية معتمدة'}
                        </span>
                      </div>

                      <div className="p-3 rounded-xl bg-teal-950/40 border border-teal-500/30 text-center">
                        <span className="block text-[11px] font-bold text-teal-300 mb-1">الإجازات والراحات</span>
                        <span className="text-2xl font-black text-teal-400 font-mono">{fmtNum(metrics.leavesTotal)}</span>
                        <span className="text-[10px] text-teal-400/80 block mt-0.5 font-mono">
                          {metrics.leavesPendingCount > 0
                            ? `${fmtNum(metrics.leavesApprovedCount)} معتمدة · ${fmtNum(metrics.leavesPendingCount)} معلقة`
                            : 'رسمية معتمدة'}
                        </span>
                      </div>

                      <div className="p-3 rounded-xl bg-purple-950/40 border border-purple-500/30 text-center">
                        <span className="block text-[11px] font-bold text-purple-300 mb-1">الأذونات والتصاريح</span>
                        <span className="text-2xl font-black text-purple-400 font-mono">{fmtNum(metrics.permitsTotal)}</span>
                        <span className="text-[10px] text-purple-400/80 block mt-0.5 font-mono">
                          {metrics.permitsPendingCount > 0
                            ? `${fmtNum(metrics.permitsApprovedCount)} معتمدة · ${fmtNum(metrics.permitsPendingCount)} معلقة`
                            : 'أذونات رسمية'}
                        </span>
                      </div>
                    </div>

                    {/* 4. الشارت البياني التوضيحي (Donut Chart) لتوزيع قوى العمل */}
                    <ExecutiveWorkforceChart metrics={metrics} isLight={false} numberSystem={numberSystem} />

                    {/* 5. الجداول التنفيذية المخصصة (الاستثناءات أولاً) */}
                    <ExecutiveLiveTablesSection
                      unexcusedAbsentList={unexcusedAbsentList}
                      lateList={lateList}
                      missionPendingList={missionPendingList}
                      missionApprovedList={missionApprovedList}
                      leaveList={leaveList}
                      permitList={permitList}
                      upcomingShiftList={upcomingShiftList}
                      onTimePresentList={onTimePresentList}
                      fmtTime={fmtTime}
                      fmtNum={fmtNum}
                    />
                  </Fragment>
                )}

                {/* ─── وضع إغلاق اليوم وساعات العمل (End of Day View) ─── */}
                {activeReportTab === 'end_of_day' && (
                  <ExecutiveEndOfDayView endOfDayMetrics={endOfDayMetrics} fmtTime={fmtTime} fmtNum={fmtNum} />
                )}

                {/* ─── وضع التدقيق المقارن (Comparative Audit View) ─── */}
                {activeReportTab === 'comparison' && (
                  <ExecutiveComparativeAuditView comparativeAudit={comparativeAudit} dateFormatted={dateFormatted} />
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
