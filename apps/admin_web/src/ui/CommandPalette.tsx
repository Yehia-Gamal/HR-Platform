import { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router';

/**
 * لوحة الأوامر (Ctrl+K / Cmd+K) — تنقل سريع لكل صفحات مساحة العمل.
 * تقرأ مساحة العمل الحالية من الرابط وتعرض بنودها (بنود الإدارة
 * الحصرية تظهر داخل /admin فقط). الحماية النهائية تبقى على WorkspaceGuard.
 */
interface CommandItem {
  label: string;
  /** مسار نسبي داخل مساحة العمل — '' يعني الرئيسية. */
  path: string;
  group: string;
  adminOnly?: boolean;
}

const ITEMS: CommandItem[] = [
  { label: 'الرئيسية', path: '', group: 'عام' },
  { label: 'الإشعارات', path: 'notifications', group: 'عام' },
  { label: 'الهيكل التنظيمي', path: 'organization', group: 'عام' },
  { label: 'المخطط التنظيمي', path: 'org-chart', group: 'عام' },
  { label: 'الموظفون', path: 'employees', group: 'الموظفون' },
  { label: 'إضافة موظف', path: 'employees/new', group: 'الموظفون' },
  { label: 'دورة الحياة', path: 'lifecycle', group: 'الموظفون' },
  { label: 'التهيئة والتأهيل', path: 'onboarding', group: 'الموظفون' },
  { label: 'الحضور', path: 'attendance', group: 'الحضور' },
  { label: 'الأجهزة', path: 'devices', group: 'الحضور' },
  { label: 'الطلبات', path: 'requests', group: 'الطلبات والإجازات' },
  { label: 'الإجازات', path: 'leaves', group: 'الطلبات والإجازات' },
  { label: 'أدوات الإجازات', path: 'leave-tools', group: 'الطلبات والإجازات' },
  { label: 'العطل الرسمية', path: 'holidays', group: 'الطلبات والإجازات' },
  { label: 'الأداء (KPI)', path: 'performance', group: 'الأداء والتقارير' },
  { label: 'دورات KPI', path: 'performance/cycles', group: 'الأداء والتقارير', adminOnly: true },
  { label: 'التقارير والتحليلات', path: 'reports', group: 'الأداء والتقارير' },
  { label: 'التقارير اليومية', path: 'daily-reports', group: 'الأداء والتقارير' },
  { label: 'قاعدة المعرفة', path: 'knowledge', group: 'المعرفة والتعلم' },
  { label: 'التعلم والتدريب', path: 'learning', group: 'المعرفة والتعلم' },
  { label: 'المستندات', path: 'documents', group: 'المعرفة والتعلم' },
  { label: 'النشر الرسمي', path: 'official-feed', group: 'الاتصال' },
  { label: 'مركز الإجراءات', path: 'actions', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'النزاعات', path: 'disputes', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'الحوكمة', path: 'governance', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'المراقبة التنفيذية', path: 'executive-monitoring', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'الإدارة المؤسسية', path: 'enterprise', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'مركز العمليات', path: 'operations', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'الموقع المباشر', path: 'live-location', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'الدعم الفني', path: 'helpdesk', group: 'التنفيذي والإدارة', adminOnly: true },
  { label: 'المالية', path: 'finance', group: 'المالية', adminOnly: true },
  { label: 'الصلاحيات والوصول', path: 'access', group: 'النظام', adminOnly: true },
  { label: 'الإعدادات', path: 'settings', group: 'النظام', adminOnly: true },
  { label: 'إعدادات النظام', path: 'system-settings', group: 'النظام', adminOnly: true },
  { label: 'الأمن والمراجعة', path: 'audit-security', group: 'النظام', adminOnly: true },
  { label: 'سجل التدقيق', path: 'audit-trail', group: 'النظام', adminOnly: true },
  { label: 'المراقبة التقنية', path: 'observability', group: 'النظام', adminOnly: true },
  { label: 'التكاملات والمهام', path: 'integrations', group: 'النظام', adminOnly: true },
];

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const inputRef = useRef<HTMLInputElement>(null);

  // مساحة العمل الحالية من الرابط — الافتراض /hr.
  const workspace = pathname.startsWith('/admin') ? '/admin' : '/hr';

  // الاختصار العام: Ctrl+K / Cmd+K للفتح والإغلاق، Escape للإغلاق.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setOpen((value) => !value);
      } else if (event.key === 'Escape') {
        setOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // تركيز الحقل عند كل فتح.
  useEffect(() => {
    if (open) {
      setQuery('');
      setActive(0);
      queueMicrotask(() => inputRef.current?.focus());
    }
  }, [open]);

  const results = useMemo(() => {
    const pool = ITEMS.filter((item) => !item.adminOnly || workspace === '/admin');
    const q = query.trim().toLowerCase();
    if (!q) return pool;
    return pool.filter((item) => item.label.toLowerCase().includes(q) || item.path.includes(q));
  }, [query, workspace]);

  const go = (item: CommandItem) => {
    setOpen(false);
    navigate(item.path ? `${workspace}/${item.path}` : workspace);
  };

  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setActive((value) => Math.min(value + 1, results.length - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActive((value) => Math.max(value - 1, 0));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      const item = results[active];
      if (item) go(item);
    }
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-start justify-center bg-black/40 p-4 pt-[12vh]" onClick={() => setOpen(false)} role="presentation">
      <div
        className="card w-full max-w-xl overflow-hidden p-0"
        dir="rtl"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label="لوحة الأوامر"
      >
        <input
          ref={inputRef}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={onKeyDown}
          placeholder="انتقل إلى صفحة…"
          aria-label="بحث لوحة الأوامر"
          className="w-full border-0 border-b border-[var(--border)] bg-transparent px-5 py-4 text-sm font-bold outline-none"
        />
        <ul className="max-h-[50vh] overflow-y-auto p-2">
          {results.map((item, index) => (
            <li key={item.path || 'root'}>
              <button
                type="button"
                onMouseEnter={() => setActive(index)}
                onClick={() => go(item)}
                className={`flex w-full items-center justify-between gap-3 rounded-xl px-4 py-2.5 text-start text-sm font-bold ${
                  index === active ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-primary)] hover:bg-[var(--surface-muted)]'
                }`}
              >
                <span>{item.label}</span>
                <span className={`text-xs font-bold ${index === active ? 'text-white/70' : 'text-[var(--text-muted)]'}`}>{item.group}</span>
              </button>
            </li>
          ))}
          {results.length === 0 ? <li className="p-6 text-center text-sm text-[var(--text-muted)]">لا توجد صفحات مطابقة.</li> : null}
        </ul>
        <div className="flex items-center justify-between border-t border-[var(--border)] px-5 py-2 text-xs text-[var(--text-muted)]">
          <span>↑↓ للتنقل · Enter للفتح · Esc للإغلاق</span>
          <span>{results.length} صفحة</span>
        </div>
      </div>
    </div>
  );
}
