import {
  sanitizeMissionPurpose,
  type ClassifiedEmployee,
  type ComparativeAuditItem,
  type EndOfDayMetrics,
  type ExecutiveMetrics,
} from '../executiveReportLogic';

export function buildEndOfDayWhatsAppText(params: {
  dateFormatted: string;
  nowFormatted: string;
  endOfDayMetrics: EndOfDayMetrics;
  securityInfo: { code: string; verifyUrl: string };
  fmtTime: (iso: string | null | undefined) => string;
  fmtNum: (val: number | string) => string;
}): string {
  const { dateFormatted, nowFormatted, endOfDayMetrics, securityInfo, fmtTime, fmtNum } = params;
  return `🌙 *كشف إغلاق اليوم وساعات العمل والانصراف (المدير التنفيذي)*
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
${
  endOfDayMetrics.missingCheckoutsCount > 0
    ? `⚠️ *بصمات الانصراف الناقصة (${endOfDayMetrics.missingCheckoutsCount}):*
${endOfDayMetrics.missingCheckoutList.map((m, i) => `${fmtNum(i + 1)}. ${m.item.employeeName} (${m.item.departmentName ?? '—'}) · حضور: ${fmtTime(m.firstCheckIn)} [⚠️ لم يسجل خروجاً]`).join('\n')}
━━━━━━━━━━━━━━━━━━━━\n`
    : ''
}${
    endOfDayMetrics.earlyDeparturesCount > 0
      ? `⏱️ *الانصراف المبكر (${fmtNum(endOfDayMetrics.earlyDeparturesCount)}):*
${endOfDayMetrics.earlyDepartureList.map((e, i) => `${fmtNum(i + 1)}. ${e.item.employeeName} (${e.item.departmentName ?? '—'}) · خروج: ${fmtTime(e.lastCheckOut)} [تبكير: ${fmtNum(e.formattedEarlyDeparture)}]`).join('\n')}
━━━━━━━━━━━━━━━━━━━━\n`
      : ''
  }🔐 *كود التحقق الرقمي:* ${securityInfo.code}
رابط التحقق: ${securityInfo.verifyUrl}`;
}

export function buildComparativeAuditWhatsAppText(params: {
  dateFormatted: string;
  comparativeAudit: ComparativeAuditItem[];
  securityCode: string;
}): string {
  const { dateFormatted, comparativeAudit, securityCode } = params;
  return `🔍 *مصفوفة التدقيق والتحقق المنطقي لكشف الحضور (قبل وبعد)*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
━━━━━━━━━━━━━━━━━━━━
${comparativeAudit
  .map(
    (a, i) => `${i + 1}. *${a.metric}*:
   • سابقاً: ${a.oldValue}
   • معتمد الآن: ${a.newValue}
   • السبب: ${a.explanation}`,
  )
  .join('\n\n')}
━━━━━━━━━━━━━━━━━━━━
🔐 *كود التحقق الرقمي:* ${securityCode}`;
}

