import { Briefcase, ChevronDown, ChevronLeft, Crown, KeyRound, Plus, Save, Scale, Search, Shield, ShieldCheck, Trash2, UserPlus, Users, Users2 } from 'lucide-react';
import { useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAccessAdminCatalog, useAccessCommands } from './useAdminOperations';
import type { AccessAdminCatalog } from '@ahla/shared-contracts';

// ─── ترجمة النطاقات ────────────────────────────────────────────────────────
const SCOPE_AR: Record<string, string> = {
  self: 'الذات', direct_reports: 'المرؤوسين المباشرين', management_descendants: 'الفريق الموسع',
  selected_employees: 'موظفين محددين', team: 'الفريق', department: 'القسم',
  selected_departments: 'أقسام محددة', branch: 'الفرع', selected_branches: 'فروع محددة',
  organization: 'المنظمة', assigned_cases: 'القضايا المسندة', workflow_inbox: 'صندوق الوارد',
  records_created_by_user: 'السجلات الخاصة', archive_readonly: 'الأرشيف (قراءة)',
};

const MODULE_AR: Record<string, string> = {
  access: 'إدارة الوصول', assets: 'الأصول', assignments: 'التكليفات', attendance: 'الحضور والانصراف',
  audit: 'التدقيق', automation: 'الأتمتة', comms: 'التواصل', communications: 'الاتصالات',
  disputes: 'لجنة الخلافات', documents: 'المستندات', engagement: 'المشاركة', governance: 'الحوكمة',
  holidays: 'العطلات الرسمية', kpi: 'مؤشرات الأداء', learning: 'التعلم والتطوير',
  live_location: 'الموقع المباشر', location: 'الموقع', meetings: 'الاجتماعات',
  offboarding: 'إنهاء الخدمة', onboarding: 'التهيئة', operations: 'العمليات',
  organization: 'الهيكل التنظيمي', payroll: 'الرواتب', people: 'شؤون الموظفين',
  performance: 'الأداء', posts: 'المنشورات', privacy: 'الخصوصية', projects: 'المشاريع',
  quality: 'الجودة', recruitment: 'التوظيف', relations: 'علاقات الموظفين', release: 'الإصدارات',
  reports: 'التقارير', requests: 'الطلبات', risk: 'المخاطر', security: 'الأمان',
  service: 'الخدمات', strategy: 'الاستراتيجية', system: 'النظام', wellbeing: 'الرفاهية',
  workforce: 'القوى العاملة',
};

// ─── قوالب الأدوار المعتمدة ────────────────────────────────────────────────
type RoleTemplate = {
  slug: string;
  name: string;
  description: string;
  icon: typeof Shield;
  color: string;
  bgColor: string;
  borderColor: string;
};

const ROLE_TEMPLATES: RoleTemplate[] = [
  { slug: 'admin', name: 'أدمن', description: 'السكرتير التنفيذي والأدمن الرئيسي — جميع صلاحيات لوحة الإدارة', icon: Shield, color: 'text-red-600', bgColor: 'bg-red-50', borderColor: 'border-red-200' },
  { slug: 'hr-manager', name: 'الموارد البشرية', description: 'إدارة كل ما يخص الموظفين — سجلات، حضور، طلبات، مستندات، أداء', icon: Users2, color: 'text-blue-600', bgColor: 'bg-blue-50', borderColor: 'border-blue-200' },
  { slug: 'executive', name: 'المدير التنفيذي', description: 'الاطلاع على جميع التقارير، إرسال واستقبال مواقع الموظفين، اتخاذ القرارات', icon: Crown, color: 'text-amber-600', bgColor: 'bg-amber-50', borderColor: 'border-amber-200' },
  { slug: 'operations-manager-1', name: 'مدير تشغيل', description: 'تحت المدير التنفيذي — قبول طلبات الإجازة والمأموريات عند غياب المدير المباشر', icon: Briefcase, color: 'text-emerald-600', bgColor: 'bg-emerald-50', borderColor: 'border-emerald-200' },
  { slug: 'committee-member', name: 'عضو لجنة الخلافات', description: 'الاطلاع على مشاكل الموظفين واتخاذ إجراءات بشأنها', icon: Scale, color: 'text-purple-600', bgColor: 'bg-purple-50', borderColor: 'border-purple-200' },
  { slug: 'direct-manager', name: 'مدير', description: 'قبول أو رفض طلبات الإجازة والمأموريات، وتقييم الموظفين المباشرين', icon: Users, color: 'text-teal-600', bgColor: 'bg-teal-50', borderColor: 'border-teal-200' },
  { slug: 'employee', name: 'موظف', description: 'الخدمة الذاتية — تسجيل حضور، تقديم طلبات، عرض البيانات الشخصية', icon: ShieldCheck, color: 'text-slate-600', bgColor: 'bg-slate-50', borderColor: 'border-slate-200' },
];

