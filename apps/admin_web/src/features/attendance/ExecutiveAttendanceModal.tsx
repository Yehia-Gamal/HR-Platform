import { Fragment, useEffect, useState } from 'react';
import { Calendar, Camera, Check, CheckCircle2, Clock3, Copy, Download, Loader2, MessageSquare, Plane, UserCheck, UserX, Users, X } from 'lucide-react';
import { useAttendanceRosterPage } from './useAttendanceDashboard';
import { DialogPortal } from '../../ui/DialogPortal';
import type { AttendanceRosterItem } from '@ahla/shared-contracts';
import { ASSOCIATION_LOGO_WHITE_DATA_URL } from './brandAssets';

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

  // هل الموظف في مأمورية (معتمدة أو طلب معلق)؟
  const isMissionItem = (i: AttendanceRosterItem): boolean => {
    return i.status === 'on_mission' || Boolean(i.hasMission) || (Boolean(i.hasPendingRequest) && i.pendingRequestType === 'mission');
  };

  // هل الموظف في إجازة (معتمدة أو طلب معلق)؟
  const isLeaveItem = (i: AttendanceRosterItem): boolean => {
    return (
      (i.status === 'on_leave' ||
        Boolean(i.hasApprovedLeave) ||
        (Boolean(i.hasPendingRequest) && i.pendingRequestType === 'leave')) &&
      !isMissionItem(i)
    );
  };

  // فرز قائمة الحاضرين:
  // 1. الملتزمون في الموعد والمتواجدون بالمجمع أولاً
  // 2. الموظفون الذين بصموا حضور ثم خرجوا في مأموريات عمل ميدانية (زي محمد سيد)
  // 3. المتأخرون في نهاية القائمة مع إبرازهم
  const sortPresentRoster = (list: AttendanceRosterItem[]): AttendanceRosterItem[] => {
    return [...list].sort((a, b) => {
      const getPriority = (item: AttendanceRosterItem): number => {
        if ((item.lateMinutes ?? 0) > 0) return 3;
        if (isMissionItem(item)) return 2;
        return 1;
      };

      const pA = getPriority(a);
      const pB = getPriority(b);
      if (pA !== pB) return pA - pB;

      // الطاقم الطبي في نهاية كل فئة
      const aClinic = isClinicMedicalStaff(a) ? 1 : 0;
      const bClinic = isClinicMedicalStaff(b) ? 1 : 0;
      if (aClinic !== bClinic) return aClinic - bClinic;

      // ترتيب المتأخرين تنازلياً حسب مدة التأخير
      if (pA === 3 && pB === 3) {
        const diff = (b.lateMinutes ?? 0) - (a.lateMinutes ?? 0);
        if (diff !== 0) return diff;
      }

      return (a.employeeName ?? '').localeCompare(b.employeeName ?? '', 'ar');
    });
  };

  const items = rawItems.filter((i) => !isAttendanceExempt(i));
  const totalScheduled = items.length;

  // تصنيف الموظفين
  const onMission = sortClinicStaffToEnd(items.filter((i) => isMissionItem(i)));
  const onLeave = sortClinicStaffToEnd(items.filter((i) => isLeaveItem(i)));

  // الحضور الفعلي: كل من سجل بصمة حضور اليوم، أو حالته حضور/تأخير
  // يشمل المتواجدين بالمجمع، وأيضاً من بصموا حضور وخرجوا في مأمورية ميدانية (مثل محمد سيد)
  const present = sortPresentRoster(
    items.filter(
      (i) =>
        !isLeaveItem(i) &&
        (Boolean(i.firstCheckIn) ||
          i.status === 'present' ||
          i.status === 'late' ||
          i.status === 'missing_checkout')
    )
  );

  const late = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.lateMinutes ?? 0) > 0 &&
        Boolean(i.firstCheckIn) &&
        !isLeaveItem(i)
    )
  );

  const absent = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        !i.firstCheckIn &&
        !isLeaveItem(i) &&
        !isMissionItem(i) &&
        i.status !== 'present' &&
        i.status !== 'late'
    )
  );
  const pendingRequests = items.filter((i) => Boolean(i.hasPendingRequest));

  const attendancePct = totalScheduled > 0 ? Math.round((present.length / totalScheduled) * 100) : 0;

  const dateFormatted = new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full' }).format(new Date(`${dateIso}T00:00:00`));
  const nowFormatted = new Intl.DateTimeFormat('ar-EG', { timeStyle: 'short' }).format(new Date());

  // دالة مساعدة مركزية لالتقاط صورة فائقة الدقة لكامل الكشف من البداية وحتى التذييل بلا أي اقتطاع
  const captureExecutiveCardCanvas = async (el: HTMLElement): Promise<HTMLCanvasElement> => {
    const h2cModule = await import('html2canvas-pro');
    const html2canvas = typeof h2cModule.default === 'function' ? h2cModule.default : (h2cModule as any);

    // 1. التأكد التام من اكتمال تحميل الشعار والخطوط قبل الالتقاط
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

    // 2. حساب الأبعاد الحقيقية الكاملة لكامل الكرت شاملاً كل الجداول حتى التذييل
    const fullWidth = Math.max(el.scrollWidth, el.offsetWidth, 1040);
    const fullHeight = Math.max(el.scrollHeight, el.offsetHeight);

    // 3. إعادة ضبط التمرير في الحاوية الأب مؤقتاً لتفادي إزاحات التمرير
    const scrollParent = el.parentElement;
    const prevScrollTop = scrollParent ? scrollParent.scrollTop : 0;
    if (scrollParent) {
      scrollParent.scrollTop = 0;
    }

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
          // فك قيود الارتفاع وتجاوز المحتوى (overflow) في الشجرة المستنسخة لضمان رسم كامل المحتوى
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
      if (scrollParent) {
        scrollParent.scrollTop = prevScrollTop;
      }
    }
  };

  // 1. التقاط الصورة وتنزيلها كملف PNG عالي الدقة لكامل الكشف
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
        a.download = `تقرير_حضور_المدير_التنفيذي_${dateIso}.png`;
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

  // 2. نسخ الصورة للحافظة للصقها مباشرة في واتساب (Ctrl + V)
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
            setToastMessage('تم نسخ الصورة الكاملة للحافظة! يمكنك الآن لصقها (Ctrl + V) في واتساب مباشرة ✅');
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
• المأموريات الرسمية: ${onMission.length} موظف
• الإجازات الرسمية: ${onLeave.length} موظف
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
            }${
              isMissionItem(p) ? ` [✈️ خرج لمأمورية${(p.leaveTitle ?? p.pendingRequestTitle) ? `: ${p.leaveTitle ?? p.pendingRequestTitle}` : ''}]` : ''
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

✈️ *المأموريات الرسمية والتكليفات (${onMission.length}):*
${
  onMission.length === 0
    ? '— لا توجد مأموريات مسجلة —'
    : onMission
        .map((m, i) => {
          const isPending = Boolean(m.hasPendingRequest) && !m.hasApprovedLeave;
          const statusLabel = isPending ? 'طلب مأمورية معلّق' : 'مأمورية معتمدة';
          const reqNum = m.pendingRequestNumber ?? m.leaveRequestNumber;
          const reqPart = reqNum ? ` (#${reqNum})` : '';
          const destination = m.leaveTitle ?? m.pendingRequestTitle ?? m.leaveName;
          const destPart = destination ? ` [📍 ${destination}]` : '';
          const reasonPart = m.leaveReason ? ` - الغرض: ${m.leaveReason}` : '';
          const checkInPart = m.firstCheckIn ? ` (سجل حضور ${formatTime12(m.firstCheckIn)})` : '';
          return `${i + 1}. ${m.employeeName} (${m.departmentName ?? '—'}) · ${statusLabel}${reqPart}${destPart}${reasonPart}${checkInPart}`;
        })
        .join('\n')
}

🏖️ *الإجازات والراحات الرسمية (${onLeave.length}):*
${
  onLeave.length === 0
    ? '— لا توجد إجازات مسجلة —'
    : onLeave
        .map((l, i) => {
          const isPending = Boolean(l.hasPendingRequest) && !l.hasApprovedLeave;
          const statusLabel = isPending ? 'طلب إجازة معلّق' : (l.leaveName ?? 'إجازة معتمدة');
          const reqNum = l.pendingRequestNumber ?? l.leaveRequestNumber;
          const reqPart = reqNum ? ` (#${reqNum})` : '';
          const titlePart = l.leaveTitle && l.leaveTitle !== l.leaveName && l.leaveTitle !== l.leaveReason ? ` [${l.leaveTitle}]` : '';
          const reasonPart = l.leaveReason ? ` - سبب: ${l.leaveReason}` : '';
          return `${i + 1}. ${l.employeeName} (${l.departmentName ?? '—'}) · ${statusLabel}${reqPart}${titlePart}${reasonPart}`;
        })
        .join('\n')
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
                className="w-full max-w-[1040px] rounded-2xl p-6 sm:p-8 shadow-2xl shrink-0"
                dir="rtl"
                style={{
                  minWidth: '880px',
                  backgroundColor: '#0b1329',
                  color: '#f8fafc',
                  border: '1px solid rgba(255, 255, 255, 0.12)',
                  fontFamily: "'Cairo', 'Noto Sans Arabic', 'Segoe UI', Tahoma, Arial, sans-serif",
                  letterSpacing: 'normal',
                }}
              >
                {/* 1. الترويسة الملكية للجمعية مع الشعار الرسمي */}
                <div className="flex items-center justify-between pb-5 border-b border-slate-800/90 mb-6 gap-4">
                  <div className="flex items-center gap-4">
                    <div className="size-20 rounded-2xl bg-gradient-to-br from-slate-900 to-slate-950 border border-slate-700/80 p-2 flex items-center justify-center shadow-2xl shrink-0 ring-1 ring-white/10">
                      <img
                        src={ASSOCIATION_LOGO_WHITE_DATA_URL}
                        alt="شعار جمعية خواطر أحلى شباب"
                        className="size-full object-contain"
                      />
                    </div>
                    <div>
                      <h1 className="text-xl sm:text-2xl font-black text-white leading-tight" style={{ letterSpacing: 'normal' }}>
                        جمعية خواطر أحلى شباب
                      </h1>
                      <p className="text-xs font-bold text-slate-300 mt-1" style={{ letterSpacing: 'normal' }}>
                        منظومة الإدارة والمتابعة المؤسسية · الإدارة التنفيذية
                      </p>
                    </div>
                  </div>

                  <div className="text-start bg-slate-900/90 border border-slate-700/80 rounded-2xl px-4 py-2.5 shadow-md shrink-0">
                    <div className="flex items-center gap-2 text-xs font-black text-slate-100" style={{ letterSpacing: 'normal' }}>
                      <Calendar className="size-4 text-sky-400" />
                      <span>{dateFormatted}</span>
                    </div>
                    <div className="flex items-center gap-2 text-[11px] font-bold text-slate-400 mt-1" style={{ letterSpacing: 'normal' }}>
                      <Clock3 className="size-3.5 text-slate-400" />
                      <span>توقيت الإصدار: {nowFormatted}</span>
                    </div>
                  </div>
                </div>

                {/* عنوان الكشف الصريح المنسق */}
                <div className="flex flex-col items-center justify-center mb-6 gap-1.5 text-center">
                  <div className="inline-flex items-center gap-2.5 px-6 py-2 rounded-2xl bg-gradient-to-r from-sky-500/15 via-indigo-500/20 to-sky-500/15 border border-sky-400/30 shadow-inner">
                    <span className="size-2 rounded-full bg-sky-400 animate-pulse" />
                    <h2 className="text-base sm:text-lg font-black text-sky-300" style={{ letterSpacing: 'normal' }}>
                      كشف المتابعة اليومية للحضور والانصراف
                    </h2>
                  </div>
                  <p className="text-[11px] font-semibold text-slate-400" style={{ letterSpacing: 'normal' }}>
                    بيان تنفيذي رسمي معتمد للإدارة التنفيذية وفق بيانات الحضور وبصمات الدوام والمأموريات الميدانية
                  </p>
                </div>

              {/* 2. شريط المؤشرات الرقمية (KPI Strip) */}
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
                <div className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-center">
                  <span className="block text-[11px] font-bold text-slate-400 mb-1">إجمالي قوة العمل</span>
                  <span className="text-2xl font-black text-white">{totalScheduled}</span>
                  <span className="text-[10px] text-slate-500 block mt-0.5">موظف مجدول</span>
                </div>

                <div className="p-3 rounded-xl bg-emerald-950/40 border border-emerald-500/30 text-center">
                  <span className="block text-[11px] font-bold text-emerald-300 mb-1">الحضور الفعلي</span>
                  <span className="text-2xl font-black text-emerald-400">{present.length}</span>
                  <span className="text-[10px] font-bold text-emerald-400/80 block mt-0.5">نسبة: {attendancePct}%</span>
                </div>

                <div className="p-3 rounded-xl bg-amber-950/40 border border-amber-500/30 text-center">
                  <span className="block text-[11px] font-bold text-amber-300 mb-1">المتأخرون</span>
                  <span className="text-2xl font-black text-amber-400">{late.length}</span>
                  <span className="text-[10px] text-amber-400/80 block mt-0.5">حضروا بعد الموعد</span>
                </div>

                <div className="p-3 rounded-xl bg-rose-950/40 border border-rose-500/30 text-center">
                  <span className="block text-[11px] font-bold text-rose-300 mb-1">الغياب</span>
                  <span className="text-2xl font-black text-rose-400">{absent.length}</span>
                  <span className="text-[10px] text-rose-400/80 block mt-0.5">{absent.length > 0 ? 'لم يسجلوا حضوراً' : 'لا يوجد غياب'}</span>
                </div>

                <div className="p-3 rounded-xl bg-sky-950/40 border border-sky-500/30 text-center">
                  <span className="block text-[11px] font-bold text-sky-300 mb-1">المأموريات</span>
                  <span className="text-2xl font-black text-sky-400">{onMission.length}</span>
                  <span className="text-[10px] text-sky-400/80 block mt-0.5">ميدانية ورسمية</span>
                </div>

                <div className="p-3 rounded-xl bg-teal-950/40 border border-teal-500/30 text-center">
                  <span className="block text-[11px] font-bold text-teal-300 mb-1">الإجازات</span>
                  <span className="text-2xl font-black text-teal-400">{onLeave.length}</span>
                  <span className="text-[10px] text-teal-400/80 block mt-0.5">معتمدة ومعلقة</span>
                </div>
              </div>

              {/* 3. الجداول التنفيذية الأربعة */}
              <div className="space-y-6">
                {/* أ) جدول الحاضرين */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  {(() => {
                    const presentInComplexCount = present.filter((p) => !isMissionItem(p) && (p.lateMinutes ?? 0) <= 0).length;
                    const presentMissionCount = present.filter((p) => isMissionItem(p) && (p.lateMinutes ?? 0) <= 0).length;
                    const presentLateCount = present.filter((p) => (p.lateMinutes ?? 0) > 0).length;

                    return (
                      <>
                        <div className="bg-emerald-900/70 border-b border-emerald-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                          <div className="flex items-center gap-1.5">
                            <UserCheck className="size-4 text-emerald-400" />
                            <span>قائمة الحاضرين (المتواجدون بالمجمع والمأموريات)</span>
                          </div>
                          <div className="flex items-center gap-1.5 flex-wrap">
                            {presentInComplexCount > 0 ? (
                              <span className="bg-emerald-800/80 text-emerald-200 border border-emerald-600/40 px-2 py-0.5 rounded-full text-[10.5px]">
                                {presentInComplexCount} متواجد بالمجمع
                              </span>
                            ) : null}
                            {presentMissionCount > 0 ? (
                              <span className="bg-sky-500/20 text-sky-300 border border-sky-500/40 px-2 py-0.5 rounded-full text-[10.5px]">
                                {presentMissionCount} في مأمورية
                              </span>
                            ) : null}
                            {presentLateCount > 0 ? (
                              <span className="bg-amber-500/20 text-amber-300 border border-amber-500/40 px-2 py-0.5 rounded-full text-[10.5px]">
                                {presentLateCount} متأخر
                              </span>
                            ) : null}
                            <span className="bg-emerald-800 px-2.5 py-0.5 rounded-full text-[11px] font-black">{present.length} إجمالي الحضور</span>
                          </div>
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
                                <th className="p-2">الموقع / وقت الانصراف</th>
                                <th className="p-2">الحالة</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-800 font-medium">
                              {(() => {
                                const firstMissionIndex = present.findIndex((p) => isMissionItem(p) && (p.lateMinutes ?? 0) <= 0);
                                const firstLateIndex = present.findIndex((p) => (p.lateMinutes ?? 0) > 0);

                                return present.map((p, idx) => {
                                  const isLate = (p.lateMinutes ?? 0) > 0;
                                  const isMission = isMissionItem(p);
                                  const destination = p.leaveTitle ?? p.pendingRequestTitle ?? p.leaveName;
                                  const isPendingMission = isMission && Boolean(p.hasPendingRequest);
                                  const isFirstMission = firstMissionIndex !== -1 && idx === firstMissionIndex;
                                  const isFirstLate = firstLateIndex !== -1 && idx === firstLateIndex;

                                  return (
                                    <Fragment key={p.employeeId}>
                                      {isFirstMission && (
                                        <tr className="bg-sky-950/70 border-y-2 border-sky-500/40 text-sky-300 font-black text-[10.5px]">
                                          <td colSpan={7} className="p-2 px-3">
                                            <div className="flex items-center justify-between">
                                              <span className="flex items-center gap-1.5">
                                                <Plane className="size-3.5 text-sky-400" />
                                                <span>موظفون سجلوا حضوراً ثم خرجوا في مأموريات عمل ميدانية (زيارات ومهمات رسمية)</span>
                                              </span>
                                              <span className="text-[10px] bg-sky-500/20 text-sky-300 border border-sky-500/40 px-2 py-0.5 rounded-full font-bold">
                                                {presentMissionCount} موظف
                                              </span>
                                            </div>
                                          </td>
                                        </tr>
                                      )}
                                      {isFirstLate && (
                                        <tr className="bg-amber-950/70 border-y-2 border-amber-500/40 text-amber-300 font-black text-[10.5px]">
                                          <td colSpan={7} className="p-2 px-3">
                                            <div className="flex items-center justify-between">
                                              <span className="flex items-center gap-1.5">
                                                <Clock3 className="size-3.5 text-amber-400" />
                                                <span>المتأخرون عن موعد الوردية الرسمية (المسجلون بعد الموعد)</span>
                                              </span>
                                              <span className="text-[10px] bg-amber-500/20 text-amber-300 border border-amber-500/40 px-2 py-0.5 rounded-full font-bold">
                                                {presentLateCount} موظف
                                              </span>
                                            </div>
                                          </td>
                                        </tr>
                                      )}
                                      <tr
                                        className={
                                          isLate
                                            ? 'bg-amber-950/25 hover:bg-amber-950/40 border-s-2 border-amber-500'
                                            : isMission
                                            ? 'bg-sky-950/20 hover:bg-sky-950/35 border-s-2 border-sky-500'
                                            : idx % 2 === 0
                                            ? 'bg-slate-950/40'
                                            : 'bg-slate-900/40'
                                        }
                                      >
                                        <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                                        <td className="p-2 font-black text-white">
                                          <div className="flex items-center gap-1.5 flex-wrap">
                                            <span>{p.employeeName}</span>
                                            {isClinicMedicalStaff(p) ? (
                                              <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-cyan-950/80 text-cyan-300 border border-cyan-800/60 inline-flex items-center gap-0.5">
                                                🩺 عيادات
                                              </span>
                                            ) : null}
                                            {isLate ? (
                                              <span className="px-1.5 py-0.2 rounded text-[9px] font-black bg-amber-500/20 text-amber-300 border border-amber-500/40">
                                                متأخر
                                              </span>
                                            ) : null}
                                            {isMission ? (
                                              <span className="px-1.5 py-0.2 rounded text-[9px] font-black bg-sky-500/20 text-sky-300 border border-sky-500/40 inline-flex items-center gap-0.5">
                                                ✈️ مأمورية
                                              </span>
                                            ) : null}
                                          </div>
                                        </td>
                                        <td className="p-2 text-slate-300">
                                          <span>{p.departmentName ?? '—'}</span>
                                          {p.branchName ? <span className="text-slate-400 text-[10px] block">{p.branchName}</span> : null}
                                        </td>
                                        <td className="p-2 text-slate-300">{p.shiftName ?? '—'}</td>
                                        <td
                                          className={`p-2 font-bold ${
                                            isLate ? 'text-amber-300' : isMission ? 'text-sky-300' : 'text-emerald-400'
                                          }`}
                                        >
                                          {p.firstCheckIn ? formatTime12(p.firstCheckIn) : '—'}
                                        </td>
                                        <td className="p-2 font-bold">
                                          {p.lastCheckOut ? (
                                            <span className="text-slate-300">{formatTime12(p.lastCheckOut)}</span>
                                          ) : isMission ? (
                                            <div className="flex flex-col gap-0.5">
                                              <span className="text-sky-300 flex items-center gap-1 text-[11px]">
                                                <Plane className="size-3 text-sky-400 inline" />
                                                خرج في مأمورية ميدانية
                                              </span>
                                              {destination ? (
                                                <span className="text-slate-400 text-[10px] font-normal truncate max-w-[210px]" title={destination}>
                                                  📍 {destination}
                                                </span>
                                              ) : null}
                                            </div>
                                          ) : (
                                            <span className="text-emerald-300">متواجد حالياً في المجمع</span>
                                          )}
                                        </td>
                                        <td className="p-2">
                                          {isLate ? (
                                            <span className="inline-block px-2 py-0.5 rounded bg-amber-500/25 text-amber-300 border border-amber-500/40 font-black text-[10px] shadow-xs">
                                              ⚠️ متأخر {formatMinutes(p.lateMinutes)}
                                            </span>
                                          ) : isMission ? (
                                            <span className="inline-block px-1.5 py-0.5 rounded bg-sky-500/20 text-sky-300 border border-sky-500/40 font-bold text-[10px]">
                                              {isPendingMission ? `⏳ طلب مأمورية${p.pendingRequestNumber ? ` (#${p.pendingRequestNumber})` : ''}` : '✈️ مأمورية معتمدة'}
                                            </span>
                                          ) : (
                                            <span className="inline-block px-1.5 py-0.5 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 font-bold text-[10px]">
                                              في الموعد
                                            </span>
                                          )}
                                        </td>
                                      </tr>
                                    </Fragment>
                                  );
                                });
                              })()}
                            </tbody>
                          </table>
                        )}
                      </>
                    );
                  })()}
                </div>

                {/* ب) جدول الغائبين */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-rose-900/70 border-b border-rose-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <UserX className="size-4 text-rose-400" />
                      <span>قائمة الموظفين الغائبين</span>
                    </div>
                    <span className="bg-rose-800 px-2.5 py-0.5 rounded-full text-[11px]">{absent.length} موظف</span>
                  </div>

                  {absent.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا يوجد غياب لهذا اليوم.</div>
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
                            <td className="p-2 font-black text-white">
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span>{a.employeeName}</span>
                                {isClinicMedicalStaff(a) ? (
                                  <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-cyan-950/80 text-cyan-300 border border-cyan-800/60 inline-flex items-center gap-0.5">
                                    🩺 عيادات
                                  </span>
                                ) : null}
                              </div>
                            </td>
                            <td className="p-2 text-slate-300">
                              <span>{a.departmentName ?? '—'}</span>
                              {a.branchName ? <span className="text-slate-400 text-[10px] block">{a.branchName}</span> : null}
                            </td>
                            <td className="p-2 text-slate-300">{a.shiftName ?? '—'}</td>
                            <td className="p-2">
                              {a.hasPendingRequest ? (
                                <div className="flex flex-col gap-0.5">
                                  <span className="inline-block px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/40 font-bold text-[10px] w-fit">
                                    ⏳ طلب معلّق{a.pendingRequestNumber ? ` (#${a.pendingRequestNumber})` : ''}
                                  </span>
                                  {a.pendingRequestTitle ? (
                                    <span className="text-slate-200 font-medium text-[10.5px]">📌 {a.pendingRequestTitle}</span>
                                  ) : null}
                                  {a.leaveReason ? (
                                    <span className="text-slate-400 font-normal text-[10px]">💬 {a.leaveReason}</span>
                                  ) : null}
                                </div>
                              ) : (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-rose-500/20 text-rose-300 border border-rose-500/30 font-bold text-[10px]">
                                  غياب بدون إذن
                                </span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* ج) جدول المأموريات الرسمية والتكليفات الخارجية (لوحدها) */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-sky-900/70 border-b border-sky-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <Plane className="size-4 text-sky-400" />
                      <span>قائمة المأموريات والتكليفات الرسمية الميدانية</span>
                    </div>
                    <span className="bg-sky-800 px-2.5 py-0.5 rounded-full text-[11px] font-black">{onMission.length} مأمورية</span>
                  </div>

                  {onMission.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا توجد مأموريات عمل مسجلة لهذا اليوم.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">حالة المأمورية</th>
                          <th className="p-2">وجهة المأمورية والغرض الرسمي</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800 font-medium">
                        {onMission.map((item, idx) => {
                          const isPending = Boolean(item.hasPendingRequest) && !item.hasApprovedLeave;
                          const reqNum = item.pendingRequestNumber ?? item.leaveRequestNumber;
                          const reqSuffix = reqNum ? ` (#${reqNum})` : '';

                          return (
                            <tr key={item.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/40' : 'bg-slate-900/40'}>
                              <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                              <td className="p-2 font-black text-white">
                                <div className="flex items-center gap-1.5 flex-wrap">
                                  <span>{item.employeeName}</span>
                                  {isClinicMedicalStaff(item) ? (
                                    <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-cyan-950/80 text-cyan-300 border border-cyan-800/60 inline-flex items-center gap-0.5">
                                      🩺 عيادات
                                    </span>
                                  ) : null}
                                </div>
                              </td>
                              <td className="p-2 text-slate-300">
                                <span>{item.departmentName ?? '—'}</span>
                                {item.branchName ? <span className="text-slate-400 text-[10px] block">{item.branchName}</span> : null}
                              </td>
                              <td className="p-2">
                                <span
                                  className={`inline-block px-1.5 py-0.5 rounded font-black text-[10px] ${
                                    isPending
                                      ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                                      : 'bg-sky-500/20 text-sky-300 border border-sky-500/30'
                                  }`}
                                >
                                  {isPending ? `⏳ طلب مأمورية معلّق${reqSuffix}` : `✈️ مأمورية رسمية${reqSuffix}`}
                                </span>
                              </td>
                              <td className="p-2 text-slate-200 font-bold">
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
                                  {item.firstCheckIn ? (
                                    <span className="text-emerald-400 font-bold text-[10px] block mt-0.5">
                                      ✓ سجل حضور صباحاً ({formatTime12(item.firstCheckIn)}) ثم خرج لمأمورية
                                    </span>
                                  ) : null}
                                </div>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* د) جدول الإجازات والراحات الرسمية (بعد منها) */}
                <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/40">
                  <div className="bg-teal-900/70 border-b border-teal-500/20 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <Calendar className="size-4 text-teal-400" />
                      <span>قائمة الإجازات والراحات الرسمية والطلبات</span>
                    </div>
                    <span className="bg-teal-800 px-2.5 py-0.5 rounded-full text-[11px] font-black">{onLeave.length} إجازة</span>
                  </div>

                  {onLeave.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-400 font-bold bg-slate-900/20">لا توجد إجازات مسجلة لهذا اليوم.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-900/90 text-slate-300 border-b border-slate-800 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">نوع الإجازة والمعاملة</th>
                          <th className="p-2">السبب والبيان الرسمي</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800 font-medium">
                        {onLeave.map((item, idx) => {
                          const isPending = Boolean(item.hasPendingRequest) && !item.hasApprovedLeave;
                          const reqNum = item.pendingRequestNumber ?? item.leaveRequestNumber;
                          const reqSuffix = reqNum ? ` (#${reqNum})` : '';

                          return (
                            <tr key={item.employeeId} className={idx % 2 === 0 ? 'bg-slate-950/40' : 'bg-slate-900/40'}>
                              <td className="p-2 text-center text-slate-500 font-bold">{idx + 1}</td>
                              <td className="p-2 font-black text-white">
                                <div className="flex items-center gap-1.5 flex-wrap">
                                  <span>{item.employeeName}</span>
                                  {isClinicMedicalStaff(item) ? (
                                    <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-cyan-950/80 text-cyan-300 border border-cyan-800/60 inline-flex items-center gap-0.5">
                                      🩺 عيادات
                                    </span>
                                  ) : null}
                                </div>
                              </td>
                              <td className="p-2 text-slate-300">
                                <span>{item.departmentName ?? '—'}</span>
                                {item.branchName ? <span className="text-slate-400 text-[10px] block">{item.branchName}</span> : null}
                              </td>
                              <td className="p-2">
                                <span
                                  className={`inline-block px-1.5 py-0.5 rounded font-black text-[10px] ${
                                    isPending
                                      ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                                      : 'bg-teal-500/20 text-teal-300 border border-teal-500/30'
                                  }`}
                                >
                                  {isPending ? `⏳ طلب إجازة معلّق${reqSuffix}` : `${item.leaveName ?? 'إجازة معتمدة'}${reqSuffix}`}
                                </span>
                              </td>
                              <td className="p-2 text-slate-200 font-bold">
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
