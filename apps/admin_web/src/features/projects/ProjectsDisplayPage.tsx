import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router';
import type { AssociationProjectListItem, ProjectLedStatus } from '@ahla/shared-contracts';
import { AlertTriangle, ArrowRight, CalendarClock, Crown, Maximize, Minimize, WifiOff } from 'lucide-react';
import { useAssociationProjects } from './useAssociationProjects';
import { LED_META, LED_URGENCY, activityDays, daysAgoLabel } from './projectLedStatus';

/**
 * وضع العرض على شاشة كبيرة (تلفزيون غرفة الإدارة):
 * ملء الشاشة بلا قوائم، خط يُقرأ من بعيد (يتناسب مع عرض الشاشة)، الأحوج للتدخل
 * أولاً، تقليب تلقائي للصفحات، تحديث كل دقيقة مع الإبقاء على آخر بيانات عند
 * انقطاع الاتصال، ومنع الشاشة من النوم. للقراءة فقط.
 */

const REFRESH_MS = 60_000;
const ROTATE_MS = 15_000;
const IDLE_MS = 3_000;
const TICKER_MS = 8_000;

const TILES: { key: ProjectLedStatus; label: string; color: string }[] = [
  { key: 'active', label: 'تعمل بانتظام', color: '#10b981' },
  { key: 'halted', label: 'متوقفة', color: '#ef4444' },
  { key: 'critical', label: 'تحتاج تدخل', color: '#ef4444' },
  { key: 'completed', label: 'مكتملة', color: '#3b82f6' },
];

function useNow(intervalMs: number): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

function useViewport(): { width: number; height: number } {
  const [size, setSize] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  useEffect(() => {
    const onResize = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return size;
}

function useOnline(): boolean {
  const [online, setOnline] = useState(() => navigator.onLine);
  useEffect(() => {
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('offline', off);
    };
  }, []);
  return online;
}

/** يمنع الشاشة من النوم ما دامت الصفحة ظاهرة (Screen Wake Lock). */
function useWakeLock(): void {
  useEffect(() => {
    type Sentinel = { release: () => Promise<void> };
    const wl = (navigator as Navigator & { wakeLock?: { request: (t: 'screen') => Promise<Sentinel> } }).wakeLock;
    if (!wl) return;
    let sentinel: Sentinel | null = null;
    let cancelled = false;
    const acquire = async () => {
      try {
        const s = await wl.request('screen');
        if (cancelled) void s.release();
        else sentinel = s;
      } catch {
        // غير مدعوم أو رفضه المتصفح — العرض يعمل بدونه.
      }
    };
    // القفل يسقط عند إخفاء الصفحة — نعيد طلبه عند عودتها.
    const onVisible = () => {
      if (document.visibilityState === 'visible') void acquire();
    };
    void acquire();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      void sentinel?.release();
    };
  }, []);
}

/** يُخفي المؤشر والأزرار بعد ثوانٍ بلا حركة. */
function useIdle(ms: number): boolean {
  const [idle, setIdle] = useState(false);
  useEffect(() => {
    let timer = window.setTimeout(() => setIdle(true), ms);
    const wake = () => {
      setIdle(false);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => setIdle(true), ms);
    };
    window.addEventListener('mousemove', wake);
    window.addEventListener('keydown', wake);
    window.addEventListener('touchstart', wake);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener('mousemove', wake);
      window.removeEventListener('keydown', wake);
      window.removeEventListener('touchstart', wake);
    };
  }, [ms]);
  return idle;
}

