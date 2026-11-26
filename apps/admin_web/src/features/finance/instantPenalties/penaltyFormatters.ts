import { addDays, cairoTodayIso } from '../../../core/cairoTime';
import type { InstantPenalty } from '../useInstantPenalties';

export const dateFormatter = new Intl.DateTimeFormat('ar-EG-u-nu-latn', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
});

const currencyFmt = new Intl.NumberFormat('ar-EG-u-nu-latn', {
  style: 'currency',
  currency: 'EGP',
  maximumFractionDigits: 0,
});

export function formatCurrency(amount: number | null | undefined): string {
  if (amount == null) return '—';
  return currencyFmt.format(amount);
}

/** تنسيق دقائق التأخير → بحد أقصى ساعتان (120 دقيقة) */
export function fmtLateDisplay(totalMinutes: number | null | undefined): string {
  if (totalMinutes == null || totalMinutes <= 0) return '0 دقيقة';
  const capped = Math.min(120, totalMinutes);
  if (capped >= 120) return 'ساعتان';
  const h = Math.floor(capped / 60);
  const m = capped % 60;
  if (h === 0) return `${m} دقيقة`;
  if (m === 0) return h === 2 ? 'ساعتان' : 'ساعة واحدة';
  return `${h === 1 ? 'ساعة' : `${h} ساعات`} و ${m} دقيقة`;
}

const ARABIC_DAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const ARABIC_MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/** تنسيق التاريخ مع اسم اليوم بالعربية الرسمية دون علامات سالبة تسبب انعكاس النص في PDF */
export function fmtDateWithDay(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  const d = new Date(dateStr + 'T00:00:00');
  if (Number.isNaN(d.getTime())) return dateStr;
  const dayName = ARABIC_DAYS[d.getDay()];
  const day = d.getDate();
  const month = ARABIC_MONTHS[d.getMonth()];
  const year = d.getFullYear();
  return `${dayName}، ${day} ${month} ${year}`;
}

export function getYesterdayIso(): string {
  return addDays(cairoTodayIso(), -1);
}

export function generateEmployeePenaltyWhatsAppText(p: InstantPenalty, empName: string): string {
  const name = empName.trim() || 'الزميل العزيز';
  const dayDate = fmtDateWithDay(p.workDate);
  const lateFormatted = fmtLateDisplay(p.lateMinutes);
  const isUnpunched = Boolean(p.notes && p.notes.includes('لم يسجل بصمة'));

  if (p.status === 'suspended') {
    return [
      `*إشعار هام وعاجل من إدارة الموارد البشرية (جمعية أحلى شباب)* ⚠️`,
      ``,
      `السلام عليكم ورحمة الله، أستاذ *${name}* 🌸`,
      ``,
      `نود إحاطتكم بأنه قد تم *تعليق حسابكم مؤقتاً على السيستم* لتجاوز مهلة سداد غرامة الحضور المضاعفة (500 ج.م) ليوم *${dayDate}*.`,
      ``,
      `📌 *بيانات الغرامة:*`,
      `• التاريخ: ${dayDate}`,
      `• سبب الغرامة: ${lateFormatted} تأخير ${isUnpunched ? '(عدم تسجيل بصمة)' : ''}`,
      `• المبلغ المطلوب لسداد الغرامة ورفع الإيقاف: *500 ج.م*`,
      ``,
      `💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.`,
      `السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع لرفع التعليق واستئناف العمل فوراً.`,
      ``,
      `🤝 *تنويه هام:* جميع الغرامات المحصلة تُودع بالكامل في *صندوق الزمالة والتكافل* لدعم الزملاء والمساعدات الاجتماعية.`,
      ``,
      `مع خالص التقدير والاحترام 🌺`,
    ].join('\n');
  }

  if (p.status === 'doubled') {
    return [
      `*تنبيه عاجل: غرامة حضور مضاعفة (500 ج.م)* ⚠️`,
      ``,
      `السلام عليكم ورحمة الله، أستاذ *${name}* 🌸`,
      ``,
      `نود تذكيركم بأنه نظراً لانقضاء مهلة الـ 24 ساعة، تضاعفت غرامة الحضور ليوم *${dayDate}* لتصبح *500 ج.م*.`,
      ``,
      `📌 *تفاصيل الغرامة:*`,
      `• التاريخ: ${dayDate}`,
      `• مدة التأخير: ${lateFormatted}`,
      `• المبلغ المطلوب: *500 ج.م* (الغرامة الأصلية: ${formatCurrency(p.originalAmount)})`,
      ``,
      `💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.`,
      `⏰ يرجى سرعة السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع لتفادي تعليق الحساب على المنظومة.`,
      ``,
      `🤝 *نحيطكم علماً بأن 100% من حصيلة الغرامات تذهب لصالح صندوق الزمالة والتكافل لدعم الزملاء.*`,
      ``,
      `مع تمنياتنا لكم بالتوفيق 🌺`,
    ].join('\n');
  }

  return [
    `*إشعار تسجيل غرامة حضور وتأخير — جمعية أحلى شباب* ⏰`,
    ``,
    `السلام عليكم ورحمة الله، أستاذ *${name}* 🌸`,
    ``,
    `نحيطكم علماً بأنه تم تسجيل غرامة حضور وتأخير ليوم *${dayDate}*:`,
    `• مدة التأخير: *${lateFormatted}* ${isUnpunched ? '(لم يُسجل بصمة)' : ''}`,
    `• المبلغ المطلوب سداده: *${formatCurrency(p.currentAmount)}*`,
    ``,
    `⏳ *المهلة النظامية:* متبقي على مهلة الـ 24 ساعة قبل مضاعفة الغرامة إلى 500 ج.م.`,
    `💳 *طرق السداد المتاحة:* يمكنكم السداد نقداً لدى الإدارة المالية أو عبر إنستاباي، أو تقديم عذر رسمي عبر تطبيق المنظومة في حال وجود ظرف طارئ.`,
    `السداد إلى أ/ إبراهيم سلامة وإبلاغ باشمهندس يحيى بالدفع.`,
    ``,
    `🤝 *تنويه:* جميع المبالغ المحصلة تذهب لصالح صندوق الزمالة والتكافل ولا تمثل أي ربح للإدارة.`,
    ``,
    `شكراً لتعاونكم وحرصكم الدائم على الانضباط 🌺`,
  ].join('\n');
}

