import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import type { AssociationProjectDetail, AssociationProjectStep } from '@ahla/shared-contracts';
import {
  AlertTriangle,
  Ban,
  CalendarClock,
  Check,
  CheckCircle2,
  Circle,
  Loader2,
  MessageSquarePlus,
  Pencil,
  Plus,
  Send,
  Trash2,
  X,
} from 'lucide-react';
import { ConfirmDialog } from '../../ui/ConfirmDialog';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useOrganizationLookups } from '../employees/useOrganizationLookups';
import {
  useAssociationProjectDetail,
  useApproveProject,
  useDeleteAssociationProject,
  useDeleteProjectStep,
  useRejectProject,
  useSetProjectStepStatus,
  useSubmitProjectForApproval,
  useUpsertProjectStep,
} from './useAssociationProjects';
import { ProjectLed } from './ProjectLed';
import { ProjectFormDialog } from './ProjectFormDialog';
import { QuickUpdateDialog } from './QuickUpdateDialog';
import {
  APPROVAL_LABELS,
  LED_META,
  PRIORITY_LABELS,
  STATUS_LABELS,
  STEP_STATUS_LABELS,
  activityDays,
  daysAgoLabel,
  formatDate,
} from './projectLedStatus';

interface Props {
  projectId: string;
  isFullAccess: boolean;
  myDepartmentId: string | null;
  onClose: () => void;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

export function ProjectDetailPanel({ projectId, isFullAccess, myDepartmentId, onClose }: Props) {
  const { data, isLoading, error, refetch } = useAssociationProjectDetail(projectId);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // الحوارات الداخلية تعالج Escape بنفسها — لا نغلق اللوحة من تحتها.
      if (e.key === 'Escape' && !document.querySelector('[role="dialog"][aria-modal="true"]')) onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return createPortal(
    <div className="fixed inset-0 z-[90] flex justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-[rgb(3_10_23/50%)] backdrop-blur-[2px]" />
      <aside
        className="relative flex h-full w-full max-w-2xl flex-col overflow-y-auto bg-[var(--app-bg)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        aria-label="تفاصيل المشروع"
      >
        {isLoading ? (
          <div className="grid flex-1 place-items-center">
            <Loader2 className="size-8 animate-spin text-[var(--brand-primary)]" aria-label="جارٍ التحميل" />
          </div>
        ) : error || !data ? (
          <div className="p-6">
            <ErrorState description={safeErrorMessage(error)} onRetry={() => void refetch()} />
            <button className="btn-secondary mt-4 w-full" onClick={onClose}>
              إغلاق
            </button>
          </div>
        ) : (
          <DetailContent detail={data} isFullAccess={isFullAccess} myDepartmentId={myDepartmentId} onClose={onClose} />
        )}
      </aside>
    </div>,
    document.body,
  );
}

function DetailContent({
  detail,
  isFullAccess,
  myDepartmentId,
  onClose,
}: {
  detail: AssociationProjectDetail;
  isFullAccess: boolean;
  myDepartmentId: string | null;
  onClose: () => void;
}) {
  const { project: p, steps, updates } = detail;
  // قبل نشر 0553 لا تصل الصلاحيات — نشتقها بنفس قاعدة الخادم.
  const perms = detail.permissions ?? {
    canManage: isFullAccess || p.canManage,
    canApprove: isFullAccess && p.approvalStatus === 'pending_approval',
    canEdit: isFullAccess || p.approvalStatus === 'draft' || p.approvalStatus === 'rejected',
    canSubmit: p.approvalStatus === 'draft' || p.approvalStatus === 'rejected',
    canUpdate: p.approvalStatus === 'approved',
    canDelete: isFullAccess || p.approvalStatus === 'draft' || p.approvalStatus === 'rejected',
  };
  const led = p.ledStatus;
  const meta = LED_META[led];
  const days = activityDays(p);

  const approve = useApproveProject();
  const reject = useRejectProject();
  const submit = useSubmitProjectForApproval();
  const deleteProject = useDeleteAssociationProject();
  const setStepStatus = useSetProjectStepStatus();
  const deleteStep = useDeleteProjectStep();

  const [editOpen, setEditOpen] = useState(false);
  const [updateOpen, setUpdateOpen] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [stepDialog, setStepDialog] = useState<{ step: AssociationProjectStep | null } | null>(null);
  const [deleteStepId, setDeleteStepId] = useState<string | null>(null);

  const doneSteps = steps.filter((s) => s.status === 'done').length;
  const remainingSteps = steps.length - doneSteps;
  const currentStep = steps.find((s) => s.status !== 'done');

  return (
    <>
      {/* الرأس */}
      <header className="sticky top-0 z-10 border-b border-[var(--border)] bg-[var(--surface)] p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <ProjectLed status={led} large />
              <span className="text-sm font-black" style={{ color: meta.tone }}>
                {meta.label}
              </span>
              <span className="rounded-full bg-[var(--surface-muted)] px-2 py-0.5 text-xs font-bold">{APPROVAL_LABELS[p.approvalStatus]}</span>
            </div>
            <h2 className="text-2xl leading-tight font-black">{p.name}</h2>
            <p className="mt-1 text-sm text-[var(--text-muted)]">
              <span dir="ltr" className="font-mono">
                {p.code}
              </span>{' '}
              • {p.departmentName} • المسؤول: {p.ownerName}
            </p>
          </div>
          <div className="flex shrink-0 gap-1">
            {perms.canEdit && (
              <button className="icon-button" onClick={() => setEditOpen(true)} aria-label="تعديل بيانات المشروع" title="تعديل">
                <Pencil className="size-4" />
              </button>
            )}
            {perms.canDelete && (
              <button className="icon-button text-[var(--danger)]" onClick={() => setDeleteOpen(true)} aria-label="حذف المشروع" title="حذف">
                <Trash2 className="size-4" />
              </button>
            )}
            <button className="icon-button" onClick={onClose} aria-label="إغلاق">
              <X className="size-5" />
            </button>
          </div>
        </div>
      </header>

      <div className="space-y-5 p-5">
        {/* شريط الحالة: ماذا يحدث ومن يجب أن يتحرك */}
        <StatusBanner
          led={led}
          days={days}
          isFullAccess={isFullAccess}
          rejectionReason={p.rejectionReason}
          actions={
            <>
              {perms.canApprove && (
                <>
                  <button className="btn-primary btn-sm" disabled={approve.isPending} onClick={() => approve.mutate(p.id)}>
                    <Check className="size-4" aria-hidden="true" /> اعتماد المشروع
                  </button>
                  <button className="btn-danger btn-sm" onClick={() => setRejectOpen(true)}>
                    <X className="size-4" aria-hidden="true" /> إعادة للإدارة
                  </button>
                </>
              )}
              {perms.canSubmit && perms.canManage && (
                <button className="btn-primary btn-sm" disabled={submit.isPending} onClick={() => submit.mutate(p.id)}>
                  <Send className="size-4" aria-hidden="true" /> إرسال للاعتماد
                </button>
              )}
              {perms.canUpdate && perms.canManage && (led === 'critical' || led === 'halted') && (
                <button className="btn-primary btn-sm" onClick={() => setUpdateOpen(true)}>
                  <MessageSquarePlus className="size-4" aria-hidden="true" /> تسجيل تحديث
                </button>
              )}
            </>
          }
        />

        {/* الملخص */}
        <section className="card p-5">
          <div className="flex items-end justify-between gap-4">
            <div>
              <p className="text-xs font-bold text-[var(--text-muted)]">نسبة الإنجاز</p>
              <p className="tabular text-4xl font-black">{Math.round(p.progress)}%</p>
            </div>
            <div className="text-end text-sm">
              <p className="font-bold">{STATUS_LABELS[p.status]}</p>
              <p className="text-xs text-[var(--text-muted)]">آخر نشاط: {daysAgoLabel(days)}</p>
            </div>
          </div>
          <div className="mt-3 h-3 overflow-hidden rounded-full bg-[var(--surface-muted)]">
            <div className="h-full rounded-full transition-all duration-700" style={{ width: `${p.progress}%`, background: meta.tone }} />
          </div>
          {steps.length > 0 && <p className="mt-2 text-xs text-[var(--text-muted)]">تُحسب تلقائياً من الخطوات المكتملة.</p>}

          <dl className="mt-4 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <Stat label="تم إنجازه" value={`${doneSteps} خطوة`} tone="var(--success)" />
            <Stat label="متبقي" value={`${remainingSteps} خطوة`} />
            <Stat label="الأولوية" value={PRIORITY_LABELS[p.priority]} />
            <Stat
              label="الموعد المستهدف"
              value={formatDate(p.targetEndDate)}
              tone={p.isOverdue ? 'var(--danger)' : undefined}
              note={p.isOverdue ? 'تجاوز الموعد' : undefined}
            />
          </dl>

          {currentStep && p.status !== 'completed' && (
            <div className="mt-4 rounded-xl bg-[var(--surface-subtle)] p-3 text-sm">
              <span className="text-[var(--text-muted)]">المرحلة الحالية: </span>
              <span className="font-black">{currentStep.title}</span>
            </div>
          )}
          {steps.length > 0 && remainingSteps === 0 && p.status !== 'completed' && perms.canUpdate && perms.canManage && (
            <div className="mt-4 flex items-center justify-between gap-3 rounded-xl bg-[var(--success-soft)] p-3 text-sm">
              <span className="font-bold text-[var(--success)]">كل الخطوات تمت — أعلن اكتمال المشروع.</span>
              <button className="btn-primary btn-sm" onClick={() => setUpdateOpen(true)}>
                تسجيل الاكتمال
              </button>
            </div>
          )}
          {p.description && <p className="mt-4 text-sm leading-7 text-[var(--text-secondary)]">{p.description}</p>}
        </section>

        {/* خطوات التنفيذ والمهام */}
        <section className="card p-5">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <h3 className="text-lg font-black">خطوات التنفيذ والمهام</h3>
              <p className="text-xs text-[var(--text-muted)]">
                تم {doneSteps} • متبقي {remainingSteps}
                {perms.canManage ? ' — علّم الخطوة عند إنجازها ليتحدّث المشروع تلقائياً' : ''}
              </p>
            </div>
            {perms.canManage && (
              <button className="btn-secondary btn-sm" onClick={() => setStepDialog({ step: null })}>
                <Plus className="size-4" aria-hidden="true" /> خطوة
              </button>
            )}
          </div>

          {steps.length === 0 ? (
            <p className="rounded-xl border border-dashed border-[var(--border-strong)] p-6 text-center text-sm text-[var(--text-muted)]">
              لم تُضف خطوات بعد. قسّم المشروع إلى خطوات واضحة (مثل: دراسة، تعاقد، تنفيذ، تسليم) ليظهر تقدمه تلقائياً.
            </p>
          ) : (
            <ol className="space-y-2">
              {steps.map((s, i) => {
                const overdue = s.status !== 'done' && s.dueDate && s.dueDate < todayIso();
                const isCurrent = s.id === currentStep?.id;
                return (
                  <li
                    key={s.id}
                    className={`flex items-start gap-3 rounded-xl border p-3 ${
                      isCurrent ? 'border-[var(--brand-primary)] bg-[var(--brand-primary-soft)]' : 'border-[var(--border)] bg-[var(--surface)]'
                    }`}
                  >
                    <StepToggle
                      step={s}
                      index={i}
                      disabled={!perms.canManage || setStepStatus.isPending}
                      onToggle={() => setStepStatus.mutate({ stepId: s.id, status: s.status === 'done' ? 'pending' : 'done' })}
                    />
                    <div className="min-w-0 flex-1">
                      <p className={`font-bold ${s.status === 'done' ? 'text-[var(--text-muted)] line-through' : ''}`}>{s.title}</p>
                      {s.description && <p className="mt-0.5 text-xs text-[var(--text-muted)]">{s.description}</p>}
                      <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[var(--text-muted)]">
                        {s.assigneeName && <span>المكلَّف: {s.assigneeName}</span>}
                        {s.dueDate && (
                          <span className={overdue ? 'font-bold text-[var(--danger)]' : ''}>
                            <CalendarClock className="inline size-3" aria-hidden="true" /> {formatDate(s.dueDate)}
                            {overdue ? ' — متأخرة' : ''}
                          </span>
                        )}
                        {s.status === 'done' && s.completedAt && <span className="text-[var(--success)]">تمت {formatDate(s.completedAt)}</span>}
                      </div>
                    </div>
                    {perms.canManage ? (
                      <div className="flex shrink-0 items-center gap-1">
                        <select
                          className="input !w-auto !px-2 !py-1 text-xs"
                          value={s.status}
                          onChange={(e) => setStepStatus.mutate({ stepId: s.id, status: e.target.value })}
                          aria-label={`حالة الخطوة ${s.title}`}
                        >
                          {Object.entries(STEP_STATUS_LABELS).map(([k, v]) => (
                            <option key={k} value={k}>
                              {v}
                            </option>
                          ))}
                        </select>
                        <button className="icon-button !size-8" onClick={() => setStepDialog({ step: s })} aria-label={`تعديل الخطوة ${s.title}`}>
                          <Pencil className="size-3.5" />
                        </button>
                        <button className="icon-button !size-8 text-[var(--danger)]" onClick={() => setDeleteStepId(s.id)} aria-label={`حذف الخطوة ${s.title}`}>
                          <Trash2 className="size-3.5" />
                        </button>
                      </div>
                    ) : (
                      <span className="shrink-0 rounded-full bg-[var(--surface-muted)] px-2 py-0.5 text-xs font-bold">{STEP_STATUS_LABELS[s.status]}</span>
                    )}
                  </li>
                );
              })}
            </ol>
          )}
        </section>

        {/* سجل التحديثات */}
        <section className="card p-5">
          <div className="mb-4 flex items-center justify-between gap-3">
            <h3 className="text-lg font-black">سجل التحديثات</h3>
            {perms.canUpdate && perms.canManage && (
              <button className="btn-secondary btn-sm" onClick={() => setUpdateOpen(true)}>
                <MessageSquarePlus className="size-4" aria-hidden="true" /> تحديث
              </button>
            )}
          </div>
          {updates.length === 0 ? (
            <p className="text-sm text-[var(--text-muted)]">
              {p.approvalStatus === 'approved' ? 'لا توجد تحديثات بعد.' : 'تبدأ التحديثات بعد اعتماد المشروع.'}
            </p>
          ) : (
            <ol className="relative space-y-4 border-s-2 border-[var(--border)] ps-4">
              {updates.map((u) => (
                <li key={u.id} className="relative">
                  <span className="absolute -start-[1.4rem] top-1.5 size-2.5 rounded-full bg-[var(--brand-primary)]" aria-hidden="true" />
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="text-sm font-bold">{u.authorName}</span>
                    <time className="text-xs text-[var(--text-muted)]" dateTime={u.createdAt}>
                      {new Date(u.createdAt).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' })}
                    </time>
                  </div>
                  <p className="mt-1 text-sm leading-7 whitespace-pre-line">{u.note}</p>
                  {u.statusChange && (
                    <span className="mt-1 inline-block rounded-full bg-[var(--surface-muted)] px-2 py-0.5 text-xs font-bold">
                      الحالة ← {STATUS_LABELS[u.statusChange as keyof typeof STATUS_LABELS] ?? u.statusChange}
                    </span>
                  )}
                </li>
              ))}
            </ol>
          )}
        </section>

        <p className="text-center text-xs text-[var(--text-muted)]">
          {p.approvedAt ? `اعتُمد ${formatDate(p.approvedAt)}` : 'لم يُعتمد بعد'}
          {p.startDate ? ` • البدء ${formatDate(p.startDate)}` : ''}
        </p>
      </div>

      {/* الحوارات */}
      {editOpen && <ProjectFormDialog project={p} isFullAccess={isFullAccess} myDepartmentId={myDepartmentId} onClose={() => setEditOpen(false)} />}
      {updateOpen && <QuickUpdateDialog project={p} onClose={() => setUpdateOpen(false)} />}
      {stepDialog && <StepDialog projectId={p.id} step={stepDialog.step} onClose={() => setStepDialog(null)} />}
      {rejectOpen && (
        <RejectDialog
          projectName={p.name}
          pending={reject.isPending}
          onCancel={() => setRejectOpen(false)}
          onConfirm={async (reason) => {
            await reject.mutateAsync({ projectId: p.id, reason });
            setRejectOpen(false);
          }}
        />
      )}
      <ConfirmDialog
        open={Boolean(deleteStepId)}
        title="حذف الخطوة"
        message="ستُحذف الخطوة نهائياً ويُعاد حساب نسبة الإنجاز."
        confirmLabel="حذف"
        tone="danger"
        loading={deleteStep.isPending}
        onConfirm={async () => {
          if (deleteStepId) await deleteStep.mutateAsync(deleteStepId);
          setDeleteStepId(null);
        }}
        onCancel={() => setDeleteStepId(null)}
      />
      <ConfirmDialog
        open={deleteOpen}
        title="حذف المشروع"
        message={`سيُحذف مشروع «${p.name}» بكل خطواته وتحديثاته نهائياً.`}
        confirmLabel="حذف المشروع"
        tone="danger"
        loading={deleteProject.isPending}
        onConfirm={async () => {
          await deleteProject.mutateAsync(p.id);
          setDeleteOpen(false);
          onClose();
        }}
        onCancel={() => setDeleteOpen(false)}
      />
    </>
  );
}

function Stat({ label, value, tone, note }: { label: string; value: string; tone?: string; note?: string }) {
  return (
    <div className="rounded-xl bg-[var(--surface-subtle)] p-3">
      <dt className="text-xs text-[var(--text-muted)]">{label}</dt>
      <dd className="mt-0.5 font-black" style={tone ? { color: tone } : undefined}>
        {value}
      </dd>
      {note && <dd className="text-xs font-bold" style={{ color: tone }}>{note}</dd>}
    </div>
  );
}

function StepToggle({ step, index, disabled, onToggle }: { step: AssociationProjectStep; index: number; disabled: boolean; onToggle: () => void }) {
  const done = step.status === 'done';
  const Icon = done ? CheckCircle2 : step.status === 'blocked' ? Ban : Circle;
  const color = done ? 'var(--success)' : step.status === 'blocked' ? 'var(--danger)' : step.status === 'in_progress' ? 'var(--brand-primary)' : 'var(--text-disabled)';
  return (
    <button
      type="button"
      onClick={onToggle}
      disabled={disabled}
      className="relative mt-0.5 grid size-7 shrink-0 place-items-center rounded-full disabled:cursor-default"
      aria-label={done ? `إلغاء إنجاز الخطوة ${index + 1}` : `تعليم الخطوة ${index + 1} كمنجزة`}
      aria-pressed={done}
      title={disabled ? STEP_STATUS_LABELS[step.status] : done ? 'إلغاء الإنجاز' : 'تعليم كمنجزة'}
    >
      <Icon className="size-6" style={{ color }} aria-hidden="true" />
      {!done && step.status !== 'blocked' && <span className="absolute text-[0.6rem] font-black" style={{ color }}>{index + 1}</span>}
    </button>
  );
}

function StatusBanner({
  led,
  days,
  isFullAccess,
  rejectionReason,
  actions,
}: {
  led: AssociationProjectDetail['project']['ledStatus'];
  days: number | null;
  isFullAccess: boolean;
  rejectionReason: string | null;
  actions: React.ReactNode;
}) {
  const since = daysAgoLabel(days);
  const content: Record<typeof led, { text: string; bg: string; fg: string } | null> = {
    active: null,
    completed: null,
    stale: null,
    critical: {
      text: isFullAccess
        ? `لا يوجد أي تحديث على المشروع (آخر نشاط ${since}). يحتاج تدخلك لمعرفة سبب التوقف.`
        : `المشروع بلا أي تحديث (آخر نشاط ${since}) وتم تنبيه المدير التنفيذي. سجّل تحديثاً أو حدّث الخطوات.`,
      bg: 'var(--danger-soft)',
      fg: 'var(--danger)',
    },
    halted: {
      text: `المشروع متوقف أو لم يُحدَّث منذ فترة (آخر نشاط ${since}).`,
      bg: 'var(--danger-soft)',
      fg: 'var(--danger)',
    },
    pending: {
      text: isFullAccess ? 'أرسلت الإدارة هذا المشروع وينتظر قرارك.' : 'بانتظار اعتماد المدير التنفيذي. يمكنك إضافة الخطوات من الآن.',
      bg: 'var(--warning-soft)',
      fg: 'var(--warning)',
    },
    rejected: {
      text: `أُعيد المشروع للتعديل${rejectionReason ? `: «${rejectionReason}»` : '.'} عدّل البيانات ثم أعد الإرسال.`,
      bg: 'var(--danger-soft)',
      fg: 'var(--danger)',
    },
    draft: {
      text: 'مسودة لم تُرسل بعد. أرسلها للمدير التنفيذي ليعتمدها وتظهر على اللوحة.',
      bg: 'var(--surface-muted)',
      fg: 'var(--text-secondary)',
    },
  };
  const c = content[led];
  if (!c) return null;
  return (
    <div className="flex flex-col gap-3 rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between" style={{ background: c.bg }} role="status">
      <p className="flex items-start gap-2 text-sm leading-7 font-bold" style={{ color: c.fg }}>
        <AlertTriangle className="mt-1 size-4 shrink-0" aria-hidden="true" />
        {c.text}
      </p>
      <div className="flex shrink-0 flex-wrap gap-2">{actions}</div>
    </div>
  );
}

function StepDialog({ projectId, step, onClose }: { projectId: string; step: AssociationProjectStep | null; onClose: () => void }) {
  const upsert = useUpsertProjectStep();
  const { data: org } = useOrganizationLookups();
  const [title, setTitle] = useState(step?.title ?? '');
  const [description, setDescription] = useState(step?.description ?? '');
  const [status, setStatus] = useState<string>(step?.status ?? 'pending');
  const [dueDate, setDueDate] = useState(step?.dueDate ?? '');
  const [assigneeId, setAssigneeId] = useState(step?.assigneeId ?? '');

  async function save() {
    if (!title.trim()) return;
    try {
      await upsert.mutateAsync({
        projectId,
        stepId: step?.id,
        title: title.trim(),
        description: description.trim(),
        sortOrder: step?.sortOrder ?? null,
        status,
        dueDate,
        assigneeId: assigneeId || null,
      });
      onClose();
    } catch {
      // الخطأ يظهر كتنبيه عام
    }
  }

  return (
    <DialogOverlay title={step ? 'تعديل الخطوة' : 'خطوة / مهمة جديدة'} onClose={onClose} maxWidth="max-w-lg">
      <div className="space-y-4">
        <label className="block">
          <span className="text-sm font-bold">عنوان الخطوة *</span>
          <input className="input mt-1" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="مثال: التعاقد مع المورد" />
        </label>
        <label className="block">
          <span className="text-sm font-bold">تفاصيل (اختياري)</span>
          <textarea className="input mt-1" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block">
            <span className="text-sm font-bold">الحالة</span>
            <select className="input mt-1" value={status} onChange={(e) => setStatus(e.target.value)}>
              {Object.entries(STEP_STATUS_LABELS).map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="text-sm font-bold">موعد الإنجاز</span>
            <input type="date" className="input mt-1" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </label>
        </div>
        <label className="block">
          <span className="text-sm font-bold">المكلَّف بالتنفيذ</span>
          <select className="input mt-1" value={assigneeId} onChange={(e) => setAssigneeId(e.target.value)}>
            <option value="">— بدون —</option>
            {org?.managers.map((m) => (
              <option key={m.id} value={m.id}>
                {m.label}
              </option>
            ))}
          </select>
        </label>
        <button className="btn-primary w-full" disabled={!title.trim() || upsert.isPending} onClick={save}>
          {upsert.isPending && <Loader2 className="size-4 animate-spin" aria-hidden="true" />}
          حفظ الخطوة
        </button>
      </div>
    </DialogOverlay>
  );
}

export function RejectDialog({
  projectName,
  pending,
  onCancel,
  onConfirm,
}: {
  projectName: string;
  pending: boolean;
  onCancel: () => void;
  onConfirm: (reason: string) => void | Promise<void>;
}) {
  const [reason, setReason] = useState('');
  return (
    <DialogOverlay title="إعادة المشروع للإدارة" onClose={onCancel} maxWidth="max-w-md">
      <div className="space-y-4">
        <p className="text-sm leading-7">
          سيُعاد مشروع <strong>«{projectName}»</strong> للإدارة لتعديله وإعادة إرساله. اكتب لهم ما المطلوب تعديله:
        </p>
        <textarea className="input" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: حدّدوا الميزانية المطلوبة والجدول الزمني" />
        <div className="flex justify-end gap-2">
          <button className="btn-secondary" onClick={onCancel}>
            إلغاء
          </button>
          <button className="btn-danger" disabled={pending || !reason.trim()} onClick={() => void onConfirm(reason.trim())}>
            {pending ? 'جارٍ الإرسال…' : 'إعادة للإدارة'}
          </button>
        </div>
      </div>
    </DialogOverlay>
  );
}
