import type { RequestHistoryEntry, RequestInsights } from '@ahla/shared-contracts';
import { Ban, Check, CornerUpLeft, Repeat2, Send, TimerOff, TrendingUp, X, type LucideIcon } from 'lucide-react';

/// نفس صياغة شاشة الطلب في التطبيق (mobile_request_detail_page / request_display) —
/// المصطلحات والألوان واحدة بين الويب والموبايل.

/** اسم المرحلة الموحّد: تعريفات المسار القديمة تسمّي المرحلة نفسها بأسماء مختلفة. */
export function requestStageName(name: string | null | undefined, roleSlug?: string | null, order?: number | null): string {
  let n = (name ?? '').trim();
  if (roleSlug === 'operations-manager-1' || n.includes('مشرف العمليات') || n.includes('مدير التشغيل') || n.includes('الأوبريشن')) {
    return 'مدير التشغيل 1';
  }
  if (n.includes('المدير المباشر')) return 'المدير المباشر';
  for (const prefix of ['موافقة ', 'اعتماد ', 'مراجعة ']) {
    if (n.startsWith(prefix)) n = n.slice(prefix.length).trim();
  }
  if (roleSlug === 'hr-manager' || n === 'الموارد البشرية' || n === 'إدارة الموارد البشرية') return 'الموارد البشرية';
  if (!n) return order === 1 ? 'المدير المباشر' : 'مرحلة الاعتماد';
  return n;
}

/** الجهة التي صُعِّد إليها الطلب آليًا. */
export function escalationTargetLabel(roleSlug: string | null | undefined): string {
  switch (roleSlug) {
    case 'operations-manager-1':
      return 'مدير التشغيل 1';
    case 'operations-manager-2':
      return 'مدير التشغيل 2';
    case 'operations-officer':
      return 'ضابط العمليات';
    case 'hr-manager':
    case 'hr-specialist':
    case 'hr-officer':
      return 'الموارد البشرية';
    case 'executive':
    case 'executive-director':
      return 'المدير التنفيذي';
    default:
      return 'المستوى التالي';
  }
}

interface JourneyEvent {
  icon: LucideIcon;
  color: string;
  title: string;
  subtitle?: string | null;
  at: string;
  comment?: string | null;
}

const RETURN_COLOR = '#C2410C';

function journeyEvents(history: RequestHistoryEntry[], employeeName: string): JourneyEvent[] {
  const events: JourneyEvent[] = [];
  for (const h of history) {
    const stage = h.stepOrder == null && !h.stepName ? null : requestStageName(h.stepName, h.stepRole, h.stepOrder);
    const actor = h.actorName || 'المعتمِد';
    switch (h.action) {
      case 'submit':
        events.push({
          icon: h.isResubmit ? Repeat2 : Send,
          color: 'var(--brand-primary)',
          title: h.isResubmit ? 'أُعيد رفع الطلب بعد التعديل' : 'قُدِّم الطلب',
          subtitle: h.actorName || employeeName,
          at: h.at,
        });
        break;
      case 'escalate': {
        const repeat = h.repeat ?? 1;
        events.push({
          icon: TrendingUp,
          color: 'var(--warning)',
          title: `صُعِّد تلقائيًا إلى ${escalationTargetLabel(h.targetRole)}`,
          subtitle: repeat > 1 ? `لعدم صدور قرار في المهلة · تكرر التذكير ${repeat} مرات` : 'لعدم صدور قرار في المهلة',
          at: h.at,
        });
        break;
      }
      case 'approve':
        events.push({ icon: Check, color: 'var(--success)', title: `اعتمده ${actor}`, subtitle: stage, at: h.at, comment: h.comment });
        break;
      case 'reject':
        events.push({ icon: X, color: 'var(--danger)', title: `رفضه ${actor}`, subtitle: stage, at: h.at, comment: h.comment });
        break;
      case 'return':
      case 'request_changes':
        events.push({ icon: CornerUpLeft, color: RETURN_COLOR, title: `أعاده ${actor} للتعديل`, subtitle: stage, at: h.at, comment: h.comment });
        break;
      case 'cancel':
      case 'withdraw':
        events.push({
          icon: Ban,
          color: 'var(--text-muted)',
          title: 'سُحب الطلب',
          subtitle: !h.actorName || h.actorName === employeeName ? 'بواسطة صاحب الطلب' : `بواسطة ${h.actorName}`,
          at: h.at,
          comment: h.comment,
        });
        break;
      case 'expire':
        events.push({ icon: TimerOff, color: 'var(--text-muted)', title: 'انتهت مهلة الطلب', at: h.at });
        break;
      default:
        break;
    }
  }
  // الأحدث أولًا (قاعدة المالك لكل قائمة)
  return events.sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime());
}

