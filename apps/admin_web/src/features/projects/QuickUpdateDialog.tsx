import { useState } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { Loader2 } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useAddProjectUpdate } from './useAssociationProjects';
import { STATUS_LABELS, projectProgressPercent, stepProgressLabel } from './projectLedStatus';

interface Props {
  project: AssociationProjectListItem;
  onClose: () => void;
}

const STATUS_CHOICES = ['active', 'on_hold'] as const;

/** تسجيل تحديث على مشروع معتمد — يعيد اللمبة للأخضر ويُحفظ في سجل المشروع. */
export function QuickUpdateDialog({ project, onClose }: Props) {
  const addUpdate = useAddProjectUpdate();
  const [note, setNote] = useState('');
  const [status, setStatus] = useState<string>(project.status === 'planned' ? 'active' : project.status);
  const [progress, setProgress] = useState<number | null>(null);
  const manualProgress = project.totalSteps === 0;
  const isClosed = project.status === 'completed' || project.status === 'cancelled';
  const pausing = status === 'on_hold' && project.status !== 'on_hold';
  const shownProgress = progress ?? projectProgressPercent({ ...project, status: 'active' });
  const canSubmit = note.trim().length > 0 && !addUpdate.isPending;

  function submit() {
    if (!canSubmit) return;
    addUpdate.mutate(
      {
        projectId: project.id,
        note: note.trim(),
        progress: manualProgress && !isClosed ? progress : null,
        statusChange: status !== project.status ? status : null,
      },
      { onSuccess: onClose },
    );
  }

  return (
    <DialogOverlay title={`تحديث على «${project.name}»`} onClose={onClose} maxWidth="max-w-lg">
      <div className="space-y-4">
        <label className="block">
          <span className="text-sm font-bold">{pausing ? 'سبب توقف المشروع *' : 'ما الذي تم إنجازه؟ *'}</span>
          <textarea
            className="input mt-1"
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder={pausing ? 'مثال: التوريد معلق حتى اعتماد الدفعة' : 'مثال: تم الاتفاق مع المورد وبدأ التوريد'}
          />
        </label>

        {!isClosed && <fieldset>
          <legend className="text-sm font-bold">حالة المشروع</legend>
          <div className="mt-2 flex flex-wrap gap-2">
            {STATUS_CHOICES.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setStatus(s)}
                className={`filter-chip${status === s ? ' is-active' : ''}`}
                aria-pressed={status === s}
              >
                {STATUS_LABELS[s]}
              </button>
            ))}
          </div>
        </fieldset>}

        {manualProgress && !isClosed ? (
          <label className="block">
            <span className="text-sm font-bold">التقدم المُبلّغ عنه</span>
            <div className="mt-1 flex items-center gap-3">
              <input
                type="range"
                min={0}
                max={99}
                step={1}
                className="flex-1 accent-[var(--brand-primary)]"
                value={shownProgress ?? 0}
                onChange={(e) => setProgress(Number(e.target.value))}
              />
              <span className="tabular w-12 text-center text-lg font-black">{shownProgress === null ? '—' : `${shownProgress}%`}</span>
            </div>
          </label>
        ) : !manualProgress ? (
          <p className="rounded-xl bg-[var(--surface-subtle)] p-3 text-xs text-[var(--text-muted)]">
            {stepProgressLabel(project.completedSteps, project.totalSteps)}
          </p>
        ) : null}

        <button onClick={submit} disabled={!canSubmit} className="btn-primary w-full">
          {addUpdate.isPending && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          {addUpdate.isPending ? 'جارٍ الحفظ…' : 'حفظ التحديث'}
        </button>
      </div>
    </DialogOverlay>
  );
}
