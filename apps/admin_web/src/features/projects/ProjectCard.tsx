import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { LED_COLORS, ledCardClass, daysSince } from './projectLedStatus';
import { StatusBadge } from '../../ui/StatusBadge';
import { Clock, AlertTriangle, CheckCircle2, Target, Zap } from 'lucide-react';

interface Props {
  project: AssociationProjectListItem;
  onClick: () => void;
  onQuickUpdate?: (project: AssociationProjectListItem) => void;
}

const PRIORITY_LABELS: Record<string, string> = {
  low: 'منخفضة', medium: 'متوسطة', high: 'عالية', critical: 'حرجة',
};

export function ProjectCard({ project, onClick, onQuickUpdate }: Props) {
  const led = project.ledStatus;
  const colors = LED_COLORS[led];

  return (
    <div className={`text-end w-full p-0 ${ledCardClass(led)} group overflow-hidden`}>
      {/* شريط LED العلوي */}
      <div className={`h-1.5 w-full ${
        led === 'active' ? 'bg-emerald-500' : led === 'halted' ? 'bg-red-500' : 'bg-gray-400'
      } ${led === 'active' ? 'animate-pulse' : ''}`} />

      <div className="p-5">
        {/* LED + الحالة + الأولوية + زر التحديث السريع */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <div className="relative">
              <div className={`w-5 h-5 rounded-full ${colors.bg} ${colors.glow} ${led === 'active' ? 'animate-pulse' : ''}`} />
              {led === 'active' && (
                <div className="absolute inset-0 w-5 h-5 rounded-full bg-emerald-400 animate-ping opacity-30" />
              )}
            </div>
            <span className="text-xs font-bold tracking-wide text-gray-600 dark:text-gray-300 uppercase">
              {colors.label}
            </span>
          </div>
          <div className="flex items-center gap-2">
            {onQuickUpdate && led !== 'stale' && (
              <button
                onClick={(e) => { e.stopPropagation(); onQuickUpdate(project); }}
                className="p-1.5 rounded-lg bg-emerald-50 text-emerald-600 hover:bg-emerald-100 dark:bg-emerald-900/20 dark:hover:bg-emerald-900/40 transition-colors"
                title="تحديث سريع"
              >
                <Zap className="w-3.5 h-3.5" />
              </button>
            )}
            <StatusBadge status={project.status} />
          </div>
        </div>

        {/* الاسم والكود */}
        <button onClick={onClick} className="w-full text-end cursor-pointer">
          <h3 className="text-lg font-extrabold text-gray-900 dark:text-white mb-1 leading-tight group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
            {project.name}
          </h3>
        </button>
        <p className="text-xs text-gray-400 font-mono mb-3 tracking-wider">{project.code}</p>

        {/* الإدارة والمسؤول */}
        <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400 mb-4 pb-3 border-b border-gray-100 dark:border-gray-800">
          <Target className="w-3 h-3 text-gray-400" />
          <span className="font-medium">{project.departmentName}</span>
          <span className="text-gray-300 dark:text-gray-600">•</span>
          <span>{project.ownerName}</span>
        </div>

        {/* شريط التقدم */}
        <div className="mb-4">
          <div className="flex justify-between items-center text-xs mb-1.5">
            <span className="text-gray-500">نسبة الإنجاز</span>
            <span className="font-bold text-gray-700 dark:text-gray-200">{project.progress}%</span>
          </div>
          <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2.5 overflow-hidden">
            <div
              className={`h-full rounded-full transition-all duration-700 ease-out ${
                led === 'active' ? 'bg-gradient-to-r from-emerald-500 to-emerald-400' :
                led === 'halted' ? 'bg-gradient-to-r from-red-500 to-red-400' :
                'bg-gray-400'
              }`}
              style={{ width: `${project.progress}%` }}
            />
          </div>
        </div>

        {/* الخطوات */}
        <div className="flex items-center gap-4 text-xs text-gray-500 mb-3">
          <span className="flex items-center gap-1">
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" />
            {project.completedSteps} مكتملة
          </span>
          <span className="flex items-center gap-1">
            <Target className="w-3.5 h-3.5 text-blue-500" />
            {project.remainingSteps} متبقية
          </span>
          {project.blockedSteps > 0 && (
            <span className="flex items-center gap-1 text-red-500 font-bold">
              <AlertTriangle className="w-3.5 h-3.5" />
              {project.blockedSteps} متوقفة
            </span>
          )}
        </div>

        {/* الأولوية + آخر تحديث */}
        <div className="flex items-center justify-between pt-3 border-t border-gray-100 dark:border-gray-800">
          <StatusBadge status={project.priority} label={PRIORITY_LABELS[project.priority]} />
          {project.lastUpdateAt && (
            <span className="flex items-center gap-1 text-xs text-gray-400">
              <Clock className="w-3 h-3" />
              {daysSince(project.lastUpdateAt)}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
