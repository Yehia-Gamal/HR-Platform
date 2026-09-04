import { useState, useMemo } from 'react';
import { Sparkles, AlertCircle, CheckCircle, RefreshCw, Layers } from 'lucide-react';
import type { DailyReportFeedItem } from '@ahla/shared-contracts';

interface DailyReportsSummarizerCardProps {
  reports: DailyReportFeedItem[];
}

export function DailyReportsSummarizerCard({ reports }: DailyReportsSummarizerCardProps) {
  const [isGenerating, setIsGenerating] = useState(false);
  const [customSummary, setCustomSummary] = useState<string | null>(null);

  // تحليل فوري للمعوقات والإنجازات بدون أي خوادم خارجية
  const analytics = useMemo(() => {
    const totalReports = reports.length;
    const uniqueEmployees = new Set(reports.map((r) => r.employeeId)).size;

    const allBlockers = reports
      .map((r) => r.blockers?.trim())
      .filter((b): b is string => Boolean(b && b.length > 3 && b !== 'لا يوجد' && b !== 'لا توجد'));

    const allAchievements = reports
      .map((r) => r.achievements?.trim())
      .filter((a): a is string => Boolean(a && a.length > 5));

    return {
      totalReports,
      uniqueEmployees,
      blockersCount: allBlockers.length,
      blockersList: allBlockers.slice(0, 5),
      achievementsCount: allAchievements.length,
      achievementsSample: allAchievements.slice(0, 3),
    };
  }, [reports]);

  const generateSmartSummary = () => {
    setIsGenerating(true);
    setTimeout(() => {
      let text = `تم استلام ${analytics.totalReports} تقريراً يومياً من ${analytics.uniqueEmployees} موظفاً. `;
      if (analytics.blockersCount > 0) {
        text += `رُصدت (${analytics.blockersCount}) معوقات تشغيلية ميدانية تستوجب انتباه الإدارة، أبرزها: "${analytics.blockersList[0] || 'مشاكل توريد أو شبكة'}". `;
      } else {
        text += 'تسير العمليات الميدانية بسلاسة دون تسجيل أي معوقات حرجة من الفرق اليوم. ';
      }
      text += `تم إنجاز ${analytics.achievementsCount} مهمة ومحطة رئيسية تركزت حول استكمال مستهدفات الورديات ومتابعة العملاء.`;
      setCustomSummary(text);
      setIsGenerating(false);
    }, 400);
  };

  if (reports.length === 0) return null;

  return (
    <div className="card p-5 border rounded-2xl bg-gradient-to-br from-[var(--surface)] to-[var(--surface-muted)] text-right space-y-4 shadow-sm border-[var(--border)]">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] pb-3">
        <div className="flex items-center gap-2.5">
          <div className="size-10 rounded-xl bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] flex items-center justify-center">
            <Sparkles className="size-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-black text-[var(--text)]">الملخص التنفيذي الذكي للتقارير اليومية</h3>
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-600 font-bold">
                تحليل فوري مجاني
              </span>
            </div>
            <p className="text-xs text-[var(--text-muted)]">
              تلخيص تقارير الموظفين الميدانيين تلقائياً لإبراز المعوقات التشغيلية الحيوية
            </p>
          </div>
        </div>

        <button
          type="button"
          onClick={generateSmartSummary}
          disabled={isGenerating}
          className="btn-secondary text-xs flex items-center gap-1.5 py-1.5 px-3"
        >
          <RefreshCw className={`size-3.5 ${isGenerating ? 'animate-spin' : ''}`} />
          {customSummary ? 'إعادة التلخيص' : 'توليد الموجز التنفيذي'}
        </button>
      </div>

      {/* ملخص الإحصائيات السريعة */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <div className="p-3 rounded-xl border border-[var(--border)] bg-[var(--surface)]">
          <div className="text-[11px] text-[var(--text-muted)]">إجمالي التقارير المرفوعة</div>
          <div className="text-lg font-black text-[var(--text)] mt-0.5">{analytics.totalReports}</div>
        </div>

        <div className="p-3 rounded-xl border border-[var(--border)] bg-[var(--surface)]">
          <div className="text-[11px] text-[var(--text-muted)]">معوقات تشغيلية مرصودة</div>
          <div className={`text-lg font-black mt-0.5 ${analytics.blockersCount > 0 ? 'text-rose-500' : 'text-emerald-500'}`}>
            {analytics.blockersCount}
          </div>
        </div>

        <div className="p-3 rounded-xl border border-[var(--border)] bg-[var(--surface)] col-span-2 sm:col-span-1">
          <div className="text-[11px] text-[var(--text-muted)]">المهام المنجزة اليوم</div>
          <div className="text-lg font-black text-blue-500 mt-0.5">{analytics.achievementsCount}</div>
        </div>
      </div>

      {/* فقرة الملخص التنفيذي */}
      {customSummary && (
        <div className="p-4 rounded-xl bg-blue-500/10 border border-blue-500/20 text-xs leading-relaxed space-y-2">
          <div className="font-bold text-blue-800 dark:text-blue-300 flex items-center gap-1.5">
            <Sparkles className="size-4" />
            موجز الإدارة التنفيذية لليوم:
          </div>
          <p className="text-[var(--text)] text-sm font-medium">{customSummary}</p>
        </div>
      )}

      {/* المعوقات البارزة التي تتطلب تدخلاً */}
      {analytics.blockersList.length > 0 && (
        <div className="space-y-2 pt-2 border-t border-[var(--border)]">
          <div className="flex items-center gap-1.5 text-xs font-bold text-rose-600">
            <AlertCircle className="size-4 shrink-0" />
            أهم المعوقات الميدانية التي أبلغ عنها الموظفون اليوم:
          </div>
          <div className="space-y-1.5">
            {analytics.blockersList.map((blocker, idx) => (
              <div
                key={idx}
                className="text-xs p-2.5 rounded-lg bg-rose-500/5 border border-rose-500/15 text-[var(--text)] flex items-start gap-2"
              >
                <span className="size-1.5 rounded-full bg-rose-500 mt-1.5 shrink-0" />
                <span className="leading-relaxed">{blocker}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
