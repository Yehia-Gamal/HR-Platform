import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { Users } from 'lucide-react';
import { MetricCard } from './MetricCard';

describe('MetricCard', () => {
  it('يعرض التسمية والقيمة', () => {
    render(<MetricCard label="إجمالي الموظفين" value={150} icon={Users} />);
    expect(screen.getByText('إجمالي الموظفين')).toBeDefined();
    expect(screen.getByText('150')).toBeDefined();
  });

  it('يقبل قيمة نصية', () => {
    render(<MetricCard label="النسبة" value="95%" icon={Users} />);
    expect(screen.getByText('95%')).toBeDefined();
  });

  it('يعرض التلميح عند توفره', () => {
    render(<MetricCard label="الحضور" value={45} icon={Users} hint="آخر 30 يوم" />);
    expect(screen.getByText('آخر 30 يوم')).toBeDefined();
  });

  it('يعرض الاتجاه عند توفره', () => {
    render(<MetricCard label="الأداء" value={88} icon={Users} trend="+5%" />);
    expect(screen.getByText('+5%')).toBeDefined();
  });

  it('لا يعرض hint أو trend عند عدم توفرها', () => {
    const { container } = render(<MetricCard label="المجموع" value={10} icon={Users} />);
    const paragraphs = container.querySelectorAll('p');
    // label + value فقط
    expect(paragraphs.length).toBeLessThanOrEqual(2);
  });
});
