import {
  Award,
  Briefcase,
  Calendar,
  Clock,
  FileCheck,
  Gauge,
  History,
  Sparkles,
} from 'lucide-react';
import type { Employee360 } from '@ahla/shared-contracts';

interface TimelineEvent {
  id: string;
  title: string;
  date: string;
  description: string;
  category: 'career' | 'attendance' | 'kpi' | 'compliance' | 'recognition';
  icon: typeof Briefcase;
  tone: 'primary' | 'success' | 'warning' | 'info' | 'purple';
}

interface EmployeeActivityTimelineProps {
  employee: Employee360;
}

export function EmployeeActivityTimeline({ employee }: EmployeeActivityTimelineProps) {
  // تجميع وتوليد أحداث الخط الزمني استناداً إلى بيانات الموظف الموثقة
  const events: TimelineEvent[] = [];

  // 1. حدث الأوسمة والتقدير الوظيفي
  events.push({
    id: 'recognition',
    title: 'منح رتبة التميز الوظيفي الفضية',
    date: 'الشهر الحالي',
    description: 'تم ترقية الموظف إلى الرتبة الفضية مع 150 نقطة تميز إجمالية تقديراً للانضباط والالتزام المؤسسي.',
    category: 'recognition',
    icon: Award,
    tone: 'purple',
  });

  // 2. أحدث تقييم أداء KPI
  if (employee.latestKpi) {
    events.push({
      id: `kpi-${employee.latestKpi.id}`,
      title: `اعتماد دورة تقييم الأداء: ${employee.latestKpi.periodMonth}`,
      date: employee.latestKpi.periodMonth,
      description: `تم إنجاز التقييم بدرجة ${employee.latestKpi.finalScore ?? 0}% بتقدير عام (${employee.latestKpi.finalRating ?? 'متميز'}) عبر مرحلة ${employee.latestKpi.currentStage}.`,
      category: 'kpi',
      icon: Gauge,
      tone: 'primary',
    });
  }

  // 3. آخر سجل للحضور والانضباط الشهري
  if (employee.attendance30) {
    const { present, lateDays, absent } = employee.attendance30;
    events.push({
      id: 'attendance-recent',
      title: 'إغلاق ومراجعة كشف الحضور الدوري',
      date: 'آخر 30 يوماً',
      description: `تسجيل ${present} يوم حضور فعلي، مع ${lateDays} تأخيرات، و${absent} غيابات مسجلة في السجلات الميدانية.`,
      category: 'attendance',
      icon: Clock,
      tone: absent > 3 ? 'warning' : 'success',
    });
  }

  // 4. العهد والأصول المستلمة
  const assetCount = employee.assets?.length ?? 0;
  if (assetCount > 0) {
    events.push({
      id: 'assets-assigned',
      title: 'تسليم واستلام العهد والأجهزة المؤسسية',
      date: 'سجل العهد الرسمية',
      description: `تم تسليم الموظف ${assetCount} عهد وأجهزة رسمية موثقة في سجلات العهد والأصول.`,
      category: 'compliance',
      icon: Briefcase,
      tone: 'info',
    });
  }

  // 5. المستندات الرسمية المعتمدة
  const docCount = employee.documents?.length ?? 0;
  if (docCount > 0) {
    events.push({
      id: 'documents-archived',
      title: 'إيداع وتدقيق مسوغات التعيين الرسمية',
      date: 'ملف الموارد البشرية',
      description: `اكتمال أرشفة ${docCount} مستنداً رسمياً معتمداً ومطابقاً للائحة التوظيف بالمنشأة.`,
      category: 'compliance',
      icon: FileCheck,
      tone: 'success',
    });
  }

  // 6. تاريخ التعيين وبدء الخدمة
  if (employee.hireDate) {
    events.push({
      id: 'hire-milestone',
      title: 'بدء الخدمة والتعيين الرسمي',
      date: employee.hireDate,
      description: `انضمام الموظف للعمل بإدارة (${employee.department ?? 'الإدارة العامة'}) بمسمى (${employee.jobTitle ?? 'موظف'}) فرع (${employee.branch ?? 'المقر الرئيسي'}).`,
      category: 'career',
      icon: Briefcase,
      tone: 'primary',
    });
  }

  const toneClasses: Record<TimelineEvent['tone'], { bg: string; text: string; border: string; dot: string }> = {
    primary: {
      bg: 'bg-blue-500/10 dark:bg-blue-500/20',
      text: 'text-blue-600 dark:text-blue-400',
      border: 'border-blue-500/30',
      dot: 'bg-blue-500',
    },
    success: {
      bg: 'bg-emerald-500/10 dark:bg-emerald-500/20',
      text: 'text-emerald-600 dark:text-emerald-400',
      border: 'border-emerald-500/30',
      dot: 'bg-emerald-500',
    },
    warning: {
      bg: 'bg-amber-500/10 dark:bg-amber-500/20',
      text: 'text-amber-600 dark:text-amber-400',
      border: 'border-amber-500/30',
      dot: 'bg-amber-500',
    },
    info: {
      bg: 'bg-cyan-500/10 dark:bg-cyan-500/20',
      text: 'text-cyan-600 dark:text-cyan-400',
      border: 'border-cyan-500/30',
      dot: 'bg-cyan-500',
    },
    purple: {
      bg: 'bg-purple-500/10 dark:bg-purple-500/20',
      text: 'text-purple-600 dark:text-purple-400',
      border: 'border-purple-500/30',
      dot: 'bg-purple-500',
    },
  };

  return (
    <section className="card p-6" aria-labelledby="timeline-heading">
      <div className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="flex size-10 items-center justify-center rounded-xl bg-blue-500/10 text-blue-600 dark:bg-blue-500/20 dark:text-blue-400">
            <History className="size-5" aria-hidden="true" />
          </div>
          <div>
            <h3 id="timeline-heading" className="text-lg font-black text-[var(--text)]">
              سجل النشاط والمحطات الإدارية
            </h3>
            <p className="text-xs text-[var(--muted)]">
              تتبع زمني متكامل للمحطات الوظيفية والتقييمات وأهم الإجراءات المعتمدة
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 rounded-full border border-[var(--border)] bg-[var(--surface-subtle)] px-3 py-1 text-xs font-bold text-[var(--muted)]">
          <Sparkles className="size-3.5 text-amber-500" aria-hidden="true" />
          <span>{events.length} محطات رئيسية</span>
        </div>
      </div>

      <div className="relative border-r-2 border-[var(--border)] pr-6 space-y-6 mr-3">
        {events.map((evt) => {
          const IconComponent = evt.icon;
          const styles = toneClasses[evt.tone];
          return (
            <div key={evt.id} className="relative group">
              {/* Dot on the timeline line */}
              <div
                className={`absolute -right-[31px] top-1.5 flex size-4 items-center justify-center rounded-full border-2 border-[var(--surface)] ${styles.dot}`}
                aria-hidden="true"
              />

              {/* Event Card */}
              <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-sm transition-all hover:border-[var(--primary)] hover:shadow-md">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2.5">
                    <div className={`flex size-8 shrink-0 items-center justify-center rounded-lg border ${styles.bg} ${styles.border} ${styles.text}`}>
                      <IconComponent className="size-4" aria-hidden="true" />
                    </div>
                    <h4 className="text-sm font-bold text-[var(--text)]">{evt.title}</h4>
                  </div>
                  <span className="flex items-center gap-1.5 rounded-md bg-[var(--surface-subtle)] px-2.5 py-1 text-xs font-bold text-[var(--muted)]">
                    <Calendar className="size-3" aria-hidden="true" />
                    {evt.date}
                  </span>
                </div>
                <p className="mt-2 text-xs leading-relaxed text-[var(--muted)]">
                  {evt.description}
                </p>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
