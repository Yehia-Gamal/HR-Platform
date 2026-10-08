import React, { useMemo, useState } from 'react';
import {
  Clock,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  TrendingUp,
  UserCheck,
  Search,
  Calendar,
  Download,
  Flame,
  ArrowUpDown,
  RefreshCw,
} from 'lucide-react';
import { useApprovalSpeedReport, ApproverSpeedItem } from './useApprovalSpeedReport';

const REQUEST_TYPE_LABELS: Record<string, string> = {
  mission: 'مأمورية عمل',
  leave: 'طلب إجازة',
  convoy: 'قافلة خارجية',
  late_permit: 'إذن تأخير',
  early_permit: 'إذن انصراف مبكر',
  fundraising: 'حملة تبرع',
  work_assignment: 'تكليف عمل',
  overtime: 'ساعات إضافية',
  payroll_advance: 'سلفة مالية',
  resignation: 'استقالة',
  dispute: 'نزاع جزاء',
};

function formatHours(hours: number): string {
  if (hours <= 0) return '0 س';
  if (hours < 1) {
    const mins = Math.round(hours * 60);
    return `${mins} د`;
  }
  return `${hours.toFixed(1)} س`;
}

function getSpeedBadge(avgHours: number) {
  if (avgHours === 0) {
    return {
      text: 'لا قرارات',
      className: 'bg-[var(--surface-muted)] text-[var(--text-muted)] border-[var(--border)]',
    };
  }
  if (avgHours <= 4) {
    return {
      text: 'سريع جداً (أقل من 4 س)',
      className: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20',
    };
  }
  if (avgHours <= 24) {
    return {
      text: 'معتدل (4-24 س)',
      className: 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    };
  }
  return {
    text: 'بطيء (أكثر من 24 س)',
    className: 'bg-rose-500/10 text-rose-600 dark:text-rose-400 border-rose-500/20',
  };
}

