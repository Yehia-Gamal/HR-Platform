import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { EmptyState } from './EmptyState';

describe('EmptyState', () => {
  it('يعرض العنوان والوصف', () => {
    render(<EmptyState title="لا توجد بيانات" description="لم يتم العثور على نتائج" />);
    expect(screen.getByText('لا توجد بيانات')).toBeDefined();
    expect(screen.getByText('لم يتم العثور على نتائج')).toBeDefined();
  });

  it('يعرض زر الإجراء عند توفره', () => {
    render(<EmptyState title="لا توجد بيانات" description="لم يتم العثور على نتائج" action={<button>إضافة جديد</button>} />);
    expect(screen.getByText('إضافة جديد')).toBeDefined();
  });

  it('لا يعرض زر إجراء عند عدم توفره', () => {
    const { container } = render(<EmptyState title="لا توجد بيانات" description="لم يتم العثور على نتائج" />);
    expect(container.querySelectorAll('button')).toHaveLength(0);
  });
});
