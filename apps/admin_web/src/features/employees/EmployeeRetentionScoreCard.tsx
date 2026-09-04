import { AlertTriangle, CheckCircle2, HeartHandshake, ShieldCheck, Sparkles } from 'lucide-react';
import type { Employee360 } from '@ahla/shared-contracts';

interface EmployeeRetentionScoreCardProps {
  employee: Employee360;
}

export function EmployeeRetentionScoreCard({ employee }: EmployeeRetentionScoreCardProps) {
  const { present, lateDays, absent } = employee.attendance30;
  const kpiScore = typeof employee.latestKpi?.finalScore === 'number' ? employee.latestKpi.finalScore : null;

  // احتساب مؤشر الاستقرار والولاء التنبؤي (0 - 100)
  let score = 95;
  score -= absent * 8;
  score -= lateDays * 3;

  if (kpiScore !== null) {
    if (kpiScore >= 85) score += 5;
    else if (kpiScore < 70) score -= 10;
  }

  // الحفاظ على النطاق بين 15 و 100
  const finalScore = Math.min(100, Math.max(15, score));

  // تصنيف مستوى الاستقرار والتوصية الإدارية
  const analysis = (() => {
    if (finalScore >= 85) {
      return {
        level: 'استقرار والتزام ممتاز',
        colorClass: 'text-emerald-500',
        bgClass: 'bg-emerald-500/10 border-emerald-500/30',
        barColor: 'bg-emerald-500',
        icon: CheckCircle2,
        recommendation:
          'الموظف يظهر التزاماً استثنائياً وانضباطاً عالياً في الحضور والأداء. يُوصى بمنحه وسام تميز أو ترشيحه للمكافآت التقديرية والمهام القيادية.',
      };
    }
    if (finalScore >= 70) {
      return {
        level: 'استقرار جيد وانضباط متوازن',
        colorClass: 'text-sky-500',
        bgClass: 'bg-sky-500/10 border-sky-500/30',
        barColor: 'bg-sky-500',
        icon: ShieldCheck,
        recommendation:
          'مؤشرات الحضور والأداء مستقرة وضمن المعدلات المستهدفة. استمرار التغذية الراجعة الدورية يحافظ على مستوى الحافز.',
      };
    }
    if (finalScore >= 50) {
      return {
        level: 'مؤشرات إجهاد تتطلب متابعة',
        colorClass: 'text-amber-500',
        bgClass: 'bg-amber-500/10 border-amber-500/30',
        barColor: 'bg-amber-500',
        icon: AlertTriangle,
        recommendation:
          'لوحظ تكرار التأخيرات أو تذبذب الحضور خلال الشهر الأخير؛ يُنصح بعقد جلسة ودية من المدير المباشر لفهم التحديات وتقديم الدعم الإداري.',
      };
    }
    return {
      level: 'خطر تسرب أو انقطاع وظيفي مرتفع',
      colorClass: 'text-rose-500',
      bgClass: 'bg-rose-500/10 border-rose-500/30',
      barColor: 'bg-rose-500',
      icon: AlertTriangle,
      recommendation:
        'تكرار الغياب والانخفاض في مؤشرات الأداء يشير إلى احتمالية عالية لمغادرة العمل أو عدم الرضا. يلزم تدخل فوري من الموارد البشرية لمعالجة الأسباب.',
    };
  })();

  const StatusIcon = analysis.icon;

  return (
    <section className="card p-5 border border-[var(--border)] space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border)] pb-3">
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 items-center justify-center rounded-xl bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]">
            <HeartHandshake className="size-5" aria-hidden="true" />
          </div>
          <div>
            <h3 className="font-black text-sm text-[var(--text)]">مؤشر الاستقرار والولاء الوظيفي (AI Retention Index)</h3>
            <p className="text-xs text-[var(--text-muted)]">تحليل تنبؤي مبني على أنماط الانضباط وأحدث تقييمات الأداء</p>
          </div>
        </div>

        <div className={`flex items-center gap-1.5 px-3 py-1 rounded-full border text-xs font-black ${analysis.bgClass} ${analysis.colorClass}`}>
          <StatusIcon className="size-3.5" aria-hidden="true" />
          <span>{analysis.level}</span>
        </div>
      </div>

      {/* شريط المؤشر والنسبة المئوية */}
      <div className="space-y-2">
        <div className="flex items-center justify-between text-xs font-bold">
          <span className="text-[var(--text-muted)]">مستوى الصحة والاستقرار العام:</span>
          <span className={`text-base font-black tabular ${analysis.colorClass}`}>{finalScore}%</span>
        </div>
        <div className="h-2.5 w-full overflow-hidden rounded-full bg-[var(--surface-muted)]">
          <div
            className={`h-full transition-all duration-500 rounded-full ${analysis.barColor}`}
            style={{ width: `${finalScore}%` }}
          />
        </div>
      </div>

      {/* شبكة العوامل المؤثرة */}
      <div className="grid gap-2 sm:grid-cols-3 pt-1">
        <div className="rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/30 p-2.5 text-center">
          <span className="text-[11px] font-bold text-[var(--text-muted)] block">أيام الحضور (30 يوم)</span>
          <span className="text-sm font-black text-[var(--text)] tabular mt-0.5 block">{present} يوم</span>
        </div>
        <div className="rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/30 p-2.5 text-center">
          <span className="text-[11px] font-bold text-[var(--text-muted)] block">أيام التأخير والغياب</span>
          <span className="text-sm font-black text-[var(--text)] tabular mt-0.5 block">
            {lateDays} تأخير • {absent} غياب
          </span>
        </div>
        <div className="rounded-lg border border-[var(--border)] bg-[var(--surface-muted)]/30 p-2.5 text-center">
          <span className="text-[11px] font-bold text-[var(--text-muted)] block">أحدث تقييم أداء</span>
          <span className="text-sm font-black text-[var(--text)] tabular mt-0.5 block">
            {kpiScore !== null ? `${kpiScore}%` : 'قيد التقييم'}
          </span>
        </div>
      </div>

      {/* صندوق التوصية الإدارية */}
      <div className={`flex items-start gap-2.5 p-3 rounded-xl border ${analysis.bgClass}`}>
        <Sparkles className={`size-4 shrink-0 mt-0.5 ${analysis.colorClass}`} aria-hidden="true" />
        <div className="space-y-0.5">
          <span className="text-xs font-black text-[var(--text)] block">التوصية الإدارية المقترحة:</span>
          <p className="text-xs text-[var(--text)] leading-relaxed">{analysis.recommendation}</p>
        </div>
      </div>
    </section>
  );
}
