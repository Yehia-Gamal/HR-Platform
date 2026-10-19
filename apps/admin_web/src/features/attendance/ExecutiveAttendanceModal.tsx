import { useEffect, useState } from 'react';
import { Calendar, Camera, Check, CheckCircle2, Clock3, Copy, Download, Loader2, MessageSquare, Plane, UserCheck, UserX, Users, X } from 'lucide-react';
import { useAttendanceRosterPage } from './useAttendanceDashboard';
import { DialogPortal } from '../../ui/DialogPortal';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';

function formatTime12(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    return new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short', timeZone: 'Africa/Cairo' }).format(new Date(iso));
  } catch {
    return String(iso);
  }
}

function formatMinutes(minutes: number | null | undefined): string {
  if (minutes == null || minutes <= 0) return '—';
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} د`;
  if (m === 0) return `${h} س`;
  return `${h} س و ${m} د`;
}

interface Props {
  dateIso: string;
  onClose: () => void;
}

export function ExecutiveAttendanceModal({ dateIso, onClose }: Props) {
  const [isCapturing, setIsCapturing] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const [copiedType, setCopiedType] = useState<'image' | 'text' | null>(null);

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

  // تمييز الطاقم الطبي للعيادات لوضعهم في نهاية أي جدول (مع استثناء مديريهم مثل مصطفى أحمد ويوسف رسمي)
  const isClinicMedicalStaff = (item: AttendanceRosterItem) => {
    if (item.isClinicMedicalStaff !== undefined && item.isClinicMedicalStaff !== null) {
      return item.isClinicMedicalStaff;
    }
    const dept = item.departmentName ?? '';
    const job = item.jobTitle ?? '';
    const isManager =
      item.employeeId === '4120ce3a-8999-453e-8d9d-acd8f3b5f04c' || // مصطفى أحمد كمال الدين
      item.employeeId === 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6' || // يوسف رسمي شعبان
      job.includes('مدير') ||
      job.includes('أدارة') ||
      job.includes('ادارة') ||
      job.includes('مسؤول') ||
      item.employeeName.includes('مصطفي أحمد كمال') ||
      item.employeeName.includes('يوسف رسمي');

    if (isManager) return false;
    return dept.includes('العيادات') || job === 'تمريض' || job === 'دكتورة المعمل' || job === 'موظف استقبال';
  };

  const sortClinicStaffToEnd = <T extends AttendanceRosterItem>(list: T[]): T[] => {
    return [...list].sort((a, b) => {
      const aClinic = isClinicMedicalStaff(a) ? 1 : 0;
      const bClinic = isClinicMedicalStaff(b) ? 1 : 0;
      if (aClinic !== bClinic) return aClinic - bClinic;
      return (a.employeeName ?? '').localeCompare(b.employeeName ?? '', 'ar');
    });
  };

  const items = rawItems.filter((i) => !isAttendanceExempt(i));
  const totalScheduled = items.length;

  // تصنيف الموظفين مع وضع الطاقم الطبي في نهاية كل جدول
  const onMission = sortClinicStaffToEnd(
    items.filter((i) => i.status === 'on_mission' || Boolean(i.hasMission) || (i.hasPendingRequest && i.pendingRequestType === 'mission'))
  );
  const onLeave = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.status === 'on_leave' ||
          Boolean(i.hasApprovedLeave) ||
          (i.hasPendingRequest && i.pendingRequestType !== 'mission' && i.pendingRequestType !== 'permit')) &&
        !i.hasMission &&
        i.pendingRequestType !== 'mission'
    )
  );
  const present = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.status === 'present' || i.status === 'late' || i.status === 'missing_checkout' || Boolean(i.firstCheckIn)) &&
        !i.hasMission &&
        !i.hasApprovedLeave &&
        i.status !== 'on_mission' &&
        i.status !== 'on_leave' &&
        !(i.hasPendingRequest && (i.pendingRequestType === 'leave' || i.pendingRequestType === 'mission'))
    )
  );
  const late = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.lateMinutes ?? 0) > 0 &&
        !i.hasMission &&
        !i.hasApprovedLeave &&
        i.status !== 'on_mission' &&
        i.status !== 'on_leave' &&
        !(i.hasPendingRequest && (i.pendingRequestType === 'leave' || i.pendingRequestType === 'mission'))
    )
  );
  const absent = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.status === 'absent' || i.status === 'unexcused_absent') &&
        !i.firstCheckIn &&
        !i.hasApprovedLeave &&
        !i.hasMission &&
        !i.hasPendingRequest
    )
  );
  const pendingRequests = items.filter((i) => Boolean(i.hasPendingRequest));

  const attendancePct = totalScheduled > 0 ? Math.round((present.length / totalScheduled) * 100) : 0;

  const dateFormatted = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`));
  const nowFormatted = new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date());

  // 1. التقاط الصورة وتنزيلها كملف PNG عالي الدقة
  const handleDownloadImage = async () => {
    const el = document.getElementById('executive-attendance-card');
    if (!el) return;
    setIsCapturing(true);
    setToastMessage('جاري توليد الصورة التنفيذية بجودة فائقة...');
    try {
      const h2cModule = await import('html2canvas');
      const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);
      const canvas = await html2canvas(el, {
        scale: 2.5,
        useCORS: true,
        logging: false,
        backgroundColor: '#0b1329',
        windowWidth: 1200,
      });

      canvas.toBlob((blob: Blob | null) => {
        if (!blob) {
          setToastMessage('تعذر حفظ الصورة.');
          return;
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `تقرير_حضور_المدير_التنفيذي_${dateIso}.png`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(() => URL.revokeObjectURL(url), 10_000);
        setToastMessage('تم تنزيل الصورة بنجاح ✅');
        setTimeout(() => setToastMessage(null), 3500);
      }, 'image/png');
    } catch (err) {
      console.error(err);
      setToastMessage('حدث خطأ أثناء حفظ الصورة.');
    } finally {
      setIsCapturing(false);
    }
  };

  // 2. نسخ الصورة للحافظة للصقها مباشرة في واتساب (Ctrl + V)
  const handleCopyImage = async () => {
    const el = document.getElementById('executive-attendance-card');
    if (!el) return;
    setIsCapturing(true);
    setToastMessage('جاري نسخ الصورة للحافظة...');
    try {
      const h2cModule = await import('html2canvas');
      const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);
      const canvas = await html2canvas(el, {
        scale: 2.5,
        useCORS: true,
        logging: false,
        backgroundColor: '#0b1329',
        windowWidth: 1200,
      });

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
            // البديل: تحميل الملف إذا كان المتصفح لا يدعم نسخ الصور
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

  // 3. نسخ ملخص واتساب نصي
  const handleCopyWhatsAppText = () => {
    const text = `📋 *تقرير الحضور والانصراف التنفيذي اليومي*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
⏰ *توقيت التقرير:* ${nowFormatted}
━━━━━━━━━━━━━━━━━━━━
📊 *المؤشرات الإجمالية:*
• إجمالي قوة العمل: ${totalScheduled} موظف
• الحضور الفعلي: ${present.length} موظف (${attendancePct}%)
• المتأخرون: ${late.length} موظف
• الغياب: ${absent.length} موظف
• الإجازات والمأموريات: ${onLeave.length + onMission.length} موظف
${pendingRequests.length > 0 ? `• طلبات معلّقة قيد المراجعة: ${pendingRequests.length} طلب` : ''}
━━━━━━━━━━━━━━━━━━━━
🟢 *الحاضرون (${present.length}):*
${
  present.length === 0
    ? '— لا يوجد حضور مسجل —'
    : present
        .map(
          (p, i) =>
            `${i + 1}. ${p.employeeName} (${p.departmentName ?? '—'}) · ${p.firstCheckIn ? formatTime12(p.firstCheckIn) : 'حاضر'}${
              (p.lateMinutes ?? 0) > 0 ? ` [تأخير ${p.lateMinutes} دقيقة]` : ''
            }`,
        )
        .join('\n')
}

🔴 *الغائبون (${absent.length}):*
${
  absent.length === 0
    ? '— لا يوجد غياب مسجل —'
    : absent
        .map((a, i) => `${i + 1}. ${a.employeeName} (${a.departmentName ?? '—'})${a.hasPendingRequest ? ` [⚠️ لديه طلب معلق: ${a.pendingRequestTitle}]` : ''}`)
        .join('\n')
}

🟡 *الإجازات والمأموريات (${onLeave.length + onMission.length}):*
${
  onLeave.length + onMission.length === 0
    ? '— لا يوجد موظفون في إجازة أو مأمورية —'
    : [
        ...onLeave.map((l, i) => {
          const isPending = Boolean(l.hasPendingRequest) && !l.hasApprovedLeave;
          const statusLabel = isPending ? 'طلب إجازة معلّق' : (l.leaveName ?? 'إجازة معتمدة');
          const reqNum = l.pendingRequestNumber ?? l.leaveRequestNumber;
          const reqPart = reqNum ? ` (#${reqNum})` : '';
          const titlePart = l.leaveTitle && l.leaveTitle !== l.leaveName && l.leaveTitle !== l.leaveReason ? ` [${l.leaveTitle}]` : '';
          const reasonPart = l.leaveReason ? ` - سبب: ${l.leaveReason}` : '';
          return `${i + 1}. ${l.employeeName} (${l.departmentName ?? '—'}) · ${statusLabel}${reqPart}${titlePart}${reasonPart}`;
        }),
        ...onMission.map((m, i) => {
          const isPending = Boolean(m.hasPendingRequest) && !m.hasApprovedLeave;
          const statusLabel = isPending ? 'طلب مأمورية معلّق' : 'مأمورية معتمدة';
          const reqNum = m.pendingRequestNumber ?? m.leaveRequestNumber;
          const reqPart = reqNum ? ` (#${reqNum})` : '';
          const destination = m.leaveTitle ?? m.pendingRequestTitle ?? m.leaveName;
          const destPart = destination ? ` [📍 ${destination}]` : '';
          const reasonPart = m.leaveReason ? ` - الغرض: ${m.leaveReason}` : '';
          return `${i + onLeave.length + 1}. ${m.employeeName} (${m.departmentName ?? '—'}) · ${statusLabel}${reqPart}${destPart}${reasonPart}`;
        }),
      ].join('\n')
}
━━━━━━━━━━━━━━━━━━━━
*صادر عن منظومة الموارد البشرية والمتابعة الميدانية*`;

    navigator.clipboard.writeText(text);
    setCopiedType('text');
    setToastMessage('تم نسخ ملخص واتساب للحافظة ✅');
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
                <h2 className="text-sm sm:text-base font-black text-white">تقرير الحضور التنفيذي (جاهز للمدير التنفيذي)</h2>
                <p className="text-[11px] text-slate-400">معاينة الصورة التنفيذية الرسمية قبل الإرسال للمدير التنفيذي</p>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-2">
              {/* زر نسخ الصورة */}
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

              {/* زر حفظ الصورة كملف PNG */}
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

              {/* زر نسخ النص */}
              <button
                type="button"
                onClick={handleCopyWhatsAppText}
                disabled={query.isLoading}
                className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 hover:border-emerald-500 transition-all"
                title="نسخ نص التقرير المنسق لإرساله كتابياً عبر واتساب"
              >
                {copiedType === 'text' ? <Check className="size-4 text-emerald-400" /> : <MessageSquare className="size-4 text-emerald-400" />}
                <span>نسخ نص واتساب</span>
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

          {/* إشعار عائم في حال النسخ أو الحفظ */}
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
                <p className="text-xs font-bold">جاري تجميع بيانات الحضور والانصراف التنفيذية...</p>
              </div>
            ) : query.isError ? (
              <div className="py-16 text-center text-red-400 text-xs font-bold">تعذر استخراج بيانات الكشف. يرجى إعادة المحاولة.</div>
            ) : (
              /* ─── البطاقة التنفيذية التي سيتم التقاطها كصورة (Executive Card) ─── */
              <div
                id="executive-attendance-card"
                className="w-full max-w-[1020px] rounded-2xl p-6 sm:p-8 shadow-2xl font-sans shrink-0"
                dir="rtl"
                style={{ minWidth: '850px', backgroundColor: '#0b1329', color: '#f8fafc', border: '1px solid rgba(255, 255, 255, 0.1)' }}
              >
                {/* 1. الترويسة الملكية للجمعية */}
              <div className="flex items-center justify-between pb-5 border-b border-slate-800 mb-6">
                <div className="flex items-center gap-3.5">
                  <div className="size-12 rounded-2xl bg-sky-600 text-white flex items-center justify-center font-black text-xl shadow-lg">أحلى</div>
                  <div>
                    <h1 className="text-xl font-black text-white tracking-tight">جمعية خواطر أحلى شباب</h1>
                    <p className="text-xs font-bold text-slate-400 mt-0.5">منظومة الإدارة والمتابعة المؤسسية · الإدارة التنفيذية</p>
                  </div>
                </div>

                <div className="text-start bg-slate-900 border border-slate-700/80 rounded-xl px-4 py-2">
                  <div className="flex items-center gap-1.5 text-xs font-black text-slate-200">
                    <Calendar className="size-3.5 text-sky-400" />
                    <span>{dateFormatted}</span>
                  </div>
                  <div className="flex items-center gap-1.5 text-[11px] font-bold text-slate-400 mt-0.5">
                    <Clock3 className="size-3 text-slate-400" />
                    <span>توقيت الإصدار: {nowFormatted}</span>
                  </div>
                </div>
              </div>

              {/* عنوان الكشف الصريح */}
              <div className="text-center mb-6">
                <h2 className="text-base font-black text-sky-400 inline-block px-6 py-1.5 bg-sky-500/10 rounded-full border border-sky-500/30">
                  كشف المتابعة اليومية للحضور والانصراف
                </h2>
              </div>

              {/* 2. شريط المؤشرات الرقمية (KPI Strip) */}
              <div className="grid grid-cols-5 gap-3 mb-6">
                <div className="p-3.5 rounded-xl bg-slate-900 border border-slate-800 text-center">
                  <span className="block text-[11px] font-bold text-slate-400 mb-1">إجمالي قوة العمل</span>
                  <span className="text-2xl font-black text-white">{totalScheduled}</span>
                  <span className="text-[10px] text-slate-500 block mt-0.5">موظف مجدول</span>
                </div>

                <div className="p-3.5 rounded-xl bg-emerald-950/40 border border-emerald-500/30 text-center">
                  <span className="block text-[11px] font-bold text-emerald-300 mb-1">الحضور الفعلي</span>
                  <span className="text-2xl font-black text-emerald-400">{present.length}</span>
                  <span className="text-[10px] font-bold text-emerald-400/80 block mt-0.5">نسبة: {attendancePct}%</span>
                </div>

                <div className="p-3.5 rounded-xl bg-amber-950/40 border border-amber-500/30 text-center">
                  <span className="block text-[11px] font-bold text-amber-300 mb-1">المتأخرون</span>
                  <span className="text-2xl font-black text-amber-400">{late.length}</span>
                  <span className="text-[10px] text-amber-400/80 block mt-0.5">حضروا بعد الموعد</span>
                </div>

                <div className="p-3.5 rounded-xl bg-rose-950/40 border border-rose-500/30 text-center">
                  <span className="block text-[11px] font-bold text-rose-300 mb-1">الغياب</span>
                  <span className="text-2xl font-black text-rose-400">{absent.length}</span>
                  <span className="text-[10px] text-rose-400/80 block mt-0.5">{absent.length > 0 ? 'لم يسجلوا حضوراً' : 'لا يوجد غياب'}</span>
                </div>

                <div className="p-3.5 rounded-xl bg-indigo-950/40 border border-indigo-500/30 text-center">
                  <span className="block text-[11px] font-bold text-indigo-300 mb-1">إجازات ومأموريات</span>
                  <span className="text-2xl font-black text-indigo-400">{onLeave.length + onMission.length}</span>
                  <span className="text-[10px] text-indigo-400/80 block mt-0.5">بعذر رسمي أو معلق</span>
                </div>
              </div>

              {/* 3. الجداول التنفيذية الثلاثة */}
              <div className="space-y-6">
                {/* أ) جدول الحاضرين */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-emerald-900/70 border-b border-emerald-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <UserCheck className="size-4 text-emerald-400" />
                      <span>قائمة الحاضرين (المتواجدون بالمجمع)</span>
                    </div>
                    <span className="bg-emerald-800 px-2.5 py-0.5 rounded-full text-[11px]">{present.length} موظف</span>
                  </div>

                  {present.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا يوجد حضور مسجل لهذا اليوم حتى الآن.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">الوردية</th>
                          <th className="p-2">وقت الحضور</th>
                          <th className="p-2">وقت الانصراف</th>
                          <th className="p-2">الحالة</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800 font-medium">
                        {present.map((p, idx) => (
                          <tr key={p.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/40' : 'bg-slate-900/40'}>
                            <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                            <td className="p-2 font-black text-white">{p.employeeName}</td>
                            <td className="p-2 text-slate-300">
                              <span>{p.departmentName ?? '—'}</span>
                              {p.branchName ? <span className="text-slate-400 text-[10px] block">{p.branchName}</span> : null}
                            </td>
                            <td className="p-2 text-slate-300">{p.shiftName ?? '—'}</td>
                            <td className="p-2 font-bold text-emerald-400">{p.firstCheckIn ? formatTime12(p.firstCheckIn) : '—'}</td>
                            <td className="p-2 text-emerald-300 font-bold">{p.lastCheckOut ? formatTime12(p.lastCheckOut) : 'متواجد حالياً في المجمع'}</td>
                            <td className="p-2">
                              {(p.lateMinutes ?? 0) > 0 ? (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30 font-black text-[10px]">
                                  متأخر {formatMinutes(p.lateMinutes)}
                                </span>
                              ) : (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-bold text-[10px]">في الموعد</span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* ب) جدول الغائبين */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-rose-900/70 border-b border-rose-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <UserX className="size-4 text-rose-400" />
                      <span>قائمة الغائبين بدون إذن</span>
                    </div>
                    <span className="bg-rose-800 px-2.5 py-0.5 rounded-full text-[11px]">{absent.length} موظف</span>
                  </div>

                  {absent.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا يوجد غياب غير مبرر لهذا اليوم.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">الوردية المقررة</th>
                          <th className="p-2">موقف العذر والطلب</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800 font-medium">
                        {absent.map((a, idx) => (
                          <tr key={a.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/40' : 'bg-slate-900/40'}>
                            <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                            <td className="p-2 font-black text-white">{a.employeeName}</td>
                            <td className="p-2 text-slate-300">
                              <span>{a.departmentName ?? '—'}</span>
                              {a.branchName ? <span className="text-slate-400 text-[10px] block">{a.branchName}</span> : null}
                            </td>
                            <td className="p-2 text-slate-300">{a.shiftName ?? '—'}</td>
                            <td className="p-2">
                              <span className="inline-block px-1.5 py-0.5 rounded bg-rose-500/20 text-rose-300 border border-rose-500/30 font-bold text-[10px]">غياب بدون إذن</span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* ج) جدول الإجازات والمأموريات */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-indigo-900/70 border-b border-indigo-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <Plane className="size-4 text-indigo-400" />
                      <span>قائمة الإجازات والمأموريات الرسمية والطلبات</span>
                    </div>
                    <span className="bg-indigo-800 px-2.5 py-0.5 rounded-full text-[11px]">{onLeave.length + onMission.length} موظف</span>
                  </div>

                  {onLeave.length + onMission.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا توجد إجازات أو مأموريات مقررة لهذا اليوم.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">النوع والمعاملة</th>
                          <th className="p-2">السبب والبيان الرسمي</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800 font-medium">
                        {[...onLeave, ...onMission].map((item, idx) => {
                          const isMission = item.status === 'on_mission' || item.hasMission || item.pendingRequestType === 'mission';
                          const isPending = Boolean(item.hasPendingRequest) && !item.hasApprovedLeave;
                          return (
                            <tr key={item.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/40' : 'bg-slate-900/40'}>
                              <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                              <td className="p-2 font-black text-white">{item.employeeName}</td>
                              <td className="p-2 text-slate-300">
                                <span>{item.departmentName ?? '—'}</span>
                                {item.branchName ? <span className="text-slate-400 text-[10px] block">{item.branchName}</span> : null}
                              </td>
                              <td className="p-2">
                                <span
                                  className={`inline-block px-1.5 py-0.5 rounded font-black text-[10px] ${
                                    isPending
                                      ? isMission
                                        ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                                        : 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                                      : isMission
                                      ? 'bg-sky-500/20 text-sky-300 border border-sky-500/30'
                                      : 'bg-teal-500/20 text-teal-300 border border-teal-500/30'
                                  }`}
                                >
                                  {(() => {
                                    const reqNum = item.pendingRequestNumber ?? item.leaveRequestNumber;
                                    const reqSuffix = reqNum ? ` (#${reqNum})` : '';
                                    if (isPending) {
                                      return isMission ? `⏳ طلب مأمورية معلّق${reqSuffix}` : `⏳ طلب إجازة معلّق${reqSuffix}`;
                                    }
                                    return isMission ? `مأمورية رسمية${reqSuffix}` : `${item.leaveName ?? 'إجازة معتمدة'}${reqSuffix}`;
                                  })()}
                                </span>
                              </td>
                              <td className="p-2 text-slate-200 font-bold">
                                {isMission ? (
                                  <div className="flex flex-col gap-0.5">
                                    {item.leaveTitle || item.leaveName || item.pendingRequestTitle ? (
                                      <span className="text-white font-black text-[11px]">
                                        📍 {item.leaveTitle ?? item.pendingRequestTitle ?? item.leaveName}
                                      </span>
                                    ) : null}
                                    {item.leaveReason ? (
                                      <span className="text-slate-300 font-medium text-[10.5px]">💬 الغرض: {item.leaveReason}</span>
                                    ) : (
                                      <span className="text-slate-400 font-normal text-[10.5px]">مأمورية رسمية</span>
                                    )}
                                  </div>
                                ) : (
                                  <div className="flex flex-col gap-0.5">
                                    {item.leaveTitle && item.leaveTitle !== item.leaveName && item.leaveTitle !== item.leaveReason ? (
                                      <span className="text-white font-black text-[11px]">📌 {item.leaveTitle}</span>
                                    ) : null}
                                    {item.leaveReason ? (
                                      <span className="text-slate-300 font-medium text-[10.5px]">💬 السبب: {item.leaveReason}</span>
                                    ) : (
                                      <span className="text-slate-400 font-normal text-[10.5px]">— معتمدة ومسجلة نظامياً</span>
                                    )}
                                  </div>
                                )}
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>

              {/* 4. تذييل التقرير الرسمي */}
              <div className="mt-8 pt-4 border-t border-slate-800 flex items-center justify-between text-[11px] font-bold text-slate-400">
                <span>صادر عن منظومة الموارد البشرية والمتابعة الميدانية · جمعية خواطر أحلى شباب</span>
                <span className="text-slate-400">تقرير رسمي معتمد للإرسال للإدارة التنفيذية</span>
                <span className="font-mono text-[10px]">كود التحقق: {dateIso.replace(/-/g, '')}-EXEC</span>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  </DialogPortal>
  );
}
