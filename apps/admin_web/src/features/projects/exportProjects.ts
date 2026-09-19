import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { printReport, downloadCsv, toCsv, type ExportColumn } from '../../core/exportUtils';

const LED_LABELS: Record<string, string> = { active: 'نشط', halted: 'متوقف', stale: 'مطفأ' };
const STATUS_LABELS: Record<string, string> = { planned: 'مخطط', active: 'نشط', on_hold: 'متوقف', completed: 'مكتمل', cancelled: 'ملغى' };
const PRIORITY_LABELS: Record<string, string> = { low: 'منخفضة', medium: 'متوسطة', high: 'عالية', critical: 'حرجة' };

export function exportProjectsCsv(projects: AssociationProjectListItem[]): void {
  const columns: ExportColumn<AssociationProjectListItem>[] = [
    { key: 'code', header: 'الكود', get: (r) => r.code },
    { key: 'name', header: 'اسم المشروع', get: (r) => r.name },
    { key: 'departmentName', header: 'الإدارة', get: (r) => r.departmentName },
    { key: 'ownerName', header: 'المسؤول', get: (r) => r.ownerName },
    { key: 'status', header: 'الحالة', get: (r) => STATUS_LABELS[r.status] ?? r.status },
    { key: 'priority', header: 'الأولوية', get: (r) => PRIORITY_LABELS[r.priority] ?? r.priority },
    { key: 'ledStatus', header: 'LED', get: (r) => LED_LABELS[r.ledStatus] ?? r.ledStatus },
    { key: 'progress', header: 'نسبة الإنجاز %', get: (r) => r.progress },
    { key: 'completedSteps', header: 'الخطوات المكتملة', get: (r) => r.completedSteps },
    { key: 'remainingSteps', header: 'الخطوات المتبقية', get: (r) => r.remainingSteps },
    { key: 'lastUpdateAt', header: 'آخر تحديث', get: (r) => r.lastUpdateAt ? new Date(r.lastUpdateAt).toLocaleDateString('ar-EG') : '—' },
  ];
  const csv = toCsv(columns, projects);
  downloadCsv(`مشاريع_الجمعية_${new Date().toLocaleDateString('ar-EG')}.csv`, csv);
}

export function exportProjectsPdf(projects: AssociationProjectListItem[]): void {
  const stats = {
    total: projects.length,
    active: projects.filter((p) => p.ledStatus === 'active').length,
    halted: projects.filter((p) => p.ledStatus === 'halted').length,
    stale: projects.filter((p) => p.ledStatus === 'stale').length,
  };

  const statsHtml = `
    <div style="display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap;">
      <div style="flex:1;min-width:120px;padding:12px;background:#f0fdf4;border-radius:8px;text-align:center;border:1px solid #bbf7d0;">
        <div style="font-size:24px;font-weight:900;color:#166534;">${stats.total}</div>
        <div style="font-size:11px;color:#166534;">إجمالي المشاريع</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#ecfdf5;border-radius:8px;text-align:center;border:1px solid #a7f3d0;">
        <div style="font-size:24px;font-weight:900;color:#059669;">${stats.active}</div>
        <div style="font-size:11px;color:#059669;">نشطة</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#fef2f2;border-radius:8px;text-align:center;border:1px solid #fecaca;">
        <div style="font-size:24px;font-weight:900;color:#dc2626;">${stats.halted}</div>
        <div style="font-size:11px;color:#dc2626;">متوقفة</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#f3f4f6;border-radius:8px;text-align:center;border:1px solid #d1d5db;">
        <div style="font-size:24px;font-weight:900;color:#6b7280;">${stats.stale}</div>
        <div style="font-size:11px;color:#6b7280;">مطفأة</div>
      </div>
    </div>`;

  const rows = projects.map((p) => [
    p.code,
    p.name,
    p.departmentName,
    p.ownerName,
    STATUS_LABELS[p.status] ?? p.status,
    PRIORITY_LABELS[p.priority] ?? p.priority,
    LED_LABELS[p.ledStatus] ?? p.ledStatus,
    `${p.progress}%`,
    `${p.completedSteps}/${p.completedSteps + p.remainingSteps}`,
    p.lastUpdateAt ? new Date(p.lastUpdateAt).toLocaleDateString('ar-EG') : '—',
  ]);

  printReport([{
    title: 'مشاريع الجمعية',
    subtitle: `تاريخ التصدير: ${new Date().toLocaleDateString('ar-EG')}`,
    table: {
      headers: ['الكود', 'المشروع', 'الإدارة', 'المسؤول', 'الحالة', 'الأولوية', 'LED', 'التقدم', 'الخطوات', 'آخر تحديث'],
      rows,
    },
  }], 'تقارير مشاريع الجمعية');

  // نحقن الإحصائيات بعد فتح النافذة
  setTimeout(() => {
    const frames = document.querySelectorAll('iframe');
    const lastFrame = frames[frames.length - 1] as HTMLIFrameElement | undefined;
    if (lastFrame?.contentDocument) {
      const body = lastFrame.contentDocument.body;
      const statsContainer = document.createElement('div');
      statsContainer.innerHTML = statsHtml;
      body.insertBefore(statsContainer, body.firstChild);
    }
  }, 500);
}
