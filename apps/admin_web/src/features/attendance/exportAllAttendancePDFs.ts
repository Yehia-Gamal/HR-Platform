import { attendanceStatementSchema, type AttendanceStatement } from '@ahla/shared-contracts';
import type { EmployeeSummary } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';

const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

const ORG = 'جمعية خواطر أحلى شباب';
const SYSTEM = 'منظومة أحلى شباب الإدارية';

export interface ExportProgress {
  done: number;
  total: number;
  /** fetch = تحميل الكشوف من الخادم، pdf = إنشاء ملفات PDF. */
  phase?: 'fetch' | 'pdf';
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

/**
 * تصدير كشوف الحضور الشهري لكافة الموظفين كملفات PDF:
 * - ملف PDF شامل يضم الجميع، كل موظف يبدأ صفحة جديدة.
 * - ملف PDF منفصل لكل موظف.
 * تُنزَّل الملفات مباشرة بمهلة قصيرة بينها حتى لا يحجب المتصفح التنزيلات المتعددة.
 */
export async function exportAllAttendancePdfs(
  employees: EmployeeSummary[],
  year: number,
  month: number,
  onProgress?: (p: ExportProgress) => void,
): Promise<{ exported: number; skipped: number }> {
  const monthLabel = MONTHS[month - 1] ?? String(month);
  const statements: AttendanceStatement[] = [];
  let skipped = 0;

  onProgress?.({ done: 0, total: employees.length, phase: 'fetch' });
  for (let i = 0; i < employees.length; i += 1) {
    try {
      statements.push(await fetchStatement(employees[i].id, year, month));
    } catch {
      skipped += 1;
    }
    onProgress?.({ done: i + 1, total: employees.length, phase: 'fetch' });
  }
  if (statements.length === 0) return { exported: 0, skipped };

  const { statementsToPdfs, downloadBlob } = await import('./statementPdf');
  const { combined, files } = await statementsToPdfs(
    statements.map((s) => ({ statement: s, title: `كشف حضور — ${s.employee.fullNameAr} — ${monthLabel} ${year}` })),
    `كشف الحضور الشامل — ${monthLabel} ${year}`,
    ORG,
    SYSTEM,
    (p) => onProgress?.({ ...p, phase: 'pdf' }),
  );

  if (combined) downloadBlob(combined, `كشف-الحضور-الشامل-${monthLabel}-${year}.pdf`);
  for (let i = 0; i < statements.length; i += 1) {
    const emp = statements[i].employee;
    const name = safeFileNameSegment(`${emp.employeeCode ?? ''}-${emp.fullNameAr}`);
    downloadBlob(files[i].blob, `كشف-حضور-${name}-${monthLabel}-${year}.pdf`);
    await new Promise((r) => setTimeout(r, 300));
  }
  return { exported: statements.length, skipped };
}

function safeFileNameSegment(s: string): string {
  return (
    s
      .replace(/[\\/:*?"<>|]/g, '')
      .trim()
      .slice(0, 40) || 'موظف'
  );
}