export function ApprovalSpeedPage() {
  const [fromDate, setFromDate] = useState<string>('');
  const [toDate, setToDate] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [sortBy, setSortBy] = useState<'decisions' | 'avg_hours' | 'pending' | 'escalated'>('decisions');
  const [sortAsc, setSortAsc] = useState<boolean>(false);

  const { data, isLoading, isError, error, refetch, isFetching } = useApprovalSpeedReport(fromDate, toDate);

  const summary = data?.summary;
  const approvers = data?.approvers ?? [];
  const byRequestType = data?.byRequestType ?? [];

  const filteredApprovers = useMemo(() => {
    let list = [...approvers];
    if (searchQuery.trim()) {
      const q = searchQuery.trim().toLowerCase();
      list = list.filter(
        (a) => a.name.toLowerCase().includes(q) || a.code.toLowerCase().includes(q),
      );
    }

    list.sort((a, b) => {
      let valA = 0;
      let valB = 0;
      if (sortBy === 'decisions') {
        valA = a.total_decisions;
        valB = b.total_decisions;
      } else if (sortBy === 'avg_hours') {
        valA = a.avg_hours;
        valB = b.avg_hours;
      } else if (sortBy === 'pending') {
        valA = a.pending_count;
        valB = b.pending_count;
      } else if (sortBy === 'escalated') {
        valA = a.escalated_count;
        valB = b.escalated_count;
      }
      return sortAsc ? valA - valB : valB - valA;
    });

    return list;
  }, [approvers, searchQuery, sortBy, sortAsc]);

  const handleSort = (field: 'decisions' | 'avg_hours' | 'pending' | 'escalated') => {
    if (sortBy === field) {
      setSortAsc(!sortAsc);
    } else {
      setSortBy(field);
      setSortAsc(false);
    }
  };

  const handlePreset = (preset: 'today' | '7days' | 'month' | 'all') => {
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    const toStr = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

    if (preset === 'today') {
      setFromDate(toStr);
      setToDate(toStr);
    } else if (preset === '7days') {
      const past = new Date(now.getTime() - 7 * 86400000);
      setFromDate(`${past.getFullYear()}-${pad(past.getMonth() + 1)}-${pad(past.getDate())}`);
      setToDate(toStr);
    } else if (preset === 'month') {
      setFromDate(`${now.getFullYear()}-${pad(now.getMonth() + 1)}-01`);
      setToDate(toStr);
    } else {
      setFromDate('');
      setToDate('');
    }
  };

  const exportCsv = () => {
    if (!approvers.length) return;
    const header = [
      'اسم المعتمد',
      'كود الموظف / الهاتف',
      'إجمالي القرارات',
      'مقبول',
      'مرفوض',
      'متوسط زمن الرد (ساعات)',
      'وسيط زمن الرد (ساعات)',
      'طلبات معلقة',
      'أقدم معلق (ساعات)',
      'تم تصعيده',
    ];

    const rows = filteredApprovers.map((a) => [
      `"${a.name.replace(/"/g, '""')}"`,
      `"${a.code}"`,
      a.total_decisions,
      a.approved_count,
      a.rejected_count,
      a.avg_hours,
      a.median_hours,
      a.pending_count,
      a.oldest_pending_hours,
      a.escalated_count,
    ]);

    const csvContent = '\uFEFF' + [header.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `approval_speed_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  if (isLoading) {
    return (
      <div className="space-y-6 animate-pulse" dir="rtl">
        <div className="h-20 rounded-2xl bg-[var(--surface-card)] border border-[var(--border)]" />
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-28 rounded-2xl bg-[var(--surface-card)] border border-[var(--border)]" />
          ))}
        </div>
        <div className="h-96 rounded-2xl bg-[var(--surface-card)] border border-[var(--border)]" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="rounded-2xl border border-rose-500/20 bg-rose-500/5 p-6 text-center" dir="rtl">
        <AlertTriangle className="mx-auto h-10 w-10 text-rose-500 mb-2" />
        <h3 className="text-base font-bold text-rose-600 dark:text-rose-400">تعذر تحميل تقرير سرعة الاعتمادات</h3>
        <p className="text-sm text-[var(--text-muted)] mt-1">{error?.message || 'تأكد من صلاحيات الوصول'}</p>
        <button
          type="button"
          onClick={() => refetch()}
          className="mt-4 inline-flex items-center gap-2 rounded-xl bg-[var(--brand-primary)] px-4 py-2 text-xs font-bold text-white hover:opacity-90"
        >
          <RefreshCw className="h-4 w-4" /> إعادة المحاولة
        </button>
      </div>
    );
  }

  const approvalRate =
    summary && summary.total_decisions > 0
      ? Math.round((summary.total_approved / summary.total_decisions) * 100)
      : 0;

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header & Filters */}
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-5 shadow-sm">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[var(--brand-primary)]/10 text-[var(--brand-primary)]">
              <Clock className="h-5 w-5" />
            </div>
            <div>
              <h1 className="text-lg font-black text-[var(--text-primary)]">لوحة سرعة الاعتمادات وSLA</h1>
              <p className="text-xs text-[var(--text-muted)]">
                رصد وتحليل زمن استجابة متخذي القرار ومعدل إنجاز مسارات الطلبات
              </p>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] px-2.5 py-1.5 text-xs text-[var(--text-muted)]">
            <Calendar className="h-3.5 w-3.5" />
            <input
              type="date"
              aria-label="من تاريخ"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
              className="bg-transparent text-[var(--text-primary)] focus:outline-none text-xs"
            />
            <span>إلى</span>
            <input
              type="date"
              aria-label="إلى تاريخ"
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
              className="bg-transparent text-[var(--text-primary)] focus:outline-none text-xs"
            />
          </div>

          <div className="flex items-center gap-1 rounded-xl border border-[var(--border)] p-1 text-xs">
            <button
              type="button"
              onClick={() => handlePreset('today')}
              className="rounded-lg px-2.5 py-1 text-[var(--text-muted)] hover:bg-[var(--surface-raised)] transition-colors"
            >
              اليوم
            </button>
            <button
              type="button"
              onClick={() => handlePreset('7days')}
              className="rounded-lg px-2.5 py-1 text-[var(--text-muted)] hover:bg-[var(--surface-raised)] transition-colors"
            >
              7 أيام
            </button>
            <button
              type="button"
              onClick={() => handlePreset('month')}
              className="rounded-lg px-2.5 py-1 text-[var(--text-muted)] hover:bg-[var(--surface-raised)] transition-colors"
            >
              الشهر
            </button>
            <button
              type="button"
              onClick={() => handlePreset('all')}
              className="rounded-lg px-2.5 py-1 text-[var(--text-muted)] hover:bg-[var(--surface-raised)] transition-colors"
            >
              الكل
            </button>
          </div>

          <button
            type="button"
            onClick={exportCsv}
            disabled={!approvers.length}
            className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] px-3 py-1.5 text-xs font-bold text-[var(--text-primary)] hover:bg-[var(--surface-card)] transition-colors disabled:opacity-50"
          >
            <Download className="h-3.5 w-3.5" />
            <span>تصدير CSV</span>
          </button>

          <button
            type="button"
            onClick={() => refetch()}
            className="flex h-8 w-8 items-center justify-center rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors"
            title="تحديث البيانات"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${isFetching ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3.5">
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>إجمالي القرارات</span>
            <TrendingUp className="h-4 w-4 text-[var(--brand-primary)]" />
          </div>
          <div className="text-2xl font-black text-[var(--text-primary)]">
            {summary?.total_decisions.toLocaleString('ar-EG') ?? 0}
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            {approvalRate}% نسبة القبول
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>وسيط زمن الرد</span>
            <Clock className="h-4 w-4 text-emerald-500" />
          </div>
          <div className="text-2xl font-black text-emerald-600 dark:text-emerald-400">
            {formatHours(summary?.median_turnaround_hours ?? 0)}
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            زمن 50% من القرارات
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>متوسط زمن الرد</span>
            <Clock className="h-4 w-4 text-blue-500" />
          </div>
          <div className="text-2xl font-black text-blue-600 dark:text-blue-400">
            {formatHours(summary?.avg_turnaround_hours ?? 0)}
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            المتوسط الحسابي
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>مقبول / مرفوض</span>
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
          </div>
          <div className="text-xl font-black text-[var(--text-primary)]">
            <span className="text-emerald-600 dark:text-emerald-400">{summary?.total_approved ?? 0}</span>
            <span className="text-[var(--text-muted)] mx-1">/</span>
            <span className="text-rose-500">{summary?.total_rejected ?? 0}</span>
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            مكتمل الإجراء
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>طلبات معلقة</span>
            <Flame className="h-4 w-4 text-amber-500" />
          </div>
          <div className="text-2xl font-black text-amber-600 dark:text-amber-400">
            {summary?.total_pending.toLocaleString('ar-EG') ?? 0}
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            بانتظار قرار المعتمد
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-4 shadow-sm">
          <div className="flex items-center justify-between text-[var(--text-muted)] text-xs mb-1.5">
            <span>تم تصعيدها</span>
            <AlertTriangle className="h-4 w-4 text-rose-500" />
          </div>
          <div className="text-2xl font-black text-rose-600 dark:text-rose-400">
            {summary?.total_escalated.toLocaleString('ar-EG') ?? 0}
          </div>
          <div className="text-[11px] text-[var(--text-muted)] mt-1">
            تجاوزت مهلة SLA
          </div>
        </div>
      </div>

      {/* Grid: Speed by Request Type & Fast Overview */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Breakdown by Request Type */}
        <div className="lg:col-span-1 rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold text-[var(--text-primary)]">السرعة حسب نوع الطلب</h2>
            <span className="text-xs text-[var(--text-muted)]">{byRequestType.length} أنواع</span>
          </div>

          {byRequestType.length === 0 ? (
            <div className="p-6 text-center text-xs text-[var(--text-muted)]">
              لا توجد قرارات في الفترة المحددة
            </div>
          ) : (
            <div className="space-y-3">
              {byRequestType.map((item) => {
                const label = REQUEST_TYPE_LABELS[item.request_type] || item.request_type;
                const badge = getSpeedBadge(item.avg_hours);
                return (
                  <div
                    key={item.request_type}
                    className="flex flex-col gap-1.5 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] p-3"
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-[var(--text-primary)]">{label}</span>
                      <span className="text-xs font-black text-[var(--brand-primary)]">
                        {item.decisions_count} قرار
                      </span>
                    </div>

                    <div className="flex items-center justify-between text-[11px] text-[var(--text-muted)]">
                      <span>متوسط: {formatHours(item.avg_hours)}</span>
                      <span>وسيط: {formatHours(item.median_hours)}</span>
                    </div>

                    <div className="h-1.5 w-full rounded-full bg-[var(--border)] overflow-hidden">
                      <div
                        className={`h-full rounded-full ${
                          item.avg_hours <= 4
                            ? 'bg-emerald-500'
                            : item.avg_hours <= 24
                              ? 'bg-blue-500'
                              : 'bg-rose-500'
                        }`}
                        style={{
                          width: `${Math.min(100, Math.max(10, (100 * item.decisions_count) / (summary?.total_decisions || 1)))}%`,
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Approver Leaderboard Table */}
        <div className="lg:col-span-2 rounded-2xl border border-[var(--border)] bg-[var(--surface-card)] p-5 shadow-sm space-y-4">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h2 className="text-sm font-bold text-[var(--text-primary)]">سجل المعتمدين وسرعة الإنجاز</h2>
              <p className="text-xs text-[var(--text-muted)]">
                تصنيف المسؤولين حسب سرعة اتخاذ القرارات وحجم المعلقات
              </p>
            </div>

            <div className="relative">
              <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-[var(--text-muted)]" />
              <input
                type="text"
                placeholder="بحث بالاسم أو الهاتف..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full sm:w-56 rounded-xl border border-[var(--border)] bg-[var(--surface-raised)] py-1.5 pr-8 pl-3 text-xs text-[var(--text-primary)] placeholder-[var(--text-muted)] focus:outline-none focus:border-[var(--brand-primary)]"
              />
            </div>
          </div>

          <div className="overflow-x-auto rounded-xl border border-[var(--border)]">
            <table className="w-full text-right text-xs">
              <thead className="bg-[var(--surface-raised)] text-[var(--text-muted)]">
                <tr>
                  <th className="p-3 font-bold">المعتمد</th>
                  <th
                    className="p-3 font-bold cursor-pointer hover:text-[var(--text-primary)]"
                    onClick={() => handleSort('decisions')}
                  >
                    <div className="inline-flex items-center gap-1">
                      <span>القرارات</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </div>
                  </th>
                  <th className="p-3 font-bold">قبول / رفض</th>
                  <th
                    className="p-3 font-bold cursor-pointer hover:text-[var(--text-primary)]"
                    onClick={() => handleSort('avg_hours')}
                  >
                    <div className="inline-flex items-center gap-1">
                      <span>الوسيط / المتوسط</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </div>
                  </th>
                  <th
                    className="p-3 font-bold cursor-pointer hover:text-[var(--text-primary)]"
                    onClick={() => handleSort('pending')}
                  >
                    <div className="inline-flex items-center gap-1">
                      <span>المعلقات</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </div>
                  </th>
                  <th
                    className="p-3 font-bold cursor-pointer hover:text-[var(--text-primary)]"
                    onClick={() => handleSort('escalated')}
                  >
                    <div className="inline-flex items-center gap-1">
                      <span>المصعّدات</span>
                      <ArrowUpDown className="h-3 w-3" />
                    </div>
                  </th>
                  <th className="p-3 font-bold">مستوى السرعة</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {filteredApprovers.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="p-8 text-center text-xs text-[var(--text-muted)]">
                      لا يوجد معتمدون مطابقون للبحث
                    </td>
                  </tr>
                ) : (
                  filteredApprovers.map((app) => {
                    const badge = getSpeedBadge(app.avg_hours);
                    return (
                      <tr key={app.approver_id || app.name} className="hover:bg-[var(--surface-raised)] transition-colors">
                        <td className="p-3">
                          <div className="flex items-center gap-2">
                            <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-[var(--brand-primary)]/10 text-[var(--brand-primary)] font-bold text-xs">
                              {app.name.slice(0, 1)}
                            </div>
                            <div>
                              <div className="font-bold text-[var(--text-primary)]">{app.name}</div>
                              {app.code ? (
                                <div className="text-[10px] text-[var(--text-muted)] font-mono">{app.code}</div>
                              ) : null}
                            </div>
                          </div>
                        </td>
                        <td className="p-3 font-black text-[var(--text-primary)]">
                          {app.total_decisions.toLocaleString('ar-EG')}
                        </td>
                        <td className="p-3">
                          <span className="text-emerald-600 dark:text-emerald-400 font-bold">{app.approved_count}</span>
                          <span className="text-[var(--text-muted)] mx-1">/</span>
                          <span className="text-rose-500 font-bold">{app.rejected_count}</span>
                        </td>
                        <td className="p-3">
                          <div className="font-bold text-[var(--text-primary)]">
                            {formatHours(app.median_hours)}
                          </div>
                          <div className="text-[10px] text-[var(--text-muted)]">
                            متوسط: {formatHours(app.avg_hours)}
                          </div>
                        </td>
                        <td className="p-3">
                          {app.pending_count > 0 ? (
                            <div>
                              <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-black bg-amber-500/10 text-amber-600 dark:text-amber-400">
                                {app.pending_count} طلب
                              </span>
                              {app.oldest_pending_hours > 0 ? (
                                <div className="text-[10px] text-amber-600/80 dark:text-amber-400/80 mt-0.5">
                                  أقدمها منذ {formatHours(app.oldest_pending_hours)}
                                </div>
                              ) : null}
                            </div>
                          ) : (
                            <span className="text-[var(--text-muted)] text-[11px]">0</span>
                          )}
                        </td>
                        <td className="p-3">
                          {app.escalated_count > 0 ? (
                            <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-black bg-rose-500/10 text-rose-600 dark:text-rose-400">
                              {app.escalated_count}
                            </span>
                          ) : (
                            <span className="text-[var(--text-muted)] text-[11px]">0</span>
                          )}
                        </td>
                        <td className="p-3">
                          <span
                            className={`inline-flex items-center px-2.5 py-1 rounded-lg border text-[11px] font-bold ${badge.className}`}
                          >
                            {badge.text}
                          </span>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
