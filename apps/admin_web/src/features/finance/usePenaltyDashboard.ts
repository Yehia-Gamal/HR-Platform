import { useMemo } from 'react';
import { useInstantPenalties } from './useInstantPenalties';

const currencyFmt = new Intl.NumberFormat('ar-EG', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });
const fmt = (n: number) => currencyFmt.format(n);

export interface DashboardStats {
  total: number;
  totalAmount: number;
  byStatus: Record<string, { count: number; amount: number; label: string }>;
  byDepartment: { name: string; count: number; amount: number }[];
  byDate: { name: string; count: number; amount: number; paid: number; pending: number; doubled: number }[];
  byTier: { name: string; count: number; amount: number; color: string }[];
}

const STATUS_LABELS: Record<string, string> = {
  pending_payment: 'بانتظار الدفع',
  paid: 'مدفوعة',
  doubled: 'مضاعفة',
  suspended: 'معلّق',
  cancelled: 'ملغاة',
};

const TIER_LABELS: Record<string, { label: string; color: string }> = {
  '20': { label: '20 ج.م', color: '#0ea5e9' },
  '50': { label: '50 ج.م', color: '#f59e0b' },
  '150': { label: '150 ج.م', color: '#f97316' },
  '500': { label: '500 ج.م', color: '#a855f7' },
};

function getTierKey(amount: number): string {
  if (amount <= 20) return '20';
  if (amount <= 50) return '50';
  if (amount <= 150) return '150';
  return '500';
}

export function usePenaltyDashboard() {
  const penalties = useInstantPenalties({});

  const stats = useMemo((): DashboardStats | null => {
    const data = penalties.data;
    if (!data || data.length === 0) return null;

    const byStatus: DashboardStats['byStatus'] = {};
    const deptMap = new Map<string, { count: number; amount: number }>();
    const dateMap = new Map<string, { count: number; amount: number; paid: number; pending: number; doubled: number }>();
    const tierMap = new Map<string, { count: number; amount: number }>();

    let totalAmount = 0;

    for (const p of data) {
      totalAmount += p.currentAmount;

      if (!byStatus[p.status]) {
        byStatus[p.status] = { count: 0, amount: 0, label: STATUS_LABELS[p.status] ?? p.status };
      }
      byStatus[p.status].count++;
      byStatus[p.status].amount += p.currentAmount;

      const dept = p.departmentName ?? 'غير محدد';
      const existing = deptMap.get(dept) ?? { count: 0, amount: 0 };
      deptMap.set(dept, { count: existing.count + 1, amount: existing.amount + p.currentAmount });

      const dateKey = p.workDate;
      const dateEntry = dateMap.get(dateKey) ?? { count: 0, amount: 0, paid: 0, pending: 0, doubled: 0 };
      dateEntry.count++;
      dateEntry.amount += p.currentAmount;
      if (p.status === 'paid') dateEntry.paid++;
      else if (p.status === 'pending_payment' || p.status === 'doubled' || p.status === 'suspended') dateEntry.pending++;
      dateMap.set(dateKey, dateEntry);

      const tierKey = getTierKey(p.originalAmount);
      const tier = tierMap.get(tierKey) ?? { count: 0, amount: 0 };
      tier.count++;
      tier.amount += p.currentAmount;
      tierMap.set(tierKey, tier);
    }

    const byDepartment = [...deptMap.entries()]
      .map(([name, v]) => ({ name, ...v }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    const byDate = [...dateMap.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .slice(-30)
      .map(([name, v]) => ({ name, ...v }));

    const byTier = [...tierMap.entries()]
      .map(([key, v]) => ({
        name: TIER_LABELS[key]?.label ?? key,
        count: v.count,
        amount: v.amount,
        color: TIER_LABELS[key]?.color ?? '#6b7280',
      }))
      .sort((a, b) => a.count - b.count);

    return {
      total: data.length,
      totalAmount,
      byStatus,
      byDepartment,
      byDate,
      byTier,
    };
  }, [penalties.data]);

  return { stats, isLoading: penalties.isLoading, isError: penalties.isError, error: penalties.error, refetch: penalties.refetch, fmt };
}
