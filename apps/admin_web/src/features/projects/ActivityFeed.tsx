import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { LED_COLORS } from './projectLedStatus';
import { Clock, MessageSquare, TrendingUp, Zap } from 'lucide-react';
import { useState, useMemo } from 'react';

interface ActivityItem {
  projectId: string;
  projectName: string;
  projectCode: string;
  ledStatus: AssociationProjectListItem['ledStatus'];
  type: 'update' | 'progress' | 'status' | 'step';
  message: string;
  progress?: number;
  timestamp: string;
}

interface Props {
  projects: AssociationProjectListItem[];
}

export function ActivityFeed({ projects }: Props) {
  const [filter, setFilter] = useState<'all' | 'update' | 'progress'>('all');

  const activities = useMemo(() => {
    const items: ActivityItem[] = [];
    for (const p of projects) {
      if (p.lastUpdateAt) {
        items.push({
          projectId: p.id,
          projectName: p.name,
          projectCode: p.code,
          ledStatus: p.ledStatus,
          type: 'update',
          message: `آخر تحديث منذ ${Math.floor((Date.now() - new Date(p.lastUpdateAt).getTime()) / 86400000)} يوم`,
          progress: p.progress,
          timestamp: p.lastUpdateAt,
        });
      }
      if (p.progress > 0) {
        items.push({
          projectId: p.id,
          projectName: p.name,
          projectCode: p.code,
          ledStatus: p.ledStatus,
          type: 'progress',
          message: `نسبة الإنجاز ${p.progress}%`,
          progress: p.progress,
          timestamp: p.lastUpdateAt ?? new Date().toISOString(),
        });
      }
    }
    items.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
    return items;
  }, [projects]);

  const filtered = useMemo(() => {
    if (filter === 'all') return activities;
    return activities.filter((a) => a.type === filter);
  }, [activities, filter]);

  const TYPE_ICONS: Record<string, typeof Clock> = {
    update: Clock,
    progress: TrendingUp,
    status: Zap,
    step: MessageSquare,
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <span className="text-sm font-medium text-gray-500">نوع النشاط:</span>
        {[
          { key: 'all', label: 'الكل' },
          { key: 'update', label: 'التحديثات' },
          { key: 'progress', label: 'التقدم' },
        ].map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key as typeof filter)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
              filter === f.key
                ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                : 'bg-gray-100 text-gray-500 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-400'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="space-y-2 max-h-96 overflow-y-auto">
        {filtered.length === 0 ? (
          <p className="text-center text-gray-400 text-sm py-8">لا توجد نشاطات حديثة</p>
        ) : (
          filtered.map((a, i) => {
            const Icon = TYPE_ICONS[a.type] ?? Clock;
            const colors = LED_COLORS[a.ledStatus];
            return (
              <div
                key={`${a.projectId}-${a.type}-${i}`}
                className="flex items-start gap-3 p-3 rounded-lg bg-gray-50 dark:bg-gray-800/50 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
              >
                <div className={`mt-0.5 w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${colors.bg}`}>
                  <Icon className="w-4 h-4 text-white" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm truncate">{a.projectName}</span>
                    <span className="text-xs text-gray-400 font-mono">{a.projectCode}</span>
                  </div>
                  <p className="text-xs text-gray-500 mt-0.5">{a.message}</p>
                  {a.progress !== undefined && (
                    <div className="mt-1.5 w-full bg-gray-200 dark:bg-gray-700 rounded-full h-1.5">
                      <div className={`h-1.5 rounded-full ${colors.bg}`} style={{ width: `${a.progress}%` }} />
                    </div>
                  )}
                </div>
                <span className="text-xs text-gray-400 shrink-0">{new Date(a.timestamp).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}</span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