export function buildRadarWhatsAppText(emp: { employeeName: string; count: number }): string {
  return `*رسالة تقدير وتنبيه ودي من الموارد البشرية (أحلى شباب)* 🌸\n\nالسلام عليكم ورحمة الله، أستاذ ${emp.employeeName} العزيز 🌺\n\nنود لفت عنايتكم الكريمة إلى أنه تم رصد تكرار تأخير خلال الفترة الأخيرة بواقع (${emp.count} مرات).\n\nحرصاً منا على مصلحتكم وتفادياً لتراكم أي غرامات إضافية أو تعليق الحساب، نرجو التكرم بالحرص على الحضور بالموعد المحدد (10:00 ص)، ونحن جاهزون للاستماع لأي ظرف قد يواجهكم ومساعدتكم دائماً.\n\nتمنياتنا لكم بكل التوفيق والتميز! 🌟`;
}

export function buildWeeklyWhatsAppSummaryText(
  items: InstantPenalty[],
  fundBalance: number,
): string {
  const now = new Date();
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const weekAgoIso = weekAgo.toISOString().slice(0, 10);

  const thisWeek = items.filter((p) => p.workDate >= weekAgoIso);
  const pendingThisWeek = thisWeek.filter((p) => p.status === 'pending_payment');
  const paidThisWeek = thisWeek.filter((p) => p.status === 'paid');
  const doubledThisWeek = thisWeek.filter((p) => p.status === 'doubled');
  const suspendedThisWeek = thisWeek.filter((p) => p.status === 'suspended');
  const cancelledThisWeek = thisWeek.filter((p) => p.status === 'cancelled');

  const totalAmount = thisWeek.reduce((s, p) => s + p.currentAmount, 0);
  const paidAmount = paidThisWeek.reduce((s, p) => s + p.currentAmount, 0);
  const pendingAmount = pendingThisWeek.reduce((s, p) => s + p.currentAmount, 0);

  const collectionRate =
    thisWeek.length > 0 ? Math.round((paidThisWeek.length / Math.max(1, thisWeek.length - cancelledThisWeek.length)) * 100) : 0;

  const empCounts = new Map<string, { name: string; count: number }>();
  for (const p of thisWeek) {
    if (p.status === 'cancelled') continue;
    const existing = empCounts.get(p.employeeId) ?? { name: p.employeeName ?? 'موظف', count: 0 };
    existing.count++;
    empCounts.set(p.employeeId, existing);
  }
  const topLate = [...empCounts.values()].sort((a, b) => b.count - a.count).slice(0, 3);

  return `*📊 التقرير الأسبوعي لغرامات الحضور — أحلى شباب*\n*الفترة:* ${weekAgoIso} → ${cairoTodayIso()}\n\n📌 *الملخص:*\n• إجمالي الغرامات: ${thisWeek.length} غرامة\n• إجمالي المبالغ: ${formatCurrency(totalAmount)}\n• المدفوع: ${paidThisWeek.length} (${formatCurrency(paidAmount)})\n• بانتظار السداد: ${pendingThisWeek.length} (${formatCurrency(pendingAmount)})\n• المضاعفة: ${doubledThisWeek.length}\n• المعلّقة: ${suspendedThisWeek.length}\n• الملغاة (أعذار مقبولة): ${cancelledThisWeek.length}\n\n📈 *نسبة التحصيل:* ${collectionRate}%\n💰 *رصيد صندوق الزمالة:* ${formatCurrency(fundBalance)}\n\n${topLate.length > 0 ? `⚠️ *الأكثر تأخراً هذا الأسبوع:*\n${topLate.map((e, i) => `${i + 1}. ${e.name} — ${e.count} مرات`).join('\n')}\n` : '✅ لا يوجد تكرار تأخير ملحوظ هذا الأسبوع.\n'}\n🤝 *تذكير:* جميع حصيلة الغرامات تذهب كاملة لصندوق الزمالة والتكافل لدعم الزملاء.\n\n_تقرير آلي من منظومة أحلى شباب — مجاني بدون رسوم_ ✨`;
}
