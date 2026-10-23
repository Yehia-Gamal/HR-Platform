/**
 * خدمة تنسيق ومشاركة الرسائل المباشرة عبر الواتساب لمنظومة أحلى شباب (Admin Web)
 */

export function cleanPhoneForWhatsApp(phone: string | null | undefined): string {
  if (!phone) return '';
  const digits = phone.replace(/[^\d]/g, '');
  if (!digits) return '';
  // الأرقام المصرية التي تبدأ بـ 01 (مثل 010, 011, 012, 015)
  if (digits.startsWith('01') && digits.length === 11) {
    return `20${digits.substring(1)}`;
  }
  // إذا كانت 10 أرقام تبدأ بـ 1
  if (digits.startsWith('1') && digits.length === 10) {
    return `20${digits}`;
  }
  return digits;
}

export function openWhatsApp(text: string, phone?: string | null | undefined): void {
  const cleanPhone = cleanPhoneForWhatsApp(phone);
  const encoded = encodeURIComponent(text);
  if (cleanPhone) {
    window.open(`https://wa.me/${cleanPhone}?text=${encoded}`, '_blank', 'noopener,noreferrer');
  } else {
    window.open(`https://api.whatsapp.com/send?text=${encoded}`, '_blank', 'noopener,noreferrer');
  }
}

/**
 * تذكير تنفيذي ودي لمعتمد بطيء أو لديه طلبات متأخرة
 */
export function shareApproverNudge({
  approverName,
  pendingCount,
  avgHours,
  phone,
}: {
  approverName: string;
  pendingCount: number;
  avgHours?: number | null;
  phone?: string | null;
}): void {
  const lines: string[] = [
    '🔔 *تذكير إداري — منصة جمعية أحلى شباب*',
    '',
    `السلام عليكم ورحمة الله أ/ *${approverName}*،`,
    '',
    `نود تذكير سيادتكم بوجود *(${pendingCount}) طلب/إجراء* معلق بانتظار قراركم واعتمادكم الكريم.`,
  ];

  if (avgHours && avgHours > 0) {
    lines.push(`⏱️ متوسط زمن الاستجابة المسجل حالياً: *${avgHours.toFixed(1)} ساعة*.`);
  }

  lines.push('');
  lines.push('يرجى التكرم بالدخول للمنظومة والبت في الطلبات لتيسير العمل وسرعة الإنجاز:');
  lines.push('🔗 https://ahla-shabab-management-os.vercel.app/admin/requests?scope=awaiting_me');
  lines.push('');
  lines.push('شاكرين ومقدرين حسن تعاونكم الدائم 🌿');

  openWhatsApp(lines.join('\n'), phone);
}

/**
 * مشاركة تفاصيل طلب للمتابعة الفورية والاعتماد المباشر
 */
export function shareRequestDetails({
  number,
  typeLabel,
  employeeName,
  statusLabel,
  reason,
  currentStep,
  phone,
}: {
  number?: number | string | null;
  typeLabel: string;
  employeeName: string;
  statusLabel?: string | null;
  reason?: string | null;
  currentStep?: string | null;
  phone?: string | null;
}): void {
  const lines: string[] = ['📋 *تفاصيل طلب — منصة جمعية أحلى شباب*', '', `• النوع: *${typeLabel}*`];

  if (number) {
    lines.push(`• رقم الطلب: *#${number}*`);
  }

  lines.push(`• صاحب الطلب: *${employeeName}*`);

  if (statusLabel) {
    lines.push(`• الحالة: *${statusLabel}*`);
  }

  if (currentStep) {
    lines.push(`• الخطوة الحالية: *${currentStep}*`);
  }

  if (reason && reason.trim()) {
    lines.push(`• السبب/البيان: ${reason.trim()}`);
  }

  lines.push('');
  lines.push('🔗 للبت في الطلب أو مراجعته مباشرة:');
  lines.push('https://ahla-shabab-management-os.vercel.app/admin/requests');
  lines.push('');
  openWhatsApp(lines.join('\n'), phone);
}

/**
 * مشاركة تقرير الإنجاز الشهري المجمع للموظف عبر الواتساب
 */
export function shareMonthlyAchievementReport({
  employeeName,
  department,
  monthName,
  year,
  reportedDaysCount,
  achievementsCount,
  topAchievements,
  phone,
}: {
  employeeName: string;
  department?: string | null;
  monthName: string;
  year: number;
  reportedDaysCount: number;
  achievementsCount: number;
  topAchievements: string[];
  phone?: string | null;
}): void {
  const lines: string[] = [`📋 *تقرير إنجازات شهر (${monthName} ${year})*`, '', `👤 *الموظف:* ${employeeName}`];
  if (department) {
    lines.push(`🏢 *القسم:* ${department}`);
  }
  lines.push('');
  lines.push('📊 *إحصائيات الإنجاز والتوثيق:*');
  lines.push(`• أيام العمل الموثقة: *${reportedDaysCount} يوماً*`);
  lines.push(`• إجمالي المهام والمنجزات: *${achievementsCount} إنجازاً*`);
  lines.push('');
  if (topAchievements.length > 0) {
    lines.push('🌟 *أبرز الإنجازات الميدانية والمكتبية:*');
    topAchievements.slice(0, 7).forEach((ach, i) => {
      lines.push(`${i + 1}) ${ach}`);
    });
    if (topAchievements.length > 7) {
      lines.push(`... بالإضافة إلى (${topAchievements.length - 7}) مهام إضافية موثقة بالمنظومة.`);
    }
    lines.push('');
  }
  lines.push('— *صادر من منظومة إدارة جمعية أحلى شباب لإدارة الموارد البشرية* 🌿');

  openWhatsApp(lines.join('\n'), phone);
}

/**
 * مشاركة إشعار إصدار وثيقة / خطاب رسمي عبر الواتساب
 */
export function shareOfficialDocumentNotice({
  employeeName,
  docTitle,
  serialNo,
  recipient,
  phone,
}: {
  employeeName: string;
  docTitle: string;
  serialNo: string;
  recipient?: string | null;
  phone?: string | null;
}): void {
  const lines: string[] = [
    `📜 *إشعار إصدار مستند رسمي — جمعية أحلى شباب*`,
    '',
    `تم إصدار وتوثيق مستند رسمي: *«${docTitle}»*`,
    `👤 *الموظف المعني:* ${employeeName}`,
    `🔢 *الرقم المرجعي الموثق:* ${serialNo}`,
  ];
  if (recipient) {
    lines.push(`🏛️ *الجهة الموجه إليها:* ${recipient}`);
  }
  lines.push('');
  lines.push('المستند مختوم وموقع رقمياً ومزود برمز QR للتحقق الفوري من صحته.');
  lines.push('— *إدارة الموارد البشرية والعمليات المركزية* 🌿');

  openWhatsApp(lines.join('\n'), phone);
}