const dateTime = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { dateStyle: 'medium', timeStyle: 'short' });

export function RequestJourney({ history, employeeName }: { history: RequestHistoryEntry[]; employeeName: string }) {
  const events = journeyEvents(history, employeeName);
  if (events.length === 0) return null;
  return (
    <section className="mt-4 rounded-2xl border border-[var(--border)] p-4" aria-labelledby="journey-heading">
      <h3 id="journey-heading" className="mb-3 text-sm font-black">
        مسار الطلب
      </h3>
      <ol className="space-y-3">
        {events.map((event, index) => {
          const Icon = event.icon;
          return (
            <li key={`${event.at}-${index}`} className="flex gap-3">
              <span
                className="mt-0.5 inline-flex size-7 shrink-0 items-center justify-center rounded-full text-white"
                style={{ background: event.color }}
                aria-hidden="true"
              >
                <Icon className="size-4" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-bold">{event.title}</p>
                <p className="muted text-xs">
                  {[event.subtitle, dateTime.format(new Date(event.at))].filter(Boolean).join(' · ')}
                </p>
                {event.comment ? <p className="mt-1 rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs leading-6">{event.comment}</p> : null}
              </div>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

const TYPE_LABELS: Record<string, string> = {
  leave: 'إجازة',
  mission: 'مأمورية',
  convoy: 'قافلة',
  fundraising: 'فاندي',
};

function fmtUnits(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

/** سياق القرار للمعتمِد (0651): رصيد الإجازة، طلبات الشهر، ومن غاب من الفريق اليوم. */
export function DecisionInsights({ insights }: { insights: RequestInsights | null | undefined }) {
  if (!insights) return null;
  const balance = insights.leaveBalance;
  const month = insights.month;
  const away = insights.teamAway ?? [];
  const hasMonth = month && (month.total ?? 0) > 0;
  if (!balance && !hasMonth && away.length === 0) return null;
  return (
    <section className="mt-4 rounded-2xl border border-brand/20 bg-brand/5 p-4 text-sm" aria-labelledby="insights-heading">
      <h3 id="insights-heading" className="mb-3 text-sm font-black text-brand">
        قبل أن تقرر
      </h3>
      <div className="grid gap-2 sm:grid-cols-2">
        {balance && balance.available != null ? (
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-3">
            <span className="muted block text-xs">رصيد {balance.name ?? 'الإجازة'} المتاح</span>
            <strong className="text-lg">{fmtUnits(balance.available)}</strong>
            {balance.reserved ? <span className="muted ms-2 text-xs">محجوز {fmtUnits(balance.reserved)}</span> : null}
          </div>
        ) : null}
        {hasMonth ? (
          <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-3">
            <span className="muted block text-xs">طلباته هذا الشهر</span>
            <strong className="text-lg">{month?.total ?? 0}</strong>
            <span className="muted ms-2 text-xs">
              {[
                month?.leaves ? `${month.leaves} إجازة` : null,
                month?.missions ? `${month.missions} مأمورية` : null,
                month?.permits ? `${month.permits} إذن` : null,
                month?.rejected ? `${month.rejected} مرفوض` : null,
              ]
                .filter(Boolean)
                .join(' · ')}
            </span>
          </div>
        ) : null}
      </div>
      {away.length > 0 ? (
        <p className="mt-3 text-xs leading-6">
          <strong>
            غائب من الفريق اليوم ({away.length}
            {insights.teamSize ? ` من ${insights.teamSize}` : ''}):
          </strong>{' '}
          {away.map((member) => `${member.name ?? 'موظف'} (${TYPE_LABELS[member.type ?? ''] ?? member.type ?? ''})`).join('، ')}
        </p>
      ) : null}
    </section>
  );
}
