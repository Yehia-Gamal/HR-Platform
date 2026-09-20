import { useState } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { LED_COLORS } from './projectLedStatus';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { StatusBadge } from '../../ui/StatusBadge';
import { ArrowLeftRight, CheckCircle2, Target, Clock } from 'lucide-react';

interface Props {
  projectA: AssociationProjectListItem;
  projectB: AssociationProjectListItem;
  onClose: () => void;
}

const PRIORITY_LABELS: Record<string, string> = {
  low: 'منخفضة',
  medium: 'متوسطة',
  high: 'عالية',
  critical: 'حرجة',
};
function CompareRow({ label, valueA, valueB }: { label: string; valueA: React.ReactNode; valueB: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[1fr_auto_1fr] gap-3 items-center py-2 border-b border-gray-100 dark:border-gray-800 last:border-0">
      <div className="text-sm text-right">{valueA}</div>
      <span className="text-xs text-gray-400 font-bold px-2">{label}</span>
      <div className="text-sm text-left">{valueB}</div>
    </div>
  );
}

export function ProjectCompare({ projectA, projectB, onClose }: Props) {
  const ledA = LED_COLORS[projectA.ledStatus];
  const ledB = LED_COLORS[projectB.ledStatus];
  const totalA = projectA.completedSteps + projectA.remainingSteps;
  const totalB = projectB.completedSteps + projectB.remainingSteps;

  return (
    <DialogOverlay title="مقارنة المشاريع" onClose={onClose} maxWidth="max-w-2xl">
      <div className="p-4">
        {/* رؤوس المشاريع */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          <div />
          <div className="text-center">
            <div className={`w-6 h-6 rounded-full mx-auto mb-2 ${ledA.bg} ${ledA.glow}`} />
            <p className="font-extrabold text-sm">{projectA.name}</p>
            <p className="text-xs text-gray-400 font-mono">{projectA.code}</p>
          </div>
          <div className="text-center">
            <div className={`w-6 h-6 rounded-full mx-auto mb-2 ${ledB.bg} ${ledB.glow}`} />
            <p className="font-extrabold text-sm">{projectB.name}</p>
            <p className="text-xs text-gray-400 font-mono">{projectB.code}</p>
          </div>
        </div>

        {/* صفوف المقارنة */}
        <CompareRow
          label="LED"
          valueA={<span className={`inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-xs font-bold ${ledA.bg} text-white`}>{ledA.label}</span>}
          valueB={<span className={`inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-xs font-bold ${ledB.bg} text-white`}>{ledB.label}</span>}
        />
        <CompareRow label="الحالة" valueA={<StatusBadge status={projectA.status} />} valueB={<StatusBadge status={projectB.status} />} />
        <CompareRow
          label="الأولوية"
          valueA={<StatusBadge status={projectA.priority} label={PRIORITY_LABELS[projectA.priority]} />}
          valueB={<StatusBadge status={projectB.priority} label={PRIORITY_LABELS[projectB.priority]} />}
        />
        <CompareRow label="الإدارة" valueA={projectA.departmentName} valueB={projectB.departmentName} />
        <CompareRow label="المسؤول" valueA={projectA.ownerName} valueB={projectB.ownerName} />

        <CompareRow
          label="التقدم"
          valueA={
            <div className="flex items-center gap-2">
              <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
                <div className={`h-full rounded-full ${ledA.bg}`} style={{ width: `${projectA.progress}%` }} />
              </div>
              <span className="font-bold text-xs">{projectA.progress}%</span>
            </div>
          }
          valueB={
            <div className="flex items-center gap-2">
              <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
                <div className={`h-full rounded-full ${ledB.bg}`} style={{ width: `${projectB.progress}%` }} />
              </div>
              <span className="font-bold text-xs">{projectB.progress}%</span>
            </div>
          }
        />

        <CompareRow
          label="الخطوات"
          valueA={
            <span className="flex items-center gap-1">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" /> {projectA.completedSteps}/{totalA}
            </span>
          }
          valueB={
            <span className="flex items-center gap-1">
              <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" /> {projectB.completedSteps}/{totalB}
            </span>
          }
        />

        <CompareRow
          label="المتبقية"
          valueA={
            <span className="flex items-center gap-1">
              <Target className="w-3.5 h-3.5 text-blue-500" /> {projectA.remainingSteps}
            </span>
          }
          valueB={
            <span className="flex items-center gap-1">
              <Target className="w-3.5 h-3.5 text-blue-500" /> {projectB.remainingSteps}
            </span>
          }
        />

        <CompareRow
          label="آخر تحديث"
          valueA={
            projectA.lastUpdateAt ? (
              <span className="flex items-center gap-1">
                <Clock className="w-3 h-3" /> {new Date(projectA.lastUpdateAt).toLocaleDateString('ar-EG')}
              </span>
            ) : (
              '—'
            )
          }
          valueB={
            projectB.lastUpdateAt ? (
              <span className="flex items-center gap-1">
                <Clock className="w-3 h-3" /> {new Date(projectB.lastUpdateAt).toLocaleDateString('ar-EG')}
              </span>
            ) : (
              '—'
            )
          }
        />

        {projectA.startDate && projectB.startDate && <CompareRow label="تاريخ البدء" valueA={projectA.startDate} valueB={projectB.startDate} />}
        {projectA.targetEndDate && projectB.targetEndDate && (
          <CompareRow label="الموعد النهائي" valueA={projectA.targetEndDate} valueB={projectB.targetEndDate} />
        )}
      </div>
    </DialogOverlay>
  );
}

interface CompareSelectorProps {
  projects: AssociationProjectListItem[];
  onClose: () => void;
  onSelect: (a: AssociationProjectListItem, b: AssociationProjectListItem) => void;
}

export function CompareSelector({ projects, onClose, onSelect }: CompareSelectorProps) {
  const [a, setA] = useState<string>('');
  const [b, setB] = useState<string>('');

  function handleCompare() {
    const projA = projects.find((p) => p.id === a);
    const projB = projects.find((p) => p.id === b);
    if (projA && projB) onSelect(projA, projB);
  }

  return (
    <DialogOverlay title="اختر مشروعين للمقارنة" onClose={onClose} maxWidth="max-w-md">
      <div className="p-4 space-y-4">
        <label className="block">
          <span className="text-sm font-medium">المشروع الأول</span>
          <select className="input mt-1 w-full" value={a} onChange={(e) => setA(e.target.value)}>
            <option value="">— اختر مشروع —</option>
            {projects.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name} ({p.code})
              </option>
            ))}
          </select>
        </label>

        <div className="flex justify-center">
          <ArrowLeftRight className="w-5 h-5 text-gray-400" />
        </div>

        <label className="block">
          <span className="text-sm font-medium">المشروع الثاني</span>
          <select className="input mt-1 w-full" value={b} onChange={(e) => setB(e.target.value)}>
            <option value="">— اختر مشروع —</option>
            {projects
              .filter((p) => p.id !== a)
              .map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} ({p.code})
                </option>
              ))}
          </select>
        </label>

        <button onClick={handleCompare} disabled={!a || !b} className="btn-primary w-full">
          مقارنة
        </button>
      </div>
    </DialogOverlay>
  );
}
