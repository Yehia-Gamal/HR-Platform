import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { DepartmentPicker, PeoplePicker } from './TeamPicker';

const employees = [
  { id: '00000000-0000-4000-8000-000000000001', name: 'أحمد علي', jobTitle: 'منسق', departmentId: null, departmentName: 'الإعلام' },
  { id: '00000000-0000-4000-8000-000000000002', name: 'إيمان سعيد', jobTitle: 'محاسبة', departmentId: null, departmentName: 'المالية' },
  { id: '00000000-0000-4000-8000-000000000003', name: 'فاطمة حسن', jobTitle: null, departmentId: null, departmentName: null },
];

describe('PeoplePicker (فريق المشروع 0645)', () => {
  it('البحث يتجاهل الهمزات: «احمد» يجد «أحمد»', () => {
    render(<PeoplePicker label="أعضاء الفريق" employees={employees} selected={[]} onChange={() => {}} />);
    fireEvent.change(screen.getByPlaceholderText('ابحث بالاسم أو الوظيفة أو الإدارة'), { target: { value: 'احمد' } });
    expect(screen.getByText('أحمد علي')).toBeInTheDocument();
    expect(screen.queryByText('إيمان سعيد')).not.toBeInTheDocument();
  });

  it('البحث بالإدارة', () => {
    render(<PeoplePicker label="أعضاء الفريق" employees={employees} selected={[]} onChange={() => {}} />);
    fireEvent.change(screen.getByPlaceholderText('ابحث بالاسم أو الوظيفة أو الإدارة'), { target: { value: 'المالية' } });
    expect(screen.getByText('إيمان سعيد')).toBeInTheDocument();
    expect(screen.queryByText('أحمد علي')).not.toBeInTheDocument();
  });

  it('اختيار القائد يستبدل الاختيار السابق (شخص واحد فقط)', () => {
    const onChange = vi.fn();
    render(<PeoplePicker label="قائد المشروع" single employees={employees} selected={[employees[0]!.id]} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: /فاطمة حسن/ }));
    expect(onChange).toHaveBeenCalledWith([employees[2]!.id]);
  });

  it('الأعضاء: إضافة وإزالة، والقائد مستبعد من القائمة', () => {
    const onChange = vi.fn();
    render(
      <PeoplePicker
        label="أعضاء الفريق"
        employees={employees}
        selected={[employees[1]!.id]}
        exclude={[employees[0]!.id]}
        onChange={onChange}
      />,
    );
    expect(screen.queryByRole('button', { name: /أحمد علي/ })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /فاطمة حسن/ }));
    expect(onChange).toHaveBeenLastCalledWith([employees[1]!.id, employees[2]!.id]);
    fireEvent.click(screen.getByRole('button', { name: 'إزالة إيمان سعيد' }));
    expect(onChange).toHaveBeenLastCalledWith([]);
  });
});

describe('DepartmentPicker', () => {
  it('الإدارات اختيارية ومتعددة', () => {
    const onChange = vi.fn();
    const departments = [
      { id: '00000000-0000-4000-8000-00000000000a', name: 'الإعلام' },
      { id: '00000000-0000-4000-8000-00000000000b', name: 'المالية' },
    ];
    render(<DepartmentPicker departments={departments} selected={[departments[0]!.id]} onChange={onChange} />);
    expect(screen.getByRole('button', { name: 'الإعلام' })).toHaveAttribute('aria-pressed', 'true');
    fireEvent.click(screen.getByRole('button', { name: 'المالية' }));
    expect(onChange).toHaveBeenCalledWith([departments[0]!.id, departments[1]!.id]);
  });
});
