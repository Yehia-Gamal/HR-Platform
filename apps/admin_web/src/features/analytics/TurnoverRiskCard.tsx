import { AlertTriangle, CheckCircle, ShieldAlert, Sparkles, TrendingUp, UserX } from 'lucide-react';
import type { TurnoverRiskAssessment } from './turnoverRiskEngine';

interface TurnoverRiskCardProps {
  assessment: TurnoverRiskAssessment;
  onInitiateRetentionPlan?: () => void;
}

export function TurnoverRiskCard({ assessment, onInitiateRetentionPlan }: TurnoverRiskCardProps) {
  const isCritical = assessment.riskLevel === 'critical';
  const isHigh = assessment.riskLevel === 'high';
  const isMedium = assessment.riskLevel === 'medium';

  const badgeColor = isCritical
    ? 'bg-rose-500/15 text-rose-600 border-rose-500/30'
    : isHigh
      ? 'bg-amber-500/15 text-amber-600 border-amber-500/30'
      : isMedium
        ? 'bg-yellow-500/15 text-yellow-700 border-yellow-500/30'
        : 'bg-emerald-500/15 text-emerald-600 border-emerald-500/30';

  const riskLabel = isCritical
    ? 'حرج جداً (خطر استقالة وشيك)'
    : isHigh
      ? 'مرتفع (مؤشرات تسرب واضحة)'
      : isMedium
        ? 'متوسط (تذبذب بحاجة لمتابعة)'
        : 'منخفض ومستقر (ارتباط وظيفي قوي)';

  return (
    <div className="card p-5 space-y-4 border rounded-2xl bg-[var(--surface)] text-right">
      {/* Header */}
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div className={`size-10 rounded-xl flex items-center justify-center ${badgeColor}`}>
            {isCritical || isHigh ? <ShieldAlert className="size-5" /> : <TrendingUp className="size-5" />}
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-black text-[var(--text)]">مؤشر مخاطر التسرب الوظيفي الذكي</h3>
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] font-bold flex items-center gap-1">
                <Sparkles className="size-3" />
                تحليل تنبؤي
              </span>
            </div>
            <p className="text-xs text-[var(--text-muted)] mt-0.5">
              خوارزمية ذكية لتحليل الارتباط ورصد بوادر الاستقالة المبكرة
            </p>
          </div>
        </div>

        <div className={`px-3 py-1 rounded-full border text-xs font-black ${badgeColor}`}>
          {assessment.overallScore}% — {riskLabel}
        </div>
      </div>

      {/* شريط مقياس الخطورة */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-[11px] font-bold text-[var(--text-muted)]">
          <span>احتمالية الرغبة في ترك العمل</span>
          <span className="font-mono">{assessment.overallScore} / 100</span>
        </div>
        <div className="h-2.5 w-full bg-[var(--surface-muted)] rounded-full overflow-hidden p-0.5 border border-[var(--border)]">
          <div
            className={`h-full rounded-full transition-all duration-500 ${
              isCritical
                ? 'bg-rose-500'
                : isHigh
                  ? 'bg-amber-500'
                  : isMedium
                    ? 'bg-yellow-500'
                    : 'bg-emerald-500'
            }`}
            style={{ width: `${Math.max(5, assessment.overallScore)}%` }}
          />
        </div>
      </div>

      {/* العوامل الأكثر تأثيراً */}
      {assessment.topFactors.length > 0 && (
        <div className="space-y-2 pt-2 border-t border-[var(--border)]">
          <h4 className="text-xs font-bold text-[var(--text)]">أهم العوامل المؤدية لارتفاع المؤشر:</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {assessment.topFactors.slice(0, 4).map((f) => (
              <div
                key={f.id}
                className="p-2.5 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)]/40 text-xs space-y-1"
              >
                <div className="flex items-center justify-between font-bold text-[var(--text)]">
                  <span>{f.name}</span>
                  <span className="text-[10px] font-mono text-rose-500">+{f.impactScore}%</span>
                </div>
                <p className="text-[11px] text-[var(--text-muted)] leading-relaxed">{f.description}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* الإجراء الاحتوائي الموصى به للموارد البشرية */}
      <div className="p-3.5 rounded-xl bg-blue-500/10 border border-blue-500/20 text-xs space-y-2">
        <div className="flex items-center gap-1.5 font-bold text-blue-800 dark:text-blue-300">
          <CheckCircle className="size-4 shrink-0" />
          توصية الذكاء الاصطناعي التشغيلي للتدخل السريع:
        </div>
        <p className="text-[var(--text)] leading-relaxed">{assessment.recommendedAction}</p>

        {onInitiateRetentionPlan && (
          <div className="pt-2 flex justify-end">
            <button
              type="button"
              onClick={onInitiateRetentionPlan}
              className="btn-primary text-xs py-1.5 px-3.5 flex items-center gap-1.5 shadow-sm"
            >
              <UserX className="size-3.5" />
              بدء خطة استبقاء الموظف (Retention Plan)
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