// ─── النوع الداخلي لمسودة الدور المخصص ────────────────────────────────────
type RoleDraft = {
  id?: string | null;
  slug: string;
  name: string;
  nameEn: string;
  description: string;
  fullAccess: boolean;
  selected: Record<string, { scope: string; mfa: boolean; reason: boolean }>;
};

const scopes = ['self', 'direct_reports', 'management_descendants', 'team', 'department', 'branch', 'organization', 'assigned_cases', 'workflow_inbox'];

// ─── المكون الرئيسي ────────────────────────────────────────────────────────
export function AccessPage() {
  const query = useAccessAdminCatalog();
  const commands = useAccessCommands();
  const [viewRole, setViewRole] = useState<string | null>(null);
  const [customDraft, setCustomDraft] = useState<RoleDraft | null>(null);
  const [assignment, setAssignment] = useState({ userId: '', roleId: '', effectiveTo: '' });
  const [moduleFilter, setModuleFilter] = useState('all');
  const [permSearch, setPermSearch] = useState('');
  const data = query.data;

  const modules = useMemo(() => [...new Set((data?.permissions ?? []).map((p) => p.module))].sort(), [data]);

  // مطابقة قوالب الأدوار مع البيانات الحقيقية
  const templateRoles = useMemo(() => {
    if (!data) return [];
    return ROLE_TEMPLATES.map((tpl) => {
      const dbRole = data.roles.find((r) => r.slug === tpl.slug);
      return { ...tpl, dbRole };
    });
  }, [data]);

  // الدور المحدد حالياً للعرض (قالب أو DB role)
  const selectedRole = useMemo(() => {
    if (!viewRole || !data) return null;
    return data.roles.find((r) => r.slug === viewRole || r.id === viewRole) ?? null;
  }, [viewRole, data]);

  function openCustomDraft(roleId?: string) {
    if (roleId && data) {
      const role = data.roles.find((r) => r.id === roleId);
      if (!role) return;
      setCustomDraft({
        id: role.id, slug: role.slug, name: role.name, nameEn: role.nameEn ?? '',
        description: role.description ?? '', fullAccess: role.fullAccess,
        selected: Object.fromEntries(role.permissions.map((p) => [p.permissionId, { scope: p.scope, mfa: p.requiresMfa, reason: p.requiresReason }])),
      });
    } else {
      setCustomDraft({ slug: '', name: '', nameEn: '', description: '', fullAccess: false, selected: {} });
    }
  }

  async function saveRole(event: FormEvent) {
    event.preventDefault();
    if (!customDraft) return;
    const result = await commands.upsertRole.mutateAsync({ id: customDraft.id, slug: customDraft.slug, name: customDraft.name, nameEn: customDraft.nameEn || null, description: customDraft.description || null, fullAccess: customDraft.fullAccess });
    const roleId = String((result as { id?: string })?.id ?? customDraft.id ?? '');
    if (roleId) {
      await commands.setPermissions.mutateAsync({
        roleId,
        items: Object.entries(customDraft.selected).map(([permission_id, v]) => ({ permission_id, scope: v.scope, requires_mfa: v.mfa, requires_reason: v.reason })),
      });
    }
    setCustomDraft(null);
  }

  async function assign(event: FormEvent) {
    event.preventDefault();
    await commands.assignRole.mutateAsync({ userId: assignment.userId, roleId: assignment.roleId, effectiveTo: assignment.effectiveTo ? new Date(`${assignment.effectiveTo}T23:59:59`).toISOString() : null });
    setAssignment({ userId: '', roleId: '', effectiveTo: '' });
  }

  return <div className="space-y-6">
    <PageHeader title="الأدوار والصلاحيات" description="اختر قالب دور لإسناده للمستخدمين، أو أنشئ دوراً مخصصاً بصلاحيات محددة." actions={<button className="btn-primary" onClick={() => openCustomDraft()}><Plus className="size-4"/>دور مخصص</button>}/>

    {query.isError ? <ErrorState title="تعذر تحميل الصلاحيات" description={query.error instanceof Error ? query.error.message : 'غير مصرح'} onRetry={() => void query.refetch()} /> : query.isLoading && !data ? <MetricSkeletonRow /> : null}

    {data ? <>
      {/* ── الإحصائيات ── */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="الأدوار" value={data.roles.length} icon={ShieldCheck}/>
        <MetricCard label="الصلاحيات" value={data.permissions.length} icon={KeyRound}/>
        <MetricCard label="المستخدمون" value={data.users.length} icon={Users}/>
        <MetricCard label="الصلاحيات الحساسة" value={data.permissions.filter((p) => p.sensitive).length} icon={ShieldCheck}/>
      </section>

      {/* ── بطاقات قوالب الأدوار ── */}
      <section>
        <div className="mb-4">
          <h2 className="text-lg font-black">قوالب الأدوار المعتمدة</h2>
          <p className="muted mt-1 text-sm">اختر قالباً لعرض صلاحياته أو إسناده مباشرة للمستخدمين.</p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {templateRoles.map((tpl) => <RoleTemplateCard key={tpl.slug} template={tpl} permissionCount={tpl.dbRole?.permissions.length ?? 0} assignmentCount={tpl.dbRole?.assignments ?? 0} onClick={() => setViewRole(tpl.slug)}/>)}
        </div>
      </section>

      {/* ── الأدوار الأخرى (غير القوالب المعتمدة) ── */}
      {data.roles.filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug)).length > 0 && <section className="card overflow-hidden">
        <div className="border-b border-[var(--border)] p-5">
          <h2 className="font-black">أدوار أخرى</h2>
          <p className="muted mt-1 text-sm">أدوار نظامية أو مخصصة غير مدرجة في القوالب المعتمدة.</p>
        </div>
        <div className="divide-y divide-[var(--border)]">
          {data.roles.filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug)).map((role) => <div key={role.id} className="flex items-center justify-between p-4">
            <div>
              <p className="font-bold">{role.name}</p>
              <p className="muted font-mono text-xs">{role.slug}</p>
            </div>
            <div className="flex items-center gap-3">
              <span className="muted text-xs">{role.permissions.length} صلاحية · {role.assignments} مستخدم</span>
              <button className="btn-secondary px-3 py-1.5 text-xs" onClick={() => setViewRole(role.id)}>عرض</button>
              {!role.system && <button className="btn-secondary px-3 py-1.5 text-xs" onClick={() => openCustomDraft(role.id)}>تعديل</button>}
            </div>
          </div>)}
        </div>
      </section>}

      {/* ── إسناد دور ── */}
      <section className="card p-5">
        <div className="mb-5">
          <h2 className="font-black">إسناد دور</h2>
          <p className="muted mt-1 text-sm">يمكن جعل الإسناد مؤقتًا، ويُسحب تلقائيًا بعد تاريخ الانتهاء.</p>
        </div>
        <form className="grid gap-4 md:grid-cols-[1.2fr_1fr_1fr_auto]" onSubmit={(e) => void assign(e)}>
          <FormSelect label="المستخدم" required value={assignment.userId} onChange={(v) => setAssignment({ ...assignment, userId: v })}>
            {data.users.map((u) => <option key={u.userId} value={u.userId}>{u.name}{u.employeeCode ? ` · ${u.employeeCode}` : ''}</option>)}
          </FormSelect>
          <FormSelect label="الدور" required value={assignment.roleId} onChange={(v) => setAssignment({ ...assignment, roleId: v })}>
            {data.roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
          </FormSelect>
          <label>
            <span className="mb-1.5 block text-sm font-bold">تاريخ الانتهاء</span>
            <input className="input" type="date" value={assignment.effectiveTo} onChange={(e) => setAssignment({ ...assignment, effectiveTo: e.target.value })}/>
          </label>
          <button className="btn-primary self-end" disabled={commands.assignRole.isPending}>
            <UserPlus className="size-4"/>{commands.assignRole.isPending ? 'جارٍ الإسناد…' : 'إسناد'}
          </button>
        </form>
      </section>

      {/* ── إسنادات المستخدمين ── */}
      <section className="card overflow-hidden">
        <div className="border-b border-[var(--border)] p-5">
          <h2 className="font-black">إسنادات المستخدمين</h2>
        </div>
        {commands.revokeRole.isError && <div className="p-5 pb-0"><ErrorBanner message={`تعذر سحب الدور: ${commands.revokeRole.error instanceof Error ? commands.revokeRole.error.message : 'حدث خطأ غير متوقع'}`} /></div>}
        <div className="divide-y divide-[var(--border)]">
          {data.users.map((user) => <article key={user.userId} className="p-5">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="flex items-center gap-2">
                <UserAvatar displayName={user.name} size="sm" />
                <div>
                  <p className="font-black">{user.name}</p>
                  <p className="muted text-xs">{user.employeeCode ?? user.userId}</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {user.roles.length ? user.roles.map((role) => <span key={role.roleId} className="inline-flex items-center gap-2 rounded-full bg-[var(--surface-muted)] px-3 py-1.5 text-xs font-bold">
                  {role.name}{role.effectiveTo ? ` · حتى ${new Date(role.effectiveTo).toLocaleDateString('ar-EG')}` : ''}
                  <button aria-label="سحب الدور" className="text-[var(--danger)]" onClick={() => void commands.revokeRole.mutateAsync({ userId: user.userId, roleId: role.roleId })}><Trash2 className="size-3"/></button>
                </span>) : <span className="muted text-sm">بلا دور فعال</span>}
              </div>
            </div>
          </article>)}
        </div>
      </section>
    </> : null}

    {/* ── حوار عرض تفاصيل الدور ── */}
    {selectedRole && data && <DialogOverlay title={`صلاحيات: ${selectedRole.name}`} onClose={() => setViewRole(null)} maxWidth="max-w-4xl">
      <RolePermissionsView role={selectedRole} permissions={data.permissions} />
    </DialogOverlay>}

    {/* ── حوار إنشاء / تعديل دور مخصص ── */}
    {customDraft && data && <DialogOverlay title={customDraft.id ? 'تعديل الدور' : 'إنشاء دور مخصص'} onClose={() => setCustomDraft(null)} maxWidth="max-w-5xl">
      <form className="space-y-5" onSubmit={(e) => void saveRole(e)}>
        <div className="grid gap-4 sm:grid-cols-2">
          <FormInput label="Slug" required value={customDraft.slug} disabled={Boolean(customDraft.id)} onChange={(v) => setCustomDraft({ ...customDraft, slug: v.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}/>
          <FormInput label="الاسم العربي" required value={customDraft.name} onChange={(v) => setCustomDraft({ ...customDraft, name: v })}/>
          <FormInput label="الاسم الإنجليزي" value={customDraft.nameEn} onChange={(v) => setCustomDraft({ ...customDraft, nameEn: v })}/>
          <FormInput label="الوصف" value={customDraft.description} onChange={(v) => setCustomDraft({ ...customDraft, description: v })}/>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-y border-[var(--border)] py-4">
          <h3 className="font-black">الصلاحيات</h3>
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative">
              <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]"/>
              <input className="input pe-9" placeholder="بحث…" value={permSearch} onChange={(e) => setPermSearch(e.target.value)}/>
            </div>
            <select aria-label="تصفية حسب الوحدة" className="input max-w-xs" value={moduleFilter} onChange={(e) => setModuleFilter(e.target.value)}>
              <option value="all">كل الوحدات</option>
              {modules.map((m) => <option key={m} value={m}>{MODULE_AR[m] ?? m}</option>)}
            </select>
            <p className="muted text-xs" aria-live="polite">{Object.keys(customDraft.selected).length} محددة</p>
          </div>
        </div>

        <div className="max-h-[52vh] space-y-2 overflow-y-auto pe-1">
          {data.permissions
            .filter((p) => moduleFilter === 'all' || p.module === moduleFilter)
            .filter((p) => !permSearch || (p.nameAr ?? p.name ?? p.code).includes(permSearch) || p.code.includes(permSearch))
            .map((permission) => {
              const selected = customDraft.selected[permission.id];
              return <article key={permission.id} className="rounded-xl border border-[var(--border)] p-4">
                <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                  <label className="flex items-start gap-3">
                    <input className="mt-1 size-4" type="checkbox" checked={Boolean(selected)} onChange={(e) => {
                      const next = { ...customDraft.selected };
                      if (e.target.checked) next[permission.id] = { scope: permission.allowedScopes[0] ?? 'self', mfa: permission.sensitive, reason: permission.sensitive };
                      else delete next[permission.id];
                      setCustomDraft({ ...customDraft, selected: next });
                    }}/>
                    <span>
                      <strong>{permission.nameAr ?? permission.name}</strong>
                      <span className="muted mt-1 block font-mono text-xs">{permission.code}</span>
                    </span>
                  </label>
                  {selected && <div className="flex flex-wrap gap-2">
                    <select className="input w-52" value={selected.scope} onChange={(e) => setCustomDraft({ ...customDraft, selected: { ...customDraft.selected, [permission.id]: { ...selected, scope: e.target.value } } })}>
                      {(permission.allowedScopes.length ? permission.allowedScopes : scopes).map((s) => <option key={s} value={s}>{SCOPE_AR[s] ?? s}</option>)}
                    </select>
                    <Flag checked={selected.mfa} label="MFA" onChange={(mfa) => setCustomDraft({ ...customDraft, selected: { ...customDraft.selected, [permission.id]: { ...selected, mfa } } })}/>
                    <Flag checked={selected.reason} label="سبب" onChange={(reason) => setCustomDraft({ ...customDraft, selected: { ...customDraft.selected, [permission.id]: { ...selected, reason } } })}/>
                  </div>}
                </div>
              </article>;
            })}
        </div>

        <button className="btn-primary" disabled={commands.upsertRole.isPending || commands.setPermissions.isPending}>
          <Save className="size-4"/>{commands.upsertRole.isPending || commands.setPermissions.isPending ? 'جارٍ الحفظ…' : 'حفظ الدور والصلاحيات'}
        </button>
      </form>
    </DialogOverlay>}
  </div>;
}

