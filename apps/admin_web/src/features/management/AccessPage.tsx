import {
  Briefcase,
  ChevronDown,
  ChevronLeft,
  Crown,
  KeyRound,
  Plus,
  Save,
  Scale,
  Search,
  Shield,
  ShieldCheck,
  Trash2,
  UserPlus,
  Users,
  Users2,
} from 'lucide-react';
import { useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { MetricCard } from '../../ui/MetricCard';
import { MetricSkeletonRow } from '../../ui/Skeletons';
import { PageHeader } from '../../ui/PageHeader';
import { UserAvatar } from '../../ui/UserAvatar';
import { useAccessAdminCatalog, useAccessCommands } from './useAdminOperations';
import type { AccessAdminCatalog } from '@ahla/shared-contracts';
import { safeErrorMessage } from '../../core/errorMapper';
import { useAuth } from '../auth/AuthProvider';

// ─── ترجمة النطاقات ────────────────────────────────────────────────────────
const SCOPE_AR: Record<string, string> = {
  self: 'الذات',
  direct_reports: 'المرؤوسين المباشرين',
  management_descendants: 'الفريق الموسع',
  selected_employees: 'موظفين محددين',
  team: 'الفريق',
  department: 'القسم',
  selected_departments: 'أقسام محددة',
  branch: 'الفرع',
  selected_branches: 'فروع محددة',
  organization: 'المنظمة',
  assigned_cases: 'القضايا المسندة',
  workflow_inbox: 'صندوق الوارد',
  records_created_by_user: 'السجلات الخاصة',
  archive_readonly: 'الأرشيف (قراءة)',
};

const MODULE_AR: Record<string, string> = {
  access: 'إدارة الوصول',
  assets: 'الأصول',
  assignments: 'التكليفات',
  attendance: 'الحضور والانصراف',
  audit: 'التدقيق',
  automation: 'الأتمتة',
  comms: 'التواصل',
  communications: 'الاتصالات',
  disputes: 'لجنة الخلافات',
  documents: 'المستندات',
  engagement: 'المشاركة',
  governance: 'الحوكمة',
  holidays: 'العطلات الرسمية',
  kpi: 'مؤشرات الأداء',
  learning: 'التعلم والتطوير',
  live_location: 'الموقع المباشر',
  location: 'الموقع',
  meetings: 'الاجتماعات',
  offboarding: 'إنهاء الخدمة',
  onboarding: 'التهيئة',
  operations: 'العمليات',
  organization: 'الهيكل التنظيمي',
  payroll: 'الرواتب',
  people: 'شؤون الموظفين',
  performance: 'الأداء',
  posts: 'المنشورات',
  privacy: 'الخصوصية',
  projects: 'المشاريع',
  quality: 'الجودة',
  recruitment: 'التوظيف',
  relations: 'علاقات الموظفين',
  release: 'الإصدارات',
  reports: 'التقارير',
  requests: 'الطلبات',
  risk: 'المخاطر',
  security: 'الأمان',
  service: 'الخدمات',
  strategy: 'الاستراتيجية',
  system: 'النظام',
  wellbeing: 'الرفاهية',
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
  {
    slug: 'admin',
    name: 'أدمن',
    description: 'السكرتير التنفيذي والأدمن الرئيسي — جميع صلاحيات لوحة الإدارة',
    icon: Shield,
    color: 'text-red-600',
    bgColor: 'bg-red-50',
    borderColor: 'border-red-200',
  },
  {
    slug: 'hr-manager',
    name: 'الموارد البشرية',
    description: 'إدارة كل ما يخص الموظفين — سجلات، حضور، طلبات، مستندات، أداء',
    icon: Users2,
    color: 'text-blue-600',
    bgColor: 'bg-blue-50',
    borderColor: 'border-blue-200',
  },
  {
    slug: 'executive',
    name: 'المدير التنفيذي',
    description: 'الاطلاع على جميع التقارير، إرسال واستقبال مواقع الموظفين، اتخاذ القرارات',
    icon: Crown,
    color: 'text-amber-600',
    bgColor: 'bg-amber-50',
    borderColor: 'border-amber-200',
  },
  {
    slug: 'operations-manager-1',
    name: 'مدير تشغيل',
    description: 'تحت المدير التنفيذي — قبول طلبات الإجازة والمأموريات عند غياب المدير المباشر',
    icon: Briefcase,
    color: 'text-emerald-600',
    bgColor: 'bg-emerald-50',
    borderColor: 'border-emerald-200',
  },
  {
    slug: 'committee-member',
    name: 'عضو لجنة الخلافات',
    description: 'الاطلاع على مشاكل الموظفين واتخاذ إجراءات بشأنها',
    icon: Scale,
    color: 'text-purple-600',
    bgColor: 'bg-purple-50',
    borderColor: 'border-purple-200',
  },
  {
    slug: 'direct-manager',
    name: 'مدير',
    description: 'قبول أو رفض طلبات الإجازة والمأموريات، وتقييم الموظفين المباشرين',
    icon: Users,
    color: 'text-teal-600',
    bgColor: 'bg-teal-50',
    borderColor: 'border-teal-200',
  },
  {
    slug: 'employee',
    name: 'موظف',
    description: 'الخدمة الذاتية — تسجيل حضور، تقديم طلبات، عرض البيانات الشخصية',
    icon: ShieldCheck,
    color: 'text-slate-600',
    bgColor: 'bg-slate-50',
    borderColor: 'border-slate-200',
  },
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

type AccessCommands = ReturnType<typeof useAccessCommands>;

// ─── المكون الرئيسي ────────────────────────────────────────────────────────
export function AccessPage() {
  const auth = useAuth();
  const query = useAccessAdminCatalog();
  const commands = useAccessCommands();
  const [viewRole, setViewRole] = useState<string | null>(null);
  const [customDraft, setCustomDraft] = useState<RoleDraft | null>(null);
  const [assignment, setAssignment] = useState({ userId: '', roleId: '', effectiveTo: '' });
  const data = query.data;

  // المستخدم الحالي يملك صلاحية منح الوصول الكامل (أدوار is_full_access)؟
  const canGrantFullAccess = Boolean(auth.access?.permissions.includes('*'));

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
        id: role.id,
        slug: role.slug,
        name: role.name,
        nameEn: role.nameEn ?? '',
        description: role.description ?? '',
        fullAccess: role.fullAccess,
        selected: Object.fromEntries(role.permissions.map((p) => [p.permissionId, { scope: p.scope, mfa: p.requiresMfa, reason: p.requiresReason }])),
      });
    } else {
      setCustomDraft({ slug: '', name: '', nameEn: '', description: '', fullAccess: false, selected: {} });
    }
  }

  async function assign(event: FormEvent) {
    event.preventDefault();
    try {
      await commands.assignRole.mutateAsync({
        userId: assignment.userId,
        roleId: assignment.roleId,
        effectiveTo: assignment.effectiveTo ? new Date(`${assignment.effectiveTo}T23:59:59`).toISOString() : null,
      });
      setAssignment({ userId: '', roleId: '', effectiveTo: '' });
    } catch {
      /* mutation error surfaced via mutation.isError state */
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="الأدوار والصلاحيات"
        description="اضغط على بطاقة دور لتعديل صلاحياته وإدارة المستخدمين المسندين، أو أنشئ دوراً مخصصاً."
        actions={
          <button className="btn-primary" onClick={() => openCustomDraft()}>
            <Plus className="size-4" aria-hidden="true" />
            دور مخصص
          </button>
        }
      />

      {query.isError ? (
        <ErrorState title="تعذر تحميل الصلاحيات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading && !data ? (
        <MetricSkeletonRow />
      ) : null}

      {data ? (
        <>
          {/* ── الإحصائيات ── */}
          <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard label="الأدوار" value={data.roles.length} icon={ShieldCheck} />
            <MetricCard label="الصلاحيات" value={data.permissions.length} icon={KeyRound} />
            <MetricCard label="المستخدمون" value={data.users.length} icon={Users} />
            <MetricCard label="الصلاحيات الحساسة" value={data.permissions.filter((p) => p.sensitive).length} icon={ShieldCheck} />
          </section>

          {/* ── بطاقات قوالب الأدوار ── */}
          <section>
            <div className="mb-4">
              <h2 className="text-lg font-black">قوالب الأدوار المعتمدة</h2>
              <p className="muted mt-1 text-sm">اضغط على بطاقة لتعديل صلاحياتها وإسناد المستخدمين.</p>
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {templateRoles.map((tpl) => (
                <RoleTemplateCard
                  key={tpl.slug}
                  template={tpl}
                  permissionCount={tpl.dbRole?.permissions.length ?? 0}
                  assignmentCount={tpl.dbRole?.assignments ?? 0}
                  onClick={() => setViewRole(tpl.slug)}
                />
              ))}
            </div>
          </section>

          {/* ── الأدوار الأخرى (غير القوالب المعتمدة) ── */}
          {data.roles.filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug)).length > 0 && (
            <section className="card overflow-hidden">
              <div className="border-b border-[var(--border)] p-5">
                <h2 className="font-black">أدوار أخرى</h2>
                <p className="muted mt-1 text-sm">أدوار نظامية أو مخصصة غير مدرجة في القوالب المعتمدة.</p>
              </div>
              <div className="divide-y divide-[var(--border)]">
                {data.roles
                  .filter((r) => !ROLE_TEMPLATES.some((t) => t.slug === r.slug))
                  .map((role) => (
                    <div key={role.id} className="flex items-center justify-between p-4">
                      <div>
                        <p className="font-bold">{role.name}</p>
                        <p className="muted font-mono text-xs">{role.slug}</p>
                      </div>
                      <div className="flex items-center gap-3">
                        <span className="muted text-xs">
                          {role.permissions.length} صلاحية · {role.assignments} مستخدم
                        </span>
                        <button className="btn-secondary px-3 py-1.5 text-xs" onClick={() => setViewRole(role.id)}>
                          إدارة
                        </button>
                        {!role.system && (
                          <button className="btn-secondary px-3 py-1.5 text-xs" onClick={() => openCustomDraft(role.id)}>
                            تعديل
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
              </div>
            </section>
          )}

          {/* ── إسناد دور ── */}
          <section className="card p-5">
            <div className="mb-5">
              <h2 className="font-black">إسناد دور</h2>
              <p className="muted mt-1 text-sm">يمكن جعل الإسناد مؤقتًا، ويُسحب تلقائيًا بعد تاريخ الانتهاء.</p>
            </div>
            <form className="grid gap-4 md:grid-cols-[1.2fr_1fr_1fr_auto]" onSubmit={(e) => void assign(e)}>
              <FormSelect label="المستخدم" required value={assignment.userId} onChange={(v) => setAssignment({ ...assignment, userId: v })}>
                {data.users.map((u) => (
                  <option key={u.userId} value={u.userId}>
                    {u.name}
                    {u.employeeCode ? ` · ${u.employeeCode}` : ''}
                  </option>
                ))}
              </FormSelect>
              <FormSelect label="الدور" required value={assignment.roleId} onChange={(v) => setAssignment({ ...assignment, roleId: v })}>
                {data.roles.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name}
                    {r.fullAccess ? ' · وصول كامل' : ''}
                  </option>
                ))}
              </FormSelect>
              {(() => {
                const chosen = data.roles.find((r) => r.id === assignment.roleId);
                if (chosen?.fullAccess && !canGrantFullAccess) {
                  return (
                    <p className="muted self-end text-xs text-[var(--danger)]">منح الوصول الكامل يتطلب حساباً بـ super-admin — جُهّز من المالك.</p>
                  );
                }
                return null;
              })()}
              <label>
                <span className="mb-1.5 block text-sm font-bold">تاريخ الانتهاء</span>
                <input
                  className="input"
                  type="date"
                  value={assignment.effectiveTo}
                  onChange={(e) => setAssignment({ ...assignment, effectiveTo: e.target.value })}
                />
              </label>
              <button className="btn-primary self-end" disabled={commands.assignRole.isPending}>
                <UserPlus className="size-4" aria-hidden="true" />
                {commands.assignRole.isPending ? 'جارٍ الإسناد…' : 'إسناد'}
              </button>
            </form>
          </section>

          {/* ── إسنادات المستخدمين ── */}
          <section className="card overflow-hidden">
            <div className="border-b border-[var(--border)] p-5">
              <h2 className="font-black">إسنادات المستخدمين</h2>
            </div>
            {commands.revokeRole.isError && (
              <div className="p-5 pb-0">
                <ErrorBanner message={`تعذر سحب الدور: ${safeErrorMessage(commands.revokeRole.error)}`} />
              </div>
            )}
            {commands.assignRole.isError && (
              <div className="p-5 pb-0">
                <ErrorBanner message={`تعذر إسناد الدور: ${safeErrorMessage(commands.assignRole.error)}`} />
              </div>
            )}
            <div className="divide-y divide-[var(--border)]">
              {data.users.map((user) => (
                <article key={user.userId} className="p-5">
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div className="flex items-center gap-2">
                      <UserAvatar displayName={user.name} size="sm" />
                      <div>
                        <p className="font-black">{user.name}</p>
                        <p className="muted text-xs">{user.employeeCode ?? user.userId}</p>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {user.roles.length ? (
                        user.roles.map((role) => (
                          <span
                            key={role.roleId}
                            className="inline-flex items-center gap-2 rounded-full bg-[var(--surface-muted)] px-3 py-1.5 text-xs font-bold"
                          >
                            {role.name}
                            {role.effectiveTo ? ` · حتى ${new Date(role.effectiveTo).toLocaleDateString('ar-EG')}` : ''}
                            <button
                              aria-label="سحب الدور"
                              className="text-[var(--danger)]"
                              onClick={() =>
                                commands.revokeRole.mutate({ userId: user.userId, roleId: role.roleId })
                              }
                            >
                              <Trash2 className="size-3" aria-hidden="true" />
                            </button>
                          </span>
                        ))
                      ) : (
                        <span className="muted text-sm">بلا دور فعال</span>
                      )}
                    </div>
                  </div>
                </article>
              ))}
            </div>
          </section>
        </>
      ) : null}

      {/* ── حوار إدارة الدور (صلاحيات + مستخدمون) ── */}
      {selectedRole && data && (
        <RoleManagementDialog role={selectedRole} data={data} commands={commands} canGrantFullAccess={canGrantFullAccess} onClose={() => setViewRole(null)} />
      )}

      {/* ── حوار إنشاء / تعديل دور مخصص ── */}
      {customDraft && data && (
        <CustomRoleDraftDialog
          initialDraft={customDraft}
          data={data}
          commands={commands}
          canGrantFullAccess={canGrantFullAccess}
          onClose={() => setCustomDraft(null)}
        />
      )}
    </div>
  );
}

