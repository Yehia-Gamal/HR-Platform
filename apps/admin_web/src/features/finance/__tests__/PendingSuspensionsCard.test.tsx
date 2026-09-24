import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PendingSuspension } from '@ahla/shared-contracts';
import { PendingSuspensionsCard } from '../PendingSuspensionsCard';

let canSuspend: boolean;
let pendingData: { data?: PendingSuspension[] };
let isPending: boolean;
const mutate = vi.fn();

vi.mock('../usePendingSuspensions', () => ({
  useCanSuspendEmployees: () => canSuspend,
  usePendingSuspensions: () => pendingData,
  useSuspendEmployeeForPenalty: () => ({ mutate, isPending }),
}));

vi.mock('../../../core/errorMapper', () => ({
  safeErrorMessage: () => 'تعذّر تنفيذ القرار',
}));

const row: PendingSuspension = {
  penaltyId: '11111111-1111-4111-8111-111111111111',
  employeeId: '22222222-2222-4222-8222-222222222222',
  employeeName: 'موظف متأخر',
  employeeCode: 'E-77',
  departmentName: 'الإدارة المالية',
  workDate: '2026-09-18',
  amount: 500,
  daysOverdue: 6,
};

beforeEach(() => {
  canSuspend = true;
  pendingData = { data: [row] };
  isPending = false;
  mutate.mockReset();
});

describe('PendingSuspensionsCard', () => {
  it('لا يظهر لمن لا يملك قرار التعليق', () => {
    canSuspend = false;
    const { container } = render(<PendingSuspensionsCard />);
    expect(container).toBeEmptyDOMElement();
  });

  it('لا يظهر حين لا يوجد مستحقون', () => {
    pendingData = { data: [] };
    const { container } = render(<PendingSuspensionsCard />);
    expect(container).toBeEmptyDOMElement();
  });

  it('يعرض المستحقين مع التأخير والقسم', () => {
    render(<PendingSuspensionsCard />);
    expect(screen.getByText('مستحقون للتعليق — بانتظار قرارك')).toBeInTheDocument();
    expect(screen.getByText('موظف متأخر')).toBeInTheDocument();
    expect(screen.getByText(/الإدارة المالية · غرامة يوم 2026-09-18/)).toBeInTheDocument();
    expect(screen.getByText(/متأخر 6 يوم/)).toBeInTheDocument();
  });

  it('يفتح نافذة التأكيد ويشترط سبباً قبل التنفيذ', () => {
    render(<PendingSuspensionsCard />);
    fireEvent.click(screen.getByRole('button', { name: 'تعليق موظف متأخر' }));

    expect(screen.getByText('تأكيد تعليق الموظف')).toBeInTheDocument();
    const confirm = screen.getByRole('button', { name: 'تعليق الموظف' });
    expect(confirm).toBeDisabled();

    fireEvent.change(screen.getByRole('textbox', { name: 'سبب القرار' }), { target: { value: 'ab' } });
    expect(confirm).toBeDisabled();
    expect(mutate).not.toHaveBeenCalled();
  });

  it('ينفّذ القرار بالسبب بعد تنقيته', () => {
    render(<PendingSuspensionsCard />);
    fireEvent.click(screen.getByRole('button', { name: 'تعليق موظف متأخر' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'سبب القرار' }), {
      target: { value: '  لم يُسدَّد رغم التذكير  ' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'تعليق الموظف' }));

    expect(mutate).toHaveBeenCalledTimes(1);
    expect(mutate.mock.calls[0][0]).toEqual({ penaltyId: row.penaltyId, reason: 'لم يُسدَّد رغم التذكير' });
  });

  it('يغلق النافذة عند النجاح', () => {
    mutate.mockImplementation((_args, opts: { onSuccess: () => void }) => opts.onSuccess());
    render(<PendingSuspensionsCard />);
    fireEvent.click(screen.getByRole('button', { name: 'تعليق موظف متأخر' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'سبب القرار' }), { target: { value: 'قرار الإدارة' } });
    fireEvent.click(screen.getByRole('button', { name: 'تعليق الموظف' }));

    expect(screen.queryByText('تأكيد تعليق الموظف')).not.toBeInTheDocument();
  });

  it('يعرض الخطأ داخل النافذة ويبقيها مفتوحة', () => {
    mutate.mockImplementation((_args, opts: { onError: (e: unknown) => void }) => opts.onError(new Error('x')));
    render(<PendingSuspensionsCard />);
    fireEvent.click(screen.getByRole('button', { name: 'تعليق موظف متأخر' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'سبب القرار' }), { target: { value: 'قرار الإدارة' } });
    fireEvent.click(screen.getByRole('button', { name: 'تعليق الموظف' }));

    expect(screen.getByText('تعذّر تنفيذ القرار')).toBeInTheDocument();
    expect(screen.getByText('تأكيد تعليق الموظف')).toBeInTheDocument();
  });
});
