import { useState } from 'react';
import {
  Coins,
  ArrowDownLeft,
  ArrowUpRight,
  ShieldCheck,
  History,
  Search,
  AlertTriangle,
  Clock,
  Sparkles,
  UserCheck,
  FileSpreadsheet,
  Printer,
  MessageCircle,
} from 'lucide-react';
import {
  useFellowshipFundSummary,
  useFellowshipFundTransactions,
  useWithdrawFromFellowshipFund,
  FELLOWSHIP_CATEGORIES,
  type FellowshipFundTransaction,
} from './useFellowshipFund';
import { useAuth } from '../auth/AuthProvider';
import { hasPermission } from '../workspaces/access';
import { useEmployees } from '../employees/useEmployees';
import { PageHeader } from '../../ui/PageHeader';
import { DialogOverlay } from '../../ui/DialogOverlay';
import { EmptyState } from '../../ui/EmptyState';
import { useEntityFocus } from '../../core/useEntityFocus';
import { downloadCsv, printReport, toCsv, type ExportColumn } from '../../core/exportUtils';
import { cairoTodayIso } from '../../core/cairoTime';

export function FellowshipFundPage() {
  const auth = useAuth();
  const { data: summary } = useFellowshipFundSummary();
  const [typeFilter, setTypeFilter] = useState<'all' | 'inflow' | 'outflow'>('all');
  const [search, setSearch] = useState('');
  const { data: transactions, isLoading: txLoading } = useFellowshipFundTransactions({
    type: typeFilter,
    search,
  });

  // الوصول من إشعار صندوق الزمالة → إبراز حركة الصندوق نفسها.
  const focusedId = useEntityFocus((transactions?.length ?? 0) > 0);

  const [withdrawOpen, setWithdrawOpen] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawCategory, setWithdrawCategory] = useState<string>('مساعدة زميل');
  const [withdrawReason, setWithdrawReason] = useState('');
  const [beneficiaryId, setBeneficiaryId] = useState('');
  const [withdrawNotes, setWithdrawNotes] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);

  const withdrawMutation = useWithdrawFromFellowshipFund();
  const { data: employeesData } = useEmployees();
  const employees = employeesData ?? [];

  // صلاحية الإدارة للسحب
  const canWithdraw = Boolean(
    auth.access &&
    (hasPermission(auth.access, 'payroll.run.manage') ||
      hasPermission(auth.access, 'finance.manage') ||
      auth.access.workspaces?.includes('main_admin') ||
      auth.access.permissions?.includes('*')),
  );

  const currentBalance = summary?.currentBalance ?? 0;

  async function handleWithdrawSubmit(e: React.FormEvent) {
    e.preventDefault();
    setActionError(null);
    const amount = Number(withdrawAmount);
    if (!amount || amount <= 0) {
      setActionError('يرجى إدخال مبلغ سحب صحيح أكبر من صفر');
      return;
    }
    if (amount > currentBalance) {
      setActionError(`الرصيد المتاح (${currentBalance.toLocaleString('ar-EG-u-nu-latn')} ج.م) لا يكفي لسحب هذا المبلغ`);
      return;
    }
    if (!withdrawReason.trim() || withdrawReason.trim().length < 3) {
      setActionError('يرجى توضيح سبب السحب بالتفصيل لضمان الشفافية وإشعار الفريق');
      return;
    }

    try {
      await withdrawMutation.mutateAsync({
        amount,
        category: withdrawCategory,
        reason: withdrawReason.trim(),
        beneficiaryEmployeeId: beneficiaryId || undefined,
        notes: withdrawNotes.trim() || undefined,
      });
      setWithdrawOpen(false);
      setWithdrawAmount('');
      setWithdrawReason('');
      setWithdrawNotes('');
      setBeneficiaryId('');
    } catch (err: unknown) {
      setActionError(err instanceof Error ? err.message : 'فشل تنفيذ عملية السحب');
    }
  }

  // ─── تصدير كشف حركات الصندوق إلى Excel / CSV ─────────────────────
  const exportFundLedgerToCsv = () => {
    const list = transactions ?? [];
    const cols: ExportColumn<FellowshipFundTransaction>[] = [
      { key: 'createdAt', header: 'التاريخ والتوقيت', get: (t) => t.createdAt.replace('T', ' ').slice(0, 19) },
      { key: 'transactionType', header: 'النوع', get: (t) => (t.transactionType === 'inflow' ? 'إيداع (وارد)' : 'سحب (منصرف)') },
      { key: 'category', header: 'الفئة', get: (t) => t.category },
      { key: 'amount', header: 'المبلغ (ج.م)', get: (t) => t.amount },
      { key: 'balanceAfter', header: 'الرصيد بعد الحركة (ج.م)', get: (t) => t.balanceAfter },
      { key: 'employeeName', header: 'المعني / المستفيد', get: (t) => t.employeeName || '—' },
      { key: 'reason', header: 'البيان / السبب', get: (t) => t.reason },
      { key: 'performerName', header: 'المسؤول', get: (t) => t.performerName || '—' },
      { key: 'notes', header: 'ملاحظات', get: (t) => t.notes || '—' },
    ];
    downloadCsv(`fellowship-fund-ledger-${cairoTodayIso()}.csv`, toCsv(cols, list));
  };

  // ─── طباعة كشف حركات الصندوق ──────────────────────────────────────
  const printFundReport = () => {
    const list = transactions ?? [];
    printReport(
      [
        {
          title: 'كشف حركات صندوق الزمالة والتكافل الاجتماعي',
          subtitle: `الرصيد المتاح: ${currentBalance.toLocaleString('ar-EG')} ج.م — عدد الحركات: ${list.length}`,
          table: {
            headers: ['التاريخ', 'النوع', 'الفئة', 'المبلغ', 'الرصيد بعد', 'البيان / السبب', 'المعني', 'المسؤول'],
            rows: list.map((t) => [
              t.createdAt.replace('T', ' ').slice(0, 16),
              t.transactionType === 'inflow' ? 'وارد (+)' : 'منصرف (-)',
              t.category,
              `${t.amount.toLocaleString('ar-EG')} ج.م`,
              `${t.balanceAfter.toLocaleString('ar-EG')} ج.م`,
              t.reason,
              t.employeeName || '—',
              t.performerName || '—',
            ]),
          },
        },
      ],
      'تقرير صندوق الزمالة والتكافل',
      [
        { label: 'الرصيد المتاح', value: `${currentBalance.toLocaleString('ar-EG')} ج.م` },
        { label: 'إجمالي الوارد', value: `${(summary?.totalInflows ?? 0).toLocaleString('ar-EG')} ج.م` },
        { label: 'إجمالي المنصرف', value: `${(summary?.totalOutflows ?? 0).toLocaleString('ar-EG')} ج.م` },
        { label: 'عدد الإيداعات', value: `${summary?.inflowsCount ?? 0}` },
        { label: 'عدد السحوبات', value: `${summary?.outflowsCount ?? 0}` },
      ],
    );
  };

  // ─── مشاركة ملخص الصندوق عبر واتساب (مجاني 100%) ────────────────
  const shareFundWhatsApp = () => {
    const balance = currentBalance.toLocaleString('ar-EG-u-nu-latn');
    const inflows = (summary?.totalInflows ?? 0).toLocaleString('ar-EG-u-nu-latn');
    const outflows = (summary?.totalOutflows ?? 0).toLocaleString('ar-EG-u-nu-latn');
    const inflowsCount = summary?.inflowsCount ?? 0;
    const outflowsCount = summary?.outflowsCount ?? 0;

    const breakdownText = (summary?.categoryBreakdown ?? [])
      .map((c) => `• ${c.category} (${c.type === 'inflow' ? 'وارد' : 'منصرف'}): ${c.totalAmount.toLocaleString('ar-EG-u-nu-latn')} ج.م (${c.count} حركة)`)
      .join('\n');

    const msg =
      `*🤝 تقرير صندوق الزمالة والتكافل الاجتماعي — أحلى شباب*\n` +
      `*التاريخ:* ${cairoTodayIso()}\n\n` +
      `💰 *الرصيد المتاح بالخزنة:* ${balance} ج.م\n` +
      `📥 *إجمالي الوارد:* ${inflows} ج.م (${inflowsCount} إيداع)\n` +
      `📤 *إجمالي المنصرف:* ${outflows} ج.م (${outflowsCount} سحب مساعدة)\n\n` +
      (breakdownText ? `📊 *تفصيل الأبواب:*\n${breakdownText}\n\n` : '') +
      `✨ *تأكيد هام:* الصندوق تشاركي مستقل تماماً عن الراتب الشهري، وجميع موارده مخصصة 100% لدعم الزملاء والتكافل في الأوقات الصعبة.\n\n` +
      `_تقرير صادر من لوحة إدارة أحلى شباب — شفاف ومجاني 100%_ ✨`;

    window.open(`https://wa.me/?text=${encodeURIComponent(msg)}`, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="صندوق الزمالة والتكافل"
        description="صندوق مالي تشاركي — إيداعات غرامات الحضور والمساهمات، وسحوبات المساعدات. كل حركة معلنة للجميع."
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={shareFundWhatsApp}
              className="btn-secondary flex items-center gap-1.5 text-xs text-emerald-700 dark:text-emerald-300 border-emerald-500/30 hover:bg-emerald-500/10 cursor-pointer"
              title="مشاركة تقرير الصندوق ورصيده عبر واتساب للإدارة أو الفريق (مجاناً)"
            >
              <MessageCircle className="w-4 h-4 text-emerald-600" />
              <span>مشاركة واتساب</span>
            </button>
            <button
              type="button"
              onClick={exportFundLedgerToCsv}
              disabled={!transactions || transactions.length === 0}
              className="btn-secondary flex items-center gap-1.5 text-xs cursor-pointer"
              title="تصدير كشف الحركات الكامل إلى ملف Excel / CSV"
            >
              <FileSpreadsheet className="w-4 h-4 text-emerald-600" />
              <span>تصدير Excel</span>
            </button>
            <button
              type="button"
              onClick={printFundReport}
              disabled={!transactions || transactions.length === 0}
              className="btn-secondary flex items-center gap-1.5 text-xs font-medium cursor-pointer"
              title="تصدير وطباعة كشف الصندوق الشامل"
            >
              <Printer className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
              <span>تصدير PDF</span>
            </button>
            {canWithdraw && (
              <button
                onClick={() => {
                  setActionError(null);
                  setWithdrawOpen(true);
                }}
                className="btn-primary flex items-center gap-2 bg-gradient-to-r from-amber-600 to-amber-700 hover:from-amber-700 hover:to-amber-800 text-white shadow-lg shadow-amber-600/20 cursor-pointer"
              >
                <ArrowUpRight className="w-4 h-4" /> سحب من الصندوق
              </button>
            )}
          </div>
        }
      />

      {/* ═══ بطاقة الخزنة الرقمية الفاخرة (The Digital Vault Card) ═══ */}
      <div className="relative overflow-hidden rounded-3xl border-2 border-emerald-500/30 bg-gradient-to-br from-gray-900 via-emerald-950/40 to-gray-950 p-6 md:p-8 text-white shadow-[0_0_40px_rgba(16,185,129,0.15)]">
        {/* توهج خلفي زخرفي */}
        <div className="absolute -right-20 -top-20 h-64 w-64 rounded-full bg-emerald-500/10 blur-3xl pointer-events-none" />
        <div className="absolute -left-20 -bottom-20 h-64 w-64 rounded-full bg-amber-500/10 blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center md:justify-between gap-6">
          <div className="space-y-3">
            <div className="inline-flex items-center gap-2 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-3.5 py-1 text-xs font-bold text-emerald-400">
              <Coins className="w-3.5 h-3.5 animate-pulse text-amber-400" />
              <span>خزنة صندوق الزمالة والتكافل</span>
              <span className="text-emerald-300/50">•</span>
              <span className="flex items-center gap-1 text-emerald-300">
                <ShieldCheck className="w-3.5 h-3.5" /> شفاف ومتاح للفريق
              </span>
            </div>

            <div>
              <p className="text-xs text-white/60 font-medium">الرصيد المتاح حالياً بالصندوق</p>
              <div className="flex items-baseline gap-2 mt-1">
                <h2 className="text-4xl md:text-5xl font-black tracking-tight text-white font-mono">
                  {currentBalance.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </h2>
                <span className="text-lg md:text-xl font-bold text-emerald-400">جنيه مصري</span>
              </div>
            </div>

            <p className="text-xs text-white/60 max-w-xl leading-relaxed">
              تُورّد كل مبالغ غرامات الحضور والانصراف تلقائياً إلى هذا الصندوق لمساعدة الزملاء والمناسبات الاجتماعية، ويكون كل سحب أو إيداع معلناً للجميع بإشعار
              فوري.
            </p>
          </div>

          {/* كروت سريعة للإحصائيات في الخزنة */}
          <div className="grid grid-cols-2 gap-3 w-full md:w-auto shrink-0">
            <div className="rounded-2xl border border-emerald-500/20 bg-black/40 p-4 backdrop-blur-sm">
              <div className="flex items-center gap-2 text-xs font-bold text-emerald-400 mb-1">
                <ArrowDownLeft className="w-4 h-4 text-emerald-400" />
                <span>إجمالي الوارد</span>
              </div>
              <p className="text-xl font-black font-mono text-emerald-300">{(summary?.totalInflows ?? 0).toLocaleString('ar-EG-u-nu-latn')} ج.م</p>
              <p className="text-[11px] text-white/50 mt-1">{summary?.inflowsCount ?? 0} عملية إيداع</p>
            </div>

            <div className="rounded-2xl border border-red-500/20 bg-black/40 p-4 backdrop-blur-sm">
              <div className="flex items-center gap-2 text-xs font-bold text-red-400 mb-1">
                <ArrowUpRight className="w-4 h-4 text-red-400" />
                <span>إجمالي المنصرف</span>
              </div>
              <p className="text-xl font-black font-mono text-red-300">{(summary?.totalOutflows ?? 0).toLocaleString('ar-EG-u-nu-latn')} ج.م</p>
              <p className="text-[11px] text-white/50 mt-1">{summary?.outflowsCount ?? 0} عملية سحب</p>
            </div>
          </div>
        </div>
      </div>

      {/* ═══ تفصيل مصادر وأبواب الصندوق (Breakdown by Category) ═══ */}
      {summary?.categoryBreakdown && summary.categoryBreakdown.length > 0 && (
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-base)] p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-bold flex items-center gap-2">
              <Sparkles className="w-4 h-4 text-amber-500" />
              تفصيل مبالغ الصندوق وأبواب الصرف والإيداع
            </h3>
            <span className="text-xs text-[var(--text-muted)]">{summary.categoryBreakdown.length} فئات نشطة</span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {summary.categoryBreakdown.map((cat, idx) => {
              const isInflow = cat.type === 'inflow';
              return (
                <div
                  key={idx}
                  className={`rounded-xl p-4 border transition-all ${
                    isInflow ? 'border-emerald-500/20 bg-emerald-50/40 dark:bg-emerald-950/15' : 'border-amber-500/20 bg-amber-50/40 dark:bg-amber-950/15'
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-bold truncate">{cat.category}</span>
                    <span
                      className={`text-[10px] px-2.5 py-1 rounded-full font-bold ${
                        isInflow
                          ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300'
                          : 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300'
                      }`}
                    >
                      {isInflow ? 'وارد' : 'منصرف'}
                    </span>
                  </div>
                  <div className="flex items-baseline justify-between mt-2">
                    <span className="text-xl font-black font-mono">
                      {cat.totalAmount.toLocaleString('ar-EG-u-nu-latn')} <span className="text-xs font-medium text-[var(--text-muted)]">ج.م</span>
                    </span>
                    <span className="text-xs text-[var(--text-muted)]">{cat.count} حركة</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ═══ سجل الحركات الشفاف (Transparency Ledger) ═══ */}
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-base)] p-5 shadow-sm space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <History className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
            <h3 className="font-bold text-base">سجل الحركات والمعاملات الشفاف</h3>
            <span className="text-xs px-2 py-0.5 rounded-full bg-[var(--surface-raised)] text-[var(--text-muted)] font-medium">
              {transactions?.length ?? 0} حركة
            </span>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            {/* فلاتر النوع */}
            <div className="flex bg-[var(--surface-raised)] rounded-lg p-0.5 text-xs font-bold">
              <button
                onClick={() => setTypeFilter('all')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'all' ? 'bg-[var(--brand-primary)] text-white' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                الكل
              </button>
              <button
                onClick={() => setTypeFilter('inflow')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'inflow' ? 'bg-emerald-600 text-white' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                الإيداعات فقط (الوارد)
              </button>
              <button
                onClick={() => setTypeFilter('outflow')}
                className={`px-3 py-1.5 rounded-md transition-colors ${
                  typeFilter === 'outflow' ? 'bg-red-600 text-white' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                }`}
              >
                السحوبات فقط (المنصرف)
              </button>
            </div>

            {/* البحث */}
            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute end-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="بحث بالاسم أو السبب أو الفئة..."
                className="input ps-8 text-xs py-1.5 w-56"
              />
            </div>
          </div>
        </div>

        {/* عرض الحركات */}
        {txLoading ? (
          <div className="py-16 text-center text-sm text-[var(--text-muted)]">
            <div className="inline-block size-6 animate-spin rounded-full border-2 border-[var(--border)] border-t-[var(--brand-primary)]" />
            <p className="mt-3">جاري تحميل حركات الصندوق...</p>
          </div>
        ) : !transactions || transactions.length === 0 ? (
          <EmptyState
            title="لا توجد حركات مسجلة"
            description={search ? 'لا توجد حركات تطابق معايير البحث الحالية' : 'لم يتم تسجيل أي إيداعات أو سحوبات في صندوق الزمالة حتى الآن'}
          />
        ) : (
          <div className="overflow-x-auto -mx-5 px-5 max-h-[min(60vh,520px)] overflow-y-auto">
            <table className="w-full text-end text-[13px] min-w-[780px]">
              <thead className="sticky top-0 bg-[var(--surface-base)] shadow-xs z-10">
                <tr className="border-b-2 border-[var(--border)] text-[var(--text-muted)]">
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">الحركة</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">المبلغ</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">الموظف / المستفيد</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">السبب والتفاصيل</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">الفئة</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">الرصيد المتبقي</th>
                  <th className="px-4 py-3 font-bold whitespace-nowrap bg-[var(--surface-base)]">التاريخ والقائم بالعملية</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]/60">
                {transactions.map((tx) => {
                  const isInflow = tx.transactionType === 'inflow';
                  return (
                    <tr
                      key={tx.id}
                      data-focus-id={tx.id}
                      className={`hover:bg-[var(--surface-raised)]/30 transition-colors ${focusedId === tx.id ? 'entity-focus-highlight' : ''}`}
                    >
                      <td className="px-4 py-3">
                        <span
                          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full font-bold text-[11px] whitespace-nowrap ${
                            isInflow
                              ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300'
                              : 'bg-red-100 text-red-800 dark:bg-red-950/40 dark:text-red-300'
                          }`}
                        >
                          {isInflow ? (
                            <>
                              <ArrowDownLeft className="w-3.5 h-3.5 text-emerald-600 dark:text-emerald-400" />
                              إيداع
                            </>
                          ) : (
                            <>
                              <ArrowUpRight className="w-3.5 h-3.5 text-red-600 dark:text-red-400" />
                              سحب
                            </>
                          )}
                        </span>
                      </td>

                      <td className="px-4 py-3 font-mono font-black text-sm whitespace-nowrap">
                        <span className={isInflow ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'}>
                          {isInflow ? '+' : '-'}
                          {tx.amount.toLocaleString('ar-EG-u-nu-latn')} <span className="text-xs font-medium">ج.م</span>
                        </span>
                      </td>

                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1.5 font-bold text-[var(--text-primary)]">
                          <UserCheck className="w-3.5 h-3.5 text-[var(--text-muted)] shrink-0" />
                          <span className="truncate max-w-[140px]">{tx.employeeName}</span>
                        </div>
                      </td>

                      <td className="px-4 py-3 max-w-[200px]">
                        <p className="font-medium text-[var(--text-primary)] leading-tight line-clamp-2">{tx.reason}</p>
                        {tx.notes && <p className="text-[11px] text-[var(--text-muted)] mt-0.5 line-clamp-1">{tx.notes}</p>}
                      </td>

                      <td className="px-4 py-3">
                        <span className="rounded-md bg-[var(--surface-raised)] px-2.5 py-1 text-[11px] font-medium border border-[var(--border)] whitespace-nowrap">
                          {tx.category}
                        </span>
                      </td>

                      <td className="px-4 py-3 font-mono font-bold text-gray-700 dark:text-gray-300 whitespace-nowrap">
                        {tx.balanceAfter.toLocaleString('ar-EG-u-nu-latn')} <span className="text-xs font-medium">ج.م</span>
                      </td>

                      <td className="px-4 py-3 text-[var(--text-muted)] whitespace-nowrap">
                        <p className="flex items-center gap-1">
                          <Clock className="w-3 h-3 text-[var(--text-muted)]" />
                          {new Date(tx.createdAt).toLocaleDateString('ar-EG-u-nu-latn', {
                            year: 'numeric',
                            month: 'short',
                            day: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </p>
                        {tx.performerName && <p className="text-[10px] text-[var(--text-muted)] mt-0.5">بواسطة: {tx.performerName}</p>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* ═══ حوار سحب مبلغ من صندوق الزمالة (خاص بالأدمن فقط) ═══ */}
      {withdrawOpen && (
        <DialogOverlay title="سحب مبلغ من صندوق الزمالة والتكافل" onClose={() => setWithdrawOpen(false)} maxWidth="max-w-lg">
          <form onSubmit={handleWithdrawSubmit} className="space-y-4 p-4 text-end">
            {/* لافتة الشفافية والتنبيه */}
            <div className="rounded-xl border border-amber-500/30 bg-amber-50/50 dark:bg-amber-950/20 p-3 text-xs text-amber-800 dark:text-amber-300 space-y-1">
              <div className="flex items-center gap-1.5 font-bold">
                <AlertTriangle className="w-4 h-4 text-amber-500 shrink-0" />
                <span>إشعار شفافية إلزامي لكامل الفريق</span>
              </div>
              <p className="leading-relaxed">سيتم إرسال إشعار فوري لكافة أعضاء الفريق بمبلغ السحب والسبب والرصيد المتبقي بمجرد التنفيذ لضمان علم الجميع.</p>
              <div className="pt-1 text-[11px] font-mono">
                الرصيد المتاح حالياً: <span className="font-bold">{currentBalance.toLocaleString('ar-EG-u-nu-latn')} ج.م</span>
              </div>
            </div>

            {actionError && (
              <div className="rounded-lg bg-red-50 dark:bg-red-950/30 p-2.5 text-xs text-red-600 dark:text-red-400 border border-red-200 dark:border-red-900/30">
                {actionError}
              </div>
            )}

            <div>
              <label className="block text-xs font-bold mb-1">المبلغ المراد سحبه (ج.م) *</label>
              <input
                type="number"
                step="any"
                min={1}
                max={currentBalance}
                required
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                placeholder="أدخل المبلغ..."
                className="input w-full font-mono font-bold"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-bold mb-1">فئة السحب *</label>
                <select value={withdrawCategory} onChange={(e) => setWithdrawCategory(e.target.value)} className="input w-full text-xs">
                  {FELLOWSHIP_CATEGORIES.filter((c) => c !== 'غرامة تأخير حضور').map((cat) => (
                    <option key={cat} value={cat}>
                      {cat}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold mb-1">الموظف المستفيد (اختياري)</label>
                <select value={beneficiaryId} onChange={(e) => setBeneficiaryId(e.target.value)} className="input w-full text-xs">
                  <option value="">دعم عام / جهة مؤسسية</option>
                  {employees.map((emp) => (
                    <option key={emp.id} value={emp.id}>
                      {emp.fullNameAr}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold mb-1">سبب السحب بالتفصيل (لماذا) *</label>
              <textarea
                required
                rows={3}
                value={withdrawReason}
                onChange={(e) => setWithdrawReason(e.target.value)}
                placeholder="وضح سبب السحب بدقة ومبرراته ليتم إرساله في الإشعار للفريق..."
                className="input w-full text-xs"
              />
            </div>

            <div>
              <label className="block text-xs font-bold mb-1">ملاحظات إدارية (اختياري)</label>
              <input
                type="text"
                value={withdrawNotes}
                onChange={(e) => setWithdrawNotes(e.target.value)}
                placeholder="أي ملاحظات أو مستندات مرجعية..."
                className="input w-full text-xs"
              />
            </div>

            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setWithdrawOpen(false)} className="btn-secondary flex-1" disabled={withdrawMutation.isPending}>
                إلغاء
              </button>
              <button type="submit" className="btn-primary flex-1 bg-red-600 hover:bg-red-700 text-white" disabled={withdrawMutation.isPending}>
                {withdrawMutation.isPending ? 'جاري تنفيذ السحب...' : 'تأكيد السحب وإشعار الفريق'}
              </button>
            </div>
          </form>
        </DialogOverlay>
      )}
    </div>
  );
}
