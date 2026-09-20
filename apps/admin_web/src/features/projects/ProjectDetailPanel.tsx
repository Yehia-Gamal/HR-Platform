import { useState } from 'react';
import type { AssociationProjectDetail, AssociationProjectStep } from '@ahla/shared-contracts';
import { LED_COLORS, APPROVAL_LABELS, APPROVAL_COLORS } from './projectLedStatus';
import {
  useAddProjectUpdate,
  useUpsertProjectStep,
  useDeleteProjectStep,
  useUpdateAssociationProject,
  useSubmitProjectForApproval,
  useApproveProject,
  useRejectProject,
} from './useAssociationProjects';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import { useEmployees } from '../employees/useEmployees';
import { StatusBadge } from '../../ui/StatusBadge';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ConfirmDialog } from '../../ui/ConfirmDialog';
import { X, Plus, CheckCircle2, Clock, FileText, Ban, Edit3, Trash2, Pencil } from 'lucide-react';

interface Props {
  detail: AssociationProjectDetail;
  onClose: () => void;
  onRefresh: () => void;
}

const STEP_STATUS_ICON: Record<string, typeof CheckCircle2> = {
  done: CheckCircle2,
  in_progress: Clock,
  pending: FileText,
  blocked: Ban,
};

export function ProjectDetailPanel({ detail, onClose, onRefresh }: Props) {
  const { project, steps, updates } = detail;
  const led = project.ledStatus;
  const colors = LED_COLORS[led];

  const [editOpen, setEditOpen] = useState(false);
  const [updateOpen, setUpdateOpen] = useState(false);
  const [updateNote, setUpdateNote] = useState('');
  const [updateProgress, setUpdateProgress] = useState(project.progress);
  const [stepOpen, setStepOpen] = useState(false);
  const [editingStep, setEditingStep] = useState<AssociationProjectStep | null>(null);
  const [deleteStepId, setDeleteStepId] = useState<string | null>(null);
  const [stepTitle, setStepTitle] = useState('');
  const [stepDesc, setStepDesc] = useState('');
  const [stepDue, setStepDue] = useState('');
  const [stepStatus, setStepStatus] = useState('pending');

  const addUpdate = useAddProjectUpdate();
  const upsertStep = useUpsertProjectStep();
  const deleteStep = useDeleteProjectStep();
  const updateProject = useUpdateAssociationProject();
  const submitForApproval = useSubmitProjectForApproval();
  const approveProject = useApproveProject();
  const rejectProject = useRejectProject();
  const { data: org } = useOrganizationLookups();
  const { data: employeesData } = useEmployees();
  const employees = employeesData ?? [];

  // edit project state
  const [editName, setEditName] = useState(project.name);
  const [editDesc, setEditDesc] = useState(project.description || '');
  const [editDeptId, setEditDeptId] = useState(project.departmentId);
  const [editOwnerId, setEditOwnerId] = useState(project.ownerId);
  const [editStatus, setEditStatus] = useState(project.status);
  const [editPriority, setEditPriority] = useState(project.priority);
  const [editProgress, setEditProgress] = useState(project.progress);
  const [editStart, setEditStart] = useState(project.startDate || '');
  const [editEnd, setEditEnd] = useState(project.targetEndDate || '');

  async function submitUpdate() {
    await addUpdate.mutateAsync({ projectId: project.id, note: updateNote, progress: updateProgress });
    setUpdateOpen(false);
    setUpdateNote('');
    onRefresh();
  }

  function openEditStep(s: AssociationProjectStep) {
    setEditingStep(s);
    setStepTitle(s.title);
    setStepDesc(s.description || '');
    setStepDue(s.dueDate || '');
    setStepStatus(s.status);
    setStepOpen(true);
  }

  async function submitStep() {
    await upsertStep.mutateAsync({
      projectId: project.id,
      stepId: editingStep?.id,
      title: stepTitle,
      description: stepDesc,
      sortOrder: editingStep?.sortOrder ?? steps.length,
      status: stepStatus,
      dueDate: stepDue,
    });
    setStepOpen(false);
    setEditingStep(null);
    onRefresh();
  }

  async function handleDeleteStep(stepId: string) {
    await deleteStep.mutateAsync(stepId);
    setDeleteStepId(null);
    onRefresh();
  }

  async function submitEdit() {
    await updateProject.mutateAsync({
      projectId: project.id,
      name: editName,
      description: editDesc,
      departmentId: editDeptId,
      ownerEmployeeId: editOwnerId,
      status: editStatus,
      priority: editPriority,
      progress: editProgress,
      startDate: editStart,
      targetEndDate: editEnd,
    });
    setEditOpen(false);
    onRefresh();
  }

  const doneCount = steps.filter((s) => s.status === 'done').length;

  return (
    <>
      <div className="fixed inset-0 z-40 flex justify-end" onClick={onClose}>
        <div className="absolute inset-0 bg-black/40" />
        <div className="relative w-full max-w-2xl bg-white dark:bg-gray-900 shadow-2xl overflow-y-auto" onClick={(e) => e.stopPropagation()}>
          {/* Header */}
          <div className="sticky top-0 z-10 bg-white dark:bg-gray-900 border-b p-6">
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-3 mb-2">
                  <div className="relative">
                    <div className={`w-5 h-5 rounded-full ${colors.bg} ${colors.glow} ${led === 'active' ? 'animate-pulse' : ''}`} />
                    {led === 'active' && <div className="absolute inset-0 w-5 h-5 rounded-full bg-emerald-400 animate-ping opacity-30" />}
                  </div>
                  <span className="text-sm font-bold">{colors.label}</span>
                </div>
                <h2 className="text-2xl font-extrabold">{project.name}</h2>
                <p className="text-sm text-gray-500 font-mono">
                  {project.code} — {project.departmentName}
                </p>
                <div className="flex items-center gap-2 mt-2">
                  <span className={`px-2 py-0.5 rounded-full text-xs font-bold ${APPROVAL_COLORS[project.approvalStatus]}`}>
                    {APPROVAL_LABELS[project.approvalStatus]}
                  </span>
                  {project.rejectionReason && <span className="text-xs text-rose-500">سبب الرفض: {project.rejectionReason}</span>}
                </div>
              </div>
              <div className="flex gap-2">
                <button onClick={() => setEditOpen(true)} className="p-2 hover:bg-gray-100 rounded-lg text-gray-600" title="تعديل">
                  <Pencil className="w-5 h-5" />
                </button>
                <button onClick={onClose} className="p-2 hover:bg-gray-100 rounded-lg">
                  <X />
                </button>
              </div>
            </div>
          </div>

          <div className="p-6 space-y-6">
            {/* معلومات المشروع */}
            <section>
              <h3 className="font-bold mb-3">معلومات المشروع</h3>
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="text-gray-500">الحالة: </span>
                  <StatusBadge status={project.status} />
                </div>
                <div>
                  <span className="text-gray-500">الأولوية: </span>
                  <StatusBadge status={project.priority} />
                </div>
                <div>
                  <span className="text-gray-500">المسؤول: </span>
                  {project.ownerName}
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-gray-500">نسبة الإنجاز: </span>
                  <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
                    <div
                      className={`h-full rounded-full ${led === 'active' ? 'bg-emerald-500' : led === 'halted' ? 'bg-red-500' : 'bg-gray-400'}`}
                      style={{ width: `${project.progress}%` }}
                    />
                  </div>
                  <span className="font-bold">{project.progress}%</span>
                </div>
                {project.startDate && (
                  <div>
                    <span className="text-gray-500">تاريخ البدء: </span>
                    {project.startDate}
                  </div>
                )}
                {project.targetEndDate && (
                  <div>
                    <span className="text-gray-500">الموعد النهائي: </span>
                    {project.targetEndDate}
                  </div>
                )}
              </div>
              {project.description && <p className="mt-3 text-gray-600 dark:text-gray-400 text-sm">{project.description}</p>}

              {/* أزرار الموافقة */}
              {project.approvalStatus === 'pending_approval' && (
                <div className="flex gap-2 mt-4 p-3 bg-amber-50 dark:bg-amber-950/20 rounded-lg border border-amber-200 dark:border-amber-800">
                  <button
                    onClick={async () => {
                      await approveProject.mutateAsync(project.id);
                      onRefresh();
                    }}
                    className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-emerald-500 text-white rounded-lg hover:bg-emerald-600 transition-colors text-sm font-medium"
                  >
                    ✅ موافقة
                  </button>
                  <button
                    onClick={async () => {
                      await rejectProject.mutateAsync({ projectId: project.id });
                      onRefresh();
                    }}
                    className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors text-sm font-medium"
                  >
                    ❌ رفض
                  </button>
                </div>
              )}
              {(project.approvalStatus === 'draft' || project.approvalStatus === 'rejected') && (
                <button
                  onClick={async () => {
                    await submitForApproval.mutateAsync(project.id);
                    onRefresh();
                  }}
                  className="mt-4 w-full flex items-center justify-center gap-1.5 py-2 bg-amber-500 text-white rounded-lg hover:bg-amber-600 transition-colors text-sm font-medium"
                >
                  📤 إرسال للموافقة
                </button>
              )}
            </section>

            {/* Timeline بصرية */}
            {steps.length > 0 && (
              <section>
                <h3 className="font-bold mb-3">الجدول الزمني</h3>
                <div className="relative">
                  {/* الخط الرأسي */}
                  <div className="absolute right-4 top-0 bottom-0 w-0.5 bg-gray-200 dark:bg-gray-700" />
                  <div className="space-y-4">
                    {steps.map((s, i) => {
                      const isDone = s.status === 'done';
                      const isBlocked = s.status === 'blocked';
                      const isActive = s.status === 'in_progress';
                      return (
                        <div key={s.id} className="flex items-start gap-4 relative">
                          {/* نقطة على الخط */}
                          <div
                            className={`relative z-10 w-8 h-8 rounded-full flex items-center justify-center shrink-0 text-xs font-bold ${
                              isDone
                                ? 'bg-emerald-500 text-white'
                                : isBlocked
                                  ? 'bg-red-500 text-white'
                                  : isActive
                                    ? 'bg-blue-500 text-white animate-pulse'
                                    : 'bg-gray-300 dark:bg-gray-600 text-gray-600 dark:text-gray-300'
                            }`}
                          >
                            {isDone ? '✓' : i + 1}
                          </div>
                          {/* المحتوى */}
                          <div className={`flex-1 pb-4 ${isDone ? 'opacity-60' : ''}`}>
                            <p className={`text-sm font-medium ${isDone ? 'line-through text-gray-400' : ''}`}>{s.title}</p>
                            {s.description && <p className="text-xs text-gray-500 mt-0.5">{s.description}</p>}
                            <div className="flex items-center gap-3 mt-1 text-xs text-gray-400">
                              {s.assigneeName && <span>المسؤول: {s.assigneeName}</span>}
                              {s.dueDate && <span>الموعد: {s.dueDate}</span>}
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              </section>
            )}

            {/* الخطوات */}
            <section>
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-bold">
                  الخطوات ({doneCount}/{steps.length})
                </h3>
                <button
                  onClick={() => {
                    setEditingStep(null);
                    setStepTitle('');
                    setStepDesc('');
                    setStepDue('');
                    setStepStatus('pending');
                    setStepOpen(true);
                  }}
                  className="text-sm flex items-center gap-1 text-emerald-600 hover:underline"
                >
                  <Plus className="w-4 h-4" /> إضافة خطوة
                </button>
              </div>

              {steps.length === 0 ? (
                <p className="text-gray-400 text-sm">لا توجد خطوات بعد</p>
              ) : (
                <div className="space-y-2">
                  {steps.map((s) => {
                    const Icon = STEP_STATUS_ICON[s.status] || FileText;
                    return (
                      <div
                        key={s.id}
                        className={`flex items-center gap-3 p-3 rounded-lg border ${s.status === 'done' ? 'bg-emerald-50/50 dark:bg-emerald-950/10' : s.status === 'blocked' ? 'bg-red-50/50 dark:bg-red-950/10' : 'bg-gray-50 dark:bg-gray-800/50'}`}
                      >
                        <Icon className={`w-5 h-5 ${s.status === 'done' ? 'text-emerald-500' : s.status === 'blocked' ? 'text-red-500' : 'text-gray-400'}`} />
                        <div className="flex-1">
                          <p className={`text-sm font-medium ${s.status === 'done' ? 'line-through text-gray-400' : ''}`}>{s.title}</p>
                          {s.description && <p className="text-xs text-gray-500">{s.description}</p>}
                          {s.assigneeName && <p className="text-xs text-gray-400 mt-0.5">المسؤول: {s.assigneeName}</p>}
                        </div>
                        <StatusBadge status={s.status} />
                        <div className="flex gap-1">
                          <button onClick={() => openEditStep(s)} className="p-1 hover:bg-gray-200 rounded">
                            <Edit3 className="w-3.5 h-3.5" />
                          </button>
                          <button onClick={() => setDeleteStepId(s.id)} className="p-1 hover:bg-red-100 rounded text-red-500">
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>

            {/* تحديثات */}
            <section>
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-bold">آخر التحديثات</h3>
                <button onClick={() => setUpdateOpen(true)} className="text-sm flex items-center gap-1 text-emerald-600 hover:underline">
                  <Plus className="w-4 h-4" /> إضافة تحديث
                </button>
              </div>

              {updates.length === 0 ? (
                <p className="text-gray-400 text-sm">لا توجد تحديثات بعد</p>
              ) : (
                <div className="space-y-3">
                  {updates.map((u) => (
                    <div key={u.id} className="p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg border">
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-sm font-medium">{u.authorName}</span>
                        <span className="text-xs text-gray-400">
                          {new Date(u.createdAt).toLocaleDateString('ar-EG', {
                            year: 'numeric',
                            month: 'numeric',
                            day: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </span>
                      </div>
                      <p className="text-sm text-gray-600 dark:text-gray-400">{u.note}</p>
                      {u.progress != null && <p className="text-xs text-gray-500 mt-1">نسبة الإنجاز: {u.progress}%</p>}
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>
        </div>
      </div>

      {/* حوار تعديل المشروع */}
      {editOpen && (
        <DialogOverlay title="تعديل المشروع" onClose={() => setEditOpen(false)}>
          <div className="space-y-4 p-4">
            <label className="block">
              <span className="text-sm font-medium">اسم المشروع</span>
              <input className="input mt-1 w-full" value={editName} onChange={(e) => setEditName(e.target.value)} />
            </label>
            <label className="block">
              <span className="text-sm font-medium">الوصف</span>
              <textarea className="input mt-1 w-full" rows={2} value={editDesc} onChange={(e) => setEditDesc(e.target.value)} />
            </label>
            <div className="grid grid-cols-2 gap-4">
              <label className="block">
                <span className="text-sm font-medium">الإدارة</span>
                <select className="input mt-1 w-full" value={editDeptId} onChange={(e) => setEditDeptId(e.target.value)}>
                  {org?.departments.map((d) => (
                    <option key={d.id} value={d.id}>
                      {d.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block">
                <span className="text-sm font-medium">المسؤول</span>
                <select className="input mt-1 w-full" value={editOwnerId} onChange={(e) => setEditOwnerId(e.target.value)}>
                  {employees.map((emp) => (
                    <option key={emp.id} value={emp.id}>
                      {emp.fullNameAr}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            <div className="grid grid-cols-3 gap-4">
              <label className="block">
                <span className="text-sm font-medium">الحالة</span>
                <select
                  className="input mt-1 w-full"
                  value={editStatus}
                  onChange={(e) => setEditStatus(e.target.value as AssociationProjectDetail['project']['status'])}
                >
                  <option value="planned">مخطط</option>
                  <option value="active">نشط</option>
                  <option value="on_hold">متوقف</option>
                  <option value="completed">مكتمل</option>
                  <option value="cancelled">ملغى</option>
                </select>
              </label>
              <label className="block">
                <span className="text-sm font-medium">الأولوية</span>
                <select
                  className="input mt-1 w-full"
                  value={editPriority}
                  onChange={(e) => setEditPriority(e.target.value as AssociationProjectDetail['project']['priority'])}
                >
                  <option value="low">منخفضة</option>
                  <option value="medium">متوسطة</option>
                  <option value="high">عالية</option>
                  <option value="critical">حرجة</option>
                </select>
              </label>
              <label className="block">
                <span className="text-sm font-medium">نسبة الإنجاز</span>
                <input
                  type="number"
                  min={0}
                  max={100}
                  className="input mt-1 w-full"
                  value={editProgress}
                  onChange={(e) => setEditProgress(Number(e.target.value))}
                />
              </label>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <label className="block">
                <span className="text-sm font-medium">تاريخ البدء</span>
                <input type="date" className="input mt-1 w-full" value={editStart} onChange={(e) => setEditStart(e.target.value)} />
              </label>
              <label className="block">
                <span className="text-sm font-medium">الموعد النهائي</span>
                <input type="date" className="input mt-1 w-full" value={editEnd} onChange={(e) => setEditEnd(e.target.value)} />
              </label>
            </div>
            <button onClick={submitEdit} disabled={!editName.trim() || updateProject.isPending} className="btn-primary w-full">
              {updateProject.isPending ? 'جاري الحفظ...' : 'حفظ التعديلات'}
            </button>
          </div>
        </DialogOverlay>
      )}

      {/* حوار إضافة تحديث */}
      {updateOpen && (
        <DialogOverlay title="إضافة تحديث" onClose={() => setUpdateOpen(false)}>
          <div className="space-y-4 p-4">
            <label className="block">
              <span className="text-sm font-medium">ملاحظة التحديث</span>
              <textarea
                className="input mt-1 w-full"
                rows={3}
                value={updateNote}
                onChange={(e) => setUpdateNote(e.target.value)}
                placeholder="اكتب ملاحظة عن التحديث الذي تم..."
              />
            </label>
            <label className="block">
              <span className="text-sm font-medium">نسبة الإنجاز الحالية</span>
              <input
                type="number"
                min={0}
                max={100}
                className="input mt-1 w-full"
                value={updateProgress}
                onChange={(e) => setUpdateProgress(Number(e.target.value))}
              />
            </label>
            <button onClick={submitUpdate} disabled={!updateNote.trim() || addUpdate.isPending} className="btn-primary w-full">
              {addUpdate.isPending ? 'جاري الحفظ...' : 'حفظ التحديث'}
            </button>
          </div>
        </DialogOverlay>
      )}

      {/* حوار إضافة/تعديل خطوة */}
      {stepOpen && (
        <DialogOverlay
          title={editingStep ? 'تعديل خطوة' : 'إضافة خطوة جديدة'}
          onClose={() => {
            setStepOpen(false);
            setEditingStep(null);
          }}
        >
          <div className="space-y-4 p-4">
            <label className="block">
              <span className="text-sm font-medium">عنوان الخطوة</span>
              <input className="input mt-1 w-full" value={stepTitle} onChange={(e) => setStepTitle(e.target.value)} />
            </label>
            <label className="block">
              <span className="text-sm font-medium">الوصف</span>
              <textarea className="input mt-1 w-full" rows={2} value={stepDesc} onChange={(e) => setStepDesc(e.target.value)} />
            </label>
            <div className="grid grid-cols-2 gap-4">
              <label className="block">
                <span className="text-sm font-medium">الحالة</span>
                <select className="input mt-1 w-full" value={stepStatus} onChange={(e) => setStepStatus(e.target.value)}>
                  <option value="pending">قيد الانتظار</option>
                  <option value="in_progress">قيد التنفيذ</option>
                  <option value="done">مكتمل</option>
                  <option value="blocked">متوقف</option>
                </select>
              </label>
              <label className="block">
                <span className="text-sm font-medium">موعد التسليم</span>
                <input type="date" className="input mt-1 w-full" value={stepDue} onChange={(e) => setStepDue(e.target.value)} />
              </label>
            </div>
            <button onClick={submitStep} disabled={!stepTitle.trim() || upsertStep.isPending} className="btn-primary w-full">
              {upsertStep.isPending ? 'جاري الحفظ...' : 'حفظ الخطوة'}
            </button>
          </div>
        </DialogOverlay>
      )}

      {deleteStepId && (
        <ConfirmDialog
          open={Boolean(deleteStepId)}
          title="حذف الخطوة"
          message="هل أنت متأكد من حذف هذه الخطوة من المشروع؟"
          confirmLabel="حذف"
          cancelLabel="إلغاء"
          tone="danger"
          loading={deleteStep.isPending}
          onConfirm={() => handleDeleteStep(deleteStepId)}
          onCancel={() => setDeleteStepId(null)}
        />
      )}

      <ConfirmDialog
        open={!!deleteStepId}
        title="حذف الخطوة"
        message="هل أنت متأكد من حذف هذه الخطوة؟ لا يمكن التراجع عن هذا الإجراء."
        confirmLabel="حذف"
        tone="danger"
        loading={deleteStep.isPending}
        onConfirm={() => deleteStepId && handleDeleteStep(deleteStepId)}
        onCancel={() => setDeleteStepId(null)}
      />
    </>
  );
}
