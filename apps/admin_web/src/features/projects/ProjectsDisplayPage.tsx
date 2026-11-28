import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, useLocation } from 'react-router';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import {
  Activity, ArrowLeft, ArrowRight, CalendarClock, ChevronLeft, ChevronRight, CircleAlert, CircleCheck, ClipboardList,
  LogOut, Maximize, Minimize, MonitorPlay, Pause, Play, RefreshCw, Wifi, WifiOff,
} from 'lucide-react';
import { useAssociationProjects } from './useAssociationProjects';
import { FOLLOW_UP, compareProjectFollowUp, projectFollowUpReasons, type FollowUpReason } from './projectFollowUp';
import { LED_META, STATUS_LABELS, activityDays, daysAgoLabel, formatDate, isOnBoard, projectPhaseLabel, stepProgressLabel } from './projectLedStatus';
import './projectsDisplay.css';

const REFRESH_MS = 60_000;
const TICKER_MS = 8_000;
const DISPLAY_FILTERS = [
  { key: 'all', label: 'كل المشاريع', icon: ClipboardList },
  { key: 'follow-up', label: 'تحتاج متابعة', icon: CircleAlert },
  { key: 'active', label: 'قيد التنفيذ', icon: Activity },
  { key: 'completed', label: 'مكتملة', icon: CircleCheck },
] as const;

type DisplayFilter = (typeof DISPLAY_FILTERS)[number]['key'];

function isInterruptionReason(reason: FollowUpReason | undefined): boolean {
  return reason !== undefined && reason !== 'plan' && reason !== 'closure';
}

function useNow(): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 15_000);
    return () => window.clearInterval(id);
  }, []);
  return now;
}

function useViewport() {
  const [size, setSize] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  useEffect(() => {
    const resize = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);
  return size;
}

function useOnline(): boolean {
  const [online, setOnline] = useState(() => navigator.onLine);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);
  return online;
}

function useWakeLock(): void {
  useEffect(() => {
    if (!navigator.wakeLock) return;
    let sentinel: WakeLockSentinel | undefined;
    let requesting = false;
    let disposed = false;
    async function acquire() {
      if (document.visibilityState !== 'visible' || requesting || (sentinel && !sentinel.released)) return;
      requesting = true;
      try {
        const lock = await navigator.wakeLock.request('screen');
        if (disposed || document.visibilityState !== 'visible') await lock.release();
        else sentinel = lock;
      } catch {
        // The display also works on browsers that deny the wake lock.
      } finally {
        requesting = false;
      }
    }
    void acquire();
    document.addEventListener('visibilitychange', acquire);
    return () => {
      disposed = true;
      document.removeEventListener('visibilitychange', acquire);
      if (sentinel && !sentinel.released) void sentinel.release();
    };
  }, []);
}

