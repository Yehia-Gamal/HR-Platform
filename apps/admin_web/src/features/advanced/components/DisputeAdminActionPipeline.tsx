import { useState } from 'react';
import { Briefcase, ShieldCheck, ClipboardCheck, AlertTriangle } from 'lucide-react';
import type { DisputeCase, RunFn } from './DisputeTypes';
import type { DisputeCommands } from '../useAdvancedOperations';
import { StatusBadge } from '../../../ui/StatusBadge';
import { formatDate } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: DisputeCommands;
  run: RunFn;
}

export function DisputeAdminActionPipeline({ selected, commands, run }: Props) {
  const [proposedAction, setProposedAction] = useState('');
  const [proposedActionDetail, setProposedActionDetail] = useState('');
  const [executionNotes, setExecutionNotes] = useState('');

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">مسار الإجراء الإداري</h3>
      <p className="muted mt-1 text-sm">ثلاث خطوات: اقتراح المقرر → قرار المدير التنفيذي → تنفيذ الموارد البشرية.</p>

      <div className="mt-5 grid gap-4 md:grid-cols-3">
        <div
          className={`rounded-2xl border p-4 ${selected.proposedAdminAction ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}
        >
          <div className="flex items-center gap-2">
            <Briefcase className={`size-5 ${selected.proposedAdminAction ? 'text-[var(--success)]' : 'text-[var(--muted)]'}`} aria-hidden="true" />
            <strong className="text-sm">١. اقتراح المقرر</strong>
          </div>
          <StatusBadge value={selected.proposedAdminAction ? 'completed' : 'pending'} />
          {selected.proposedAdminAction ? (
            <p className="mt-2 text-sm leading-7">{selected.proposedAdminAction}</p>
          ) : (
            <p className="muted mt-2 text-xs">لم يُقترح إجراء بعد</p>
          )}
        </div>

        <div
          className={`rounded-2xl border p-4 ${selected.executiveDecision === 'approved' ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : selected.executiveDecision === 'rejected' ? 'border-[var(--danger)]/30 bg-[var(--danger-soft)]' : selected.executiveDecision === 'modified' ? 'border-[var(--warning)]/30 bg-[var(--warning-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}
        >
          <div className="flex items-center gap-2">
            <ShieldCheck
              className={`size-5 ${selected.executiveDecision ? (selected.executiveDecision === 'approved' ? 'text-[var(--success)]' : selected.executiveDecision === 'rejected' ? 'text-[var(--danger)]' : 'text-[var(--warning)]') : 'text-[var(--muted)]'}`}
              aria-hidden="true"
            />
            <strong className="text-sm">٢. قرار المدير التنفيذي</strong>
          </div>
          {selected.executiveDecision ? (
            <>
              <StatusBadge
                value={selected.executiveDecision === 'approved' ? 'approved' : selected.executiveDecision === 'rejected' ? 'rejected' : 'modified'}
              />
              {selected.executiveDecisionReason ? <p className="mt-2 text-sm leading-7">{selected.executiveDecisionReason}</p> : null}
              {selected.approvedAdminAction && selected.executiveDecision === 'modified' ? (
                <p className="mt-2 rounded-xl bg-[var(--surface)] p-3 text-sm leading-7">
                  <strong className="block text-xs">الإجراء المعدّل:</strong>
                  {selected.approvedAdminAction}
                </p>
              ) : null}
            </>
          ) : (
            <p className="muted mt-2 text-xs">بانتظار قرار المدير التنفيذي (عبر التطبيق)</p>
          )}
        </div>

        <div
          className={`rounded-2xl border p-4 ${selected.executedAt ? 'border-[var(--success)]/30 bg-[var(--success-soft)]' : 'border-[var(--border)] bg-[var(--surface-muted)]'}`}
        >
          <div className="flex items-center gap-2">
            <ClipboardCheck className={`size-5 ${selected.executedAt ? 'text-[var(--success)]' : 'text-[var(--muted)]'}`} aria-hidden="true" />
            <strong className="text-sm">٣. تنفيذ الموارد البشرية</strong>
          </div>
          <StatusBadge value={selected.executedAt ? 'completed' : 'pending'} />
          {selected.executedAt ? (
            <>
              <p className="mt-2 text-sm leading-7">تم التنفيذ {formatDate(selected.executedAt)}</p>
              {selected.executionNotes ? <p className="mt-2 rounded-xl bg-[var(--surface)] p-3 text-sm leading-7">{selected.executionNotes}</p> : null}
            </>
          ) : (
            <p className="muted mt-2 text-xs">لم يُنفذ بعد</p>
          )}
        </div>
      </div>

      {!selected.proposedAdminAction ? (
        <div className="mt-5 rounded-2xl border border-[var(--border)] p-4">
          <h4 className="font-bold">اقتراح الإجراء الإداري</h4>
          <p className="muted mt-1 text-xs">بصفتك مقرر اللجنة، اقترح الإجراء الإداري المناسب بناءً على قرار اللجنة.</p>
          <div className="mt-3 grid gap-3 sm:grid-cols-[200px_1fr_auto]">
            <select className="input" aria-label="نوع الإجراء" value={proposedAction} onChange={(event) => setProposedAction(event.target.value)}>
              <option value="">اختر نوع الإجراء</option>
              <option value="verbal_warning">إنذار شفهي</option>
              <option value="written_warning">إنذار كتابي</option>
              <option value="final_warning">إنذار نهائي</option>
              <option value="salary_deduction">خصم من الراتب</option>
              <option value="suspension">إيقاف عن العمل</option>
              <option value="demotion">تخفيض الدرجة</option>
              <option value="termination">إنهاء الخدمة</option>
              <option value="transfer">نقل</option>
              <option value="training_requirement">تدريب إلزامي</option>
              <option value="no_action">لا إجراء</option>
            </select>
            <textarea
              className="input min-h-20"
              placeholder="تفاصيل الإجراء المقترح (3 أحرف على الأقل)…"
              value={proposedActionDetail}
              onChange={(event) => setProposedActionDetail(event.target.value)}
              aria-label="تفاصيل الإجراء"
            />
            <button
              className="btn-primary self-end"
              disabled={!proposedAction || proposedActionDetail.trim().length < 3 || commands.proposeAdminAction.isPending}
              onClick={() =>
                void run(async () => {
                  await commands.proposeAdminAction.mutateAsync({
                    p_case_id: selected.id,
                    p_proposed_action: proposedAction,
                    p_detail: proposedActionDetail.trim(),
                  });
                  setProposedAction('');
                  setProposedActionDetail('');
                }, 'تم إرسال الاقتراح للمدير التنفيذي للمراجعة.')
              }
            >
              <Briefcase className="size-4" aria-hidden="true" />
              إرسال الاقتراح
            </button>
          </div>
        </div>
      ) : null}

      {selected.executiveDecision === 'approved' && !selected.executedAt ? (
        <div className="mt-5 rounded-2xl border border-[var(--success)]/30 bg-[var(--success-soft)] p-4">
          <h4 className="font-bold text-[var(--success)]">تنفيذ الإجراء الإداري المعتمد</h4>
          <p className="muted mt-1 text-xs">الإجراء المعتمد: {selected.approvedAdminAction ?? selected.proposedAdminAction}</p>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row">
            <textarea
              className="input min-h-20 flex-1"
              placeholder="ملاحظات التنفيذ وتفاصيل ما تم…"
              value={executionNotes}
              onChange={(event) => setExecutionNotes(event.target.value)}
              aria-label="ملاحظات التنفيذ"
            />
            <button
              className="btn-primary self-end"
              disabled={executionNotes.trim().length < 5 || commands.executeAdminAction.isPending}
              onClick={() =>
                void run(async () => {
                  await commands.executeAdminAction.mutateAsync({ p_case_id: selected.id, p_notes: executionNotes.trim() });
                  setExecutionNotes('');
                }, 'تم تنفيذ الإجراء الإداري وتسجيله.')
              }
            >
              <ClipboardCheck className="size-4" aria-hidden="true" />
              تأكيد التنفيذ
            </button>
          </div>
        </div>
      ) : null}

      {selected.executiveDecision === 'modified' && !selected.executedAt ? (
        <div className="mt-5 rounded-2xl border border-[var(--warning)]/30 bg-[var(--warning-soft)] p-4">
          <h4 className="font-bold text-[var(--warning)]">تنفيذ الإجراء الإداري المعدّل</h4>
          <p className="muted mt-1 text-xs">الإجراء المعدّل: {selected.approvedAdminAction}</p>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row">
            <textarea
              className="input min-h-20 flex-1"
              placeholder="ملاحظات التنفيذ وتفاصيل ما تم…"
              value={executionNotes}
              onChange={(event) => setExecutionNotes(event.target.value)}
              aria-label="ملاحظات التنفيذ"
            />
            <button
              className="btn-primary self-end"
              disabled={executionNotes.trim().length < 5 || commands.executeAdminAction.isPending}
              onClick={() =>
                void run(async () => {
                  await commands.executeAdminAction.mutateAsync({ p_case_id: selected.id, p_notes: executionNotes.trim() });
                  setExecutionNotes('');
                }, 'تم تنفيذ الإجراء الإداري المعدّل وتسجيله.')
              }
            >
              <ClipboardCheck className="size-4" aria-hidden="true" />
              تأكيد التنفيذ
            </button>
          </div>
        </div>
      ) : null}

      {selected.executiveDecision === 'rejected' ? (
        <div className="mt-5 rounded-2xl border border-[var(--danger)]/30 bg-[var(--danger-soft)] p-4">
          <div className="flex items-center gap-2">
            <AlertTriangle className="size-5 text-[var(--danger)]" aria-hidden="true" />
            <h4 className="font-bold text-[var(--danger)]">رفض المدير التنفيذي الإجراء المقترح</h4>
          </div>
          {selected.executiveDecisionReason ? <p className="mt-2 text-sm leading-7">{selected.executiveDecisionReason}</p> : null}
        </div>
      ) : null}
    </section>
  );
}
