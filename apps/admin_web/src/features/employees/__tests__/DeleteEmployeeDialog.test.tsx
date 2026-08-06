import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DeleteEmployeeDialog } from '../EmployeeDetailPage';

const { deleteFn } = vi.hoisted(() => ({ deleteFn: vi.fn() }));

vi.mock('../useEmployees', () => ({
  useDeleteEmployee: () => ({ isPending: false, mutateAsync: deleteFn, error: null }),
}));

const baseProps = {
  employeeId: '00000000-0000-0000-0000-000000000010',
  employeeCode: 'EMP-101',
  employeeName: 'أحمد محمد',
  onClose: vi.fn(),
  onSuccess: vi.fn(),
};

describe('DeleteEmployeeDialog', () => {
  beforeEach(() => {
    deleteFn.mockReset();
    deleteFn.mockResolvedValue(undefined);
  });

  it('يتطلب سبب حذف حقيقيًا (10 أحرف) بجانب مطابقة كود الموظف', () => {
    render(<DeleteEmployeeDialog {...baseProps} />);
    const submit = screen.getByRole('button', { name: 'حذف نهائي' });

    fireEvent.change(screen.getByPlaceholderText('EMP-101'), { target: { value: 'EMP-101' } });
    fireEvent.change(screen.getByLabelText('سبب الحذف النهائي'), { target: { value: 'سبب قصير' } });
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText('سبب الحذف النهائي'), { target: { value: 'مخالفة أخلاقية موثقة بالتقرير' } });
    expect(submit).toBeEnabled();
  });

  it('يعطّل الزر حتى يطابق كود الموظف تمامًا', () => {
    render(<DeleteEmployeeDialog {...baseProps} />);
    const submit = screen.getByRole('button', { name: 'حذف نهائي' });

    fireEvent.change(screen.getByLabelText('سبب الحذف النهائي'), { target: { value: 'مخالفة أخلاقية موثقة بالتقرير' } });
    fireEvent.change(screen.getByPlaceholderText('EMP-101'), { target: { value: 'EMP-102' } });
    expect(submit).toBeDisabled();
  });

  it('يرسل السبب الذي أدخله المسؤول لا سببًا ثابتًا', async () => {
    render(<DeleteEmployeeDialog {...baseProps} />);

    fireEvent.change(screen.getByPlaceholderText('EMP-101'), { target: { value: 'EMP-101' } });
    fireEvent.change(screen.getByLabelText('سبب الحذف النهائي'), { target: { value: '  مخالفة أخلاقية موثقة  ' } });
    fireEvent.click(screen.getByRole('button', { name: 'حذف نهائي' }));

    expect(deleteFn).toHaveBeenCalledWith({
      employeeId: baseProps.employeeId,
      confirmationCode: 'EMP-101',
      reason: 'مخالفة أخلاقية موثقة',
    });
  });
});