function useFullscreen(): [boolean, () => void] {
  const [isFull, setIsFull] = useState(() => Boolean(document.fullscreenElement));
  useEffect(() => {
    const onChange = () => setIsFull(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);
  return [isFull, () => {
    if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined);
    else void document.documentElement.requestFullscreen?.().catch(() => undefined);
  }];
}

export function displayOrder(projects: AssociationProjectListItem[]): AssociationProjectListItem[] {
  return projects.filter((p) => isOnBoard(p) && p.status !== 'cancelled' && p.ledStatus !== 'stale').sort(compareProjectFollowUp);
}

export function gridFor(width: number, height: number, count = Infinity): { cols: number; rows: number } {
  const maxCols = width >= 1500 ? 4 : width >= 1000 ? 3 : width >= 640 ? 2 : 1;
  const maxRows = height >= 1000 ? 3 : height >= 650 ? 2 : 1;
  if (count >= maxCols * maxRows) return { cols: maxCols, rows: maxRows };
  let best = { cols: maxCols, rows: maxRows };
  for (let rows = 1; rows <= maxRows; rows++) {
    for (let cols = 1; cols <= maxCols; cols++) {
      const capacity = cols * rows;
      const bestCapacity = best.cols * best.rows;
      if (capacity >= Math.max(1, count) && (capacity < bestCapacity || (capacity === bestCapacity && cols > best.cols))) best = { cols, rows };
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

const cairoClock = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeZone: 'Africa/Cairo', hour: '2-digit', minute: '2-digit' });
const cairoDate = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { timeZone: 'Africa/Cairo', weekday: 'long', day: 'numeric', month: 'long' });

function DisplayControl({ label, children, ...props }: {
  label: string;
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return <button type="button" className="projects-display__control" aria-label={label} title={label} {...props}>{children}</button>;
}

export function ProjectsDisplayPage({ displayOnly = false, onSignOut }: { displayOnly?: boolean; onSignOut?: () => Promise<void> }) {
  const { state } = useLocation();
  const { data, error, dataUpdatedAt, isFetching, refetch } = useAssociationProjects(REFRESH_MS, true, displayOnly);
  const now = useNow();
  const { width, height } = useViewport();
  const online = useOnline();
  const [isFull, toggleFull] = useFullscreen();
  useWakeLock();

  const board = useMemo(() => displayOrder(data?.projects ?? []), [data?.projects]);
  const groups = useMemo(() => ({
    all: board,
    'follow-up': board.filter((p) => projectFollowUpReasons(p).length > 0),
    active: board.filter((p) => p.status === 'active'),
    completed: board.filter((p) => p.status === 'completed'),
  }), [board]);
  const sourcePath: unknown = state?.boardPath;
  const boardPath = sourcePath === '/admin/association-projects' || sourcePath === '/hr/association-projects'
    ? sourcePath
    : data?.isFullAccess ? '/admin/association-projects' : '/hr/association-projects';
  const pendingApprovals = !displayOnly && data?.isFullAccess ? data.projects.filter((p) => p.approvalStatus === 'pending_approval').length : 0;
  const interrupted = groups['follow-up'].filter((p) => projectFollowUpReasons(p).some(isInterruptionReason)).length;

  const [filter, setFilter] = useState<DisplayFilter>('all');
  const [paused, setPaused] = useState(() => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false);
  const [speed, setSpeed] = useState(15);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [page, setPage] = useState(0);
  const filtered = groups[filter];
  const needsMoreSpace = filtered.some((p) => projectFollowUpReasons(p).some(isInterruptionReason));
  const layoutHeight = needsMoreSpace && height < 1200 ? Math.min(height, 999) : height;
  const { cols, rows } = gridFor(width, layoutHeight, filtered.length);
  const perPage = cols * rows;
  const pages = Math.max(1, Math.ceil(filtered.length / perPage));
  const current = Math.min(page, pages - 1);
  const interacting = hovered || focused;
  const rotating = !paused && !interacting && pages > 1;

  useEffect(() => {
    if (!rotating) return;
    const timer = window.setTimeout(() => setPage((current + 1) % pages), speed * 1_000);
    return () => window.clearTimeout(timer);
  }, [current, pages, rotating, speed]);

  const updates = useMemo(() => {
    const ids = new Set(filtered.map((p) => p.id));
    return (data?.recentUpdates ?? []).filter((update) => ids.has(update.projectId));
  }, [filtered, data?.recentUpdates]);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (paused || interacting || updates.length <= 1) return;
    const timer = window.setInterval(() => setTick((value) => (value + 1) % updates.length), TICKER_MS);
    return () => window.clearInterval(timer);
  }, [paused, interacting, updates.length]);

  const latest = updates[tick % (updates.length || 1)];
  const stale = !online || (Boolean(error) && Boolean(data));
  const updatedAgo = dataUpdatedAt ? formatAgo(now.getTime() - dataUpdatedAt) : null;
  const filterLabel = DISPLAY_FILTERS.find((item) => item.key === filter)?.label ?? DISPLAY_FILTERS[0].label;
  const visible = filtered.slice(current * perPage, (current + 1) * perPage);
  const visibleCols = gridFor(width, layoutHeight, visible.length).cols;

  return (
    <main className="projects-display" dir="rtl" aria-label="عرض مشاريع الجمعية">
      <header className="projects-display__header">
        <div className="projects-display__brand">
          <span className="projects-display__brand-icon"><MonitorPlay aria-hidden="true" /></span>
          <div className="min-w-0">
            <h1>مشاريع الجمعية</h1>
            <p>{board.length} مشروع معتمد{interrupted > 0 ? ` · ${interrupted} متعطل أو متأخر` : ''}{pendingApprovals ? ` · ${pendingApprovals} بانتظار الاعتماد` : ''}</p>
          </div>
        </div>
        <div className="projects-display__clock">
          <time dateTime={now.toISOString()}>{cairoClock.format(now)}</time>
          <span>{cairoDate.format(now)}</span>
        </div>
        <div className="projects-display__header-actions">
          {!displayOnly && <Link className="projects-display__control" to={boardPath} aria-label="العودة إلى لوحة المشاريع" title="العودة إلى لوحة المشاريع"><ArrowRight aria-hidden="true" /></Link>}
          {onSignOut && <DisplayControl label="تسجيل الخروج" onClick={() => void onSignOut()}><LogOut aria-hidden="true" /></DisplayControl>}
          <DisplayControl label={isFull ? 'الخروج من ملء الشاشة' : 'ملء الشاشة'} onClick={toggleFull}>
            {isFull ? <Minimize aria-hidden="true" /> : <Maximize aria-hidden="true" />}
          </DisplayControl>
        </div>
      </header>

      <section className="projects-display__filters" aria-label="تصفية شاشة العرض">
        {DISPLAY_FILTERS.map(({ key, label, icon: Icon }) => (
          <button key={key} type="button" data-filter={key} aria-pressed={filter === key} onClick={() => {
            setFilter(key);
            setPage(0);
            setTick(0);
          }}>
            <Icon aria-hidden="true" />
            <span>{label}</span>
            <strong>{groups[key].length}</strong>
          </button>
        ))}
      </section>

      {stale && (
        <p className="projects-display__connection-alert" role="status">
          <WifiOff aria-hidden="true" />
          {online ? 'تعذّر التحديث' : 'انقطع الاتصال'}
          {updatedAgo ? ` · آخر بيانات محفوظة ${updatedAgo}` : ''}
        </p>
      )}

      <div className="projects-display__toolbar">
        <div className="projects-display__view">
          <h2>{filterLabel}</h2>
          {filtered.length > 0 && <span>{current * perPage + 1}–{Math.min((current + 1) * perPage, filtered.length)} من {filtered.length}</span>}
        </div>
        <div className="projects-display__toolbar-actions">
          <DisplayControl label="تحديث البيانات" onClick={() => void refetch()} disabled={!online || isFetching}>
            <RefreshCw className={isFetching ? 'animate-spin' : undefined} aria-hidden="true" />
          </DisplayControl>
          <label className="projects-display__speed">
            <span className="sr-only">مدة عرض الصفحة</span>
            <select value={speed} onChange={(event) => setSpeed(Number(event.target.value))} disabled={pages < 2}>
              <option value={15}>15 ثانية</option>
              <option value={30}>30 ثانية</option>
              <option value={60}>دقيقة</option>
            </select>
          </label>
          <DisplayControl label={paused ? 'استئناف التقليب التلقائي' : 'إيقاف التقليب التلقائي'} onClick={() => setPaused((value) => !value)}>
            {paused ? <Play aria-hidden="true" /> : <Pause aria-hidden="true" />}
          </DisplayControl>
        </div>
      </div>

      {!data || filtered.length === 0 ? (
        <div className="projects-display__empty">
          {!data ? error ? 'تعذّر تحميل المشاريع' : 'جارٍ تحميل المشاريع…'
            : board.length === 0 ? 'لا توجد مشاريع معتمدة بعد'
              : filter === 'follow-up' ? 'لا توجد مشاريع تحتاج متابعة حاليًا' : 'لا توجد مشاريع بهذه الحالة'}
        </div>
      ) : (
        <section
          className="projects-display__grid"
          style={{ gridTemplateColumns: `repeat(${visibleCols}, minmax(0, 1fr))` }}
          aria-label={`صفحة ${current + 1} من ${pages}`}
          onPointerEnter={(event) => { if (event.pointerType === 'mouse') setHovered(true); }}
          onPointerLeave={() => setHovered(false)}
          onFocus={() => setFocused(true)}
          onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false); }}
        >
          {visible.map((project) => <DisplayCard key={project.id} project={project} boardPath={displayOnly ? null : boardPath} />)}
        </section>
      )}

      <footer className="projects-display__footer">
        <div className="projects-display__sync">
          {stale ? <WifiOff aria-hidden="true" /> : <Wifi aria-hidden="true" />}
          <span>{stale ? 'بيانات محفوظة' : updatedAgo ? `آخر مزامنة ${updatedAgo}` : 'تحديث كل دقيقة'}</span>
        </div>
        {latest && (
          <p className="projects-display__ticker">
            <strong>{latest.projectName}</strong>
            <span title={latest.note}>{latest.note}</span>
            <time dateTime={latest.createdAt}>{formatAgo(now.getTime() - new Date(latest.createdAt).getTime())}</time>
          </p>
        )}
        <nav className="projects-display__pager" aria-label="التنقل بين صفحات العرض">
          <DisplayControl label="الصفحة السابقة" onClick={() => setPage((current + pages - 1) % pages)} disabled={pages < 2}><ChevronRight aria-hidden="true" /></DisplayControl>
          <span className="tabular" aria-live={paused ? 'polite' : 'off'}>{current + 1} / {pages}</span>
          <DisplayControl label="الصفحة التالية" onClick={() => setPage((current + 1) % pages)} disabled={pages < 2}><ChevronLeft aria-hidden="true" /></DisplayControl>
        </nav>
      </footer>
    </main>
  );
}

