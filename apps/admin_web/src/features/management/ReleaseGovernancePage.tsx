import {
  BadgeAlert, DatabaseZap, KeyRound, LockKeyhole, RefreshCcw, ShieldCheck,
  Smartphone, UserCheck, Wrench,
} from 'lucide-react';
import { useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useReleaseGovernanceCatalog, useReleaseGovernanceCommands } from './useReleaseGovernance';

type Tab = 'releases' | 'devices' | 'access' | 'breakglass' | 'privacy' | 'integrations';

type PolicyDraft = {
  platform: 'android' | 'ios' | 'web'; environment: 'development' | 'staging' | 'production';
  latestVersion: string; latestBuild: number; minSupportedVersion: string; minSupportedBuild: number;
  forceUpdate: boolean; maintenance: boolean; maintenanceMessageAr: string; updateMessageAr: string;
  storeUrl: string; rolloutPercent: number; reason: string;
};

export function ReleaseGovernancePage() {
  const query = useReleaseGovernanceCatalog();
  const commands = useReleaseGovernanceCommands();
  const [tab, setTab] = useState<Tab>('releases');
  const [policy, setPolicy] = useState<PolicyDraft | null>(null);
  const [review, setReview] = useState({ name: '', description: '', dueDate: '' });
  const [emergency, setEmergency] = useState({ targetUserId: '', roleId: '', durationMinutes: 30, reason: '' });
  const data = query.data;
  const activeDevices = useMemo(() => data?.devices.filter((item) => item.status === 'active').length ?? 0, [data]);

  async function savePolicy(event: FormEvent) {
    event.preventDefault();
    if (!policy) return;
    await commands.updatePolicy.mutateAsync(policy);
    setPolicy(null);
  }

  async function createReview(event: FormEvent) {
    event.preventDefault();
    if (!review.dueDate) return;
    await commands.createAccessReview.mutateAsync({ ...review, dueAt: new Date(`${review.dueDate}T23:59:59`).toISOString() });
    setReview({ name: '', description: '', dueDate: '' });
  }

  async function requestEmergency(event: FormEvent) {
    event.preventDefault();
    await commands.requestBreakGlass.mutateAsync(emergency);
    setEmergency({ targetUserId: '', roleId: '', durationMinutes: 30, reason: '' });
  }

  function reason(label: string, minimum = 5) {
    const value = window.prompt(label)?.trim() ?? '';
    if (value.length < minimum) throw new Error(`يجب كتابة سبب واضح لا يقل عن ${minimum} أحرف.`);
    return value;
  }

  return <div className="space-y-6">
    <PageHeader title="حوكمة الإصدار والوصول والخصوصية" description="مركز موحد للتحديث الإجباري والصيانة والأجهزة ومراجعات الصلاحيات والطوارئ والخصوصية وطابور التكاملات." actions={<button className="btn-secondary" onClick={() => void query.refetch()}><RefreshCcw className="size-4" aria-hidden="true"/>تحديث</button>} />
    {query.isLoading && !data ? <LoadingScreen label="جارٍ تحميل بيانات الحوكمة…" /> : null}
    {query.isError && !data ? <ErrorState description={query.error instanceof Error ? query.error.message : undefined} onRetry={() => void query.refetch()} /> : null}
    {data ? <>
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-6">
        <MetricCard label="سياسات الإصدار" value={data.policies.length} icon={Wrench}/>
        <MetricCard label="أجهزة نشطة" value={activeDevices} icon={Smartphone}/>
        <MetricCard label="مراجعات معلقة" value={data.reviewItems.length} icon={UserCheck}/>
        <MetricCard label="طوارئ معلقة" value={data.breakGlass.filter((item) => item.status === 'pending').length} icon={LockKeyhole}/>
        <MetricCard label="طلبات خصوصية" value={data.privacyRequests.filter((item) => !['completed','cancelled','rejected'].includes(item.status)).length} icon={ShieldCheck}/>
        <MetricCard label="Outbox متعثر" value={data.outbox.failed} icon={DatabaseZap}/>
      </section>

      <nav className="card flex flex-wrap gap-2 p-3" aria-label="أقسام الحوكمة">
        {([['releases','الإصدارات'],['devices','الأجهزة'],['access','مراجعة الوصول'],['breakglass','طوارئ الوصول'],['privacy','الخصوصية'],['integrations','التكاملات']] as const).map(([value,label]) => <button key={value} className={tab===value?'btn-primary':'btn-secondary'} aria-current={tab===value?'page':undefined} onClick={() => setTab(value)}>{label}</button>)}
      </nav>

      {tab === 'releases' ? <section className="space-y-4">
        <div className="grid gap-4 lg:grid-cols-3">{data.policies.map((item) => <article key={item.id} className="card p-5"><div className="flex items-start justify-between gap-3"><div><h2 className="font-black">{item.platform.toUpperCase()} · {environmentLabel(item.environment)}</h2><p className="muted mt-1 text-xs">أحدث {item.latestVersion}+{item.latestBuild} · الحد الأدنى {item.minSupportedVersion}+{item.minSupportedBuild}</p></div><StatusBadge value={item.maintenance?'maintenance':item.forceUpdate?'critical':'active'}/></div><div className="mt-4 grid grid-cols-2 gap-3 text-sm"><Info label="التحديث الإجباري" value={item.forceUpdate?'نعم':'لا'}/><Info label="نسبة الإطلاق" value={`${item.rolloutPercent}%`}/></div><button className="btn-secondary mt-4 w-full" onClick={() => setPolicy({ platform:item.platform,environment:item.environment,latestVersion:item.latestVersion,latestBuild:item.latestBuild,minSupportedVersion:item.minSupportedVersion,minSupportedBuild:item.minSupportedBuild,forceUpdate:item.forceUpdate,maintenance:item.maintenance,maintenanceMessageAr:item.maintenanceMessageAr??'',updateMessageAr:item.updateMessageAr??'',storeUrl:item.storeUrl??'',rolloutPercent:item.rolloutPercent,reason:'' })}>تعديل السياسة</button></article>)}</div>
        {policy ? <form className="card space-y-5 p-5" onSubmit={(event) => void savePolicy(event)}><div className="flex items-center justify-between"><div><h2 className="font-black">تعديل {policy.platform.toUpperCase()} · {environmentLabel(policy.environment)}</h2><p className="muted text-sm">كل تعديل حساس يحتاج سببًا ويُسجل في Audit.</p></div><button type="button" className="btn-secondary" onClick={() => setPolicy(null)}>إلغاء</button></div><div className="grid gap-4 md:grid-cols-4"><Input label="أحدث إصدار" value={policy.latestVersion} onChange={(value) => setPolicy({...policy,latestVersion:value})}/><NumberInput label="أحدث Build" value={policy.latestBuild} onChange={(value) => setPolicy({...policy,latestBuild:value})}/><Input label="الحد الأدنى" value={policy.minSupportedVersion} onChange={(value) => setPolicy({...policy,minSupportedVersion:value})}/><NumberInput label="Minimum Build" value={policy.minSupportedBuild} onChange={(value) => setPolicy({...policy,minSupportedBuild:value})}/></div><div className="grid gap-4 md:grid-cols-2"><Input label="رسالة التحديث" value={policy.updateMessageAr} onChange={(value) => setPolicy({...policy,updateMessageAr:value})}/><Input label="رابط المتجر" value={policy.storeUrl} onChange={(value) => setPolicy({...policy,storeUrl:value})}/><Input label="رسالة الصيانة" value={policy.maintenanceMessageAr} onChange={(value) => setPolicy({...policy,maintenanceMessageAr:value})}/><NumberInput label="نسبة الإطلاق" value={policy.rolloutPercent} onChange={(value) => setPolicy({...policy,rolloutPercent:value})}/></div><div className="flex flex-wrap gap-5"><Toggle label="تحديث إجباري" checked={policy.forceUpdate} onChange={(checked) => setPolicy({...policy,forceUpdate:checked})}/><Toggle label="وضع الصيانة" checked={policy.maintenance} onChange={(checked) => setPolicy({...policy,maintenance:checked})}/></div><Input label="سبب التعديل" value={policy.reason} onChange={(value) => setPolicy({...policy,reason:value})}/><button className="btn-primary" disabled={commands.updatePolicy.isPending}>{commands.updatePolicy.isPending?'جارٍ الحفظ…':'اعتماد السياسة'}</button></form> : null}
      </section> : null}

      {tab === 'devices' ? <section className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">الأجهزة والتثبيتات</h2><p className="muted mt-1 text-sm">يمكن إبطال جهاز مفقود أو نسخة غير آمنة، ويُرفض دخوله من Release Gate.</p></div>{data.devices.length?<div className="overflow-x-auto"><table className="data-table w-full min-w-[980px] text-right text-sm"><thead className="bg-[var(--surface-muted)] text-xs text-[var(--text-muted)]"><tr><th className="px-4 py-3.5">المستخدم</th><th className="px-4 py-3.5">الجهاز</th><th className="px-4 py-3.5">الإصدار</th><th className="px-4 py-3.5">البيئة</th><th className="px-4 py-3.5">آخر ظهور</th><th className="px-4 py-3.5">الحالة</th><th className="px-4 py-3.5">إجراء</th></tr></thead><tbody className="divide-y divide-[var(--border)]">{data.devices.map((device) => <tr key={device.id}><td className="px-4 py-3.5"><div className="flex items-center gap-2"><UserAvatar displayName={device.employeeName??'حساب بلا موظف'} size="sm" /><div><strong>{device.employeeName??'حساب بلا موظف'}</strong><span className="muted block text-xs">{device.employeeCode??device.userId??'غير مرتبط'}</span></div></div></td><td className="px-4 py-3.5">{device.deviceName??device.deviceModel??device.platform}<span className="muted block text-xs">{device.osVersion??'—'} · {device.installationId.slice(0,12)}…</span></td><td className="px-4 py-3.5">{device.appVersion}+{device.appBuild}</td><td className="px-4 py-3.5">{environmentLabel(device.environment)}</td><td className="px-4 py-3.5">{formatDate(device.lastSeenAt)}</td><td className="px-4 py-3.5"><StatusBadge value={device.status}/></td><td className="px-4 py-3.5">{device.status==='active'?<button className="btn-secondary text-[var(--danger)]" onClick={() => { const value=reason('سبب إبطال الجهاز',10); void commands.revokeDevice.mutateAsync({deviceId:device.id,reason:value}); }}>إبطال</button>:<span className="muted">—</span>}</td></tr>)}</tbody></table></div>:<EmptyState title="لا توجد أجهزة مسجلة" description="لم يتم تسجيل أي أجهزة أو تثبيتات حتى الآن." />}</section> : null}

      {tab === 'access' ? <section className="grid gap-5 xl:grid-cols-[360px_1fr]"><form className="card space-y-4 p-5" onSubmit={(event) => void createReview(event)}><h2 className="font-black">بدء مراجعة صلاحيات</h2><Input label="اسم الحملة" value={review.name} onChange={(value) => setReview({...review,name:value})}/><Input label="الوصف" value={review.description} onChange={(value) => setReview({...review,description:value})}/><label><span className="mb-1.5 block text-sm font-bold">الموعد النهائي</span><input className="input" type="date" required value={review.dueDate} onChange={(event) => setReview({...review,dueDate:event.target.value})}/></label><button className="btn-primary w-full" disabled={commands.createAccessReview.isPending}>بدء الحملة</button><div className="border-t border-[var(--border)] pt-4"><h3 className="font-bold">الحملات السابقة</h3><div className="mt-3 space-y-2">{data.accessReviews.map((item) => <div key={item.id} className="rounded-xl bg-[var(--surface-muted)] p-3"><div className="flex justify-between gap-2"><strong>{item.name}</strong><StatusBadge value={item.status}/></div><p className="muted mt-2 text-xs">{item.pendingItems} معلقة من {item.totalItems} · سُحب {item.revokedItems}</p></div>)}</div></div></form><article className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">الإسنادات المنتظرة للمراجعة</h2></div><div className="divide-y divide-[var(--border)]">{data.reviewItems.length?data.reviewItems.map((item) => <div key={item.id} className="flex flex-col gap-3 p-5 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-center gap-2"><UserAvatar displayName={item.employeeName??'حساب بلا موظف'} size="sm" /><strong>{item.employeeName??'حساب بلا موظف'}</strong><p className="muted text-xs">{item.employeeCode??item.userId} · {item.roleName}</p></div><div className="flex gap-2"><button className="btn-secondary" onClick={() => { const value=reason('سبب الإبقاء على الصلاحية'); void commands.decideAccessReview.mutateAsync({itemId:item.id,decision:'keep',reason:value}); }}>إبقاء</button><button className="btn-secondary text-[var(--danger)]" onClick={() => { const value=reason('سبب سحب الصلاحية'); void commands.decideAccessReview.mutateAsync({itemId:item.id,decision:'revoke',reason:value}); }}>سحب</button></div></div>):<EmptyState title="لا توجد عناصر مراجعة معلقة" description="جميع الإسنادات تمت مراجعتها ولا يوجد ما ينتظر قرارك حاليًا." />}</div></article></section> : null}

      {tab === 'breakglass' ? <section className="grid gap-5 xl:grid-cols-[380px_1fr]"><form className="card space-y-4 p-5" onSubmit={(event) => void requestEmergency(event)}><div><h2 className="font-black">طلب صلاحية طوارئ</h2><p className="muted mt-1 text-sm">لا تتفعل إلا بموافقة مستخدم إداري آخر وتنتهي تلقائيًا.</p></div><Select label="المستخدم" value={emergency.targetUserId} onChange={(value) => setEmergency({...emergency,targetUserId:value})}>{data.users.map((user) => <option key={user.userId} value={user.userId}>{user.name??'حساب بلا موظف'}{user.employeeCode?` · ${user.employeeCode}`:''}</option>)}</Select><Select label="الدور المؤقت" value={emergency.roleId} onChange={(value) => setEmergency({...emergency,roleId:value})}>{data.roles.map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}</Select><NumberInput label="المدة بالدقائق" value={emergency.durationMinutes} onChange={(value) => setEmergency({...emergency,durationMinutes:value})}/><Input label="سبب الطوارئ" value={emergency.reason} onChange={(value) => setEmergency({...emergency,reason:value})}/><button className="btn-primary w-full">إرسال للموافقة</button></form><article className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">سجل طوارئ الوصول</h2></div><div className="divide-y divide-[var(--border)]">{data.breakGlass.length?data.breakGlass.map((item) => <div key={item.id} className="p-5"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div><div className="flex flex-wrap items-center gap-2"><strong>{item.targetName??item.targetUserId}</strong><StatusBadge value={item.status}/></div><p className="muted mt-1 text-xs">{item.roleName} · {item.durationMinutes} دقيقة · {formatDate(item.requestedAt)}</p><p className="mt-3 text-sm">{item.reason}</p>{item.activeUntil?<p className="muted mt-2 text-xs">ينتهي: {formatDate(item.activeUntil)}</p>:null}</div>{item.status==='pending'?<div className="flex gap-2"><button className="btn-secondary" onClick={() => { const value=reason('سبب الاعتماد'); void commands.approveBreakGlass.mutateAsync({requestId:item.id,reason:value}); }}>اعتماد</button><button className="btn-secondary text-[var(--danger)]" onClick={() => { const value=reason('سبب الرفض'); void commands.rejectBreakGlass.mutateAsync({requestId:item.id,reason:value}); }}>رفض</button></div>:null}</div></div>):<EmptyState title="لا توجد طلبات طوارئ" description="لم تُقدَّم أي طلبات صلاحية طارئة حتى الآن." />}</div></article></section> : null}

      {tab === 'privacy' ? <section className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">طلبات الخصوصية</h2><p className="muted mt-1 text-sm">طلبات الاطلاع والتصحيح والتقييد والحذف، مع قرار بشري وتدقيق كامل.</p></div><div className="divide-y divide-[var(--border)]">{data.privacyRequests.length?data.privacyRequests.map((item) => <article key={item.id} className="p-5"><div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"><div><div className="flex flex-wrap items-center gap-2"><strong>طلب #{item.requestNumber} · {privacyType(item.requestType)}</strong><StatusBadge value={item.status}/></div><p className="muted mt-1 text-xs">{item.employeeName??item.requesterUserId} · {formatDate(item.createdAt)} · الاستحقاق {item.dueAt?formatDate(item.dueAt):'—'}</p><p className="mt-3 max-w-3xl text-sm leading-7">{item.details}</p></div>{!['completed','cancelled','rejected'].includes(item.status)?<div className="flex flex-wrap gap-2"><button className="btn-secondary" onClick={() => void commands.decidePrivacy.mutateAsync({requestId:item.id,status:'in_review',reason:'بدء المراجعة المؤسسية'})}>بدء المراجعة</button><button className="btn-secondary" onClick={() => { const value=reason('نتيجة تنفيذ الطلب'); void commands.decidePrivacy.mutateAsync({requestId:item.id,status:'completed',reason:value}); }}>إكمال</button><button className="btn-secondary text-[var(--danger)]" onClick={() => { const value=reason('سبب رفض الطلب'); void commands.decidePrivacy.mutateAsync({requestId:item.id,status:'rejected',reason:value}); }}>رفض</button></div>:null}</div></article>):<EmptyState title="لا توجد طلبات خصوصية" description="لم تصل أي طلبات اطلاع أو تصحيح أو حذف تنتظر المعالجة." />}</div></section> : null}

      {tab === 'integrations' ? <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="بانتظار الإرسال" value={data.outbox.pending} icon={DatabaseZap}/><MetricCard label="فشل/Dead Letter" value={data.outbox.failed} icon={BadgeAlert}/><MetricCard label="تم التسليم" value={data.outbox.delivered} icon={ShieldCheck}/><MetricCard label="أقدم عنصر" value={data.outbox.oldestPendingAt?formatDate(data.outbox.oldestPendingAt):'لا يوجد'} icon={KeyRound}/></section> : null}
    </> : null}
  </div>;
}

function environmentLabel(value: string) { return value==='production'?'الإنتاج':value==='staging'?'الاختبار':'التطوير'; }
function privacyType(value: string) { return ({access:'اطلاع',correction:'تصحيح',export:'تصدير',restriction:'تقييد',deletion:'حذف',objection:'اعتراض'} as Record<string,string>)[value]??value; }
function formatDate(value: string) { return new Intl.DateTimeFormat('ar-EG',{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)); }
function Info({label,value}:{label:string;value:string}) { return <div className="rounded-xl bg-[var(--surface-muted)] p-3"><span className="muted block text-xs">{label}</span><strong className="mt-1 block">{value}</strong></div>; }
function Input({label,value,onChange}:{label:string;value:string;onChange:(value:string)=>void}) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" required value={value} onChange={(event)=>onChange(event.target.value)}/></label>; }
function NumberInput({label,value,onChange}:{label:string;value:number;onChange:(value:number)=>void}) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" type="number" min={0} required value={value} onChange={(event)=>onChange(Number(event.target.value))}/></label>; }
function Select({label,value,onChange,children}:{label:string;value:string;onChange:(value:string)=>void;children:ReactNode}) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><select className="input" required value={value} onChange={(event)=>onChange(event.target.value)}><option value="">اختر…</option>{children}</select></label>; }
function Toggle({label,checked,onChange}:{label:string;checked:boolean;onChange:(value:boolean)=>void}) { return <label className="flex items-center gap-2 text-sm font-bold"><input className="size-4" type="checkbox" checked={checked} onChange={(event)=>onChange(event.target.checked)}/>{label}</label>; }
