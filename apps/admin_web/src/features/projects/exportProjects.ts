import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { printReport, downloadCsv, toCsv, type ExportColumn } from '../../core/exportUtils';
import { APPROVAL_LABELS, LED_META, PRIORITY_LABELS, STATUS_LABELS, activityDays, daysAgoLabel } from './projectLedStatus';

const LED_LABELS: Record<string, string> = Object.fromEntries(Object.entries(LED_META).map(([k, v]) => [k, v.label]));

export function exportProjectsCsv(projects: AssociationProjectListItem[]): void {
  const columns: ExportColumn<AssociationProjectListItem>[] = [
    { key: 'code', header: 'الكود', get: (r) => r.code },
    { key: 'name', header: 'اسم المشروع', get: (r) => r.name },
    { key: 'departmentName', header: 'الإدارة', get: (r) => r.departmentName },
    { key: 'ownerName', header: 'المسؤول', get: (r) => r.ownerName },
    { key: 'status', header: 'الحالة', get: (r) => STATUS_LABELS[r.status] ?? r.status },
    { key: 'approvalStatus', header: 'الموافقة', get: (r) => APPROVAL_LABELS[r.approvalStatus] ?? r.approvalStatus },
    { key: 'priority', header: 'الأولوية', get: (r) => PRIORITY_LABELS[r.priority] ?? r.priority },
    { key: 'ledStatus', header: 'اللمبة', get: (r) => LED_LABELS[r.ledStatus] ?? r.ledStatus },
    { key: 'progress', header: 'نسبة الإنجاز %', get: (r) => r.progress },
    { key: 'completedSteps', header: 'الخطوات المكتملة', get: (r) => r.completedSteps },
    { key: 'remainingSteps', header: 'الخطوات المتبقية', get: (r) => r.remainingSteps },
    { key: 'currentStepTitle', header: 'المرحلة الحالية', get: (r) => r.currentStepTitle ?? '—' },
    { key: 'lastActivityAt', header: 'آخر نشاط', get: (r) => daysAgoLabel(activityDays(r)) },
  ];
  const csv = toCsv(columns, projects);
  downloadCsv(`مشاريع_الجمعية_${new Date().toLocaleDateString('ar-EG')}.csv`, csv);
}

export function exportProjectsPdf(projects: AssociationProjectListItem[]): void {
  const stats = {
    total: projects.length,
    active: projects.filter((p) => p.ledStatus === 'active').length,
    halted: projects.filter((p) => p.ledStatus === 'halted').length,
    critical: projects.filter((p) => p.ledStatus === 'critical').length,
  };

  const statsHtml = `
    <div style="display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap;">
      <div style="flex:1;min-width:120px;padding:12px;background:#f0fdf4;border-radius:8px;text-align:center;border:1px solid #bbf7d0;">
        <div style="font-size:24px;font-weight:900;color:#166534;">${stats.total}</div>
        <div style="font-size:11px;color:#166534;">إجمالي المشاريع</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#ecfdf5;border-radius:8px;text-align:center;border:1px solid #a7f3d0;">
        <div style="font-size:24px;font-weight:900;color:#059669;">${stats.active}</div>
        <div style="font-size:11px;color:#059669;">تعمل بانتظام</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#fef2f2;border-radius:8px;text-align:center;border:1px solid #fecaca;">
        <div style="font-size:24px;font-weight:900;color:#dc2626;">${stats.halted}</div>
        <div style="font-size:11px;color:#dc2626;">متوقفة</div>
      </div>
      <div style="flex:1;min-width:120px;padding:12px;background:#fee2e2;border-radius:8px;text-align:center;border:1px solid #fca5a5;">
        <div style="font-size:24px;font-weight:900;color:#b91c1c;">${stats.critical}</div>
        <div style="font-size:11px;color:#b91c1c;">تحتاج تدخل</div>
      </div>
    </div>`;

  const rows = projects.map((p) => [
    p.code,
    p.name,
    p.departmentName,
    p.ownerName,
    STATUS_LABELS[p.status] ?? p.status,
    APPROVAL_LABELS[p.approvalStatus] ?? p.approvalStatus,
    PRIORITY_LABELS[p.priority] ?? p.priority,
    LED_LABELS[p.ledStatus] ?? p.ledStatus,
    `${p.progress}%`,
    `${p.completedSteps}/${p.totalSteps}`,
    daysAgoLabel(activityDays(p)),
  ]);

  printReport(
    [
      {
        title: 'مشاريع الجمعية',
        subtitle: `تاريخ التصدير: ${new Date().toLocaleDateString('ar-EG')}`,
        table: {
          headers: ['الكود', 'المشروع', 'الإدارة', 'المسؤول', 'الحالة', 'الموافقة', 'الأولوية', 'اللمبة', 'التقدم', 'الخطوات', 'آخر نشاط'],
          rows,
        },
      },
    ],
    'تقارير مشاريع الجمعية',
  );

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