// ─── بطاقة قالب الدور ──────────────────────────────────────────────────────
function RoleTemplateCard({ template, permissionCount, assignmentCount, onClick }: { template: RoleTemplate & { dbRole?: AccessAdminCatalog['roles'][number] }; permissionCount: number; assignmentCount: number; onClick: () => void }) {
  const Icon = template.icon;
  return <button type="button" onClick={onClick} className={`card group relative overflow-hidden border-2 p-5 text-start transition-all hover:shadow-lg ${template.borderColor}`}>
    <div className={`absolute start-0 top-0 h-full w-1.5 ${template.bgColor}`} style={{ backgroundColor: 'currentColor' }}/>
    <div className="flex items-start gap-3">
      <div className={`flex size-12 shrink-0 items-center justify-center rounded-xl ${template.bgColor} ${template.color}`}>
        <Icon className="size-6"/>
      </div>
      <div className="min-w-0 flex-1">
        <h3 className="text-base font-black">{template.name}</h3>
        <p className="muted mt-1 line-clamp-2 text-xs leading-relaxed">{template.description}</p>
      </div>
    </div>
    <div className="mt-4 flex items-center justify-between border-t border-[var(--border)] pt-3">
      <div className="flex gap-4">
        <span className="text-xs"><strong className={template.color}>{permissionCount}</strong> <span className="muted">صلاحية</span></span>
        <span className="text-xs"><strong>{assignmentCount}</strong> <span className="muted">مستخدم</span></span>
      </div>
      <ChevronLeft className="size-4 text-[var(--text-muted)] transition-transform group-hover:rtl:translate-x-1 group-hover:ltr:-translate-x-1"/>
    </div>
  </button>;
}

