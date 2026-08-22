import { CircleCheck, Headphones, Inbox, LifeBuoy, Plus, Send } from 'lucide-react';
import { useMemo, useState, type FormEvent } from 'react';
import { safeErrorMessage } from '../../core/errorMapper';
import { DataTable, type DataTableColumn } from '../../ui/DataTable';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { FilterBar } from '../../ui/FilterBar';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useCreateTicket, useHelpdeskTickets, useSendTicketMessage, useTicketMessages, useUpdateTicketStatus } from './useHelpdesk';

type Tab = 'inbox' | 'mine';

const PRIORITIES: Record<string, string> = {
  low: 'منخفضة',
  medium: 'متوسطة',
  high: 'عالية',
  urgent: 'عاجلة',
};

const CATEGORIES = ['تقني', 'موارد بشرية', 'رواتب', 'مستندات', 'أجهزة', 'أخرى'];

function date(value: string | null) {
  if (!value) return 'غير محدد';
  return new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
}

export function HelpdeskPage() {
  const auth = useAuth();
  const query = useHelpdeskTickets();
  const commands = useCreateTicket();
  const updateStatus = useUpdateTicketStatus();
  const sendMessage = useSendTicketMessage();
  const [tab, setTab] = useState<Tab>('inbox');
  const [search, setSearch] = useState('');
  const [createOpen, setCreateOpen] = useState(false);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [draft, setDraft] = useState({ subject: '', category: '', priority: 'medium', description: '' });
  const [reply, setReply] = useState('');

  const messagesQuery = useTicketMessages(detailId);

  const canManage = Boolean(auth.access && (auth.access.permissions.includes('*') || hasPermission(auth.access, 'tickets.write')));
  const myEmployeeId = auth.access?.employeeId ?? null;

  const data = useMemo(() => query.data ?? [], [query.data]);
  const term = search.trim().toLocaleLowerCase('ar');
  // النقر على بطاقات الملخص يصفّي القائمة سريعاً.
  const [quickFilter, setQuickFilter] = useState<'all' | 'open' | 'urgent' | 'resolved'>('all');
  const filtered = useMemo(() => {
    const rows = tab === 'mine' ? data.filter((t) => t.requester_employee_id === myEmployeeId) : data;
    const byQuick =
      quickFilter === 'all'
        ? rows
        : quickFilter === 'urgent'
          ? rows.filter((t) => t.priority === 'urgent')
          : quickFilter === 'open'
            ? rows.filter((t) => ['open', 'in_progress'].includes(t.status))
            : rows.filter((t) => ['resolved', 'closed'].includes(t.status));
    if (!term) return byQuick;
    return byQuick.filter((t) => `${t.subject} ${t.category ?? ''} ${t.requester_name ?? ''}`.toLocaleLowerCase('ar').includes(term));
  }, [data, tab, term, myEmployeeId, quickFilter]);

  const openCount = data.filter((t) => ['open', 'in_progress'].includes(t.status)).length;
  const urgentCount = data.filter((t) => t.priority === 'urgent' && ['open', 'in_progress'].includes(t.status)).length;
  const resolvedCount = data.filter((t) => ['resolved', 'closed'].includes(t.status)).length;

  async function submitCreate(event: FormEvent) {
    event.preventDefault();
    try {
      await commands.mutateAsync(draft);
      setCreateOpen(false);
      setDraft({ subject: '', category: '', priority: 'medium', description: '' });
    } catch {
      /* error via ErrorBanner */
    }
  }

  async function submitReply(event: FormEvent) {
    event.preventDefault();
    if (!detailId || !reply.trim()) return;
    try {
      await sendMessage.mutateAsync({ ticketId: detailId, body: reply });
      setReply('');
    } catch {
      /* error via ErrorBanner */
    }
  }

  const columns: DataTableColumn<(typeof data)[number]>[] = [
    { key: 'subject', header: 'الموضوع', sortable: true, render: (t) => <span className="font-medium">{t.subject}</span> },
    { key: 'category', header: 'التصنيف', render: (t) => t.category ?? '—' },
    { key: 'priority', header: 'الأولوية', render: (t) => <StatusBadge status={t.priority} label={PRIORITIES[t.priority]} /> },
    { key: 'status', header: 'الحالة', render: (t) => <StatusBadge status={t.status} /> },
    { key: 'requester', header: 'مقدم الطلب', render: (t) => t.requester_name ?? '—' },
    { key: 'created_at', header: 'التاريخ', sortable: true, render: (t) => date(t.created_at) },
  ];

  const selectedTicket = detailId ? (data.find((t) => t.id === detailId) ?? null) : null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="مكتب الخدمات"
        description="تذاكر الدعم والخدمات للموظفين: تقديم طلب، متابعة الحالة، وردود الفريق."
        actions={
          <button type="button" className="btn-primary inline-flex items-center gap-2" onClick={() => setCreateOpen(true)}>
            <Plus className="size-4" /> تذكرة جديدة
          </button>
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <MetricCard label="التذاكر المفتوحة" value={openCount} icon={Inbox} hint="مفتوحة أو قيد التنفيذ" onClick={() => setQuickFilter('open')} />
        <MetricCard label="عاجلة" value={urgentCount} icon={LifeBuoy} hint="بأولوية عاجلة مفتوحة" onClick={() => setQuickFilter('urgent')} />
        <MetricCard label="تم إغلاقها" value={resolvedCount} icon={CircleCheck} hint="محلولة أو مغلقة" onClick={() => setQuickFilter('resolved')} />
        <MetricCard label="الإجمالي" value={data.length} icon={Headphones} hint="كل التذاكر" onClick={() => setQuickFilter('all')} />
      </div>

      <div className="card flex items-center gap-4 p-2">
        {(['inbox', 'mine'] as Tab[]).map((key) => (
          <button key={key} type="button" onClick={() => setTab(key)} className={`filter-chip ${tab === key ? 'filter-chip-active' : ''}`}>
            {key === 'inbox' ? 'صندوق الخدمات' : 'تذاكري'}
          </button>
        ))}
      </div>

      <FilterBar searchValue={search} onSearchChange={setSearch} searchPlaceholder="ابحث في الموضوع أو التصنيف..." resultText={`${filtered.length} تذكرة`} />

      {query.isError ? (
        <ErrorState title="تعذر تحميل التذاكر" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : query.isLoading ? (
        <ListSkeleton rows={5} />
      ) : filtered.length === 0 ? (
        <EmptyState title="لا توجد تذاكر" description="لم يتم العثور على تذاكر مطابقة." />
      ) : (
        <DataTable<(typeof data)[number]> ariaLabel="جدول التذاكر" rowKey={(t) => t.id} data={filtered} columns={columns} minWidth="900px" />
      )}

      {commands.isError ? <ErrorBanner message={safeErrorMessage(commands.error)} /> : null}
      {sendMessage.isError ? <ErrorBanner message={safeErrorMessage(sendMessage.error)} /> : null}

      {createOpen ? (
        <DialogOverlay title="تذكرة جديدة" onClose={() => setCreateOpen(false)} maxWidth="max-w-lg">
          <form onSubmit={submitCreate} className="flex flex-col gap-4">
            <label className="flex flex-col gap-1 text-sm">
              <span>الموضوع *</span>
              <input
                className="input"
                required
                value={draft.subject}
                onChange={(e) => setDraft({ ...draft, subject: e.target.value })}
                placeholder="مثال: مشكلة في تسجيل الحضور"
              />
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span>التصنيف</span>
              <select className="input" value={draft.category} onChange={(e) => setDraft({ ...draft, category: e.target.value })}>
                <option value="">— اختر تصنيفاً —</option>
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span>الأولوية</span>
              <select className="input" value={draft.priority} onChange={(e) => setDraft({ ...draft, priority: e.target.value })}>
                {Object.entries(PRIORITIES).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-sm">
              <span>التفاصيل</span>
              <textarea
                className="input min-h-28"
                value={draft.description}
                onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                placeholder="اشرح المشكلة بالتفصيل..."
              />
            </label>
            <div className="flex justify-end gap-2">
              <button type="button" className="btn-secondary" onClick={() => setCreateOpen(false)}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary">
                إرسال
              </button>
            </div>
          </form>
        </DialogOverlay>
      ) : null}

      {selectedTicket ? (
        <DialogOverlay title={selectedTicket.subject} onClose={() => setDetailId(null)} maxWidth="max-w-2xl">
          <div className="flex flex-col gap-4">
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <StatusBadge status={selectedTicket.status} />
              <StatusBadge status={selectedTicket.priority} label={PRIORITIES[selectedTicket.priority]} />
              <span className="text-[var(--muted)]">تقديم: {selectedTicket.requester_name ?? '—'}</span>
              <span className="text-[var(--muted)]">{date(selectedTicket.created_at)}</span>
            </div>

            {canManage ? (
              <label className="flex items-center gap-2 text-sm">
                <span>الحالة:</span>
                <select
                  className="input max-w-52"
                  value={selectedTicket.status}
                  onChange={(e) => void updateStatus.mutate({ id: selectedTicket.id, status: e.target.value })}
                >
                  {['open', 'in_progress', 'resolved', 'closed', 'cancelled'].map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}

            <div className="flex max-h-80 flex-col gap-2 overflow-y-auto rounded-lg bg-[var(--surface-muted)] p-3">
              {messagesQuery.isLoading ? (
                <ListSkeleton rows={3} />
              ) : (messagesQuery.data ?? []).length === 0 ? (
                <p className="text-sm text-[var(--muted)]">لا توجد رسائل بعد.</p>
              ) : (
                (messagesQuery.data ?? []).map((m) => (
                  <div key={m.id} className="rounded-lg bg-[var(--surface)] p-3 text-sm">
                    <div className="mb-1 flex items-center justify-between">
                      <span className="font-medium">{m.is_internal ? 'ملاحظة داخلية' : (m.author_name ?? 'موظف')}</span>
                      <span className="text-xs text-[var(--muted)]">{date(m.created_at)}</span>
                    </div>
                    <p className="whitespace-pre-wrap">{m.body}</p>
                  </div>
                ))
              )}
            </div>

            <form onSubmit={submitReply} className="flex gap-2">
              <textarea className="input flex-1" value={reply} onChange={(e) => setReply(e.target.value)} placeholder="اكتب رداً..." rows={2} />
              <button type="submit" className="btn-primary" disabled={!reply.trim()}>
                <Send className="size-4" />
              </button>
            </form>
          </div>
        </DialogOverlay>
      ) : null}
    </div>
  );
}
