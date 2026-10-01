import type { AttendanceStatement } from '@ahla/shared-contracts';
import { createPdfRenderer, downloadBlob } from '../../core/pdfExport';
import { attendanceDocumentShell, buildStatementBodyHtml } from './exportAttendancePDF';

export { downloadBlob };

export interface StatementPdfProgress {
  done: number;
  total: number;
}

/**
 * ملفات PDF لكشوف الحضور الشهرية: ملف لكل كشف + ملف شامل (كل موظف يبدأ صفحة
 * جديدة) من رسم واحد لكل كشف — بنفس قالب الطباعة (المحرك الموحّد core/pdfExport).
 * لا يُنزّل شيئاً — يعيد الملفات للمستدعي.
 */
export async function statementsToPdfs(
  statements: { statement: AttendanceStatement; title: string }[],
  combinedTitle: string,
  orgName: string,
  systemName: string,
  onProgress?: (p: StatementPdfProgress) => void,
): Promise<{ combined: Blob | null; files: { title: string; blob: Blob }[] }> {
  const renderer = await createPdfRenderer('landscape');
  const combined = statements.length > 1 ? renderer.newDocument(combinedTitle, systemName) : null;
  const files: { title: string; blob: Blob }[] = [];
  try {
    onProgress?.({ done: 0, total: statements.length });
    for (let i = 0; i < statements.length; i += 1) {
      const { statement, title } = statements[i];
      const pages = await renderer.render(attendanceDocumentShell(title, buildStatementBodyHtml(statement, orgName, systemName)));
      const single = renderer.newDocument(title, systemName);
      renderer.addPages(single, pages, true);
      files.push({ title, blob: single.output('blob') });
      if (combined) renderer.addPages(combined, pages, i === 0);
      onProgress?.({ done: i + 1, total: statements.length });
      // إفساح المجال للواجهة لتحديث شريط التقدم بين الكشوف
      await new Promise((r) => setTimeout(r, 0));
    }
  } finally {
    renderer.dispose();
  }
  return { combined: combined ? combined.output('blob') : null, files };
}