// ─── عرض صلاحيات الدور مجمعة حسب الوحدة ────────────────────────────────────
function RolePermissionsView({ role, permissions }: { role: AccessAdminCatalog['roles'][number]; permissions: AccessAdminCatalog['permissions'] }) {
  const [expandedModules, setExpandedModules] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');

  const grouped = useMemo(() => {
    const map = new Map<string, Array<typeof role.permissions[number] & { nameAr?: string | null; moduleAr?: string | null }>>();
    for (const rp of role.permissions) {
      const fullPerm = permissions.find((p) => p.id === rp.permissionId);
      const module = fullPerm?.module ?? rp.code.split('.')[0];
      const entry = { ...rp, nameAr: fullPerm?.nameAr, moduleAr: fullPerm?.moduleAr };
      if (!search || (entry.nameAr ?? entry.name ?? entry.code).includes(search) || entry.code.includes(search)) {
        if (!map.has(module)) map.set(module, []);
        map.get(module)!.push(entry);
      }
    }
    return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [role.permissions, permissions, search]);

  function toggleModule(module: string) {
    setExpandedModules((prev) => {
      const next = new Set(prev);
      if (next.has(module)) next.delete(module); else next.add(module);
      return next;
    });
  }

  function expandAll() {
    setExpandedModules(new Set(grouped.map(([m]) => m)));
  }

  return <div className="space-y-4">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm"><strong>{role.permissions.length}</strong> صلاحية في <strong>{grouped.length}</strong> وحدة</p>
      <div className="flex items-center gap-2">
        <div className="relative">
          <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]"/>
          <input className="input pe-9" placeholder="بحث…" value={search} onChange={(e) => setSearch(e.target.value)}/>
        </div>
        <button type="button" className="btn-secondary px-3 py-2 text-xs" onClick={expandAll}>فتح الكل</button>
        <button type="button" className="btn-secondary px-3 py-2 text-xs" onClick={() => setExpandedModules(new Set())}>إغلاق الكل</button>
      </div>
    </div>

    <div className="max-h-[60vh] space-y-2 overflow-y-auto">
      {grouped.map(([module, perms]) => {
        const isExpanded = expandedModules.has(module);
        const moduleLabel = perms[0]?.moduleAr ?? MODULE_AR[module] ?? module;
        return <div key={module} className="rounded-xl border border-[var(--border)] overflow-hidden">
          <button type="button" className="flex w-full items-center justify-between bg-[var(--surface-muted)] px-4 py-3 text-start" onClick={() => toggleModule(module)}>
            <div className="flex items-center gap-2">
              <span className="font-bold">{moduleLabel}</span>
              <span className="muted text-xs">({perms.length})</span>
            </div>
            <ChevronDown className={`size-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`}/>
          </button>
          {isExpanded && <div className="divide-y divide-[var(--border)]">
            {perms.map((p) => <div key={p.permissionId} className="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-bold">{p.nameAr ?? p.name}</p>
                <p className="muted font-mono text-xs">{p.code}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                <span className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 text-xs font-bold">{SCOPE_AR[p.scope] ?? p.scope}</span>
                {p.requiresMfa && <span className="rounded-lg bg-amber-50 px-2.5 py-1 text-xs font-bold text-amber-700">MFA</span>}
                {p.requiresReason && <span className="rounded-lg bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700">سبب مطلوب</span>}
              </div>
            </div>)}
          </div>}
        </div>;
      })}
      {grouped.length === 0 && <p className="muted py-8 text-center text-sm">لا توجد صلاحيات مطابقة</p>}
    </div>
  </div>;
}

// ─── مكونات مساعدة ──────────────────────────────────────────────────────────
function FormInput({ label, value, onChange, required, disabled }: { label: string; value: string; onChange: (v: string) => void; required?: boolean; disabled?: boolean }) {
  return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" required={required} disabled={disabled} value={value} onChange={(e) => onChange(e.target.value)}/></label>;
}
function FormSelect({ label, value, onChange, required, children }: { label: string; value: string; onChange: (v: string) => void; required?: boolean; children: ReactNode }) {
  return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><select className="input" required={required} value={value} onChange={(e) => onChange(e.target.value)}><option value="">اختر…</option>{children}</select></label>;
}
function Flag({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return <label className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs font-bold"><input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)}/>{label}</label>;
}
