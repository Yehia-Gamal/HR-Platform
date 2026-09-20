import { useState } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { useAddProjectUpdate } from './useAssociationProjects';
import { Zap, Loader2 } from 'lucide-react';

interface Props {
  project: AssociationProjectListItem;
  onClose: () => void;
}

export function QuickUpdateDialog({ project, onClose }: Props) {
  const addUpdate = useAddProjectUpdate();
  const [note, setNote] = useState('');
  const [progress, setProgress] = useState(project.progress);

  async function submit() {
    if (!note.trim()) return;
    await addUpdate.mutateAsync({ projectId: project.id, note: note.trim(), progress });
    onClose();
  }

  return (
    <DialogOverlay title={`تحديث سريع — ${project.name}`} onClose={onClose} maxWidth="max-w-md">
      <div className="space-y-4 p-4">
        <div className="flex items-center gap-2 p-3 bg-emerald-50 dark:bg-emerald-900/20 rounded-lg">
          <Zap className="w-4 h-4 text-emerald-600" />
          <span className="text-sm text-emerald-700 dark:text-emerald-400">تحديث سريع للمشروع — سيُحدَّث آخر تحديث تلقائياً</span>
        </div>

        <label className="block">
          <span className="text-sm font-medium">ما الذي تم عمله؟ *</span>
          <textarea
            className="input mt-1 w-full"
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="اكتب ملاحظة مختصرة عن التحديث..."
            autoFocus
          />
        </label>

        <label className="block">
          <span className="text-sm font-medium">نسبة الإنجاز الحالية</span>
          <div className="flex items-center gap-3 mt-1">
            <input
              type="range"
              min={0}
              max={100}
              className="flex-1 accent-emerald-500"
              value={progress}
              onChange={(e) => setProgress(Number(e.target.value))}
            />
            <span className="text-lg font-bold w-12 text-center">{progress}%</span>
          </div>
        </label>

        <button onClick={submit} disabled={!note.trim() || addUpdate.isPending} className="btn-primary w-full flex items-center justify-center gap-2">
          {addUpdate.isPending && <Loader2 className="w-4 h-4 animate-spin" />}
          {addUpdate.isPending ? 'جاري الحفظ...' : 'حفظ التحديث'}
        </button>
      </div>
    </DialogOverlay>
  );
}
