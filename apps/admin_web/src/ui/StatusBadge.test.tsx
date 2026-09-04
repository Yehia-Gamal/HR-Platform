import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it('يعرض الحالة المعروفة بشكل صحيح', () => {
    const { container } = render(<StatusBadge status="active" />);
    expect(container.textContent).toContain('نشط');
  });

  it('يعرض حالة غير معروفة كما هي', () => {
    const { container } = render(<StatusBadge status="custom_status" />);
    expect(container.textContent).toContain('custom_status');
  });

  it('يقبل label مخصص يتجاوز الافتراضي', () => {
    const { container } = render(<StatusBadge status="active" label="فعّال" />);
    expect(container.textContent).toContain('فعّال');
  });

  it('يستخدم value بدلاً من status عند توفره', () => {
    const { container } = render(<StatusBadge status="active" value="pending" />);
    expect(container.textContent).toContain('قيد المراجعة');
  });

  it('يطبق class الـ tone الصحيح', () => {
    const { container } = render(<StatusBadge status="active" />);
    const badge = container.querySelector('.status-badge');
    expect(badge?.classList.contains('status-success')).toBe(true);
  });

  it('يعرض أيقونة مخفية عن قارئات الشاشة', () => {
    const { container } = render(<StatusBadge status="active" />);
    const icon = container.querySelector('[aria-hidden="true"]');
    expect(icon).toBeTruthy();
  });

  // اختبار تغطية كل الحالات المهمة
  const criticalStatuses = [
    ['draft', 'مسودة', 'neutral'],
    ['invited', 'تمت الدعوة', 'info'],
    ['active', 'نشط', 'success'],
    ['pending', 'قيد المراجعة', 'warning'],
    ['rejected', 'مرفوض', 'danger'],
    ['approved', 'معتمد', 'success'],
    ['cancelled', 'ملغي', 'neutral'],
    ['terminated', 'منتهي', 'danger'],
    ['present', 'حاضر', 'success'],
    ['absent', 'غائب', 'danger'],
    ['on_leave', 'في إجازة', 'info'],
  ] as const;

  criticalStatuses.forEach(([status, label, tone]) => {
    it(`يعرض حالة "${status}" بالعربية: "${label}" مع tone: "${tone}"`, () => {
      const { container } = render(<StatusBadge status={status} />);
      expect(container.textContent).toContain(label);
      expect(container.querySelector(`.status-${tone}`)).toBeTruthy();
    });
  });
});
