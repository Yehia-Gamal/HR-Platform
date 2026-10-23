import type { ExecutiveMetrics } from './executiveReportLogic';

interface Props {
  metrics: ExecutiveMetrics;
  isLight?: boolean;
  numberSystem?: 'latn' | 'arab';
}

interface ChartSlice {
  key: string;
  label: string;
  count: number;
  pct: number;
  color: string;
  glowColor: string;
}

export function ExecutiveWorkforceChart({ metrics, isLight = false, numberSystem = 'latn' }: Props) {
  const total = Math.max(1, metrics.totalScheduledEmployees + metrics.shiftNotStartedYet);

  const fmt = (v: number | string) => {
    if (numberSystem === 'arab') {
      return String(v).replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
    }
    return String(v);
  };

  const slices: ChartSlice[] = [
    {
      key: 'on_time',
      label: 'حضور منتظم',
      count: metrics.presentOnTime,
      pct: Math.round((metrics.presentOnTime / total) * 1000) / 10,
      color: '#10b981', // emerald-500
      glowColor: 'rgba(16, 185, 129, 0.4)',
    },
    {
      key: 'approved_mission_leave',
      label: 'في إجازة / مأمورية معتمدة',
      count: metrics.missionsApproved + metrics.leavesTotal,
      pct: Math.round(((metrics.missionsApproved + metrics.leavesTotal) / total) * 1000) / 10,
      color: '#38bdf8', // sky-400
      glowColor: 'rgba(56, 189, 248, 0.4)',
    },
    {
      key: 'late',
      label: 'متأخرون',
      count: metrics.presentLate,
      pct: Math.round((metrics.presentLate / total) * 1000) / 10,
      color: '#f59e0b', // amber-500
      glowColor: 'rgba(245, 158, 11, 0.4)',
    },
    {
      key: 'pending_mission',
      label: 'خرج قبل الاعتماد (معلق)',
      count: metrics.missionsPendingLeft,
      pct: Math.round((metrics.missionsPendingLeft / total) * 1000) / 10,
      color: '#f97316', // orange-500
      glowColor: 'rgba(249, 115, 22, 0.4)',
    },
    {
      key: 'absent',
      label: 'غياب بدون إذن',
      count: metrics.unexcusedAbsent,
      pct: Math.round((metrics.unexcusedAbsent / total) * 1000) / 10,
      color: '#f43f5e', // rose-500
      glowColor: 'rgba(244, 63, 94, 0.4)',
    },
    {
      key: 'upcoming',
      label: 'فترات لم تبدأ بعد',
      count: metrics.shiftNotStartedYet,
      pct: Math.round((metrics.shiftNotStartedYet / total) * 1000) / 10,
      color: '#818cf8', // indigo-400
      glowColor: 'rgba(129, 140, 248, 0.4)',
    },
  ].filter((s) => s.count > 0);

  // حساب أقواس الدونات (Donut SVG Segments)
  // Radius = 58, Circumference = 2 * PI * 58 ≈ 364.425
  const radius = 58;
  const circumference = 2 * Math.PI * radius;
  let accumulatedOffset = 0;

  const renderedArcs = slices.map((slice) => {
    const strokeDash = (slice.count / total) * circumference;
    const strokeDasharray = `${strokeDash} ${circumference - strokeDash}`;
    const strokeDashoffset = -accumulatedOffset;
    accumulatedOffset += strokeDash;

    return {
      ...slice,
      strokeDasharray,
      strokeDashoffset,
    };
  });

  return (
    <div
      className={`rounded-2xl p-5 border transition-all ${
        isLight ? 'bg-white border-slate-200 text-slate-800 shadow-sm' : 'bg-slate-900/90 border-slate-800 text-slate-100 shadow-xl'
      }`}
      dir="rtl"
    >
      {/* رأس الشارت */}
      <div className="flex items-center justify-between mb-4 pb-3 border-b border-slate-800/80">
        <div>
          <h3 className="text-base font-black flex items-center gap-2">
            <span className="size-2.5 rounded-full bg-emerald-400 animate-pulse" />
            <span>توزيع قوى العمل اليوم</span>
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">نظرة بصرية شاملة على توزيع الحالات والانضباط الميداني</p>
        </div>
        <div className="text-end">
          <span className="text-xs text-slate-400 block font-medium">نسبة الحضور الفعلي</span>
          <span className="text-xl font-black text-emerald-400 font-mono">{fmt(metrics.attendancePercentage)}%</span>
        </div>
      </div>

      {/* منطقة الدونات والمؤشرات */}
      <div className="flex flex-col md:flex-row items-center justify-around gap-6 py-2">
        {/* SVG Donut Chart */}
        <div className="relative size-48 shrink-0 flex items-center justify-center">
          <svg className="size-full -rotate-90" viewBox="0 0 160 160">
            {/* حلقة الخلفية */}
            <circle cx="80" cy="80" r={radius} fill="transparent" stroke={isLight ? '#f1f5f9' : '#1e293b'} strokeWidth="14" />
            {/* شرائح الدونات المتوهجة */}
            {renderedArcs.map((arc) => (
              <circle
                key={arc.key}
                cx="80"
                cy="80"
                r={radius}
                fill="transparent"
                stroke={arc.color}
                strokeWidth="15"
                strokeDasharray={arc.strokeDasharray}
                strokeDashoffset={arc.strokeDashoffset}
                strokeLinecap="round"
                className="transition-all duration-500 ease-out"
                style={{
                  filter: isLight ? 'none' : `drop-shadow(0 0 3px ${arc.glowColor})`,
                }}
              />
            ))}
          </svg>

          {/* قلب الدونات: نسبة الحضور والعدد الإجمالي */}
          <div className="absolute inset-0 flex flex-col items-center justify-center text-center pointer-events-none">
            <span className="text-2xl font-black text-white font-mono tracking-tight leading-none">{fmt(metrics.presentTotal)}</span>
            <span className="text-[11px] font-bold text-emerald-400 mt-1">حاضر الآن</span>
            <span className="text-[10px] text-slate-400 mt-0.5 font-medium">من {fmt(metrics.totalScheduledEmployees)} مجدول</span>
          </div>
        </div>

        {/* دليل الشارت التفصيلي (Legend) بالقيم والنسب */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 w-full max-w-lg">
          {slices.map((slice) => (
            <div
              key={slice.key}
              className={`flex items-center justify-between p-2.5 rounded-xl border ${
                isLight ? 'bg-slate-50 border-slate-200' : 'bg-slate-950/60 border-slate-800/80 hover:border-slate-700'
              } transition-colors`}
            >
              <div className="flex items-center gap-2">
                <span className="size-3 rounded-full shrink-0 shadow-xs" style={{ backgroundColor: slice.color }} />
                <span className="text-xs font-bold text-slate-200">{slice.label}</span>
              </div>
              <div className="flex items-center gap-1.5 font-mono text-xs font-black">
                <span className="text-white">{fmt(slice.count)}</span>
                <span className="text-slate-400 font-normal text-[11px]">({fmt(slice.pct)}%)</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
