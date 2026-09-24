import { useState } from 'react';
import type { AssociationProjectSettings } from '@ahla/shared-contracts';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ProjectLed } from './ProjectLed';
import { useSetProjectSettings } from './useAssociationProjects';

/** ضبط عدد الأيام التي يتحول بعدها المشروع للأحمر ثم للأحمر الوامض. */
export function ProjectSettingsDialog({ settings, onClose }: { settings: AssociationProjectSettings; onClose: () => void }) {
  const save = useSetProjectSettings();
  const [warningDays, setWarningDays] = useState(settings.warningDays);
  const [criticalDays, setCriticalDays] = useState(settings.criticalDays);
  const valid = warningDays >= 1 && criticalDays > warningDays && criticalDays <= 730;

  return (
    <DialogOverlay title="إعدادات لمبة التنبيه" onClose={onClose} maxWidth="max-w-md">
      <div className="space-y-4">
        <ul className="space-y-2 rounded-xl bg-[var(--surface-subtle)] p-3 text-sm">
          <li className="flex items-center gap-2">
            <ProjectLed status="active" /> أخضر: المشروع يُحدَّث بانتظام
          </li>
          <li className="flex items-center gap-2">
            <ProjectLed status="halted" /> أحمر: متوقف أو بلا تحديث منذ {warningDays} أيام
          </li>
          <li className="flex items-center gap-2">
            <ProjectLed status="critical" /> أحمر يومض: بلا تحديث منذ {criticalDays} يوماً — يصلك إشعار
          </li>
        </ul>
        <div className="grid grid-cols-2 gap-4">
          <label className="block">
            <span className="text-sm font-bold">أحمر بعد (يوم)</span>
            <input type="number" min={1} max={365} className="input mt-1" value={warningDays} onChange={(e) => setWarningDays(Number(e.target.value))} />
          </label>
          <label className="block">
            <span className="text-sm font-bold">يومض بعد (يوم)</span>
            <input type="number" min={2} max={730} className="input mt-1" value={criticalDays} onChange={(e) => setCriticalDays(Number(e.target.value))} />
          </label>
        </div>
        {!valid && <p className="text-sm font-bold text-[var(--danger)]">أيام الوميض يجب أن تكون أكبر من أيام الأحمر.</p>}
        <button
          className="btn-primary w-full"
          disabled={!valid || save.isPending}
          onClick={async () => {
            await save.mutateAsync({ warningDays, criticalDays });
            onClose();
          }}
        >
          حفظ
        </button>
      </div>
    </DialogOverlay>
  );
}
