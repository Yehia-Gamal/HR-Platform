import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { DepartmentPicker, PeoplePicker } from './TeamPicker';

const employees = [
  { id: '00000000-0000-4000-8000-000000000001', name: 'أحمد علي', jobTitle: 'منسق', departmentId: null, departmentName: 'الإعلام' },
  { id: '00000000-0000-4000-8000-000000000002', name: 'إيمان سعيد', jobTitle: 'محاسبة', departmentId: null, departmentName: 'المالية' },
  { id: '00000000-0000-4000-8000-000000000003', name: 'فاطمة حسن', jobTitle: null, departmentId: null, departmentName: null },
];
const [AHMED, IMAN, FATMA] = employees.map((e) => e.id) as [string, string, string];

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
    render(<PeoplePicker label="قائد المشروع" single employees={employees} selected={[AHMED]} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: /فاطمة حسن/ }));
    expect(onChange).toHaveBeenCalledWith([FATMA]);
  });

  it('الأعضاء: إضافة وإزالة، والقائد مستبعد من القائمة', () => {
    const onChange = vi.fn();
    render(
      <PeoplePicker
        label="أعضاء الفريق"
        employees={employees}
        selected={[IMAN]}
        exclude={[AHMED]}
        onChange={onChange}
      />,
    );
    expect(screen.queryByRole('button', { name: /أحمد علي/ })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /فاطمة حسن/ }));
    expect(onChange).toHaveBeenLastCalledWith([IMAN, FATMA]);
    fireEvent.click(screen.getByRole('button', { name: 'إزالة إيمان سعيد' }));
    expect(onChange).toHaveBeenLastCalledWith([]);
  });
});

describe('DepartmentPicker', () => {
  it('الإدارات اختيارية ومتعددة', () => {
    const onChange = vi.fn();
    const MEDIA = '00000000-0000-4000-8000-00000000000a';
    const FINANCE = '00000000-0000-4000-8000-00000000000b';
    const departments = [
      { id: MEDIA, name: 'الإعلام' },
      { id: FINANCE, name: 'المالية' },
    ];
    render(<DepartmentPicker departments={departments} selected={[MEDIA]} onChange={onChange} />);
    expect(screen.getByRole('button', { name: 'الإعلام' })).toHaveAttribute('aria-pressed', 'true');
    fireEvent.click(screen.getByRole('button', { name: 'المالية' }));
    expect(onChange).toHaveBeenCalledWith([MEDIA, FINANCE]);
  });
});
