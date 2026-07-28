import { AlertTriangle, Briefcase, Check, ChevronDown, ChevronLeft, Crown, KeyRound, Pencil, Plus, Save, Scale, Search, Shield, ShieldAlert, ShieldCheck, Trash2, UserPlus, Users, Users2, X } from 'lucide-react';
import { useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAccessAdminCatalog, useAccessCommands } from './useAdminOperations';
import type { AccessAdminCatalog } from '@ahla/shared-contracts';
import { env } from '../../core/env';
import { safeErrorMessage } from '../../core/errorMapper';

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

const MODULE_ICON: Record<string, string> = {
  people: '👥', organization: '🏢', access: '🔐', attendance: '⏰', live_location: '📍',
  requests: '📋', operations: '⚙️', assignments: '📌', performance: '📊', documents: '📄',
  relations: '⚖️', communications: '📢', reports: '📈', system: '🖥️',
};

const RISK_CONFIG = {
  normal: { label: 'عادية', className: 'bg-emerald-50 text-emerald-700' },
  sensitive: { label: 'حساسة', className: 'bg-amber-50 text-amber-700' },
  critical: { label: 'حرجة', className: 'bg-red-50 text-red-700' },
} as const;

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

// ─── النوع الداخلي لمسودة الدور ─────────────────────────────────────────────
type RoleDraft = {
  id?: string | null;
  slug: string;
  name: string;
  nameEn: string;
  description: string;
  fullAccess: boolean;
  isSystem: boolean;
  selected: Record<string, { scope: string; mfa: boolean; reason: boolean }>;
};

const scopes = ['self', 'direct_reports', 'management_descendants', 'team', 'department', 'branch', 'organization', 'assigned_cases', 'workflow_inbox'];

