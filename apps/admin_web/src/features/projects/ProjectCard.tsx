import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { AlertTriangle, CalendarClock, CheckCircle2, Clock, Crown, Flag, Users, Zap } from 'lucide-react';
import { ProjectLed } from './ProjectLed';
import { LED_META, PRIORITY_LABELS, activityDays, daysAgoLabel, formatDate } from './projectLedStatus';

interface Props {
  project: AssociationProjectListItem;
  onOpen: () => void;
  /** يظهر زر «تحديث سريع» فقط لمن يدير المشروع. */
  onQuickUpdate?: () => void;
  /** لتمييز المشاريع التي يقودها المستخدم أو هو في فريقها. */
  myEmployeeId?: string | null;
}

export function ProjectCard({ project: p, onOpen, onQuickUpdate, myEmployeeId }: Props) {
  const led = p.ledStatus;
  const meta = LED_META[led];
  const days = activityDays(p);
  const stepsLabel = p.totalSteps > 0 ? `${p.completedSteps} من ${p.totalSteps} خطوات` : 'لا توجد خطوات بعد';

  return (
    <article className={`card card-interactive project-card project-card--${led} relative p-5`}>
      {/* رأس البطاقة: اللمبة + الحالة + آخر نشاط */}
      <div className="mb-4 flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <ProjectLed status={led} large />
          <span className="truncate text-sm font-black" style={{ color: meta.tone }}>
            {meta.label}
          </span>
        </div>
        <span className="flex shrink-0 items-center gap-1 text-xs text-[var(--text-muted)]" title="آخر نشاط على المشروع">
          <Clock className="size-3.5" aria-hidden="true" />
          {daysAgoLabel(days)}
        </span>
      </div>

      {/* الاسم يفتح التفاصيل — زر حقيقي لسهولة الوصول */}
      <button type="button" onClick={onOpen} className="text-start after:absolute after:inset-0 after:content-['']">
        <h3 className="line-clamp-2 text-lg leading-snug font-black">{p.name}</h3>
      </button>
      <p className="mt-1 flex min-w-0 items-center gap-1 text-xs text-[var(--text-muted)]">
        <Crown className="size-3.5 shrink-0 text-[var(--warning)]" aria-label="القائد" />
        <span className="truncate">
          {p.leaderName ?? p.ownerName}
          {p.departmentName ? ` • ${p.departmentName}` : ''}
        </span>
      </p>

      {/* التقدم */}
      <div className="mt-4">
        <div className="mb-1.5 flex items-center justify-between text-xs">
          <span className="text-[var(--text-muted)]">{stepsLabel}</span>
          <span className="tabular font-black">{Math.round(p.progress)}%</span>
        </div>
        <div className="h-2.5 overflow-hidden rounded-full bg-[var(--surface-muted)]">
          <div className="h-full rounded-full transition-all duration-700" style={{ width: `${p.progress}%`, background: meta.tone }} />
        </div>
      </div>

      {/* المرحلة الحالية */}
      <div className="mt-4 min-h-10 rounded-xl bg-[var(--surface-subtle)] px-3 py-2 text-xs">
        {p.status === 'completed' ? (
          <span className="flex items-center gap-1.5 font-bold text-[var(--info)]">
            <CheckCircle2 className="size-3.5" aria-hidden="true" /> اكتمل التنفيذ
          </span>
        ) : p.currentStepTitle ? (
          <>
            <span className="text-[var(--text-muted)]">المرحلة الحالية: </span>
            <span className="font-bold">{p.currentStepTitle}</span>
          </>
        ) : (
          <span className="text-[var(--text-muted)]">لم تُحدَّد خطوات التنفيذ بعد</span>
        )}
      </div>

      {/* شارات التنبيه */}
      <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
        <span className="inline-flex items-center gap-1 rounded-full bg-[var(--surface-muted)] px-2 py-0.5 font-bold">
          <Flag className="size-3" aria-hidden="true" /> {PRIORITY_LABELS[p.priority]}
        </span>
        {p.members.length > 1 && (
          <span className="inline-flex items-center gap-1 rounded-full bg-[var(--surface-muted)] px-2 py-0.5 font-bold" title={p.members.map((m) => m.name).join('، ')}>
            <Users className="size-3" aria-hidden="true" /> فريق من {p.members.length}
          </span>
        )}
        {myEmployeeId && p.members.some((m) => m.employeeId === myEmployeeId) && (
          <span className="inline-flex items-center gap-1 rounded-full bg-[var(--brand-primary-soft)] px-2 py-0.5 font-bold text-[var(--brand-primary)]">
            {p.myRole === 'leader' ? 'تقوده' : 'أنت في الفريق'}
          </span>
        )}
        {p.blockedSteps > 0 && (
          <span className="inline-flex items-center gap-1 rounded-full bg-[var(--danger-soft)] px-2 py-0.5 font-bold text-[var(--danger)]">
            <AlertTriangle className="size-3" aria-hidden="true" /> {p.blockedSteps} متعثرة
          </span>
        )}
        {p.overdueSteps > 0 && (
          <span className="inline-flex items-center gap-1 rounded-full bg-[var(--warning-soft)] px-2 py-0.5 font-bold text-[var(--warning)]">
            {p.overdueSteps} متأخرة عن موعدها
          </span>
        )}
        {p.isOverdue && (
          <span className="inline-flex items-center gap-1 rounded-full bg-[var(--danger-soft)] px-2 py-0.5 font-bold text-[var(--danger)]">
            <CalendarClock className="size-3" aria-hidden="true" /> تجاوز الموعد ({formatDate(p.targetEndDate)})
          </span>
        )}
      </div>

      {onQuickUpdate && (
        <button type="button" onClick={onQuickUpdate} className="btn-secondary btn-sm relative z-10 mt-4 w-full" title="سجّل ما تم إنجازه ليبقى المشروع أخضر">
          <Zap className="size-4" aria-hidden="true" /> تحديث سريع
        </button>
      )}
    </article>
  );
}
