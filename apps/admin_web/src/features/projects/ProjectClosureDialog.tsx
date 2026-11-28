import { useState } from 'react';
import type { AssociationProjectListItem, AssociationProjectStep } from '@ahla/shared-contracts';
import { CheckCircle2, Loader2 } from 'lucide-react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { stepProgressLabel } from './projectLedStatus';
import { useCloseAssociationProject } from './useAssociationProjects';

export function ProjectClosureDialog({ project, steps, onClose }: {
  project: AssociationProjectListItem;
  steps: AssociationProjectStep[];
  onClose: () => void;
}) {
  const [confirmed, setConfirmed] = useState(false);
  const [note, setNote] = useState('');
  const closeProject = useCloseAssociationProject();
  const revision = project.planRevision;
  const ready = project.canReviewClosure && revision !== undefined && project.approvalStatus === 'approved'
    && ['active', 'on_hold'].includes(project.status) && steps.length > 0 && steps.every((step) => step.status === 'done');

  return (
    <DialogOverlay title="مراجعة خطة التنفيذ" onClose={onClose} maxWidth="max-w-lg">
      <form className="space-y-4" onSubmit={(event) => {
        event.preventDefault();
        if (!ready || !confirmed || !note.trim() || closeProject.isPending) return;
        closeProject.mutate({ projectId: project.id, planRevision: revision, reviewNote: note.trim() }, { onSuccess: onClose });
      }}>
        <div>
          <h3 className="text-lg font-black">{project.name}</h3>
          {project.description && <p className="mt-1 text-sm text-[var(--text-secondary)]">{project.description}</p>}
          <p className="mt-2 text-sm font-bold">{stepProgressLabel(steps.filter((step) => step.status === 'done').length, steps.length)}</p>
        </div>
        <ul className="max-h-48 space-y-2 overflow-auto rounded-xl bg-[var(--surface-subtle)] p-3">
          {steps.map((step) => (
            <li key={step.id} className="flex items-center gap-2 text-sm">
              {step.status === 'done' && <CheckCircle2 className="size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />}
              {step.title}
            </li>
          ))}
        </ul>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" className="mt-1" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
          <span>راجعت خطة التنفيذ وتأكدت من إنجاز كامل نطاق المشروع.</span>
        </label>
        <label className="block text-sm font-bold">
          نتيجة المراجعة
          <textarea className="input mt-1" rows={3} value={note} onChange={(event) => setNote(event.target.value)} required />
        </label>
        {closeProject.error && <p role="alert" className="text-sm text-[var(--danger)]">{safeErrorMessage(closeProject.error)}</p>}
        <button className="btn-primary w-full" disabled={!ready || !confirmed || !note.trim() || closeProject.isPending}>
          {closeProject.isPending && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          اعتماد إغلاق المشروع
        </button>
      </form>
    </DialogOverlay>
  );
}