function useFullscreen(): [boolean, () => void] {
  const [isFull, setIsFull] = useState(() => Boolean(document.fullscreenElement));
  useEffect(() => {
    const onChange = () => setIsFull(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);
  const toggle = useCallback(() => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void document.documentElement.requestFullscreen?.().catch(() => undefined);
  }, []);
  return [isFull, toggle];
}

/** ترتيب العرض: يحتاج تدخل ← متوقف ← يعمل ← مكتمل، والأقدم نشاطاً أولاً. */
export function displayOrder(projects: AssociationProjectListItem[]): AssociationProjectListItem[] {
  return projects
    .filter((p) => p.approvalStatus === 'approved' && p.ledStatus !== 'stale')
    .sort((a, b) => LED_URGENCY[a.ledStatus] - LED_URGENCY[b.ledStatus] || (activityDays(b) ?? 9999) - (activityDays(a) ?? 9999));
}

/**
 * شبكة البطاقات حسب حجم الشاشة (CSS px) وعدد المشاريع: الحد الأقصى 4×3 على
 * شاشة 1080p، ومع مشاريع أقل نختار أصغر شبكة تكفيها فتكبر البطاقات والخط.
 */
export function gridFor(width: number, height: number, count = Infinity): { cols: number; rows: number } {
  const maxCols = width >= 1500 ? 4 : width >= 1000 ? 3 : width >= 640 ? 2 : 1;
  const maxRows = height >= 1000 ? 3 : height >= 650 ? 2 : 1;
  if (count >= maxCols * maxRows) return { cols: maxCols, rows: maxRows };
  let best = { cols: maxCols, rows: maxRows };
  for (let rows = 1; rows <= maxRows; rows++) {
    for (let cols = 1; cols <= maxCols; cols++) {
      const fits = cols * rows >= Math.max(1, count);
      // الأقل فراغاً، ثم الأعرض (الشاشة أفقية 16:9)
      if (fits && (cols * rows < best.cols * best.rows || (cols * rows === best.cols * best.rows && cols > best.cols))) best = { cols, rows };
    }
  }
  return best;
}

function formatAgo(ms: number): string {
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 1) return 'الآن';
  if (minutes === 1) return 'منذ دقيقة';
  if (minutes === 2) return 'منذ دقيقتين';
  if (minutes <= 10) return `منذ ${minutes} دقائق`;
  if (minutes < 60) return `منذ ${minutes} دقيقة`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return hours === 1 ? 'منذ ساعة' : hours === 2 ? 'منذ ساعتين' : `منذ ${hours} ساعات`;
  return daysAgoLabel(Math.floor(hours / 24));
}