export function buildLiveAttendanceWhatsAppText(params: {
  dateFormatted: string;
  nowFormatted: string;
  excludeClinics: boolean;
  metrics: ExecutiveMetrics;
  unexcusedAbsentList: ClassifiedEmployee[];
  lateList: ClassifiedEmployee[];
  missionPendingList: ClassifiedEmployee[];
  missionApprovedList: ClassifiedEmployee[];
  leaveList: ClassifiedEmployee[];
  permitList: ClassifiedEmployee[];
  securityInfo: { code: string; verifyUrl: string };
  fmtTime: (iso: string | null | undefined) => string;
  fmtNum: (val: number | string) => string;
}): string {
  const {
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
  } = params;

  return `📋 *كشف المتابعة اليومية للحضور والانصراف (المدير التنفيذي)*
📅 *اليوم:* ${dateFormatted}
🏢 *جمعية خواطر أحلى شباب - الإدارة التنفيذية*
⏰ *توقيت الإصدار:* ${nowFormatted}
${excludeClinics ? `🏥 *ملاحظة:* تم استبعاد طاقم العيادات الطبية (فترة عملهم تبدأ 3:00 عصراً لعدم التأثير على كشف الظهيرة).\n` : ''}━━━━━━━━━━━━━━━━━━━━
${
  metrics.needsDecisionCount > 0
    ? `🚨 *يحتاج قرار فوري من الإدارة (${metrics.needsDecisionCount} حالات):*
• ${metrics.missionsPendingLeft} خرجوا لمأمورية قبل الاعتماد (طلبات معلقة)
${metrics.leavesPendingCount > 0 ? `• ${metrics.leavesPendingCount} طلبات إجازة معلّقة بانتظار الاعتماد\n` : ''}${metrics.permitsPendingCount > 0 ? `• ${metrics.permitsPendingCount} طلبات إذن وتصريح معلّقة بانتظار الاعتماد\n` : ''}• ${metrics.unexcusedAbsent} غياب بدون إذن
• ${metrics.presentLate} متأخرون عن الموعد
━━━━━━━━━━━━━━━━━━━━\n`
    : ''
}📊 *المؤشرات الإجمالية المعتمدة:*
• قوة العمل المجدولة (المطالبة): ${metrics.totalScheduledEmployees} موظف
• الحضور الفعلي: ${metrics.presentTotal} موظف (حضور: ${metrics.actualPresenceRate}% · التزام شامل: ${metrics.overallComplianceRate}%)
• الحاضرون في الموعد: ${metrics.presentOnTime} موظف
• المتأخرون: ${metrics.presentLate} موظف
• المأموريات الرسمية المعتمدة: ${metrics.missionsApproved} موظف
• إجازات وراحات: ${metrics.leavesTotal} موظف (${metrics.leavesApprovedCount} معتمدة · ${metrics.leavesPendingCount} معلقة)
${metrics.permitsTotal > 0 ? `• أذونات وتصاريح: ${metrics.permitsTotal} موظف (${metrics.permitsApprovedCount} معتمدة · ${metrics.permitsPendingCount} معلقة)\n` : ''}• غياب بدون إذن: ${metrics.unexcusedAbsent} موظف
${metrics.shiftNotStartedYet > 0 ? `• فترات مسائية لم تبدأ بعد: ${metrics.shiftNotStartedYet} موظف` : ''}
━━━━━━━━━━━━━━━━━━━━
🔴 *الغياب بدون إذن (${unexcusedAbsentList.length}):*
${
  unexcusedAbsentList.length === 0
    ? '✓ لا يوجد غياب غير مبرر لهذا اليوم'
    : unexcusedAbsentList.map((a, i) => `${i + 1}. ${a.item.employeeName} (${a.item.departmentName ?? '—'}) · ${a.item.shiftName ?? 'دوام رسمي'}`).join('\n')
}

⏱️ *المتأخرون عن موعد الوردية (${lateList.length}):*
${
  lateList.length === 0
    ? '✓ لا يوجد متأخرون'
    : lateList
        .map(
          (l, i) =>
            `${fmtNum(i + 1)}. ${l.item.employeeName} (${l.item.departmentName ?? '—'}) · بصمة: ${fmtTime(l.item.firstCheckIn)} [تأخير: ${fmtNum(l.formattedLate)}]`,
        )
        .join('\n')
}

⚠️ *مأموريات معلقة بانتظار الاعتماد (${missionPendingList.length}):*
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
    : leaveList.map((l, i) => `${i + 1}. ${l.item.employeeName} (${l.item.departmentName ?? '—'}) · ${l.item.leaveName ?? 'إجازة رسمية'}`).join('\n')
}
${
  permitList.length > 0
    ? `\n⏱️ *أذونات وتصاريح العمل (${permitList.length}):*\n` +
      permitList
        .map((p, i) => {
          const badge =
            p.category === 'permit_pending' || p.category === 'present_permit_pending'
              ? `طلب إذن معلق #${p.item.pendingRequestNumber ?? ''}`
              : (p.item.permitTitle ?? 'إذن معتمد');
          const mins = p.item.permitMinutes ? ` (${p.item.permitMinutes} دقيقة)` : '';
          const punch = p.item.firstCheckIn
            ? p.trueLateMinutes === 0
              ? ` · بصمة: ${fmtTime(p.item.firstCheckIn)} (ضمن الإذن ✓)`
              : ` · بصمة: ${fmtTime(p.item.firstCheckIn)} [تجاوز بـ ${p.formattedLate}]`
            : ' · لم يبصم بعد';
          return `${i + 1}. ${p.item.employeeName} (${p.item.departmentName ?? '—'}) · ${badge}${mins}${punch}`;
        })
        .join('\n')
    : ''
}
━━━━━━━━━━━━━━━━━━━━
🔐 *كود التحقق الرقمي:* ${securityInfo.code}
رابط التحقق: ${securityInfo.verifyUrl}`;
}
