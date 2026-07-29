import {
  Activity,
  Bot,
  BriefcaseBusiness,
  CircleAlert,
  Database,
  Gauge,
  ListChecks,
  MessagesSquare,
  ShieldCheck,
  Target,
} from 'lucide-react';
import { ErrorState } from '../../ui/ErrorState';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { useEnterpriseManagementCatalog } from './useEnterpriseManagement';

export function EnterpriseManagementPage() {
  const q = useEnterpriseManagementCatalog();

  if (q.isError)
    return (
      <ErrorState
        title="تعذر تحميل مركز الإدارة المؤسسية"
        description={q.error instanceof Error ? q.error.message : undefined}
        onRetry={() => void q.refetch()}
      />
    );

  const d = q.data;

  if (!d) return <LoadingScreen label="جارٍ تحميل مركز الإدارة المؤسسية…" />;

  return (
    <div className="space-y-6">
      <PageHeader
        title="مركز الإدارة المؤسسية"
        description="الاستراتيجية والمشروعات والمخاطر والخدمات والاجتماعات والجودة والأتمتة والحوكمة من لوحة واحدة."
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <MetricCard
          label="الأهداف"
          value={d.objectives.length}
          hint="أهداف استراتيجية"
          icon={Target}
        />
        <MetricCard
          label="المشروعات"
          value={d.projects.length}
          hint="محافظ ومبادرات"
          icon={BriefcaseBusiness}
        />
        <MetricCard
          label="المخاطر المفتوحة"
          value={d.risks.filter(x => x.status !== 'closed').length}
          hint={`من ${d.risks.length} مخاطر`}
          icon={CircleAlert}
        />
        <MetricCard
          label="طلبات الخدمة"
          value={d.serviceRequests.length}
          hint="واردة ومفتوحة"
          icon={MessagesSquare}
        />
        <MetricCard
          label="حالات الجودة"
          value={d.qualityCases.length}
          hint="قيد المتابعة"
          icon={ListChecks}
        />
      </section>

      <section className="grid gap-5 xl:grid-cols-3">
        <Panel
          title="الأهداف والمشروعات"
          icon={<Gauge className="size-5" aria-hidden="true" />}
          isEmpty={d.objectives.length === 0 && d.projects.length === 0}
        >
          {d.objectives.slice(0, 5).map(x => (
            <Row
              key={x.id}
              title={`${x.code} — ${x.title}`}
              subtitle={`التقدم ${x.progress}%`}
              status={x.status}
            />
          ))}
          {d.projects.slice(0, 5).map(x => (
            <Row
              key={x.id}
              title={`${x.code} — ${x.name}`}
              subtitle={`مهام مفتوحة ${x.openTasks} · تقدم ${x.progress}%`}
              status={x.status}
            />
          ))}
        </Panel>

        <Panel
          title="المخاطر والحوادث"
          icon={<Activity className="size-5" aria-hidden="true" />}
          isEmpty={d.risks.length === 0 && d.incidents.length === 0}
        >
          {d.risks.slice(0, 6).map(x => (
            <Row
              key={x.id}
              title={x.title}
              subtitle={`درجة ${x.score} · ${x.category}`}
              status={x.status}
            />
          ))}
          {d.incidents.slice(0, 4).map(x => (
            <Row
              key={x.id}
              title={x.title}
              subtitle={`حادث #${x.number}`}
              status={x.severity}
            />
          ))}
        </Panel>

        <Panel
          title="الحوكمة والأتمتة"
          icon={<ShieldCheck className="size-5" aria-hidden="true" />}
          isEmpty={
            d.automations.length === 0 &&
            d.dataAssets.length === 0 &&
            d.aiUseCases.length === 0
          }
        >
          {d.automations.slice(0, 4).map(x => (
            <Row
              key={x.id}
              title={x.name}
              subtitle={`${x.eventType} · v${x.version}`}
              status={x.active ? 'active' : 'inactive'}
            />
          ))}
          {d.dataAssets.slice(0, 4).map(x => (
            <Row
              key={x.id}
              title={x.name}
              subtitle={`${x.sourceSystem} · ${x.classification}`}
              status={x.active ? 'active' : 'inactive'}
            />
          ))}
          {d.aiUseCases.slice(0, 4).map(x => (
            <Row
              key={x.id}
              title={x.name}
              subtitle={`${x.modelName ?? 'بدون نموذج'} · مراجعة بشرية ${x.humanReviewRequired ? 'نعم' : 'لا'}`}
              status={x.riskLevel}
            />
          ))}
        </Panel>
      </section>

      <section className="grid gap-5 xl:grid-cols-2">
        <Panel
          title="الاجتماعات والقرارات"
          icon={<MessagesSquare className="size-5" aria-hidden="true" />}
          isEmpty={d.meetings.length === 0}
        >
          {d.meetings.slice(0, 8).map(x => (
            <Row
              key={x.id}
              title={x.title}
              subtitle={`${x.meetingType} · قرارات ${x.decisions}`}
              status={x.status}
            />
          ))}
        </Panel>

        <Panel
          title="التدقيق والجودة"
          icon={<Database className="size-5" aria-hidden="true" />}
          isEmpty={d.audits.length === 0 && d.qualityCases.length === 0}
        >
          {d.audits.slice(0, 6).map(x => (
            <Row
              key={x.id}
              title={`${x.code} — ${x.title}`}
              subtitle={`ملاحظات ${x.findings}`}
              status={x.status}
            />
          ))}
          {d.qualityCases.slice(0, 6).map(x => (
            <Row
              key={x.id}
              title={x.title}
              subtitle={`حالة جودة #${x.number}`}
              status={x.severity}
            />
          ))}
        </Panel>
      </section>
    </div>
  );
}

function Panel({
  title,
  icon,
  children,
  isEmpty,
}: {
  title: string;
  icon: React.ReactNode;
  children: React.ReactNode;
  isEmpty: boolean;
}) {
  return (
    <article className="card overflow-hidden">
      <div className="flex items-center gap-2 border-b border-[var(--border)] p-5">
        {icon}
        <h2 className="font-black">{title}</h2>
      </div>
      {isEmpty ? (
        <p className="p-8 text-center text-sm text-[var(--text-muted)]">
          ستظهر البيانات بعد بدء الاستخدام.
        </p>
      ) : (
        <div className="divide-y divide-[var(--border)]">{children}</div>
      )}
    </article>
  );
}

function Row({
  title,
  subtitle,
  status,
}: {
  title: string;
  subtitle: string;
  status: string;
}) {
  return (
    <div className="flex items-center justify-between gap-4 p-4">
      <div>
        <p className="font-bold">{title}</p>
        <p className="muted text-sm">{subtitle}</p>
      </div>
      <StatusBadge value={status} />
    </div>
  );
}