export function ProjectsDisplayPage() {
  const navigate = useNavigate();
  const { data, error, dataUpdatedAt } = useAssociationProjects(REFRESH_MS);
  const now = useNow(1_000);
  const { width, height } = useViewport();
  const online = useOnline();
  const idle = useIdle(IDLE_MS);
  const [isFull, toggleFull] = useFullscreen();
  useWakeLock();

  const board = useMemo(() => displayOrder(data?.projects ?? []), [data]);
  const counts = useMemo(() => {
    const c: Record<string, number> = { active: 0, halted: 0, critical: 0, completed: 0 };
    for (const p of board) c[p.ledStatus] = (c[p.ledStatus] ?? 0) + 1;
    return c;
  }, [board]);
  const pendingApprovals = (data?.projects ?? []).filter((p) => p.approvalStatus === 'pending_approval').length;

  const { cols, rows } = gridFor(width, height, board.length);
  const perPage = cols * rows;
  const pages = Math.max(1, Math.ceil(board.length / perPage));
  const [page, setPage] = useState(0);
  const current = Math.min(page, pages - 1);

  useEffect(() => {
    if (pages <= 1) return;
    const id = window.setInterval(() => setPage((p) => (p + 1) % pages), ROTATE_MS);
    return () => window.clearInterval(id);
  }, [pages]);

  const visible = board.slice(current * perPage, current * perPage + perPage);

  // شريط آخر التحديثات: تحديث واحد كل 8 ثوانٍ.
  const updates = data?.recentUpdates ?? [];
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (updates.length <= 1) return;
    const id = window.setInterval(() => setTick((t) => t + 1), TICKER_MS);
    return () => window.clearInterval(id);
  }, [updates.length]);
  const latest = updates.length ? updates[tick % updates.length] : undefined;
  // بيانات قديمة: انقطاع، أو فشل التحديث مع بقاء آخر نسخة ناجحة.
  const stale = !online || (Boolean(error) && Boolean(data));
  const updatedAgo = dataUpdatedAt ? formatAgo(now.getTime() - dataUpdatedAt) : null;

  return (
    <main
      dir="rtl"
      className={`projects-display fixed inset-0 z-[80] flex flex-col gap-[1.2vh] overflow-hidden bg-[#070d1a] p-[1.6vw] text-slate-100 ${idle ? 'cursor-none' : ''}`}
      aria-label="عرض مشاريع الجمعية"
    >
      {/* الرأس: العنوان + الساعة + حالة التحديث */}
      <header className="flex items-center justify-between gap-[2vw]">
        <div className="flex min-w-0 items-center gap-[1vw]">
          <div className={`flex gap-2 transition-opacity duration-500 ${idle ? 'pointer-events-none opacity-0' : 'opacity-100'}`}>
            <button
              type="button"
              onClick={() => (window.history.length > 1 ? navigate(-1) : navigate('/'))}
              className="grid size-[clamp(2.25rem,2.6vw,4rem)] place-items-center rounded-xl bg-white/10 hover:bg-white/20"
              aria-label="رجوع"
              title="رجوع"
            >
              <ArrowRight className="size-1/2" />
            </button>
            <button
              type="button"
              onClick={toggleFull}
              className="grid size-[clamp(2.25rem,2.6vw,4rem)] place-items-center rounded-xl bg-white/10 hover:bg-white/20"
              aria-label={isFull ? 'الخروج من ملء الشاشة' : 'ملء الشاشة'}
              title={isFull ? 'الخروج من ملء الشاشة' : 'ملء الشاشة'}
            >
              {isFull ? <Minimize className="size-1/2" /> : <Maximize className="size-1/2" />}
            </button>
          </div>
          <div className="min-w-0">
            <h1 className="truncate text-[clamp(1.5rem,2.4vw,5rem)] leading-tight font-black">مشاريع الجمعية</h1>
            <p className="text-[clamp(0.8rem,0.95vw,2rem)] text-slate-400">
              {board.length} مشروع معتمد
              {pendingApprovals > 0 && data?.isFullAccess ? ` • ${pendingApprovals} بانتظار اعتمادك` : ''}
            </p>
          </div>
        </div>

        <div className="text-end">
          <p className="tabular text-[clamp(1.6rem,2.8vw,6rem)] leading-none font-black">
            {now.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' })}
          </p>
          <p className="mt-[0.4vh] text-[clamp(0.8rem,0.95vw,2rem)] text-slate-400">
            {now.toLocaleDateString('ar-EG', { weekday: 'long', day: 'numeric', month: 'long' })}
          </p>
        </div>
      </header>

      {/* العدّادات */}
      <section className="grid grid-cols-4 gap-[1vw]" aria-label="ملخص الحالات">
        {TILES.map((t) => (
          <div
            key={t.key}
            className={`flex items-center gap-[1vw] rounded-[1vw] border bg-white/[0.04] px-[1.2vw] py-[1.2vh] ${
              t.key === 'critical' && counts.critical > 0 ? 'projects-display__alert border-red-500/70' : 'border-white/10'
            }`}
          >
            <span className={`project-led project-led--${t.key} is-xl`} aria-hidden="true" />
            <span>
              <span className="tabular block text-[clamp(1.8rem,3.2vw,7rem)] leading-none font-black" style={{ color: t.color }}>
                {counts[t.key] ?? 0}
              </span>
              <span className="mt-[0.3vh] block text-[clamp(0.85rem,1.05vw,2.2rem)] font-bold text-slate-300">{t.label}</span>
            </span>
          </div>
        ))}
      </section>

      {/* شريط التنبيه */}
      {stale && (
        <div className="flex items-center gap-3 rounded-xl bg-amber-500/15 px-[1.2vw] py-[0.8vh] text-[clamp(0.85rem,1vw,2rem)] font-bold text-amber-300" role="status">
          <WifiOff className="size-[1.2em]" aria-hidden="true" />
          {online ? 'تعذّر التحديث' : 'لا يوجد اتصال بالإنترنت'} — المعروض آخر بيانات وصلت {updatedAgo ?? ''}، ويُعاد المحاولة تلقائياً.
        </div>
      )}

      {/* البطاقات */}
      {!data ? (
        <div className="grid flex-1 place-items-center text-[clamp(1rem,1.6vw,3rem)] text-slate-400">
          {error ? 'تعذّر تحميل المشاريع — يُعاد المحاولة تلقائياً…' : 'جارٍ تحميل المشاريع…'}
        </div>
      ) : board.length === 0 ? (
        <div className="grid flex-1 place-items-center text-[clamp(1rem,1.6vw,3rem)] text-slate-400">لا توجد مشاريع معتمدة بعد</div>
      ) : (
        <section
          key={current}
          className="projects-display__page grid min-h-0 flex-1 gap-[1vw]"
          style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`, gridTemplateRows: `repeat(${rows}, minmax(0, 1fr))` }}
          aria-label={`صفحة ${current + 1} من ${pages}`}
        >
          {visible.map((p) => (
            <DisplayCard key={p.id} project={p} />
          ))}
        </section>
      )}

      {/* التذييل: الصفحات + آخر تحديث */}
      <footer className="flex items-center justify-between gap-[2vw] text-[clamp(0.75rem,0.85vw,1.8rem)] text-slate-500">
        <span className="shrink-0">{updatedAgo ? `آخر تحديث ${updatedAgo} • يتحدّث كل دقيقة` : ''}</span>
        {latest && (
          <p key={latest.id} className="projects-display__ticker min-w-0 flex-1 truncate text-center text-[clamp(0.85rem,1vw,2.2rem)] text-slate-300" aria-live="polite">
            <span className="font-black text-sky-300">{latest.projectName}</span>
            <span className="mx-2 text-slate-500">•</span>
            {latest.note}
            <span className="mx-2 text-slate-500">—</span>
            <span className="text-slate-400">
              {latest.authorName}، {formatAgo(now.getTime() - new Date(latest.createdAt).getTime())}
            </span>
          </p>
        )}
        {pages > 1 && (
          <span className="flex items-center gap-2" aria-hidden="true">
            {Array.from({ length: pages }, (_, i) => (
              <span key={i} className={`h-[0.6vh] rounded-full transition-all ${i === current ? 'w-[2.2vw] bg-slate-200' : 'w-[0.6vw] bg-slate-600'}`} />
            ))}
          </span>
        )}
      </footer>
    </main>
  );
}

function DisplayCard({ project: p }: { project: AssociationProjectListItem }) {
  const meta = LED_META[p.ledStatus];
  const days = activityDays(p);
  const tone = p.ledStatus === 'completed' ? '#3b82f6' : p.ledStatus === 'active' ? '#10b981' : '#ef4444';
  const critical = p.ledStatus === 'critical';
  const scope = p.departmentName || (p.members.length > 1 ? `فريق من ${p.members.length}` : '');

  return (
    <article
      className={`flex min-h-0 flex-col overflow-hidden rounded-[1vw] border border-t-[0.4vh] bg-white/[0.05] p-[clamp(0.75rem,4cqw,2.5rem)] ${
        critical ? 'projects-display__alert border-red-500/70' : 'border-white/10'
      }`}
      // الخط داخل البطاقة يتناسب مع عرضها (cqw) — بطاقات أقل = خط أكبر.
      style={{ borderTopColor: tone, containerType: 'inline-size' }}
    >
      <div className="flex shrink-0 items-center justify-between gap-2">
        <span className="flex min-w-0 items-center gap-[2cqw]">
          <span className={`project-led project-led--${p.ledStatus} is-card`} aria-hidden="true" />
          <span className="truncate text-[clamp(0.85rem,4.4cqw,2.6rem)] font-black" style={{ color: tone }}>
            {critical ? 'يحتاج تدخل' : meta.label}
          </span>
        </span>
        <span className="shrink-0 text-[clamp(0.75rem,3.6cqw,2.2rem)] text-slate-400">{daysAgoLabel(days)}</span>
      </div>

      <h2 className="mt-[2cqw] line-clamp-2 shrink-0 text-[clamp(1.05rem,6.4cqw,4rem)] leading-[1.3] font-black">{p.name}</h2>
      <p className="mt-[1cqw] flex min-w-0 shrink-0 items-center gap-[1.5cqw] text-[clamp(0.75rem,3.7cqw,2.2rem)] text-slate-400">
        <Crown className="size-[1.1em] shrink-0 text-amber-400" aria-label="القائد" />
        <span className="truncate">
          {p.leaderName ?? p.ownerName}
          {scope ? ` • ${scope}` : ''}
        </span>
      </p>

      <div className="mt-auto pt-[1vh]">
        <div className="mb-[0.5vh] flex items-end justify-between">
          <span className="truncate text-[clamp(0.75rem,3.7cqw,2.2rem)] text-slate-300">
            {p.status === 'completed' ? 'اكتمل التنفيذ' : p.currentStepTitle ? `المرحلة: ${p.currentStepTitle}` : 'لم تُحدَّد خطوات بعد'}
          </span>
          <span className="tabular ms-2 shrink-0 text-[clamp(1.1rem,7.5cqw,4.5rem)] leading-none font-black">{Math.round(p.progress)}%</span>
        </div>
        <div className="h-[clamp(0.4rem,2cqw,1.2rem)] overflow-hidden rounded-full bg-white/10">
          <div className="h-full rounded-full" style={{ width: `${Math.min(100, Math.max(0, p.progress))}%`, background: tone }} />
        </div>
        {(p.blockedSteps > 0 || p.overdueSteps > 0 || p.isOverdue) && (
          <div className="mt-[2cqw] flex flex-wrap gap-[1.5cqw] text-[clamp(0.7rem,3.3cqw,2rem)] font-bold">
            {p.blockedSteps > 0 && (
              <span className="inline-flex items-center gap-1 rounded-full bg-red-500/15 px-[2cqw] py-[0.5cqw] text-red-300">
                <AlertTriangle className="size-[1em]" aria-hidden="true" /> {p.blockedSteps} متعثرة
              </span>
            )}
            {p.overdueSteps > 0 && <span className="rounded-full bg-amber-500/15 px-[2cqw] py-[0.5cqw] text-amber-300">{p.overdueSteps} متأخرة</span>}
            {p.isOverdue && (
              <span className="inline-flex items-center gap-1 rounded-full bg-red-500/15 px-[2cqw] py-[0.5cqw] text-red-300">
                <CalendarClock className="size-[1em]" aria-hidden="true" /> تجاوز الموعد
              </span>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