// ─── المكون الرئيسي ────────────────────────────────────────────────────────
export function AccessPage() {
  const query = useAccessAdminCatalog();
  const commands = useAccessCommands();
  const [editDraft, setEditDraft] = useState<RoleDraft | null>(null);
  const [assignment, setAssignment] = useState({ userId: '', roleId: '', effectiveTo: '' });
  const [saveError, setSaveError] = useState('');
  const data = query.data;

  // مطابقة قوالب الأدوار مع البيانات الحقيقية
  const templateRoles = useMemo(() => {
    if (!data) return [];
    return ROLE_TEMPLATES.map((tpl) => {
      const dbRole = data.roles.find((r) => r.slug === tpl.slug);
      return { ...tpl, dbRole };
    });
  }, [data]);

  // فتح حوار التعديل لدور (نظامي أو مخصص)
  function openEditor(roleId?: string) {
    setSaveError('');
    if (roleId && data) {
      const role = data.roles.find((r) => r.id === roleId || r.slug === roleId);
      if (!role) return;
      setEditDraft({
        id: role.id, slug: role.slug, name: role.name, nameEn: role.nameEn ?? '',
        description: role.description ?? '', fullAccess: role.fullAccess, isSystem: role.system,
        selected: Object.fromEntries(role.permissions.map((p) => [p.permissionId, { scope: p.scope, mfa: p.requiresMfa, reason: p.requiresReason }])),
      });
    } else {
      setEditDraft({ slug: '', name: '', nameEn: '', description: '', fullAccess: false, isSystem: false, selected: {} });
    }
  }

  async function saveRole(event: FormEvent) {
    event.preventDefault();
    if (!editDraft) return;
    setSaveError('');
    try {
      const result = await commands.upsertRole.mutateAsync({ id: editDraft.id, slug: editDraft.slug, name: editDraft.name, nameEn: editDraft.nameEn || null, description: editDraft.description || null, fullAccess: editDraft.fullAccess });
      const roleId = String((result as { id?: string })?.id ?? editDraft.id ?? '');
      if (roleId) {
        await commands.setPermissions.mutateAsync({
          roleId,
          items: Object.entries(editDraft.selected).map(([permission_id, v]) => ({ permission_id, scope: v.scope, requires_mfa: v.mfa, requires_reason: v.reason })),
        });
      }
      setEditDraft(null);
    } catch (err) {
      setSaveError(safeErrorMessage(err));
    }
  }

  async function assign(event: FormEvent) {
    event.preventDefault();
    await commands.assignRole.mutateAsync({ userId: assignment.userId, roleId: assignment.roleId, effectiveTo: assignment.effectiveTo ? new Date(`${assignment.effectiveTo}T23:59:59`).toISOString() : null });
    setAssignment({ userId: '', roleId: '', effectiveTo: '' });
  }

  return <div className="space-y-6">
    <PageHeader title="الأدوار والصلاحيات" description="إدارة أدوار المستخدمين وصلاحياتهم — اختر دوراً للتعديل أو أنشئ دوراً مخصصاً." actions={env.appEnvironment !== 'production' ? <button className="btn-primary" onClick={() => openEditor()}><Plus className="size-4"/>دور مخصص</button> : undefined}/>

    {query.isError ? <ErrorState title="تعذر تحميل الصلاحيات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} /> : query.isLoading && !data ? <MetricSkeletonRow /> : null}

    {data ? <>
      {/* ── الإحصائيات ── */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="الأدوار" value={data.roles.length} icon={ShieldCheck}/>
        <MetricCard label="الصلاحيات" value={data.permissions.length} icon={KeyRound}/>
        <MetricCard label="المستخدمون" value={data.users.length} icon={Users}/>
        <MetricCard label="الصلاحيات الحساسة" value={data.permissions.filter((p) => p.sensitive).length} icon={ShieldAlert}/>
      </section>

      {/* ── بطاقات قوالب الأدوار ── */}
      <section>
        <div className="mb-4">
          <h2 className="text-lg font-black">قوالب الأدوار المعتمدة</h2>
          <p className="muted mt-1 text-sm">اضغط على قالب لعرض وتعديل صلاحياته.</p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {templateRoles.map((tpl) => <RoleTemplateCard key={tpl.slug} template={tpl} permissionCount={tpl.dbRole?.permissions.length ?? 0} assignmentCount={tpl.dbRole?.assignments ?? 0} onClick={() => openEditor(tpl.dbRole?.id ?? tpl.slug)}/>)}
        </div>
      </section>

      {/* ── الأدوار الأخرى (غير القوالب) ── */}
      {data.roles.filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug)).length > 0 && <section className="card overflow-hidden">
        <div className="border-b border-[var(--border)] p-5">
          <h2 className="font-black">أدوار أخرى</h2>
          <p className="muted mt-1 text-sm">أدوار نظامية أو مخصصة غير مدرجة في القوالب.</p>
        </div>
        <div className="divide-y divide-[var(--border)]">
          {data.roles.filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug)).map((role) => <div key={role.id} className="flex items-center justify-between p-4">
            <div>
              <p className="font-bold">{role.name}</p>
              <p className="muted font-mono text-xs">{role.slug}</p>
            </div>
            <div className="flex items-center gap-3">
              <span className="muted text-xs">{role.permissions.length} صلاحية · {role.assignments} مستخدم</span>
              <button className="btn-secondary flex items-center gap-1.5 px-3 py-1.5 text-xs" onClick={() => openEditor(role.id)}><Pencil className="size-3"/>عرض وتعديل</button>
            </div>
          </div>)}
        </div>
      </section>}

      {/* ── إسناد دور ── */}
      <section className="card p-5">
        <div className="mb-5">
          <h2 className="font-black">إسناد دور</h2>
          <p className="muted mt-1 text-sm">يمكن جعل الإسناد مؤقتًا — يُسحب تلقائيًا بعد تاريخ الانتهاء.</p>
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
        {commands.revokeRole.isError && <div className="p-5 pb-0"><ErrorBanner message={`تعذر سحب الدور: ${safeErrorMessage(commands.revokeRole.error)}`} /></div>}
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

    {/* ── حوار تعديل الدور ── */}
    {editDraft && data && <RoleEditorDialog draft={editDraft} permissions={data.permissions} onDraftChange={setEditDraft} onSave={saveRole} onClose={() => setEditDraft(null)} saving={commands.upsertRole.isPending || commands.setPermissions.isPending} error={saveError}/>}
  </div>;
}