// ─── بطاقة قالب الدور ──────────────────────────────────────────────────────
function RoleTemplateCard({
  template,
  permissionCount,
  assignmentCount,
  onClick,
}: {
  template: RoleTemplate & { dbRole?: AccessAdminCatalog['roles'][number] };
  permissionCount: number;
  assignmentCount: number;
  onClick: () => void;
}) {
  const Icon = template.icon;
  return (
    <button
      type="button"
      onClick={onClick}
      className={`card group relative overflow-hidden border-2 p-5 text-start transition-all hover:shadow-lg ${template.borderColor}`}
    >
      <div className={`absolute start-0 top-0 h-full w-1.5 ${template.bgColor}`} style={{ backgroundColor: 'currentColor' }} />
      <div className="flex items-start gap-3">
        <div className={`flex size-12 shrink-0 items-center justify-center rounded-xl ${template.bgColor} ${template.color}`}>
          <Icon className="size-6" aria-hidden="true" />
        </div>
        <div className="min-w-0 flex-1">
          <h3 className="text-base font-black">{template.name}</h3>
          <p className="muted mt-1 line-clamp-2 text-xs leading-relaxed">{template.description}</p>
        </div>
      </div>
      <div className="mt-4 flex items-center justify-between border-t border-[var(--border)] pt-3">
        <div className="flex gap-4">
          <span className="text-xs">
            <strong className={template.color}>{permissionCount}</strong> <span className="muted">صلاحية</span>
          </span>
          <span className="text-xs">
            <strong>{assignmentCount}</strong> <span className="muted">مستخدم</span>
          </span>
        </div>
        <ChevronLeft
          className="size-4 text-[var(--text-muted)] transition-transform group-hover:rtl:translate-x-1 group-hover:ltr:-translate-x-1"
          aria-hidden="true"
        />
      </div>
    </button>
  );
}

