import { useState } from 'react';
import { Calendar, Camera, Check, CheckCircle2, Clock3, Copy, Download, Loader2, MessageSquare, Plane, UserCheck, UserX, Users, X } from 'lucide-react';
import { useAttendanceRosterPage } from './useAttendanceDashboard';
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
  const onMission = sortClinicStaffToEnd(items.filter((i) => i.status === 'on_mission' || Boolean(i.hasMission)));
  const onLeave = sortClinicStaffToEnd(items.filter((i) => (i.status === 'on_leave' || Boolean(i.hasApprovedLeave)) && !i.hasMission));
  const present = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.status === 'present' || i.status === 'late' || i.status === 'missing_checkout' || Boolean(i.firstCheckIn)) &&
        !i.hasMission &&
        !i.hasApprovedLeave &&
        i.status !== 'on_mission' &&
        i.status !== 'on_leave'
    )
  );
  const late = sortClinicStaffToEnd(
    items.filter((i) => (i.lateMinutes ?? 0) > 0 && !i.hasMission && !i.hasApprovedLeave && i.status !== 'on_mission')
  );
  const absent = sortClinicStaffToEnd(
    items.filter(
      (i) =>
        (i.status === 'absent' || i.status === 'unexcused_absent') &&
        !i.firstCheckIn &&
        !i.hasApprovedLeave &&
        !i.hasMission
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
        backgroundColor: '#ffffff',
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
        backgroundColor: '#ffffff',
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
          const reqPart = l.leaveRequestNumber ? ` (#${l.leaveRequestNumber})` : '';
          const titlePart = l.leaveTitle && l.leaveTitle !== l.leaveName && l.leaveTitle !== l.leaveReason ? ` [${l.leaveTitle}]` : '';
          const reasonPart = l.leaveReason ? ` - سبب: ${l.leaveReason}` : '';
          return `${i + 1}. ${l.employeeName} (${l.departmentName ?? '—'}) · ${l.leaveName ?? 'إجازة'}${reqPart}${titlePart}${reasonPart}`;
        }),
        ...onMission.map((m, i) => {
          const reqPart = m.leaveRequestNumber ? ` (#${m.leaveRequestNumber})` : '';
          const titlePart = m.leaveTitle && m.leaveTitle !== m.leaveName ? ` [${m.leaveTitle}]` : (m.leaveName ? ` [${m.leaveName}]` : '');
          const reasonPart = m.leaveReason ? ` - الغرض: ${m.leaveReason}` : '';
          return `${i + onLeave.length + 1}. ${m.employeeName} (${m.departmentName ?? '—'}) · مأمورية معتمدة${reqPart}${titlePart}${reasonPart}`;
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
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-5 bg-black/75 backdrop-blur-sm overflow-y-auto"
      role="dialog"
      aria-modal="true"
    >
      <div className="relative w-full max-w-5xl bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden my-auto max-h-[92vh] flex flex-col">
        {/* شريط التحكم العلوي */}
        <header className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-[var(--border)] bg-[var(--surface-muted)] shrink-0">
          <div className="flex items-center gap-2.5">
            <div className="size-9 rounded-xl bg-[var(--primary)]/10 text-[var(--primary)] flex items-center justify-center">
              <Camera className="size-5" />
            </div>
            <div>
              <h2 className="text-sm sm:text-base font-black text-[var(--text)]">تقرير الحضور التنفيذي (جاهز للمدير التنفيذي)</h2>
              <p className="text-[11px] text-[var(--text-muted)]">معاينة الصورة التنفيذية الرسمية قبل الإرسال للمدير التنفيذي</p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {/* زر نسخ الصورة */}
            <button
              type="button"
              onClick={() => void handleCopyImage()}
              disabled={isCapturing || query.isLoading}
              className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 border border-[var(--border)] hover:border-[var(--primary)] transition-all"
              title="نسخ الصورة للحافظة للصقها مباشرة (Ctrl + V) في واتساب"
            >
              {copiedType === 'image' ? <Check className="size-4 text-emerald-500" /> : <Copy className="size-4 text-[var(--primary)]" />}
              <span>نسخ الصورة لواتساب</span>
            </button>

            {/* زر حفظ الصورة كملف PNG */}
            <button
              type="button"
              onClick={() => void handleDownloadImage()}
              disabled={isCapturing || query.isLoading}
              className="btn-primary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 shadow-sm"
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
              className="btn-secondary btn-sm h-9 px-3 text-xs font-bold rounded-xl inline-flex items-center gap-1.5 border border-[var(--border)] hover:border-emerald-500 transition-all"
              title="نسخ نص التقرير المنسق لإرساله كتابياً عبر واتساب"
            >
              {copiedType === 'text' ? <Check className="size-4 text-emerald-500" /> : <MessageSquare className="size-4 text-emerald-500" />}
              <span>نسخ نص واتساب</span>
            </button>

            {/* زر الإغلاق */}
            <button
              type="button"
              onClick={onClose}
              className="p-1.5 rounded-xl hover:bg-[var(--surface-muted)] text-[var(--text-muted)] hover:text-[var(--text)] transition-colors"
              aria-label="إغلاق النافذة"
            >
              <X className="size-5" />
            </button>
          </div>
        </header>

        {/* إشعار عائم في حال النسخ أو الحفظ */}
        {toastMessage && (
          <div className="bg-[var(--primary)] text-white text-xs font-bold px-4 py-2 text-center shrink-0 animate-fade-in flex items-center justify-center gap-2">
            <span>{toastMessage}</span>
          </div>
        )}

        {/* منطقة المعاينة القابلة للتمرير */}
        <div className="p-4 sm:p-6 overflow-y-auto bg-[var(--surface-subtle)] flex justify-center">
          {query.isLoading ? (
            <div className="py-20 flex flex-col items-center justify-center gap-3 text-[var(--text-muted)]">
              <Loader2 className="size-8 animate-spin text-[var(--primary)]" />
              <p className="text-xs font-bold">جاري تجميع بيانات الحضور والانصراف التنفيذية...</p>
            </div>
          ) : query.isError ? (
            <div className="py-16 text-center text-red-500 text-xs font-bold">تعذر استخراج بيانات الكشف. يرجى إعادة المحاولة.</div>
          ) : (
            /* ─── البطاقة التنفيذية التي سيتم التقاطها كصورة (Executive Card) ─── */
            <div
              id="executive-attendance-card"
              className="w-full max-w-[1100px] bg-white text-slate-900 rounded-2xl p-6 sm:p-8 shadow-md border border-slate-200 font-sans"
              dir="rtl"
              style={{ minWidth: '950px', backgroundColor: '#ffffff', color: '#0f172a' }}
            >
              {/* 1. الترويسة الملكية للجمعية */}
              <div className="flex items-center justify-between pb-5 border-b-2 border-slate-900/10 mb-6">
                <div className="flex items-center gap-3.5">
                  <div className="size-12 rounded-2xl bg-sky-900 text-white flex items-center justify-center font-black text-xl shadow-sm">أحلى</div>
                  <div>
                    <h1 className="text-xl font-black text-slate-900 tracking-tight">جمعية خواطر أحلى شباب</h1>
                    <p className="text-xs font-bold text-slate-500 mt-0.5">منظومة الإدارة والمتابعة المؤسسية · الإدارة التنفيذية</p>
                  </div>
                </div>

                <div className="text-start bg-slate-50 border border-slate-200 rounded-xl px-4 py-2">
                  <div className="flex items-center gap-1.5 text-xs font-black text-slate-800">
                    <Calendar className="size-3.5 text-sky-700" />
                    <span>{dateFormatted}</span>
                  </div>
                  <div className="flex items-center gap-1.5 text-[11px] font-bold text-slate-500 mt-0.5">
                    <Clock3 className="size-3 text-slate-400" />
                    <span>توقيت الإصدار: {nowFormatted}</span>
                  </div>
                </div>
              </div>

              {/* عنوان الكشف الصريح */}
              <div className="text-center mb-6">
                <h2 className="text-lg font-black text-slate-900 inline-block px-6 py-1.5 bg-sky-50 text-sky-900 rounded-full border border-sky-200">
                  كشف المتابعة اليومية للحضور والانصراف
                </h2>
              </div>

              {/* 2. شريط المؤشرات الرقمية (KPI Strip) */}
              <div className="grid grid-cols-5 gap-3 mb-6">
                <div className="p-3.5 rounded-xl bg-slate-100 border border-slate-200 text-center">
                  <span className="block text-[11px] font-bold text-slate-600 mb-1">إجمالي قوة العمل</span>
                  <span className="text-2xl font-black text-slate-900">{totalScheduled}</span>
                  <span className="text-[10px] text-slate-500 block mt-0.5">موظف مجدول</span>
                </div>

                <div className="p-3.5 rounded-xl bg-emerald-50 border border-emerald-200 text-center">
                  <span className="block text-[11px] font-bold text-emerald-800 mb-1">الحضور الفعلي</span>
                  <span className="text-2xl font-black text-emerald-700">{present.length}</span>
                  <span className="text-[10px] font-bold text-emerald-600 block mt-0.5">نسبة: {attendancePct}%</span>
                </div>

                <div className="p-3.5 rounded-xl bg-amber-50 border border-amber-200 text-center">
                  <span className="block text-[11px] font-bold text-amber-800 mb-1">المتأخرون</span>
                  <span className="text-2xl font-black text-amber-700">{late.length}</span>
                  <span className="text-[10px] text-amber-600 block mt-0.5">حضروا بعد الموعد</span>
                </div>

                <div className="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-center">
                  <span className="block text-[11px] font-bold text-rose-800 mb-1">الغياب</span>
                  <span className="text-2xl font-black text-rose-700">{absent.length}</span>
                  <span className="text-[10px] text-rose-600 block mt-0.5">{absent.length > 0 ? 'لم يسجلوا حضوراً' : 'لا يوجد غياب'}</span>
                </div>

                <div className="p-3.5 rounded-xl bg-indigo-50 border border-indigo-200 text-center">
                  <span className="block text-[11px] font-bold text-indigo-800 mb-1">إجازات ومأموريات</span>
                  <span className="text-2xl font-black text-indigo-700">{onLeave.length + onMission.length}</span>
                  <span className="text-[10px] text-indigo-600 block mt-0.5">بعذر رسمي</span>
                </div>
              </div>

              {/* 3. الجداول التنفيذية الثلاثة */}
              <div className="space-y-6">
                {/* أ) جدول الحاضرين */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-emerald-700 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <UserCheck className="size-4" />
                      <span>قائمة الحاضرين على رأس العمل</span>
                    </div>
                    <span className="bg-emerald-800 px-2 py-0.5 rounded-full text-[11px]">{present.length} موظف</span>
                  </div>

                  {present.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-500 font-bold bg-slate-50">لا يوجد حضور مسجل لهذا اليوم حتى الآن.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-100 text-slate-700 border-b border-slate-200 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">الوردية</th>
                          <th className="p-2">وقت الحضور</th>
                          <th className="p-2">وقت الانصراف</th>
                          <th className="p-2">الحالة</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {present.map((p, idx) => (
                          <tr key={p.employeeId} className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50/50'}>
                            <td className="p-2 text-center text-slate-400 font-bold">{idx + 1}</td>
                            <td className="p-2 font-black text-slate-900">{p.employeeName}</td>
                            <td className="p-2 text-slate-600">
                              <span>{p.departmentName ?? '—'}</span>
                              {p.branchName ? <span className="text-slate-400 text-[10px] block">{p.branchName}</span> : null}
                            </td>
                            <td className="p-2 text-slate-600">{p.shiftName ?? '—'}</td>
                            <td className="p-2 font-bold text-emerald-800">{p.firstCheckIn ? formatTime12(p.firstCheckIn) : '—'}</td>
                            <td className="p-2 text-slate-600">{p.lastCheckOut ? formatTime12(p.lastCheckOut) : 'على رأس العمل'}</td>
                            <td className="p-2">
                              {(p.lateMinutes ?? 0) > 0 ? (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-amber-100 text-amber-800 font-black text-[10px]">
                                  متأخر {formatMinutes(p.lateMinutes)}
                                </span>
                              ) : (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-emerald-100 text-emerald-800 font-bold text-[10px]">في الموعد</span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* ب) جدول الغائبين */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-rose-700 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <UserX className="size-4" />
                      <span>قائمة الغائبين</span>
                    </div>
                    <span className="bg-rose-800 px-2 py-0.5 rounded-full text-[11px]">{absent.length} موظف</span>
                  </div>

                  {absent.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-500 font-bold bg-slate-50">لا يوجد غياب اليوم (نسبة الحضور مكتملة).</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-100 text-slate-700 border-b border-slate-200 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">الوردية المقررة</th>
                          <th className="p-2">موقف العذر والطلب</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {absent.map((a, idx) => (
                          <tr key={a.employeeId} className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50/50'}>
                            <td className="p-2 text-center text-slate-400 font-bold">{idx + 1}</td>
                            <td className="p-2 font-black text-slate-900">{a.employeeName}</td>
                            <td className="p-2 text-slate-600">
                              <span>{a.departmentName ?? '—'}</span>
                              {a.branchName ? <span className="text-slate-400 text-[10px] block">{a.branchName}</span> : null}
                            </td>
                            <td className="p-2 text-slate-600">{a.shiftName ?? '—'}</td>
                            <td className="p-2">
                              {a.hasPendingRequest ? (
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-amber-100 text-amber-900 font-black text-[10px]">
                                  <span>⏳</span>
                                  <span>
                                    طلب معلّق {a.pendingRequestNumber ? `(#${a.pendingRequestNumber})` : ''}: {a.pendingRequestTitle ?? 'قيد الاعتماد'}
                                  </span>
                                </span>
                              ) : (
                                <span className="inline-block px-1.5 py-0.5 rounded bg-rose-100 text-rose-800 font-bold text-[10px]">غياب بدون إذن</span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* ج) جدول الإجازات والمأموريات المعتمدة */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-indigo-700 text-white px-4 py-2 flex items-center justify-between text-xs font-black">
                    <div className="flex items-center gap-1.5">
                      <Plane className="size-4" />
                      <span>قائمة الإجازات والمأموريات الرسمية المعتمدة</span>
                    </div>
                    <span className="bg-indigo-800 px-2 py-0.5 rounded-full text-[11px]">{onLeave.length + onMission.length} موظف</span>
                  </div>

                  {onLeave.length + onMission.length === 0 ? (
                    <div className="py-4 text-center text-xs text-slate-500 font-bold bg-slate-50">لا توجد إجازات أو مأموريات مقررة لهذا اليوم.</div>
                  ) : (
                    <table className="w-full text-[11px] border-collapse">
                      <thead>
                        <tr className="bg-slate-100 text-slate-700 border-b border-slate-200 text-start font-black">
                          <th className="p-2 w-8 text-center">#</th>
                          <th className="p-2">اسم الموظف</th>
                          <th className="p-2">الإدارة والفرع</th>
                          <th className="p-2">النوع والمعاملة</th>
                          <th className="p-2">السبب والبيان الرسمي</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {[...onLeave, ...onMission].map((item, idx) => {
                          const isMission = item.status === 'on_mission' || item.hasMission;
                          return (
                            <tr key={item.employeeId} className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50/50'}>
                              <td className="p-2 text-center text-slate-400 font-bold">{idx + 1}</td>
                              <td className="p-2 font-black text-slate-900">{item.employeeName}</td>
                              <td className="p-2 text-slate-600">
                                <span>{item.departmentName ?? '—'}</span>
                                {item.branchName ? <span className="text-slate-400 text-[10px] block">{item.branchName}</span> : null}
                              </td>
                              <td className="p-2">
                                <span
                                  className={`inline-block px-1.5 py-0.5 rounded font-black text-[10px] ${
                                    isMission ? 'bg-indigo-100 text-indigo-800' : 'bg-teal-100 text-teal-800'
                                  }`}
                                >
                                  {isMission ? 'مأمورية رسمية' : item.leaveName ?? 'إجازة معتمدة'}
                                  {item.leaveRequestNumber ? ` (#${item.leaveRequestNumber})` : ''}
                                </span>
                              </td>
                              <td className="p-2 text-slate-800 font-bold">
                                {isMission ? (
                                  <div className="flex flex-col gap-0.5">
                                    {item.leaveTitle || item.leaveName ? (
                                      <span className="text-slate-900 font-black text-[11px]">📍 {item.leaveTitle ?? item.leaveName}</span>
                                    ) : null}
                                    {item.leaveReason ? (
                                      <span className="text-slate-600 font-medium text-[10.5px]">💬 الغرض: {item.leaveReason}</span>
                                    ) : (
                                      <span className="text-slate-500 font-normal text-[10.5px]">مأمورية رسمية معتمدة</span>
                                    )}
                                  </div>
                                ) : (
                                  <div className="flex flex-col gap-0.5">
                                    {item.leaveTitle && item.leaveTitle !== item.leaveName && item.leaveTitle !== item.leaveReason ? (
                                      <span className="text-slate-900 font-black text-[11px]">📌 {item.leaveTitle}</span>
                                    ) : null}
                                    {item.leaveReason ? (
                                      <span className="text-slate-600 font-medium text-[10.5px]">💬 السبب: {item.leaveReason}</span>
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
              <div className="mt-8 pt-4 border-t border-slate-200 flex items-center justify-between text-[11px] font-bold text-slate-500">
                <span>صادر عن منظومة الموارد البشرية والمتابعة الميدانية · جمعية خواطر أحلى شباب</span>
                <span className="text-slate-400">تقرير رسمي معتمد للإرسال للإدارة التنفيذية</span>
                <span className="font-mono text-[10px]">كود التحقق: {dateIso.replace(/-/g, '')}-EXEC</span>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
