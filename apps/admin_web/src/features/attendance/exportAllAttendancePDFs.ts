import { attendanceStatementSchema, type AttendanceStatement } from '@ahla/shared-contracts';
import type { EmployeeSummary } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';
import { attendanceDocumentShell, buildStatementBodyHtml, esc } from './exportAttendancePDF';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

const ORG = 'جمعية خواطر أحلى شباب';
const SYSTEM = 'منظومة أحلى شباب الإدارية';

export interface ExportProgress {
  done: number;
  total: number;
}

/** جلب كشف الحضور الشهري لموظف عبر RPC (نفس مسار الصفحة). */
async function fetchStatement(employeeId: string, year: number, month: number): Promise<AttendanceStatement> {
  const data = await rpc('get_employee_monthly_attendance_statement', {
    p_employee_id: employeeId,
    p_year: year,
    p_month: month,
  });
  return attendanceStatementSchema.parse(data);
}

/** تحميل نص كمستند HTML باسم ملف عربي. */
function downloadHtmlFile(filename: string, html: string): void {
  const blob = new Blob(['\uFEFF' + html], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function safeFileNameSegment(s: string): string {
  return s.replace(/[\\/:*?"<>|]/g, '').trim().slice(0, 40) || 'موظف';
}

/**
 * طباعة/تصدير كشوف الحضور الشهري لكافة الموظفين:
 * - ملف HTML منفصل لكل موظف (جاهز للطباعة/الحفظ كـ PDF).
 * - ملف HTML شامل يضم الجميع، كل موظف على صفحة مستقلة.
 * تُنزَّل الملفات مباشرة بدل فتح نوافذ طباعة متعددة (يمنعها المتصفح).
 */
export async function exportAllAttendancePdfs(
  employees: EmployeeSummary[],
  year: number,
  month: number,
  onProgress?: (p: ExportProgress) => void,
): Promise<{ exported: number; skipped: number }> {
  const monthLabel = MONTHS[month - 1] ?? month;
  const statements: AttendanceStatement[] = [];
  const failed: string[] = [];

  onProgress?.({ done: 0, total: employees.length });

  // الجمع بين طلبات أصغر لتفادي إغراق الخادم، مع فتح نافذة التحميل لكل موظف.
  // تُجلب البيانات أولاً ثم تُنزَّل الملفات واحدًا تلو الآخر بمهلة صغيرة لتفادي
  // منع المتصفح للتحميلات المتعددة.
  for (let i = 0; i < employees.length; i += 1) {
    const emp = employees[i];
    try {
      const stmt = await fetchStatement(emp.id, year, month);
      statements.push(stmt);
    } catch {
      failed.push(emp.fullNameAr);
      statements.push(null as unknown as AttendanceStatement);
    }
    onProgress?.({ done: i + 1, total: employees.length });
  }

  // الملف الشامل: كل موظف على صفحة مستقلة.
  const combinedBody = statements
    .filter((s): s is AttendanceStatement => Boolean(s))
    .map((s) => `<div class="page-break">${buildStatementBodyHtml(s, ORG, SYSTEM)}</div>`)
    .join('\n');

  if (combinedBody) {
    downloadHtmlFile(
      `كشف-الحضور-الشامل-${monthLabel}-${year}.html`,
      attendanceDocumentShell(`كشف الحضور الشامل — ${monthLabel} ${year}`, `<div class="page">${combinedBody}</div>`),
    );
  }

  // ملف منفصل لكل موظف — مهلة بسيطة بين التنزيلات لتجنب حظر المتصفح.
  for (let i = 0; i < statements.length; i += 1) {
    const stmt = statements[i];
    if (!stmt) continue;
    const emp = stmt.employee;
    const name = safeFileNameSegment(`${emp.employeeCode ?? ''}-${emp.fullNameAr}`);
    downloadHtmlFile(`كشف-حضور-${name}-${monthLabel}-${year}.html`, attendanceDocumentShell(`كشف حضور — ${emp.fullNameAr} — ${monthLabel} ${year}`, buildStatementBodyHtml(stmt, ORG, SYSTEM)));
    // مهلة قصيرة غير مُنتظرة لإتاحة متصفح التنزيلات المتعددة
    await new Promise((r) => setTimeout(r, 250));
  }

  return { exported: statements.filter(Boolean).length, skipped: failed.length };
}
