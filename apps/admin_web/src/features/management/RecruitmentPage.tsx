import { BriefcaseBusiness, CalendarPlus, CheckCircle2, FileClock, FileSignature, Plus, Send, UserCheck, UserPlus, Users, X } from 'lucide-react';
import { useState, type FormEvent, type ReactNode } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useOrganizationAdminCatalog, useRecruitmentCommands } from './useAdminOperations';
import { useRecruitmentWorkbench, useRecruitmentWorkbenchCommands } from './useEnterpriseOperations';
import { useRecruitmentOverview } from './useManagementOverviews';

type RequisitionDraft = {
  departmentId: string;
  title: string;
  headcount: number;
  reason: string;
  budgetRange: string;
  submit: boolean;
};

export function RecruitmentPage() {
  const overview = useRecruitmentOverview();
  const organization = useOrganizationAdminCatalog();
  const commands = useRecruitmentCommands();
  const workbench = useRecruitmentWorkbench();
  const workbenchCommands = useRecruitmentWorkbenchCommands();
  const [draft, setDraft] = useState<RequisitionDraft | null>(null);
  const [interviewDraft, setInterviewDraft] = useState<{ applicationId: string; mode: string; scheduledAt: string; locationOrLink: string } | null>(null);
  const [offerDraft, setOfferDraft] = useState<{ applicationId: string; title: string; salary: string; contractType: string; startDate: string; expiresAt: string } | null>(null);
  const data = overview.data;

  const applicationOptions = workbench.data?.applications ?? [];
  const applicationLabel = (id: string) => {
    const app = applicationOptions.find((item) => item.id === id);
    return app ? `${app.candidateName} — ${app.jobTitle}` : id;
  };

  async function submitInterview(event: FormEvent) {
    event.preventDefault();
    if (!interviewDraft) return;
    try {
      await workbenchCommands.scheduleInterview.mutateAsync({
        applicationId: interviewDraft.applicationId,
        mode: interviewDraft.mode,
        scheduledAt: new Date(interviewDraft.scheduledAt).toISOString(),
        locationOrLink: interviewDraft.locationOrLink || undefined,
      });
      setInterviewDraft(null);
    } catch { /* mutation error surfaced via mutation.isError state */ }
  }

  async function submitOffer(event: FormEvent) {
    event.preventDefault();
    if (!offerDraft) return;
    try {
      await workbenchCommands.createOffer.mutateAsync({
        applicationId: offerDraft.applicationId,
        title: offerDraft.title || undefined,
        salary: offerDraft.salary ? Number(offerDraft.salary) : null,
        contractType: offerDraft.contractType || undefined,
        startDate: offerDraft.startDate || null,
        expiresAt: offerDraft.expiresAt ? new Date(offerDraft.expiresAt).toISOString() : null,
      });
      setOfferDraft(null);
    } catch { /* mutation error surfaced via mutation.isError state */ }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft) return;
    try {
      await commands.createRequisition.mutateAsync({
        departmentId: draft.departmentId,
        title: draft.title,
        headcount: draft.headcount,
        reason: draft.reason || null,
        budgetRange: draft.budgetRange || null,
        submit: draft.submit,
      });
      setDraft(null);
    } catch { /* mutation error surfaced via mutation.isError state */ }
  }

  const openDraft = (submitNow: boolean) => setDraft({
    departmentId: organization.data?.departments[0]?.id ?? '',
    title: '',
    headcount: 1,
    reason: '',
    budgetRange: '',
    submit: submitNow,
  });

  const error = overview.error ?? organization.error ?? workbench.error;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="إدارة الموارد"
        title="التوظيف وATS"
        description="إنشاء احتياج وظيفي موثق، حفظه كمسودة أو إرساله للاعتماد، ثم متابعة الإعلانات والمرشحين حتى التعيين."
        actions={<div className="flex flex-wrap gap-2"><button className="btn-secondary" onClick={() => openDraft(false)}><Plus className="size-4" aria-hidden="true" />مسودة</button><button className="btn-primary" onClick={() => openDraft(true)}><Send className="size-4" aria-hidden="true" />طلب توظيف</button></div>}
      />

      {error ? (
        <ErrorState
          title="تعذر تحميل التوظيف"
          description={safeErrorMessage(error)}
          onRetry={() => { void overview.refetch(); void organization.refetch(); void workbench.refetch(); }}
        />
      ) : overview.isLoading || organization.isLoading ? (
        <MetricSkeletonRow count={5} />
      ) : null}

      {data ? (
        <>
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-5">
            <MetricCard label="طلبات التوظيف" value={data.requisitions} icon={BriefcaseBusiness} />
            <MetricCard label="تنتظر الاعتماد" value={data.pendingRequisitions} icon={FileClock} />
            <MetricCard label="إعلانات مفتوحة" value={data.openPostings} icon={UserPlus} />
            <MetricCard label="المرشحون" value={data.candidates} icon={Users} />
            <MetricCard label="تم تعيينهم" value={data.hiredApplications} icon={CheckCircle2} />
          </section>

          <section className="grid gap-5 xl:grid-cols-[1.4fr_1fr]">
            <article className="card overflow-hidden">
              <div className="flex items-center justify-between border-b border-[var(--border)] p-5">
                <div><h2 className="font-black">أحدث طلبات التوظيف</h2><p className="muted mt-1 text-sm">المسودة لا تدخل مسار الموافقة حتى يتم إرسالها رسميًا.</p></div>
                <button className="btn-secondary" onClick={() => openDraft(false)}><Plus className="size-4" aria-hidden="true" />احتياج جديد</button>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {data.recentRequisitions.length ? data.recentRequisitions.map((requisition) => (
                  <div key={requisition.id} className="flex flex-col gap-3 p-5 sm:flex-row sm:items-center sm:justify-between">
                    <div><p className="font-black">{requisition.title}</p><p className="muted mt-1 text-sm">{requisition.department} · العدد {requisition.headcount}</p></div>
                    <StatusBadge value={requisition.status} />
                  </div>
                )) : <EmptyState title="لا توجد طلبات توظيف" description="أنشئ أول احتياج وحدد الإدارة والعدد وسبب الطلب." />}
              </div>
            </article>

            <article className="card p-5">
              <h2 className="font-black">مسار المرشحين</h2>
              <p className="muted mt-1 text-sm">توزيع الطلبات النشطة على مراحل الـATS.</p>
              <div className="mt-5 space-y-4">
                {data.pipeline.map((item) => (
                  <div key={item.stage}>
                    <div className="flex justify-between text-sm"><span>{item.stage}</span><strong>{item.count}</strong></div>
                    <div className="mt-2 h-2 rounded-full bg-[var(--surface-muted)]"><div className="h-full rounded-full bg-brand" style={{ width: `${Math.min(100, data.activeApplications ? Math.max(8, item.count / data.activeApplications * 100) : 0)}%` }} /></div>
                  </div>
                ))}
              </div>
            </article>
          </section>
        </>
      ) : null}



      {workbench.data ? (
        <section className="card overflow-hidden">
          <div className="border-b border-[var(--border)] p-5">
            <h2 className="font-black">لوحة المرشحين والمراحل</h2>
            <p className="muted mt-1 text-sm">تحريك المرشح بين المراحل مع حفظ سجل الانتقال وسبب الحركة.</p>
          </div>
          <div className="overflow-x-auto">
            <table className="data-table min-w-[900px] text-sm">
              <thead className="bg-[var(--surface-muted)] text-start"><tr><th scope="col" className="p-3">المرشح</th><th scope="col" className="p-3">الوظيفة</th><th scope="col" className="p-3">المرحلة</th><th scope="col" className="p-3">تاريخ التقديم</th><th scope="col" className="p-3">نقل إلى</th></tr></thead>
              <tbody className="divide-y divide-[var(--border)]">
                {workbench.data.applications.map((application) => {
                  const stages = workbench.data!.stages.filter((stage) => stage.postingId === application.postingId);
                  return <tr key={application.id}><td className="p-3 font-bold">{application.candidateName}</td><td className="p-3">{application.jobTitle}</td><td className="p-3"><StatusBadge value={application.stageName ?? application.status} /></td><td className="p-3 muted">{new Date(application.appliedAt).toLocaleDateString('ar-EG')}</td><td className="p-3"><select className="input max-w-48" aria-label={`نقل ${application.candidateName} إلى مرحلة`} value={application.stageId ?? ''} onChange={(event) => { if (event.target.value && event.target.value !== application.stageId) workbenchCommands.moveStage.mutate({ applicationId: application.id, stageId: event.target.value, reason: 'نقل من لوحة ATS' }); }}><option value="">اختر المرحلة</option>{stages.map((stage) => <option key={stage.id} value={stage.id}>{stage.name}</option>)}</select></td></tr>;
                })}
                {!workbench.data.applications.length ? <tr><td colSpan={5} className="p-8"><EmptyState title="لا توجد طلبات مرشحين" description="ستظهر الطلبات بعد نشر وظيفة واستقبال مرشح." /></td></tr> : null}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      {workbench.data ? (
        <section className="grid gap-5 xl:grid-cols-2">
          <article className="card overflow-hidden">
            <div className="flex items-center justify-between border-b border-[var(--border)] p-5">
              <div><h2 className="font-black">المقابلات</h2><p className="muted mt-1 text-sm">جدولة المقابلات ومتابعة نتائجها لكل طلب.</p></div>
              <button className="btn-secondary" disabled={!applicationOptions.length} onClick={() => setInterviewDraft({ applicationId: applicationOptions[0]?.id ?? '', mode: 'onsite', scheduledAt: '', locationOrLink: '' })}><CalendarPlus className="size-4" aria-hidden="true" />جدولة مقابلة</button>
            </div>
            <div className="divide-y divide-[var(--border)]">
              {workbench.data.interviews.length ? workbench.data.interviews.map((interview) => (
                <div key={interview.id} className="flex flex-col gap-3 p-5 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="font-black">{interview.candidateName}</p>
                    <p className="muted mt-1 text-sm">{interview.mode === 'remote' ? 'عن بُعد' : 'حضوري'} · {interview.scheduledAt ? new Date(interview.scheduledAt).toLocaleString('ar-EG') : 'غير مجدولة'}{interview.locationOrLink ? ` · ${interview.locationOrLink}` : ''}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <StatusBadge value={interview.status} />
                    {interview.status === 'scheduled' ? (
                      <>
                        <button className="btn-secondary" onClick={() => workbenchCommands.decideInterview.mutate({ interviewId: interview.id, status: 'completed' })}>إتمام</button>
                        <button className="btn-secondary" onClick={() => workbenchCommands.decideInterview.mutate({ interviewId: interview.id, status: 'no_show' })}>عدم حضور</button>
                        <button className="btn-secondary" onClick={() => workbenchCommands.decideInterview.mutate({ interviewId: interview.id, status: 'cancelled' })}>إلغاء</button>
                      </>
                    ) : null}
                  </div>
                </div>
              )) : <EmptyState title="لا توجد مقابلات" description="جدول مقابلة لأحد المرشحين النشطين." />}
            </div>
          </article>

          <article className="card overflow-hidden">
            <div className="flex items-center justify-between border-b border-[var(--border)] p-5">
              <div><h2 className="font-black">العروض الوظيفية والتعيين</h2><p className="muted mt-1 text-sm">إنشاء العرض، اعتماده وإرساله، ثم اعتماد التعيين بعد القبول.</p></div>
              <button className="btn-secondary" disabled={!applicationOptions.length} onClick={() => setOfferDraft({ applicationId: applicationOptions[0]?.id ?? '', title: '', salary: '', contractType: '', startDate: '', expiresAt: '' })}><FileSignature className="size-4" aria-hidden="true" />عرض جديد</button>
            </div>
            <div className="divide-y divide-[var(--border)]">
              {workbench.data.offers.length ? workbench.data.offers.map((offer) => {
                const canHire = offer.status === 'accepted';
                return (
                  <div key={offer.id} className="flex flex-col gap-3 p-5">
                    <div className="flex items-center justify-between gap-3">
                      <div><p className="font-black">{offer.candidateName}</p><p className="muted mt-1 text-sm">{offer.title ?? 'عرض توظيف'} · نسخة {offer.version}{offer.startDate ? ` · يبدأ ${offer.startDate}` : ''}</p></div>
                      <StatusBadge value={offer.status} />
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {offer.status === 'draft' ? <button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'submit' })}>إرسال للاعتماد</button> : null}
                      {offer.status === 'pending' ? <button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'approve' })}>اعتماد</button> : null}
                      {offer.status === 'approved' ? <button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'send' })}>إرسال للمرشح</button> : null}
                      {offer.status === 'sent' ? <><button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'accept' })}>تسجيل القبول</button><button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'decline' })}>تسجيل الرفض</button></> : null}
                      {['draft', 'pending', 'approved', 'sent'].includes(offer.status) ? <button className="btn-secondary" onClick={() => workbenchCommands.transitionOffer.mutate({ offerId: offer.id, action: 'withdraw' })}>سحب</button> : null}
                      {canHire ? <button className="btn-primary" disabled={workbenchCommands.hireApplicant.isPending} aria-busy={workbenchCommands.hireApplicant.isPending} onClick={() => workbenchCommands.hireApplicant.mutate({ applicationId: offer.applicationId })}><UserCheck className="size-4" aria-hidden="true" />{workbenchCommands.hireApplicant.isPending ? 'جارٍ…' : 'اعتماد التعيين'}</button> : null}
                    </div>
                  </div>
                );
              }) : <EmptyState title="لا توجد عروض" description="أنشئ عرضًا لمرشح اجتاز المقابلات." />}
            </div>
          </article>
        </section>
      ) : null}

      {interviewDraft ? (
        <DialogOverlay title="جدولة مقابلة" onClose={() => setInterviewDraft(null)} maxWidth="max-w-4xl">
          <form className="space-y-5" onSubmit={(event) => void submitInterview(event)}>
            <Select label="الطلب/المرشح" required value={interviewDraft.applicationId} onChange={(value) => setInterviewDraft({ ...interviewDraft, applicationId: value })}>
              {applicationOptions.map((app) => <option key={app.id} value={app.id}>{applicationLabel(app.id)}</option>)}
            </Select>
            <div className="grid gap-4 sm:grid-cols-2">
              <Select label="النمط" required value={interviewDraft.mode} onChange={(value) => setInterviewDraft({ ...interviewDraft, mode: value })}>
                <option value="onsite">حضوري</option>
                <option value="remote">عن بُعد</option>
              </Select>
              <label><span className="mb-1.5 block text-sm font-bold">الموعد</span><input className="input" type="datetime-local" required value={interviewDraft.scheduledAt} onChange={(event) => setInterviewDraft({ ...interviewDraft, scheduledAt: event.target.value })} /></label>
            </div>
            <Input label="المكان أو رابط الاجتماع" value={interviewDraft.locationOrLink} onChange={(value) => setInterviewDraft({ ...interviewDraft, locationOrLink: value })} />
            <button className="btn-primary" disabled={!interviewDraft.applicationId || !interviewDraft.scheduledAt || workbenchCommands.scheduleInterview.isPending}><CalendarPlus className="size-4" aria-hidden="true" />{workbenchCommands.scheduleInterview.isPending ? 'جارٍ الحفظ…' : 'جدولة'}</button>
          </form>
        </DialogOverlay>
      ) : null}

      {offerDraft ? (
        <DialogOverlay title="عرض توظيف جديد" onClose={() => setOfferDraft(null)} maxWidth="max-w-4xl">
          <form className="space-y-5" onSubmit={(event) => void submitOffer(event)}>
            <Select label="الطلب/المرشح" required value={offerDraft.applicationId} onChange={(value) => setOfferDraft({ ...offerDraft, applicationId: value })}>
              {applicationOptions.map((app) => <option key={app.id} value={app.id}>{applicationLabel(app.id)}</option>)}
            </Select>
            <div className="grid gap-4 sm:grid-cols-2">
              <Input label="المسمى الوظيفي" value={offerDraft.title} onChange={(value) => setOfferDraft({ ...offerDraft, title: value })} />
              <Input label="نوع العقد" value={offerDraft.contractType} onChange={(value) => setOfferDraft({ ...offerDraft, contractType: value })} placeholder="مثال: دائم / مؤقت" />
              <label><span className="mb-1.5 block text-sm font-bold">الراتب</span><input className="input" type="number" min={0} value={offerDraft.salary} onChange={(event) => setOfferDraft({ ...offerDraft, salary: event.target.value })} /></label>
              <label><span className="mb-1.5 block text-sm font-bold">تاريخ المباشرة</span><input className="input" type="date" value={offerDraft.startDate} onChange={(event) => setOfferDraft({ ...offerDraft, startDate: event.target.value })} /></label>
              <label><span className="mb-1.5 block text-sm font-bold">تنتهي صلاحية العرض</span><input className="input" type="datetime-local" value={offerDraft.expiresAt} onChange={(event) => setOfferDraft({ ...offerDraft, expiresAt: event.target.value })} /></label>
            </div>
            <button className="btn-primary" disabled={!offerDraft.applicationId || workbenchCommands.createOffer.isPending}><FileSignature className="size-4" aria-hidden="true" />{workbenchCommands.createOffer.isPending ? 'جارٍ الحفظ…' : 'إنشاء العرض'}</button>
          </form>
        </DialogOverlay>
      ) : null}

      {draft && organization.data ? (
        <DialogOverlay title="طلب توظيف جديد" onClose={() => setDraft(null)} maxWidth="max-w-4xl">
          <form className="space-y-5" onSubmit={(event) => void submit(event)}>
            <div className="grid gap-4 sm:grid-cols-2">
              <Select label="الإدارة" required value={draft.departmentId} onChange={(value) => setDraft({ ...draft, departmentId: value })}>
                {organization.data.departments.filter((item) => item.active).map((department) => <option key={department.id} value={department.id}>{department.name}</option>)}
              </Select>
              <Input label="المسمى المطلوب" required value={draft.title} onChange={(value) => setDraft({ ...draft, title: value })} />
              <NumberInput label="العدد" min={1} value={draft.headcount} onChange={(value) => setDraft({ ...draft, headcount: value })} />
              <Input label="نطاق الميزانية" value={draft.budgetRange} onChange={(value) => setDraft({ ...draft, budgetRange: value })} placeholder="مثال: وفق الدرجة G4" />
            </div>
            <label><span className="mb-1.5 block text-sm font-bold">سبب الاحتياج</span><textarea className="input min-h-28" value={draft.reason} onChange={(event) => setDraft({ ...draft, reason: event.target.value })} /></label>
            <label className="flex items-center gap-3 rounded-xl bg-[var(--surface-muted)] p-4 text-sm font-bold"><input type="checkbox" checked={draft.submit} onChange={(event) => setDraft({ ...draft, submit: event.target.checked })} />إرسال الطلب للاعتماد فور الحفظ</label>
            <button className="btn-primary" disabled={commands.createRequisition.isPending}><Send className="size-4" aria-hidden="true" />{commands.createRequisition.isPending ? 'جارٍ الحفظ…' : draft.submit ? 'حفظ وإرسال' : 'حفظ كمسودة'}</button>
          </form>
        </DialogOverlay>
      ) : null}
    </div>
  );
}

function Input({ label, value, onChange, required, placeholder }: { label: string; value: string; onChange: (value: string) => void; required?: boolean; placeholder?: string }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" required={required} placeholder={placeholder} value={value} onChange={(event) => onChange(event.target.value)} /></label>; }
function NumberInput({ label, value, onChange, min }: { label: string; value: number; onChange: (value: number) => void; min: number }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" type="number" min={min} required value={value} onChange={(event) => onChange(Math.max(min, Number(event.target.value) || min))} /></label>; }
function Select({ label, value, onChange, required, children }: { label: string; value: string; onChange: (value: string) => void; required?: boolean; children: ReactNode }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><select className="input" required={required} value={value} onChange={(event) => onChange(event.target.value)}><option value="">اختر…</option>{children}</select></label>; }