// ─── حوار إدارة الدور — صلاحيات + مستخدمون ──────────────────────────────────
type PermDraft = Record<string, { scope: string; mfa: boolean; reason: boolean }>;

function RoleManagementDialog({
  role,
  data,
  commands,
  canGrantFullAccess,
  onClose,
}: {
  role: AccessAdminCatalog['roles'][number];
  data: AccessAdminCatalog;
  commands: AccessCommands;
  canGrantFullAccess: boolean;
  onClose: () => void;
}) {
  const [tab, setTab] = useState<'perms' | 'users'>('perms');
  const [search, setSearch] = useState('');
  const [moduleFilter, setModuleFilter] = useState('all');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [assignUserId, setAssignUserId] = useState('');
  const [expandedModules, setExpandedModules] = useState<Set<string>>(new Set());

  // مسودة الصلاحيات المحلية — تُحفظ فقط عند الضغط على زر الحفظ
  const [draft, setDraft] = useState<PermDraft>(() =>
    Object.fromEntries(role.permissions.map((p) => [p.permissionId, { scope: p.scope, mfa: p.requiresMfa, reason: p.requiresReason }])),
  );

  const modules = useMemo(() => [...new Set(data.permissions.map((p) => p.module))].sort(), [data.permissions]);
  const filtered = useMemo(
    () =>
      data.permissions
        .filter((p) => moduleFilter === 'all' || p.module === moduleFilter)
        .filter((p) => !search || (p.nameAr ?? p.name ?? p.code).includes(search) || p.code.includes(search)),
    [data.permissions, moduleFilter, search],
  );

  // تجميع حسب الوحدة
  const grouped = useMemo(() => {
    const map = new Map<string, typeof filtered>();
    for (const p of filtered) {
      const bucket = map.get(p.module);
      if (bucket) bucket.push(p);
      else map.set(p.module, [p]);
    }
    return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [filtered]);

  // المستخدمون المسندون لهذا الدور
  const assignedUsers = useMemo(() => data.users.filter((u) => u.roles.some((r) => r.roleId === role.id)), [data.users, role.id]);

  // المستخدمون المتاحون للإسناد (غير مسندين لهذا الدور)
  const availableUsers = useMemo(() => data.users.filter((u) => !u.roles.some((r) => r.roleId === role.id)), [data.users, role.id]);

  async function savePermissions() {
    setSaving(true);
    setSaved(false);
    try {
      await commands.setPermissions.mutateAsync({
        roleId: role.id,
        items: Object.entries(draft).map(([permission_id, v]) => ({ permission_id, scope: v.scope, requires_mfa: v.mfa, requires_reason: v.reason })),
      });
      setSaved(true);
      setTimeout(() => setSaved(false), 2500);
    } catch {
      /* mutation error surfaced via mutation.isError state */
    } finally {
      setSaving(false);
    }
  }

  async function assignUser() {
    if (!assignUserId) return;
    try {
      await commands.assignRole.mutateAsync({ userId: assignUserId, roleId: role.id });
      setAssignUserId('');
    } catch {
      /* mutation error surfaced via mutation.isError state */
    }
  }

  const tabClass = (active: boolean) =>
    `px-5 py-3 text-sm font-black transition-colors ${active ? 'border-b-2 border-[var(--brand)] text-[var(--brand)]' : 'muted hover:text-[var(--text)]'}`;

  return (
    <DialogOverlay title={`إدارة دور: ${role.name}`} onClose={onClose} maxWidth="max-w-5xl">
      {/* ── التبويبات ── */}
      <div className="mb-5 flex gap-1 border-b border-[var(--border)]">
        <button type="button" className={tabClass(tab === 'perms')} onClick={() => setTab('perms')}>
          <KeyRound className="mb-0.5 inline size-4" aria-hidden="true" /> الصلاحيات <span className="muted text-xs">({Object.keys(draft).length})</span>
        </button>
        <button type="button" className={tabClass(tab === 'users')} onClick={() => setTab('users')}>
          <Users className="mb-0.5 inline size-4" aria-hidden="true" /> المستخدمون <span className="muted text-xs">({assignedUsers.length})</span>
        </button>
      </div>

      {/* ══════════════ تبويب الصلاحيات ══════════════ */}
      {tab === 'perms' && (
        <div className="space-y-4">
          {/* أدوات البحث والتصفية */}
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm">
              <strong>{Object.keys(draft).length}</strong> صلاحية محددة من أصل <strong>{data.permissions.length}</strong>
            </p>
            <div className="flex flex-wrap items-center gap-3">
              <div className="relative">
                <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
                <input className="input pe-9" placeholder="بحث…" aria-label="بحث الصلاحيات" value={search} onChange={(e) => setSearch(e.target.value)} />
              </div>
              <select aria-label="تصفية حسب الوحدة" className="input max-w-xs" value={moduleFilter} onChange={(e) => setModuleFilter(e.target.value)}>
                <option value="all">كل الوحدات</option>
                {modules.map((m) => (
                  <option key={m} value={m}>
                    {MODULE_AR[m] ?? m}
                  </option>
                ))}
              </select>
              <button type="button" className="btn-secondary px-3 py-2 text-xs" onClick={() => setExpandedModules(new Set(grouped.map(([m]) => m)))}>
                فتح الكل
              </button>
              <button type="button" className="btn-secondary px-3 py-2 text-xs" onClick={() => setExpandedModules(new Set())}>
                إغلاق الكل
              </button>
            </div>
          </div>

          {/* قائمة الصلاحيات مجمعة حسب الوحدة */}
          <div className="max-h-[52vh] space-y-2 overflow-y-auto pe-1">
            {grouped.map(([module, perms]) => {
              const isExpanded = expandedModules.has(module);
              const moduleLabel = perms[0]?.moduleAr ?? MODULE_AR[module] ?? module;
              const selectedInModule = perms.filter((p) => draft[p.id]).length;
              return (
                <div key={module} className="overflow-hidden rounded-xl border border-[var(--border)]">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between bg-[var(--surface-muted)] px-4 py-3 text-start"
                    onClick={() =>
                      setExpandedModules((prev) => {
                        const n = new Set(prev);
                        if (n.has(module)) n.delete(module);
                        else n.add(module);
                        return n;
                      })
                    }
                  >
                    <div className="flex items-center gap-2">
                      <span className="font-bold">{moduleLabel}</span>
                      <span className="muted text-xs">
                        ({selectedInModule}/{perms.length})
                      </span>
                    </div>
                    <ChevronDown aria-hidden="true" className={`size-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
                  </button>
                  {isExpanded && (
                    <div className="divide-y divide-[var(--border)]">
                      {perms.map((permission) => {
                        const sel = draft[permission.id];
                        return (
                          <div key={permission.id} className="flex flex-col gap-3 px-4 py-3 lg:flex-row lg:items-center lg:justify-between">
                            <label className="flex items-start gap-3">
                              <input
                                className="mt-1 size-4"
                                type="checkbox"
                                checked={Boolean(sel)}
                                onChange={(e) => {
                                  const next = { ...draft };
                                  if (e.target.checked)
                                    next[permission.id] = {
                                      scope: permission.allowedScopes[0] ?? 'self',
                                      mfa: permission.sensitive,
                                      reason: permission.sensitive,
                                    };
                                  else delete next[permission.id];
                                  setDraft(next);
                                }}
                              />
                              <span>
                                <strong>{permission.nameAr ?? permission.name}</strong>
                                <span className="muted mt-1 block font-mono text-xs">{permission.code}</span>
                              </span>
                            </label>
                            {sel && (
                              <div className="flex flex-wrap gap-2">
                                <select
                                  className="input w-52"
                                  aria-label="نطاق الصلاحية"
                                  value={sel.scope}
                                  onChange={(e) => setDraft({ ...draft, [permission.id]: { ...sel, scope: e.target.value } })}
                                >
                                  {(permission.allowedScopes.length ? permission.allowedScopes : scopes).map((s) => (
                                    <option key={s} value={s}>
                                      {SCOPE_AR[s] ?? s}
                                    </option>
                                  ))}
                                </select>
                                <Flag checked={sel.mfa} label="MFA" onChange={(mfa) => setDraft({ ...draft, [permission.id]: { ...sel, mfa } })} />
                                <Flag checked={sel.reason} label="سبب" onChange={(reason) => setDraft({ ...draft, [permission.id]: { ...sel, reason } })} />
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
            {grouped.length === 0 && <p className="muted py-8 text-center text-sm">لا توجد صلاحيات مطابقة</p>}
          </div>

          {/* زر الحفظ */}
          {commands.setPermissions.isError && <ErrorBanner message={safeErrorMessage(commands.setPermissions.error)} />}
          <div className="flex items-center gap-3 border-t border-[var(--border)] pt-4">
            <button type="button" className="btn-primary" disabled={saving} onClick={() => void savePermissions()}>
              <Save className="size-4" aria-hidden="true" />
              {saving ? 'جارٍ الحفظ…' : 'حفظ التعديلات'}
            </button>
            {saved && <span className="text-sm font-bold text-[var(--success)]">✓ تم الحفظ</span>}
          </div>
        </div>
      )}

      {/* ══════════════ تبويب المستخدمون ══════════════ */}
      {tab === 'users' && (
        <div className="space-y-5">
          {role.fullAccess && !canGrantFullAccess && (
            <p className="rounded-xl bg-[var(--surface-muted)] p-3 text-xs font-semibold text-[var(--danger)]">
              هذا الدور ذو وصول كامل — إسناده يتطلب حساباً بـ super-admin.
            </p>
          )}
          {/* إسناد مستخدم جديد */}
          <div className="flex flex-wrap items-end gap-3 rounded-xl bg-[var(--surface-muted)] p-4">
            <label className="min-w-0 flex-1">
              <span className="mb-1.5 block text-sm font-bold">إسناد مستخدم لهذا الدور</span>
              <select className="input" value={assignUserId} onChange={(e) => setAssignUserId(e.target.value)}>
                <option value="">اختر مستخدماً…</option>
                {availableUsers.map((u) => (
                  <option key={u.userId} value={u.userId}>
                    {u.name}
                    {u.employeeCode ? ` · ${u.employeeCode}` : ''}
                  </option>
                ))}
              </select>
            </label>
            <button type="button" className="btn-primary" disabled={!assignUserId || commands.assignRole.isPending} onClick={() => void assignUser()}>
              <UserPlus className="size-4" aria-hidden="true" />
              {commands.assignRole.isPending ? 'جارٍ الإسناد…' : 'إسناد'}
            </button>
          </div>

          {commands.revokeRole.isError && <ErrorBanner message={`تعذر سحب الدور: ${safeErrorMessage(commands.revokeRole.error)}`} />}
          {commands.assignRole.isError && <ErrorBanner message={safeErrorMessage(commands.assignRole.error)} />}

          {/* قائمة المستخدمين المسندين */}
          {assignedUsers.length === 0 ? (
            <p className="muted py-8 text-center text-sm">لا يوجد مستخدمون مسندون لهذا الدور حالياً</p>
          ) : (
            <div className="divide-y divide-[var(--border)] rounded-xl border border-[var(--border)]">
              {assignedUsers.map((user) => {
                const userRole = user.roles.find((r) => r.roleId === role.id);
                return (
                  <div key={user.userId} className="flex items-center justify-between p-4">
                    <div className="flex items-center gap-3">
                      <UserAvatar displayName={user.name} size="sm" />
                      <div>
                        <p className="font-bold">{user.name}</p>
                        <p className="muted text-xs">
                          {user.employeeCode ?? user.userId}
                          {userRole?.effectiveTo ? ` · حتى ${new Date(userRole.effectiveTo).toLocaleDateString('ar-EG')}` : ''}
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      className="btn-secondary px-3 py-1.5 text-xs text-[var(--danger)]"
                      onClick={() =>
                        commands.revokeRole.mutate({ userId: user.userId, roleId: role.id })
                      }
                    >
                      <Trash2 className="size-3.5" aria-hidden="true" />
                      سحب
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </DialogOverlay>
  );
}

// ─── مكونات مساعدة ──────────────────────────────────────────────────────────

// ─── حوار إنشاء / تعديل دور مخصص ──────────────────────────────────────────
function CustomRoleDraftDialog({
  initialDraft,
  data,
  commands,
  canGrantFullAccess,
  onClose,
}: {
  initialDraft: RoleDraft;
  data: AccessAdminCatalog;
  commands: AccessCommands;
  canGrantFullAccess: boolean;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState<RoleDraft>(initialDraft);
  const [moduleFilter, setModuleFilter] = useState('all');
  const [permSearch, setPermSearch] = useState('');

  const modules = useMemo(() => [...new Set((data.permissions ?? []).map((p) => p.module))].sort(), [data]);

  async function saveRole(event: FormEvent) {
    event.preventDefault();
    try {
      const result = await commands.upsertRole.mutateAsync({
        id: draft.id,
        slug: draft.slug,
        name: draft.name,
        nameEn: draft.nameEn || null,
        description: draft.description || null,
        fullAccess: draft.fullAccess,
      });
      const roleId = String((result as { id?: string })?.id ?? draft.id ?? '');
      if (roleId) {
        await commands.setPermissions.mutateAsync({
          roleId,
          items: Object.entries(draft.selected).map(([permission_id, v]) => ({
            permission_id,
            scope: v.scope,
            requires_mfa: v.mfa,
            requires_reason: v.reason,
          })),
        });
      }
      onClose();
    } catch {
      /* mutation error surfaced via mutation.isError state */
    }
  }

  return (
    <DialogOverlay title={draft.id ? 'تعديل الدور' : 'إنشاء دور مخصص'} onClose={onClose} maxWidth="max-w-5xl">
      <form className="space-y-5" onSubmit={(e) => void saveRole(e)}>
        <div className="grid gap-4 sm:grid-cols-2">
          <FormInput
            label="Slug"
            required
            value={draft.slug}
            disabled={Boolean(draft.id)}
            onChange={(v) => setDraft({ ...draft, slug: v.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}
          />
          <FormInput label="الاسم العربي" required value={draft.name} onChange={(v) => setDraft({ ...draft, name: v })} />
          <FormInput label="الاسم الإنجليزي" value={draft.nameEn} onChange={(v) => setDraft({ ...draft, nameEn: v })} />
          <FormInput label="الوصف" value={draft.description} onChange={(v) => setDraft({ ...draft, description: v })} />
        </div>

        <label className={`flex items-center gap-3 rounded-xl p-3 text-sm font-semibold ${canGrantFullAccess ? 'bg-[var(--surface-muted)]' : 'bg-[var(--surface-muted)] opacity-60'}`}>
          <input
            className="size-4"
            type="checkbox"
            disabled={!canGrantFullAccess}
            checked={draft.fullAccess}
            onChange={(e) => setDraft({ ...draft, fullAccess: e.target.checked })}
          />
          <span>
            الوصول الكامل (is_full_access)
            {canGrantFullAccess ? (
              <span className="muted block text-xs font-normal">الدور يمنح كل الصلاحيات تلقائياً. منحه للمستخدمين يتطلب super-admin.</span>
            ) : (
              <span className="muted block text-xs font-normal">يتطلب حساباً بـ super-admin — حالياً مقفول. أدوار الموظفين تُمنح بالصلاحيات أدناه.</span>
            )}
          </span>
        </label>

        <div className="flex flex-wrap items-center justify-between gap-3 border-y border-[var(--border)] py-4">
          <h3 className="font-black">الصلاحيات</h3>
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative">
              <Search className="pointer-events-none absolute end-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
              <input className="input pe-9" placeholder="بحث…" aria-label="بحث الصلاحيات" value={permSearch} onChange={(e) => setPermSearch(e.target.value)} />
            </div>
            <select aria-label="تصفية حسب الوحدة" className="input max-w-xs" value={moduleFilter} onChange={(e) => setModuleFilter(e.target.value)}>
              <option value="all">كل الوحدات</option>
              {modules.map((m) => (
                <option key={m} value={m}>
                  {MODULE_AR[m] ?? m}
                </option>
              ))}
            </select>
            <p className="muted text-xs" aria-live="polite">
              {Object.keys(draft.selected).length} محددة
            </p>
          </div>
        </div>

        <div className="max-h-[52vh] space-y-2 overflow-y-auto pe-1">
          {data.permissions
            .filter((p) => moduleFilter === 'all' || p.module === moduleFilter)
            .filter((p) => !permSearch || (p.nameAr ?? p.name ?? p.code).includes(permSearch) || p.code.includes(permSearch))
            .map((permission) => {
              const selected = draft.selected[permission.id];
              return (
                <article key={permission.id} className="rounded-xl border border-[var(--border)] p-4">
                  <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                    <label className="flex items-start gap-3">
                      <input
                        className="mt-1 size-4"
                        type="checkbox"
                        checked={Boolean(selected)}
                        onChange={(e) => {
                          const next = { ...draft.selected };
                          if (e.target.checked)
                            next[permission.id] = { scope: permission.allowedScopes[0] ?? 'self', mfa: permission.sensitive, reason: permission.sensitive };
                          else delete next[permission.id];
                          setDraft({ ...draft, selected: next });
                        }}
                      />
                      <span>
                        <strong>{permission.nameAr ?? permission.name}</strong>
                        <span className="muted mt-1 block font-mono text-xs">{permission.code}</span>
                      </span>
                    </label>
                    {selected && (
                      <div className="flex flex-wrap gap-2">
                        <select
                          className="input w-52"
                          aria-label="نطاق الصلاحية"
                          value={selected.scope}
                          onChange={(e) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, scope: e.target.value } } })}
                        >
                          {(permission.allowedScopes.length ? permission.allowedScopes : scopes).map((s) => (
                            <option key={s} value={s}>
                              {SCOPE_AR[s] ?? s}
                            </option>
                          ))}
                        </select>
                        <Flag
                          checked={selected.mfa}
                          label="MFA"
                          onChange={(mfa) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, mfa } } })}
                        />
                        <Flag
                          checked={selected.reason}
                          label="سبب"
                          onChange={(reason) => setDraft({ ...draft, selected: { ...draft.selected, [permission.id]: { ...selected, reason } } })}
                        />
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
        </div>

        {(commands.upsertRole.isError || commands.setPermissions.isError) && (
          <ErrorBanner message={safeErrorMessage(commands.upsertRole.error ?? commands.setPermissions.error)} />
        )}
        <button className="btn-primary" disabled={commands.upsertRole.isPending || commands.setPermissions.isPending}>
          <Save className="size-4" aria-hidden="true" />
          {commands.upsertRole.isPending || commands.setPermissions.isPending ? 'جارٍ الحفظ…' : 'حفظ الدور والصلاحيات'}
        </button>
      </form>
    </DialogOverlay>
  );
}

function FormInput({
  label,
  value,
  onChange,
  required,
  disabled,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  disabled?: boolean;
}) {
  return (
    <label>
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      <input className="input" required={required} disabled={disabled} value={value} onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}
function FormSelect({
  label,
  value,
  onChange,
  required,
  children,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  children: ReactNode;
}) {
  return (
    <label>
      <span className="mb-1.5 block text-sm font-bold">{label}</span>
      <select className="input" required={required} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">اختر…</option>
        {children}
      </select>
    </label>
  );
}
function Flag({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <label className="flex items-center gap-2 rounded-xl bg-[var(--surface-muted)] px-3 py-2 text-xs font-bold">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      {label}
    </label>
  );
}
