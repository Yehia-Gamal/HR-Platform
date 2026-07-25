import { KeyRound, Plus, Save, ShieldCheck, Trash2, UserPlus, Users, X } from 'lucide-react';
import { useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAccessAdminCatalog, useAccessCommands } from './useAdminOperations';

type RoleDraft = { id?: string | null; slug: string; name: string; nameEn: string; description: string; fullAccess: boolean; selected: Record<string, { scope: string; mfa: boolean; reason: boolean }> };
const scopes = ['self','direct_reports','management_descendants','team','department','branch','organization','assigned_cases','workflow_inbox'];

export function AccessPage() {
  const query = useAccessAdminCatalog();
  const commands = useAccessCommands();
  const [draft, setDraft] = useState<RoleDraft | null>(null);
  const [assignment, setAssignment] = useState<{ userId: string; roleId: string; effectiveTo: string }>({ userId: '', roleId: '', effectiveTo: '' });
  const [moduleFilter, setModuleFilter] = useState('all');
  const data = query.data;
  const modules = useMemo(() => [...new Set((data?.permissions ?? []).map((item) => item.module))].sort(), [data]);

  function editRole(roleId: string) {
    const role = data?.roles.find((item) => item.id === roleId);
    if (!role) return;
    setDraft({
      id: role.id, slug: role.slug, name: role.name, nameEn: role.nameEn ?? '', description: role.description ?? '', fullAccess: role.fullAccess,
      selected: Object.fromEntries(role.permissions.map((permission) => [permission.permissionId, { scope: permission.scope, mfa: permission.requiresMfa, reason: permission.requiresReason }])),
    });
  }

  async function saveRole(event: FormEvent) {
    event.preventDefault();
    if (!draft) return;
    const result = await commands.upsertRole.mutateAsync({ id: draft.id, slug: draft.slug, name: draft.name, nameEn: draft.nameEn || null, description: draft.description || null, fullAccess: draft.fullAccess });
    const roleId = String((result as { id?: string })?.id ?? draft.id ?? '');
    if (roleId) {
      await commands.setPermissions.mutateAsync({
        roleId,
        items: Object.entries(draft.selected).map(([permission_id, value]) => ({ permission_id, scope: value.scope, requires_mfa: value.mfa, requires_reason: value.reason })),
      });
    }
    setDraft(null);
  }

  async function assign(event: FormEvent) {
    event.preventDefault();
    await commands.assignRole.mutateAsync({ userId: assignment.userId, roleId: assignment.roleId, effectiveTo: assignment.effectiveTo ? new Date(`${assignment.effectiveTo}T23:59:59`).toISOString() : null });
    setAssignment({ userId: '', roleId: '', effectiveTo: '' });
  }

  return <div className="space-y-6">
    <PageHeader title="الأدوار والصلاحيات" description="Role Builder فعلي بنطاقات ومصادقة إضافية وفصل بين المسؤوليات، وإسناد مؤقت للمستخدمين." actions={<button className="btn-primary" onClick={() => setDraft({ slug: '', name: '', nameEn: '', description: '', fullAccess: false, selected: {} })}><Plus className="size-4"/>دور مخصص</button>}/>
    {query.isError ? <ErrorState title="تعذر تحميل الصلاحيات" description={query.error instanceof Error ? query.error.message : 'غير مصرح'} onRetry={() => void query.refetch()} /> : query.isLoading && !data ? <MetricSkeletonRow /> : null}
    {data ? <>
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><MetricCard label="الأدوار" value={data.roles.length} icon={ShieldCheck}/><MetricCard label="الصلاحيات" value={data.permissions.length} icon={KeyRound}/><MetricCard label="المستخدمون" value={data.users.length} icon={Users}/><MetricCard label="الصلاحيات الحساسة" value={data.permissions.filter((item) => item.sensitive).length} icon={ShieldCheck}/></section>

      <section className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">قوالب الأدوار</h2><p className="muted mt-1 text-sm">الأدوار النظامية محمية، ويمكن إنشاء أدوار مخصصة دون تعديل الكود.</p></div><div className="overflow-x-auto"><table className="w-full min-w-[780px] text-right text-sm"><thead className="bg-[var(--surface-muted)]"><tr><th className="p-4">الدور</th><th className="p-4">النوع</th><th className="p-4">المستخدمون</th><th className="p-4">الصلاحيات</th><th className="p-4">عالي الخطورة</th><th className="p-4">إجراء</th></tr></thead><tbody>{data.roles.map((role) => <tr key={role.id} className="border-t border-[var(--border)]"><td className="p-4"><p className="font-black">{role.name}</p><p className="muted font-mono text-xs">{role.slug}</p></td><td className="p-4"><StatusBadge value={role.fullAccess ? 'critical' : role.system ? 'system' : 'custom'} /></td><td className="p-4">{role.assignments}</td><td className="p-4">{role.permissions.length}</td><td className="p-4">{role.permissions.filter((item) => item.requiresMfa || item.requiresReason).length}</td><td className="p-4"><button className="btn-secondary px-3 py-2" onClick={() => editRole(role.id)}>فتح</button></td></tr>)}</tbody></table></div></section>

      <section className="card p-5"><div className="mb-5"><h2 className="font-black">إسناد دور</h2><p className="muted mt-1 text-sm">يمكن جعل الإسناد مؤقتًا، ويُسحب تلقائيًا بعد تاريخ الانتهاء.</p></div><form className="grid gap-4 md:grid-cols-[1.2fr_1fr_1fr_auto]" onSubmit={(event) => void assign(event)}><Select label="المستخدم" required value={assignment.userId} onChange={(value) => setAssignment({ ...assignment, userId: value })}>{data.users.map((user) => <option key={user.userId} value={user.userId}>{user.name}{user.employeeCode ? ` · ${user.employeeCode}` : ''}</option>)}</Select><Select label="الدور" required value={assignment.roleId} onChange={(value) => setAssignment({ ...assignment, roleId: value })}>{data.roles.map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}</Select><label><span className="mb-1.5 block text-sm font-bold">تاريخ الانتهاء</span><input className="input" type="date" value={assignment.effectiveTo} onChange={(event) => setAssignment({ ...assignment, effectiveTo: event.target.value })}/></label><button className="btn-primary self-end" disabled={commands.assignRole.isPending}><UserPlus className="size-4"/>{commands.assignRole.isPending ? 'جارٍ الإسناد…' : 'إسناد'}</button></form></section>

      <section className="card overflow-hidden"><div className="border-b border-[var(--border)] p-5"><h2 className="font-black">إسنادات المستخدمين</h2></div>{commands.revokeRole.isError ? <div className="p-5 pb-0"><ErrorBanner message={`تعذر سحب الدور: ${commands.revokeRole.error instanceof Error ? commands.revokeRole.error.message : 'حدث خطأ غير متوقع'}`} /></div> : null}<div className="divide-y divide-[var(--border)]">{data.users.map((user) => <article key={user.userId} className="p-5"><div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"><div className="flex items-center gap-2"><UserAvatar displayName={user.name} size="sm" /><div><p className="font-black">{user.name}</p><p className="muted text-xs">{user.employeeCode ?? user.userId}</p></div></div><div className="flex flex-wrap gap-2">{user.roles.length ? user.roles.map((role) => <span key={role.roleId} className="inline-flex items-center gap-2 rounded-full bg-[var(--surface-muted)] px-3 py-1.5 text-xs font-bold">{role.name}{role.effectiveTo ? ` · حتى ${new Date(role.effectiveTo).toLocaleDateString('ar-EG')}` : ''}<button aria-label="سحب الدور" className="text-[var(--danger)]" onClick={() => void commands.revokeRole.mutateAsync({ userId: user.userId, roleId: role.roleId })}><Trash2 className="size-3"/></button></span>) : <span className="muted text-sm">بلا دور فعال</span>}</div></div></article>)}</div></section>
    </> : null}

    {draft && data ? <Dialog title={draft.id ? 'تعديل الدور' : 'إنشاء دور مخصص'} onClose={() => setDraft(null)}><form className="space-y-5" onSubmit={(event) => void saveRole(event)}><div className="grid gap-4 sm:grid-cols-2"><Input label="Slug" required value={draft.slug} disabled={Boolean(draft.id)} onChange={(value) => setDraft({ ...draft, slug: value.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}/><Input label="الاسم العربي" required value={draft.name} onChange={(value) => setDraft({ ...draft, name: value })}/><Input label="الاسم الإنجليزي" value={draft.nameEn} onChange={(value) => setDraft({ ...draft, nameEn: value })}/><Input label="الوصف" value={draft.description} onChange={(value) => setDraft({ ...draft, description: value })}/></div><div className="flex flex-wrap items-center justify-between gap-3 border-y border-[var(--border)] py-4"><h3 className="font-black">الصلاحيات</h3><div className="flex flex-wrap items-center gap-3"><p className="muted text-xs" aria-live="polite">{data.permissions.filter((permission) => moduleFilter === 'all' || permission.module === moduleFilter).length} صلاحية</p><select aria-label="تصفية حسب الوحدة" className="input max-w-xs" value={moduleFilter} onChange={(event) => setModuleFilter(event.target.value)}><option value="all">كل الوحدات</option>{modules.map((module) => <option key={module} value={module}>{module}</option>)}</select></div></div><div className="max-h-[52vh] space-y-2 overflow-y-auto pr-1">{data.permissions.filter((permission) => moduleFilter === 'all' || permission.module === moduleFilter).map((permission) => { const selected = draft.selected[permission.id]; return <article key={permission.id} className="rounded-xl border border-[var(--border)] p-4"><div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between"><label className="flex items-start gap-3"><input className="mt-1 size-4" type="checkbox" checked={Boolean(selected)} onChange={(event) => { const next = { ...draft.selected }; if (event.target.checked) next[permission.id] = { scope: permission.allowedScopes[0] ?? 'self', mfa: permission.sensitive, reason: permission.sensitive }; else delete next[permission.id]; setDraft({ ...draft, selected: next }); }}/><span><strong>{permission.name}</strong><span className="muted mt-1 block font-mono text-xs">{permission.code}</span></span></label>{selected ? <div className="flex flex-wrap gap-2"><select className="input w-52" value={selected.scope} onChange={(event) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, scope: event.target.value } } })}>{(permission.allowedScopes.length ? permission.allowedScopes : scopes).map((scope) => <option key={scope} value={scope}>{scope}</option>)}</select><Flag checked={selected.mfa} label="MFA" onChange={(mfa) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, mfa } } })}/><Flag checked={selected.reason} label="سبب" onChange={(reason) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, reason } } })}/></div> : null}</div></article>; })}</div><button className="btn-primary" disabled={commands.upsertRole.isPending || commands.setPermissions.isPending}><Save className="size-4"/>{commands.upsertRole.isPending || commands.setPermissions.isPending ? 'جارٍ الحفظ…' : 'حفظ الدور والصلاحيات'}</button></form></Dialog> : null}
  </div>;
}

function Dialog({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) { return <div className="fixed inset-0 z-50 grid place-items-center bg-[var(--text-primary)]/50 p-4" role="dialog" aria-modal="true"><section className="card max-h-[94vh] w-full max-w-5xl overflow-y-auto p-6"><div className="mb-5 flex items-center justify-between"><h2 className="text-xl font-black">{title}</h2><button className="icon-button" onClick={onClose} aria-label="إغلاق"><X className="size-5"/></button></div>{children}</section></div>; }
function Input({ label, value, onChange, required, disabled }: { label: string; value: string; onChange: (value: string) => void; required?: boolean; disabled?: boolean }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" required={required} disabled={disabled} value={value} onChange={(event) => onChange(event.target.value)}/></label>; }
function Select({ label, value, onChange, required, children }: { label: string; value: string; onChange: (value: string) => void; required?: boolean; children: ReactNode }) { return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><select className="input" required={required} value={value} onChange={(event) => onChange(event.target.value)}><option value="">اختر…</option>{children}</select></label>; }
function Flag({ checked, onChange, label }: { checked: boolean; onChange: (value: boolean) => void; label: string }) { return <label className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs font-bold"><input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)}/>{label}</label>; }
