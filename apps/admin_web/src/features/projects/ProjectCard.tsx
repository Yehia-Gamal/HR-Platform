import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { LED_COLORS, ledCardClass } from './projectLedStatus';
import { StatusBadge } from '../../ui/StatusBadge';

interface Props {
  project: AssociationProjectListItem;
  onClick: () => void;
}

const PRIORITY_LABELS: Record<string, string> = {
  low: 'منخفضة', medium: 'متوسطة', high: 'عالية', critical: 'حرجة',
};

export function ProjectCard({ project, onClick }: Props) {
  const led = project.ledStatus;
  const colors = LED_COLORS[led];

  return (
    <button
      onClick={onClick}
      className={`text-right w-full p-5 ${ledCardClass(led)} cursor-pointer group`}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <div
            className={`w-4 h-4 rounded-full ${colors.bg} ${colors.glow} ${led === 'active' ? 'animate-pulse' : ''}`}
            title={colors.label}
          />
          <span className="text-xs font-medium text-gray-500">{colors.label}</span>
        </div>
        <StatusBadge status={project.status} />
      </div>

      <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-1 group-hover:text-emerald-600 transition-colors">
        {project.name}
      </h3>
      <p className="text-sm text-gray-500 font-mono mb-3">{project.code}</p>

      <div className="flex items-center gap-3 text-sm text-gray-600 dark:text-gray-400 mb-3">
        <span>{project.ownerName}</span>
        <span className="text-gray-300">|</span>
        <span>{project.departmentName}</span>
      </div>

      <div className="mb-3">
        <div className="flex justify-between text-xs mb-1">
          <span className="font-medium">{project.progress}%</span>
          <span className="text-gray-500">الإنجاز</span>
        </div>
        <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
          <div
            className={`h-2 rounded-full transition-all duration-500 ${
              led === 'active' ? 'bg-emerald-500' : led === 'halted' ? 'bg-red-500' : 'bg-gray-400'
            }`}
            style={{ width: `${project.progress}%` }}
          />
        </div>
      </div>

      <div className="flex items-center justify-between text-xs text-gray-500">
        <div className="flex items-center gap-3">
          <span>{project.remainingSteps} خطوة متبقية</span>
          {project.blockedSteps > 0 && (
            <span className="text-red-500 font-medium">{project.blockedSteps} متوقفة</span>
          )}
        </div>
        <StatusBadge status={project.priority} label={PRIORITY_LABELS[project.priority]} />
      </div>

      {project.lastUpdateAt && (
        <p className="text-xs text-gray-400 mt-2">
          آخر تحديث: منذ {Math.floor((Date.now() - new Date(project.lastUpdateAt).getTime()) / 86400000)} يوم
        </p>
      )}
    </button>
  );
}
