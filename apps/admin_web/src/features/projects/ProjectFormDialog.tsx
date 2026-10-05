import { useState } from 'react';
import type { AssociationProjectListItem, AssociationProjectPermissions } from '@ahla/shared-contracts';
import { Loader2 } from 'lucide-react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useProjectPickers, useSaveAssociationProject } from './useAssociationProjects';
import { PRIORITY_LABELS } from './projectLedStatus';
import { DepartmentPicker, PeoplePicker } from './TeamPicker';

interface Props {
  /** غياب المشروع = إنشاء جديد. */
  project?: AssociationProjectListItem;
  /** صلاحيات المشروع عند التعديل (الاسم والوصف قد يكونان مقفلين). */
  permissions?: AssociationProjectPermissions;
  isFullAccess: boolean;
  /** إدارة المستخدم — تُقترح افتراضياً عند الإنشاء. */
  myDepartmentId: string | null;
  /** المستخدم الحالي — القائد الافتراضي عند الإنشاء. */
  myEmployeeId: string | null;
  onClose: () => void;
}

export function ProjectFormDialog({ project, permissions, isFullAccess, myDepartmentId, myEmployeeId, onClose }: Props) {
  const isEdit = Boolean(project);
  const save = useSaveAssociationProject();
  const { data: pickers, isLoading: pickersLoading, error: pickersError } = useProjectPickers();

  const [name, setName] = useState(project?.name ?? '');
  const [code, setCode] = useState('');
  const [description, setDescription] = useState(project?.description ?? '');
  const [priority, setPriority] = useState<string>(project?.priority ?? 'medium');
  const [startDate, setStartDate] = useState(project?.startDate ?? '');
  const [targetEndDate, setTargetEndDate] = useState(project?.targetEndDate ?? '');
  const [leaderId, setLeaderId] = useState<string | null>(project ? (project.leaderId ?? project.ownerId) : myEmployeeId);
  const [memberIds, setMemberIds] = useState<string[]>(project ? project.members.filter((m) => !m.isLeader).map((m) => m.employeeId) : []);
  const [departmentIds, setDepartmentIds] = useState<string[]>(
    project ? project.departments.map((d) => d.id) : !isFullAccess && myDepartmentId ? [myDepartmentId] : [],
  );
  // غير المدير التنفيذي يرسل مشروعه للاعتماد مباشرة افتراضياً.
  const [submitNow, setSubmitNow] = useState(true);

  // بعد الإرسال للاعتماد: الاسم والوصف هما ما اعتُمد.
  const coreLocked = isEdit && !isFullAccess && permissions?.canEditCore === false;
  const datesInvalid = Boolean(startDate && targetEndDate && targetEndDate < startDate);
  const canSave = name.trim() && leaderId && !datesInvalid && !save.isPending;
  const teamSize = (leaderId ? 1 : 0) + memberIds.filter((id) => id !== leaderId).length;

  async function submit() {
    if (!canSave) return;
    try {
      await save.mutateAsync({
        projectId: project?.id,
        code: code.trim(),
        name: name.trim(),
        description: description.trim(),
        priority,
        startDate,
        targetEndDate,
        leaderId,
        memberIds: memberIds.filter((id) => id !== leaderId),
        departmentIds,
        submit: !isEdit && !isFullAccess && submitNow,
      });
      onClose();
    } catch {
      // الخطأ يظهر في الشريط أعلى النموذج
    }
  }

  return (
    <DialogOverlay title={isEdit ? 'تعديل المشروع وفريقه' : 'مشروع جديد'} onClose={onClose} maxWidth="max-w-3xl">
      <div className="space-y-5">
        {save.isError && <ErrorBanner message={safeErrorMessage(save.error)} />}
        {pickersError && <ErrorBanner message={safeErrorMessage(pickersError)} />}

        {!isEdit && (
          <p className="rounded-xl bg-[var(--surface-subtle)] p-3 text-sm leading-7 text-[var(--text-muted)]">
            {isFullAccess
              ? 'المشاريع التي ينشئها المدير التنفيذي تُعتمد مباشرة وتظهر على اللوحة.'
              : 'حدّد قائد المشروع وفريقه (والإدارات إن وُجدت)، ثم يُرسل للمدير التنفيذي لاعتماده ليظهر على لوحة مشاريع الجمعية.'}
          </p>
        )}

        <section className="space-y-4">
          <label className="block">
            <span className="text-sm font-bold">اسم المشروع *</span>
            <input
              className="input mt-1"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="مثال: حملة كفالة الأيتام"
              disabled={coreLocked}
            />
          </label>
          <label className="block">
            <span className="text-sm font-bold">وصف مختصر وهدف المشروع</span>
            <textarea
              className="input mt-1"
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="ما الذي سيحققه المشروع؟"
              disabled={coreLocked}
            />
          </label>
          {coreLocked && <p className="text-xs font-bold text-[var(--text-muted)]">الاسم والوصف مقفلان بعد إرسال المشروع للاعتماد — يمكن تعديل الفريق والأولوية والمواعيد.</p>}

          <div className="grid gap-4 sm:grid-cols-3">
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
            <label className="block">
              <span className="text-sm font-bold">تاريخ البدء</span>
              <input type="date" className="input mt-1" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </label>
            <label className="block">
              <span className="text-sm font-bold">الموعد المستهدف للانتهاء</span>
              <input type="date" className="input mt-1" value={targetEndDate} onChange={(e) => setTargetEndDate(e.target.value)} />
            </label>
          </div>
          {datesInvalid && <p className="text-sm font-bold text-[var(--danger)]">الموعد المستهدف يجب أن يكون بعد تاريخ البدء.</p>}
        </section>

        {/* فريق المشروع */}
        <section className="space-y-4 rounded-2xl border border-[var(--border)] p-4">
          <div className="flex items-baseline justify-between gap-3">
            <h3 className="font-black">فريق المشروع</h3>
            <span className="text-xs text-[var(--text-muted)]">{teamSize} {teamSize === 1 ? 'شخص' : 'أشخاص'}</span>
          </div>
          {pickersLoading ? (
            <p className="flex items-center gap-2 text-sm text-[var(--text-muted)]">
              <Loader2 className="size-4 animate-spin" aria-hidden="true" /> جارٍ تحميل قائمة الموظفين…
            </p>
          ) : (
            <div className="grid gap-5 md:grid-cols-2">
              <PeoplePicker
                label="قائد المشروع *"
                hint="شخص واحد مسؤول أول عن المشروع ويدير فريقه."
                single
                employees={pickers?.employees ?? []}
                selected={leaderId ? [leaderId] : []}
                onChange={(ids) => {
                  const next = ids[0] ?? null;
                  // القائد السابق يبقى عضواً في الفريق بدل أن يخرج فجأة.
                  if (leaderId && next && next !== leaderId) setMemberIds((m) => [...m.filter((x) => x !== next), leaderId]);
                  setLeaderId(next);
                }}
              />
              <PeoplePicker
                label="أعضاء الفريق"
                hint="المسؤولون مع القائد — يديرون الخطوات ويسجّلون التحديثات."
                employees={pickers?.employees ?? []}
                selected={memberIds.filter((id) => id !== leaderId)}
                exclude={leaderId ? [leaderId] : []}
                onChange={setMemberIds}
              />
            </div>
          )}
          <DepartmentPicker departments={pickers?.departments ?? []} selected={departmentIds} onChange={setDepartmentIds} />
        </section>

        {!isEdit && (
          <label className="block">
            <span className="text-sm font-bold">كود المشروع (اختياري)</span>
            <input className="input mt-1" dir="ltr" value={code} onChange={(e) => setCode(e.target.value)} placeholder="يُولَّد تلقائياً مثل PRJ-2026-001" />
          </label>
        )}

        {!isEdit && !isFullAccess && (
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={submitNow} onChange={(e) => setSubmitNow(e.target.checked)} className="size-4 accent-[var(--brand-primary)]" />
            إرسال للمدير التنفيذي للاعتماد فوراً (أو احفظه مسودة وأرسله لاحقاً)
          </label>
        )}

        <button onClick={submit} disabled={!canSave} className="btn-primary w-full">
          {save.isPending && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          {save.isPending
            ? 'جارٍ الحفظ…'
            : isEdit
              ? 'حفظ التعديلات'
              : isFullAccess
                ? 'إنشاء واعتماد المشروع'
                : submitNow
                  ? 'إنشاء وإرسال للاعتماد'
                  : 'حفظ كمسودة'}
        </button>
        {!leaderId && <p className="text-center text-xs font-bold text-[var(--danger)]">اختر قائد المشروع.</p>}
      </div>
    </DialogOverlay>
  );
}