function DisplayCard({ project: p, boardPath }: { project: AssociationProjectListItem; boardPath: string | null }) {
  const reason = projectFollowUpReasons(p)[0];
  const interrupted = isInterruptionReason(reason);
  const owner = p.leaderName || p.ownerName || 'غير محدد';
  const deadline = p.nextDeadline ?? (p.status === 'completed' ? null : p.targetEndDate);
  const cause = p.interruptionNote
    || p.blockedStepReason
    || (p.blockedStepTitle ? `تعطلت خطوة «${p.blockedStepTitle}» · السبب غير مسجّل` : null)
    || (reason === 'deadline' ? 'تجاوز الموعد المستهدف وبقي المشروع مفتوحًا' : null)
    || (reason === 'late' ? 'تجاوزت خطوات مفتوحة موعدها' : null)
    || (reason === 'inactive' ? 'لم يُسجّل نشاط حديث' : 'سبب التوقف غير مسجّل');

  return (
    <article className="projects-display__card" data-status={p.ledStatus} data-reason={reason} data-interrupted={interrupted || undefined}>
      <div className="projects-display__card-meta">
        <span className="projects-display__card-status">{reason ? FOLLOW_UP[reason].label : LED_META[p.ledStatus].label}</span>
        <span>{daysAgoLabel(activityDays(p))}</span>
      </div>
      <h3>
        {boardPath ? (
          <Link to={`${boardPath}?project=${encodeURIComponent(p.id)}`}>
            <span>{p.name}</span>
            <ArrowLeft aria-hidden="true" />
          </Link>
        ) : <span>{p.name}</span>}
      </h3>
      <p className="projects-display__card-owner">
        <span>المسؤول</span> <strong>{owner}</strong>
      </p>

      <div className="projects-display__card-body">
        {interrupted ? (
          <div className="projects-display__card-blocker">
            <p title={cause}><strong>سبب التعطل</strong> {cause}</p>
            {p.blockedStepAssignee && p.blockedStepAssignee !== owner && <p>مسؤول الخطوة {p.blockedStepAssignee}</p>}
          </div>
        ) : <p className="projects-display__card-phase">{projectPhaseLabel(p)}</p>}
        <div className="projects-display__card-facts">
          <span>{stepProgressLabel(p.completedSteps, p.totalSteps)}</span>
          <strong>{STATUS_LABELS[p.status]}</strong>
        </div>
        {p.status !== 'completed' && (
          <p className="projects-display__card-deadline" title={p.nextDeadlineTitle ?? undefined}>
            <CalendarClock aria-hidden="true" /> <strong>أقرب موعد</strong> {deadline ? formatDate(deadline) : 'غير محدد'}
            {p.nextDeadlineTitle && p.nextDeadlineTitle !== 'الموعد المستهدف للمشروع' && (
              <span className="projects-display__deadline-title">{p.nextDeadlineTitle}</span>
            )}
          </p>
        )}
      </div>
    </article>
  );
}
