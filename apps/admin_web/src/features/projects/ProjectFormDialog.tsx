import { useState } from 'react';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { Loader2 } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import { useCreateAssociationProject, useUpdateAssociationProject } from './useAssociationProjects';
import { PRIORITY_LABELS } from './projectLedStatus';

interface Props {
  /** غياب المشروع = إنشاء جديد. */
  project?: AssociationProjectListItem;
  isFullAccess: boolean;
  /** إدارة المستخدم — تُفرض على غير المدير التنفيذي. */
  myDepartmentId: string | null;
  onClose: () => void;
}

export function ProjectFormDialog({ project, isFullAccess, myDepartmentId, onClose }: Props) {
  const isEdit = Boolean(project);
  const create = useCreateAssociationProject();
  const update = useUpdateAssociationProject();
  const { data: org } = useOrganizationLookups();
  const mutation = isEdit ? update : create;

  const [name, setName] = useState(project?.name ?? '');
  const [code, setCode] = useState(project?.code ?? '');
  const [description, setDescription] = useState(project?.description ?? '');
  const [departmentId, setDepartmentId] = useState(project?.departmentId ?? (isFullAccess ? '' : (myDepartmentId ?? '')));
  const [ownerId, setOwnerId] = useState(project?.ownerId ?? '');
  const [priority, setPriority] = useState<string>(project?.priority ?? 'medium');
  const [startDate, setStartDate] = useState(project?.startDate ?? '');
  const [targetEndDate, setTargetEndDate] = useState(project?.targetEndDate ?? '');
  // غير المدير التنفيذي يرسل مشروعه للاعتماد مباشرة افتراضياً.
  const [submitNow, setSubmitNow] = useState(true);

  const departmentLocked = !isFullAccess;
  const datesInvalid = Boolean(startDate && targetEndDate && targetEndDate < startDate);
  const canSubmit = name.trim() && departmentId && !datesInvalid && !mutation.isPending;
  const departmentName = org?.departments.find((d) => d.id === departmentId)?.label ?? project?.departmentName;

  async function submit() {
    if (!canSubmit) return;
    const input = {
      code: code.trim(),
      name: name.trim(),
      description: description.trim(),
      departmentId,
      ownerEmployeeId: isFullAccess ? ownerId || null : null,
      priority,
      startDate,
      targetEndDate,
    };
    try {
      if (project) await update.mutateAsync({ projectId: project.id, ...input });
      else await create.mutateAsync({ ...input, submit: !isFullAccess && submitNow });
      onClose();
    } catch {
      // الخطأ يظهر في الشريط أعلى النموذج
    }
  }

  return (
    <DialogOverlay title={isEdit ? 'تعديل بيانات المشروع' : 'مشروع جديد'} onClose={onClose} maxWidth="max-w-2xl">
      <div className="space-y-4">
        {mutation.isError && <ErrorBanner message={safeErrorMessage(mutation.error)} />}

        {!isEdit && (
          <p className="rounded-xl bg-[var(--surface-subtle)] p-3 text-sm leading-7 text-[var(--text-muted)]">
            {isFullAccess
              ? 'المشاريع التي ينشئها المدير التنفيذي تُعتمد مباشرة وتظهر على اللوحة.'
              : 'يُرسل المشروع للمدير التنفيذي لاعتماده، وبعد الاعتماد يظهر على لوحة مشاريع الجمعية وتبدأ إدارتك في متابعة خطواته.'}
          </p>
        )}

        <label className="block">
          <span className="text-sm font-bold">اسم المشروع *</span>
          <input className="input mt-1" value={name} onChange={(e) => setName(e.target.value)} placeholder="مثال: حملة كفالة الأيتام" />
        </label>

        <label className="block">
          <span className="text-sm font-bold">وصف مختصر وهدف المشروع</span>
          <textarea className="input mt-1" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="ما الذي سيحققه المشروع؟" />
        </label>

        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block">
            <span className="text-sm font-bold">الإدارة المسؤولة *</span>
            {departmentLocked ? (
              <input className="input mt-1" value={departmentName ?? 'إدارتك'} disabled />
            ) : (
              <select className="input mt-1" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
                <option value="">— اختر الإدارة —</option>
                {org?.departments.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.label}
                  </option>
                ))}
              </select>
            )}
          </label>

          {isFullAccess ? (
            <label className="block">
              <span className="text-sm font-bold">مسؤول المشروع</span>
              <select className="input mt-1" value={ownerId} onChange={(e) => setOwnerId(e.target.value)}>
                <option value="">{isEdit ? '— بدون تغيير —' : 'أنا'}</option>
                {org?.managers.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.label}
                  </option>
                ))}
              </select>
            </label>
          ) : (
            <label className="block">
              <span className="text-sm font-bold">الأولوية</span>
              <select className="input mt-1" value={priority} onChange={(e) => setPriority(e.target.value)}>
                {Object.entries(PRIORITY_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </label>
          )}
        </div>

        <div className="grid gap-4 sm:grid-cols-3">
          {isFullAccess && (
            <label className="block">
              <span className="text-sm font-bold">الأولوية</span>
              <select className="input mt-1" value={priority} onChange={(e) => setPriority(e.target.value)}>
                {Object.entries(PRIORITY_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </label>
          )}
          <label className="block">
            <span className="text-sm font-bold">تاريخ البدء</span>
            <input type="date" className="input mt-1" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
          </label>
          <label className="block">
            <span className="text-sm font-bold">الموعد المستهدف للانتهاء</span>
            <input type="date" className="input mt-1" value={targetEndDate} onChange={(e) => setTargetEndDate(e.target.value)} />
          </label>
          {!isFullAccess && (
            <label className="block">
              <span className="text-sm font-bold">كود المشروع</span>
              <input className="input mt-1" dir="ltr" value={code} onChange={(e) => setCode(e.target.value)} placeholder="تلقائي" disabled={isEdit} />
            </label>
          )}
        </div>
        {isFullAccess && !isEdit && (
          <label className="block">
            <span className="text-sm font-bold">كود المشروع (اختياري)</span>
            <input className="input mt-1" dir="ltr" value={code} onChange={(e) => setCode(e.target.value)} placeholder="يُولَّد تلقائياً مثل PRJ-2026-001" />
          </label>
        )}
        {datesInvalid && <p className="text-sm font-bold text-[var(--danger)]">الموعد المستهدف يجب أن يكون بعد تاريخ البدء.</p>}

        {!isEdit && !isFullAccess && (
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={submitNow} onChange={(e) => setSubmitNow(e.target.checked)} className="size-4 accent-[var(--brand-primary)]" />
            إرسال للمدير التنفيذي للاعتماد فوراً (أو احفظه مسودة وأرسله لاحقاً)
          </label>
        )}

        <button onClick={submit} disabled={!canSubmit} className="btn-primary w-full">
          {mutation.isPending && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          {mutation.isPending ? 'جارٍ الحفظ…' : isEdit ? 'حفظ التعديلات' : isFullAccess ? 'إنشاء واعتماد المشروع' : submitNow ? 'إنشاء وإرسال للاعتماد' : 'حفظ كمسودة'}
        </button>
      </div>
    </DialogOverlay>
  );
}