// ─── بطاقة قالب الدور ──────────────────────────────────────────────────────
function RoleTemplateCard({ template, permissionCount, assignmentCount, onClick }: { template: RoleTemplate & { dbRole?: AccessAdminCatalog['roles'][number] }; permissionCount: number; assignmentCount: number; onClick: () => void }) {
  const Icon = template.icon;
  const isFullAccess = template.dbRole?.fullAccess === true;
  return <button type="button" onClick={onClick} className={`card group relative overflow-hidden border-2 p-5 text-right transition-all hover:shadow-lg ${template.borderColor}`}>
    <div className={`absolute left-0 top-0 h-full w-1.5 ${template.bgColor}`} style={{ backgroundColor: 'currentColor' }}/>
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
      <div className="flex items-center gap-3">
        {isFullAccess
          ? <span className="inline-flex items-center gap-1 rounded-lg bg-amber-100 px-2.5 py-1 text-xs font-black text-amber-800">✦ وصول كامل</span>
          : <span className="text-xs"><strong className={template.color}>{permissionCount}</strong> <span className="muted">صلاحية</span></span>}
        <span className="text-xs"><strong>{assignmentCount}</strong> <span className="muted">مستخدم</span></span>
      </div>
      <ChevronLeft className="size-4 text-[var(--text-muted)] transition-transform group-hover:-translate-x-1"/>
    </div>
  </button>;
}

