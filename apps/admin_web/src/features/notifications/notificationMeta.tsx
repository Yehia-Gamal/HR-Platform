import {
  Award,
  Bell,
  BriefcaseBusiness,
  CalendarDays,
  ClipboardCheck,
  FileText,
  Fingerprint,
  Gavel,
  HeartHandshake,
  MapPin,
  Megaphone,
  MessageSquare,
  ScrollText,
  Settings,
  ShieldCheck,
  ThumbsUp,
  UserCheck,
  Users,
  Vote,
  type LucideIcon,
} from 'lucide-react';

/** تسميات عربية لتصنيفات الإشعارات (category في جدول notifications). */
export const NOTIFICATION_CATEGORY_LABELS: Record<string, string> = {
  general: 'عام',
  decision: 'قرار رسمي',
  announcement: 'إعلان',
  survey: 'استبيان',
  request: 'طلب',
  dispute: 'قضية',
  recognition: 'تقدير',
  system: 'نظام',
  kpi: 'الأداء',
  device: 'جهاز بصمة',
  attendance: 'حضور',
  location: 'موقع',
  security: 'أمان',
  privacy: 'خصوصية',
  documents: 'مستندات',
  service: 'خدمة',
  wellbeing: 'رفاهية',
  offboarding: 'إنهاء خدمة',
  daily_report: 'تقرير يومي',
  daily_report_like: 'إعجاب بتقرير',
  daily_report_comment: 'تعليق على تقرير',
  attendance_manager_notify: 'حضور',
};

/** أيقونة كل تصنيف إشعار. */
export function notificationCategoryIcon(category: string): LucideIcon {
  return (
    {
      decision: ScrollText,
      announcement: Megaphone,
      survey: Vote,
      request: ClipboardCheck,
      dispute: Gavel,
      recognition: Award,
      system: Settings,
      kpi: UserCheck,
      device: Fingerprint,
      attendance: CalendarDays,
      location: MapPin,
      security: ShieldCheck,
      privacy: ShieldCheck,
      documents: FileText,
      service: BriefcaseBusiness,
      wellbeing: HeartHandshake,
      offboarding: Users,
      daily_report: FileText,
      daily_report_like: ThumbsUp,
      daily_report_comment: MessageSquare,
      attendance_manager_notify: CalendarDays,
    }[category] ?? Bell
  );
}

/** تسمية عربية لتصنيف إشعار (مع fallback للقيمة الخام). */
export function notificationCategoryLabel(category: string): string {
  return NOTIFICATION_CATEGORY_LABELS[category] ?? category;
}

/** هل الأولوية تستحق إبرازاً خاصاً في القوائم؟ */
export function isUrgentPriority(priority: string): boolean {
  return priority === 'urgent' || priority === 'high';
}
