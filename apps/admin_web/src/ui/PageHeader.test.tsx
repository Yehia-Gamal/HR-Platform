import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { PageHeader } from './PageHeader';

describe('PageHeader', () => {
  it('يعرض العنوان', () => {
    render(<PageHeader title="إدارة الموظفين" />);
    expect(screen.getByRole('heading', { level: 1 })).toBeDefined();
    expect(screen.getByText('إدارة الموظفين')).toBeDefined();
  });

  it('يعرض الوصف عند توفره', () => {
    render(<PageHeader title="الموظفون" description="قائمة الموظفين النشطين" />);
    expect(screen.getByText('قائمة الموظفين النشطين')).toBeDefined();
  });

  it('يعرض eyebrow عند توفره', () => {
    render(<PageHeader title="الحضور" eyebrow="لوحة التحكم" />);
    expect(screen.getByText('لوحة التحكم')).toBeDefined();
  });

  it('يعرض أزرار الإجراءات عند توفرها', () => {
    render(
      <PageHeader title="الموظفون" actions={<button>إضافة موظف</button>} />,
    );
    expect(screen.getByText('إضافة موظف')).toBeDefined();
  });

  it('لا يعرض الوصف أو الأزرار عند عدم توفرها', () => {
    const { container } = render(<PageHeader title="الموظفون" />);
    expect(container.querySelectorAll('p')).toHaveLength(0);
  });
});