// ─── حوار تعديل الدور (موحّد: عرض + تعديل) ─────────────────────────────────
function RoleEditorDialog({ draft, permissions, onDraftChange, onSave, onClose, saving, error }: {
  draft: RoleDraft;
  permissions: AccessAdminCatalog['permissions'];
  onDraftChange: (d: RoleDraft) => void;
  onSave: (e: FormEvent) => void;
  onClose: () => void;
  saving: boolean;
  error: string;
}) {
  const [moduleFilter, setModuleFilter] = useState('all');
  const [permSearch, setPermSearch] = useState('');
  const [expandedModules, setExpandedModules] = useState<Set<string>>(new Set());

  const modules = useMemo(() => [...new Set(permissions.map((p) => p.module))].sort(), [permissions]);

  // تجميع الصلاحيات حسب الوحدة مع تطبيق الفلاتر
  const grouped = useMemo(() => {
    const map = new Map<string, AccessAdminCatalog['permissions']>();
    for (const p of permissions) {
      if (moduleFilter !== 'all' && p.module !== moduleFilter) continue;
      const nameAr = p.nameAr ?? p.name ?? p.code;
      if (permSearch && !nameAr.includes(permSearch) && !p.code.includes(permSearch)) continue;
      if (!map.has(p.module)) map.set(p.module, []);
      map.get(p.module)!.push(p);
    }
    return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [permissions, moduleFilter, permSearch]);

  const selectedCount = Object.keys(draft.selected).length;
  const totalVisible = grouped.reduce((sum, [, perms]) => sum + perms.length, 0);

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

  // تحديد/إلغاء كل صلاحيات وحدة
  function toggleModuleAll(module: string, perms: AccessAdminCatalog['permissions']) {
    const allSelected = perms.every((p) => draft.selected[p.id]);
    const next = { ...draft.selected };
    if (allSelected) {
      for (const p of perms) delete next[p.id];
    } else {
      for (const p of perms) {
        if (!next[p.id]) next[p.id] = { scope: p.allowedScopes[0] ?? 'self', mfa: p.sensitive, reason: p.sensitive };
      }
    }
    onDraftChange({ ...draft, selected: next });
  }

  return <DialogOverlay title={draft.id ? `تعديل الدور: ${draft.name}` : 'إنشاء دور مخصص'} onClose={onClose} maxWidth="max-w-6xl">
    <form className="space-y-5" onSubmit={onSave}>
      {/* ── معلومات الدور ── */}
      <div className="rounded-xl border border-[var(--border)] p-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <FormInput label="Slug (معرّف)" required value={draft.slug} disabled={Boolean(draft.id)} onChange={(v) => onDraftChange({ ...draft, slug: v.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}/>
          <FormInput label="الاسم العربي" required value={draft.name} disabled={draft.isSystem} onChange={(v) => onDraftChange({ ...draft, name: v })}/>
          <FormInput label="الاسم الإنجليزي" value={draft.nameEn} disabled={draft.isSystem} onChange={(v) => onDraftChange({ ...draft, nameEn: v })}/>
          <FormInput label="الوصف" value={draft.description} disabled={draft.isSystem} onChange={(v) => onDraftChange({ ...draft, description: v })}/>
        </div>
        {draft.isSystem && <p className="muted mt-3 flex items-center gap-1.5 text-xs"><Shield className="size-3.5"/>دور نظامي — يمكن تعديل الصلاحيات فقط.</p>}
        {draft.fullAccess && <p className="mt-3 flex items-center gap-1.5 text-xs font-bold text-amber-700"><Crown className="size-3.5"/>وصول كامل — جميع الصلاحيات مفعّلة تلقائياً.</p>}
      </div>

      {/* ── شريط الأدوات ── */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-[var(--surface-muted)] px-4 py-3">
        <div className="flex items-center gap-3">
          <h3 className="font-black">الصلاحيات</h3>
          <span className="rounded-lg bg-[var(--primary)] px-2.5 py-1 text-xs font-bold text-white">{selectedCount} / {permissions.length}</span>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <Search className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]"/>
            <input className="input pr-9 text-sm" placeholder="بحث بالعربي أو الكود…" value={permSearch} onChange={(e) => setPermSearch(e.target.value)}/>
          </div>
          <select aria-label="تصفية حسب الوحدة" className="input max-w-[200px] text-sm" value={moduleFilter} onChange={(e) => setModuleFilter(e.target.value)}>
            <option value="all">كل الوحدات ({permissions.length})</option>
            {modules.map((m) => <option key={m} value={m}>{MODULE_AR[m] ?? m}</option>)}
          </select>
          <button type="button" className="btn-secondary px-2.5 py-1.5 text-xs" onClick={expandAll}>فتح الكل</button>
          <button type="button" className="btn-secondary px-2.5 py-1.5 text-xs" onClick={() => setExpandedModules(new Set())}>إغلاق الكل</button>
        </div>
      </div>

      {/* ── قائمة الصلاحيات مجمعة حسب الوحدة ── */}
      <div className="max-h-[55vh] space-y-3 overflow-y-auto pl-1">
        {grouped.map(([module, perms]) => {
          const isExpanded = expandedModules.has(module);
          const moduleLabel = perms[0]?.moduleAr ?? MODULE_AR[module] ?? module;
          const moduleIcon = MODULE_ICON[module] ?? '📦';
          const selectedInModule = perms.filter((p) => draft.selected[p.id]).length;
          const allSelected = perms.every((p) => draft.selected[p.id]);
          return <div key={module} className="overflow-hidden rounded-xl border border-[var(--border)]">
            {/* رأس الوحدة */}
            <div className="flex items-center bg-[var(--surface-muted)]">
              <button type="button" className="flex min-w-0 flex-1 items-center gap-2.5 px-4 py-3 text-right" onClick={() => toggleModule(module)}>
                <span className="text-lg">{moduleIcon}</span>
                <span className="font-bold">{moduleLabel}</span>
                <span className="muted text-xs">({selectedInModule}/{perms.length})</span>
                <ChevronDown className={`mr-auto size-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`}/>
              </button>
              {!draft.fullAccess && <button type="button" className={`ml-1 mr-3 rounded-lg px-2.5 py-1 text-xs font-bold transition-colors ${allSelected ? 'bg-red-50 text-red-600 hover:bg-red-100' : 'bg-emerald-50 text-emerald-600 hover:bg-emerald-100'}`} onClick={() => toggleModuleAll(module, perms)}>
                {allSelected ? <span className="flex items-center gap-1"><X className="size-3"/>إلغاء الكل</span> : <span className="flex items-center gap-1"><Check className="size-3"/>تحديد الكل</span>}
              </button>}
            </div>
            {/* صلاحيات الوحدة */}
            {isExpanded && <div className="divide-y divide-[var(--border)]">
              {perms.map((permission) => {
                const sel = draft.selected[permission.id];
                const nameAr = permission.nameAr ?? permission.name;
                const risk = RISK_CONFIG[permission.riskLevel as keyof typeof RISK_CONFIG] ?? RISK_CONFIG.normal;
                return <div key={permission.id} className={`px-4 py-3 transition-colors ${sel ? 'bg-blue-50/30' : ''}`}>
                  <div className="flex flex-col gap-2 lg:flex-row lg:items-center lg:justify-between">
                    <label className="flex items-start gap-3">
                      {!draft.fullAccess && <input className="mt-1 size-4 accent-[var(--primary)]" type="checkbox" checked={Boolean(sel)} onChange={(e) => {
                        const next = { ...draft.selected };
                        if (e.target.checked) next[permission.id] = { scope: permission.allowedScopes[0] ?? 'self', mfa: permission.sensitive, reason: permission.sensitive };
                        else delete next[permission.id];
                        onDraftChange({ ...draft, selected: next });
                      }}/>}
                      <span className="min-w-0">
                        <span className="flex flex-wrap items-center gap-2">
                          <strong className="text-sm">{nameAr}</strong>
                          <span className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-bold ${risk.className}`}>{risk.label}</span>
                          {permission.sensitive && <span title="صلاحية حساسة"><AlertTriangle className="size-3.5 text-amber-500"/></span>}
                        </span>
                        <span className="muted mt-0.5 block font-mono text-xs leading-relaxed" dir="ltr">{permission.code}</span>
                      </span>
                    </label>
                    {/* أدوات التحكم: النطاق + MFA + سبب */}
                    {sel && !draft.fullAccess && <div className="flex flex-wrap items-center gap-2 pr-7 lg:pr-0">
                      <select className="input w-44 text-xs" value={sel.scope} onChange={(e) => onDraftChange({ ...draft, selected: { ...draft.selected, [permission.id]: { ...sel, scope: e.target.value } } })}>
                        {(permission.allowedScopes.length ? permission.allowedScopes : scopes).map((s) => <option key={s} value={s}>{SCOPE_AR[s] ?? s}</option>)}
                      </select>
                      <Flag checked={sel.mfa} label="MFA مطلوب" onChange={(mfa) => onDraftChange({ ...draft, selected: { ...draft.selected, [permission.id]: { ...sel, mfa } } })}/>
                      <Flag checked={sel.reason} label="سبب مطلوب" onChange={(reason) => onDraftChange({ ...draft, selected: { ...draft.selected, [permission.id]: { ...sel, reason } } })}/>
                    </div>}
                    {/* وضع full-access: عرض النطاق فقط */}
                    {sel && draft.fullAccess && <div className="flex flex-wrap gap-2 pr-7 lg:pr-0">
                      <span className="rounded-lg bg-[var(--surface-muted)] px-2.5 py-1 text-xs font-bold">{SCOPE_AR[sel.scope] ?? sel.scope}</span>
                      {sel.mfa && <span className="rounded-lg bg-amber-50 px-2.5 py-1 text-xs font-bold text-amber-700">MFA</span>}
                      {sel.reason && <span className="rounded-lg bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700">سبب مطلوب</span>}
                    </div>}
                  </div>
                </div>;
              })}
            </div>}
          </div>;
        })}
        {grouped.length === 0 && <p className="muted py-8 text-center text-sm">لا توجد صلاحيات مطابقة للبحث</p>}
      </div>

      {/* ── شريط الحفظ ── */}
      {error && <ErrorBanner message={error}/>}
      {!draft.fullAccess && <div className="flex items-center justify-between gap-4 rounded-xl border border-[var(--border)] bg-[var(--surface-muted)] px-4 py-3">
        <p className="text-sm"><strong>{selectedCount}</strong> صلاحية محددة من أصل <strong>{totalVisible}</strong></p>
        <button className="btn-primary" disabled={saving}>
          <Save className="size-4"/>{saving ? 'جارٍ الحفظ…' : 'حفظ الدور والصلاحيات'}
        </button>
      </div>}
    </form>
  </DialogOverlay>;
}

// ─── مكونات مساعدة ──────────────────────────────────────────────────────────
function FormInput({ label, value, onChange, required, disabled }: { label: string; value: string; onChange: (v: string) => void; required?: boolean; disabled?: boolean }) {
  return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><input className="input" required={required} disabled={disabled} value={value} onChange={(e) => onChange(e.target.value)}/></label>;
}
function FormSelect({ label, value, onChange, required, children }: { label: string; value: string; onChange: (v: string) => void; required?: boolean; children: ReactNode }) {
  return <label><span className="mb-1.5 block text-sm font-bold">{label}</span><select className="input" required={required} value={value} onChange={(e) => onChange(e.target.value)}><option value="">اختر…</option>{children}</select></label>;
}
function Flag({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return <label className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs font-bold cursor-pointer hover:bg-[var(--border)] transition-colors"><input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)}/>{label}</label>;
}
