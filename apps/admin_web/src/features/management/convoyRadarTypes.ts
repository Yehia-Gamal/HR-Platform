export interface ConvoyCheckpoint {
  id: string;
  title: string;
  status: 'pending' | 'in_progress' | 'completed';
  time?: string;
  notes?: string;
  target?: number;
  achieved?: number;
}

export interface ConvoyRadarData {
  id: string;
  name: string;
  origin: string;
  destination: string;
  responsibleName: string;
  status: string;
  departureAt: string;
  passengers: number;
  vehicles: number;
  aidType: string;
  targetAid: number;
  deliveredAid: number;
  checkpoints: ConvoyCheckpoint[];
}

export function generateDefaultCheckpoints(destination: string): ConvoyCheckpoint[] {
  return [
    {
      id: 'cp-1',
      title: 'الانطلاق من المقر الرئيسي وتجهيز الشاحنات',
      status: 'completed',
      time: '07:30 ص',
      notes: 'تم فحص المركبات وحضور طاقم المتطوعين وشحن المساعدات بالكامل.',
    },
    {
      id: 'cp-2',
      title: `الوصول لنقطة التجمع الميداني (${destination})`,
      status: 'in_progress',
      time: '09:45 ص',
      notes: 'الوصول لمقر الوحدة المحلية والبدء في التنسيق مع لجان القرية.',
    },
    {
      id: 'cp-3',
      title: 'نقطة التوزيع الرئيسية (الأسر المستحقة)',
      status: 'pending',
      target: 150,
      achieved: 0,
      notes: 'توزيع كراتين المواد الغذائية والبطاطين بنظام الكوبونات.',
    },
    {
      id: 'cp-4',
      title: 'نقطة التوزيع الفرعية والمسح الميداني للحالات',
      status: 'pending',
      target: 100,
      achieved: 0,
      notes: 'زيارة كبار السن وذوي الهمم في المنازل وتسليم المساعدات.',
    },
    {
      id: 'cp-5',
      title: 'انتهاء أعمال القافلة والعودة للمقر الرئيسي',
      status: 'pending',
      notes: 'حصر المتبقي وتسليم عهدة القافلة وكتابة التقرير الختامي.',
    },
  ];
}

export function formatConvoyWhatsAppBroadcast(convoy: ConvoyRadarData): string {
  const percent = convoy.targetAid > 0 ? Math.round((convoy.deliveredAid / convoy.targetAid) * 100) : 0;

  const currentCp =
    convoy.checkpoints.find((c) => c.status === 'in_progress') || convoy.checkpoints.filter((c) => c.status === 'completed').pop() || convoy.checkpoints[0];

  const lines: string[] = [
    '🚌 *بث مستجدات القافلة الميدانية — جمعية أحلى شباب* 🚌',
    '',
    `📍 القافلة: *«${convoy.name}»*`,
    `🛣️ خط السير: *${convoy.origin} ← ${convoy.destination}*`,
    `👤 المسؤول الميداني: *${convoy.responsibleName}*`,
    `👥 الطاقم: *${convoy.passengers} فرد / متطوع* | 🚐 *${convoy.vehicles} مركبات*`,
    '',
    `📦 نوع المساعدات: *${convoy.aidType}*`,
    `📊 نسبة إنجاز التوزيع: *${convoy.deliveredAid} من ${convoy.targetAid} (${percent}%)*`,
    '',
    `🚩 المحطة الحالية: *${currentCp?.title || 'المسار الميداني'}*`,
  ];

  if (currentCp?.notes) {
    lines.push(`📝 الملاحظات: ${currentCp.notes}`);
  }

  lines.push('');
  lines.push('دعواتكم لفريق الميدان والمتطوعين بالتيسير والقبول 💚🌿');
  lines.push('— *غرفة عمليات جمعية أحلى شباب*');

  return lines.join('\n');
}
