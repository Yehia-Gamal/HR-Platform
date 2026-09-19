import { useState } from 'react';
import type { AssociationProjectDetail, AssociationProjectStep } from '@ahla/shared-contracts';
import { LED_COLORS } from './projectLedStatus';
import { useAddProjectUpdate, useUpsertProjectStep, useDeleteProjectStep } from './useAssociationProjects';
import { StatusBadge } from '../../ui/StatusBadge';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { format } from 'date-fns';
import { X, Plus, CheckCircle2, Clock, FileText, Ban, Edit3, Trash2 } from 'lucide-react';

interface Props {
  detail: AssociationProjectDetail;
  onClose: () => void;
  onRefresh: () => void;
}

const STEP_STATUS_ICON: Record<string, typeof CheckCircle2> = {
  done: CheckCircle2, in_progress: Clock, pending: FileText, blocked: Ban,
};

export function ProjectDetailPanel({ detail, onClose, onRefresh }: Props) {
  const { project, steps, updates } = detail;
  const led = project.ledStatus;
  const colors = LED_COLORS[led];

  const [updateOpen, setUpdateOpen] = useState(false);
  const [updateNote, setUpdateNote] = useState('');
  const [updateProgress, setUpdateProgress] = useState(project.progress);
  const [stepOpen, setStepOpen] = useState(false);
  const [editingStep, setEditingStep] = useState<AssociationProjectStep | null>(null);
  const [stepTitle, setStepTitle] = useState('');
  const [stepDesc, setStepDesc] = useState('');
  const [stepDue, setStepDue] = useState('');
  const [stepStatus, setStepStatus] = useState('pending');

  const addUpdate = useAddProjectUpdate();
  const upsertStep = useUpsertProjectStep();
  const deleteStep = useDeleteProjectStep();

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
    onRefresh();
  }

  const doneCount = steps.filter((s) => s.status === 'done').length;

  return (
    <>
      <div className="fixed inset-0 z-40 flex justify-end" onClick={onClose}>
        <div className="absolute inset-0 bg-black/40" />
        <div
          className="relative w-full max-w-2xl bg-white dark:bg-gray-900 shadow-2xl overflow-y-auto"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="sticky top-0 z-10 bg-white dark:bg-gray-900 border-b p-6">
            <div className="flex items-start justify-between">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <div className={`w-5 h-5 rounded-full ${colors.bg} ${colors.glow} ${led === 'active' ? 'animate-pulse' : ''}`} />
                  <span className="text-sm font-medium">{colors.label}</span>
                </div>
                <h2 className="text-2xl font-bold">{project.name}</h2>
                <p className="text-sm text-gray-500 font-mono">{project.code} — {project.departmentName}</p>
              </div>
              <button onClick={onClose} className="p-2 hover:bg-gray-100 rounded-lg">
                <X />
              </button>
            </div>
          </div>

          <div className="p-6 space-y-6">
            <section>
              <h3 className="font-bold mb-3">معلومات المشروع</h3>
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div><span className="text-gray-500">الحالة: </span><StatusBadge status={project.status} /></div>
                <div><span className="text-gray-500">الأولوية: </span><StatusBadge status={project.priority} /></div>
                <div><span className="text-gray-500">المسؤول: </span>{project.ownerName}</div>
                <div><span className="text-gray-500">نسبة الإنجاز: </span>{project.progress}%</div>
                {project.startDate && <div><span className="text-gray-500">تاريخ البدء: </span>{project.startDate}</div>}
                {project.targetEndDate && <div><span className="text-gray-500">الموعد النهائي: </span>{project.targetEndDate}</div>}
              </div>
              {project.description && <p className="mt-3 text-gray-600 dark:text-gray-400">{project.description}</p>}
            </section>

            <section>
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-bold">الخطوات ({doneCount}/{steps.length})</h3>
                <button
                  onClick={() => { setEditingStep(null); setStepTitle(''); setStepDesc(''); setStepDue(''); setStepStatus('pending'); setStepOpen(true); }}
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
                      <div key={s.id} className={`flex items-center gap-3 p-3 rounded-lg border ${s.status === 'done' ? 'bg-emerald-50/50 dark:bg-emerald-950/10' : s.status === 'blocked' ? 'bg-red-50/50 dark:bg-red-950/10' : 'bg-gray-50 dark:bg-gray-800/50'}`}>
                        <Icon className={`w-5 h-5 ${s.status === 'done' ? 'text-emerald-500' : s.status === 'blocked' ? 'text-red-500' : 'text-gray-400'}`} />
                        <div className="flex-1">
                          <p className={`text-sm font-medium ${s.status === 'done' ? 'line-through text-gray-400' : ''}`}>{s.title}</p>
                          {s.description && <p className="text-xs text-gray-500">{s.description}</p>}
                        </div>
                        <StatusBadge status={s.status} />
                        <div className="flex gap-1">
                          <button onClick={() => openEditStep(s)} className="p-1 hover:bg-gray-200 rounded"><Edit3 className="w-3.5 h-3.5" /></button>
                          <button onClick={() => handleDeleteStep(s.id)} className="p-1 hover:bg-red-100 rounded text-red-500"><Trash2 className="w-3.5 h-3.5" /></button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>

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
                        <span className="text-xs text-gray-400">{format(new Date(u.createdAt), 'yyyy/MM/dd HH:mm')}</span>
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

      {updateOpen && (
        <DialogOverlay title="إضافة تحديث" onClose={() => setUpdateOpen(false)}>
          <div className="space-y-4 p-4">
            <label className="block">
              <span className="text-sm font-medium">ملاحظة التحديث</span>
              <textarea className="input mt-1 w-full" rows={3} value={updateNote} onChange={(e) => setUpdateNote(e.target.value)} />
            </label>
            <label className="block">
              <span className="text-sm font-medium">نسبة الإنجاز الحالية</span>
              <input type="number" min={0} max={100} className="input mt-1 w-full" value={updateProgress} onChange={(e) => setUpdateProgress(Number(e.target.value))} />
            </label>
            <button onClick={submitUpdate} disabled={!updateNote.trim() || addUpdate.isPending} className="btn-primary w-full">
              {addUpdate.isPending ? 'جاري الحفظ...' : 'حفظ التحديث'}
            </button>
          </div>
        </DialogOverlay>
      )}

      {stepOpen && (
        <DialogOverlay title={editingStep ? 'تعديل خطوة' : 'إضافة خطوة جديدة'} onClose={() => { setStepOpen(false); setEditingStep(null); }}>
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
    </>
  );
}
