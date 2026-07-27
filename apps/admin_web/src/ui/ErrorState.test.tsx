import { fireEvent, render } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ErrorBanner, ErrorState } from './ErrorState';

describe('ErrorState', () => {
  it('يعرض العنوان الافتراضي', () => {
    const { container } = render(<ErrorState />);
    expect(container.textContent).toContain('تعذّر تحميل البيانات');
  });

  it('يعرض عنواناً مخصصاً', () => {
    const { container } = render(<ErrorState title="خطأ في الشبكة" />);
    expect(container.textContent).toContain('خطأ في الشبكة');
  });

  it('يعرض الوصف عند توفره', () => {
    const { container } = render(<ErrorState description="تحقق من الاتصال" />);
    expect(container.textContent).toContain('تحقق من الاتصال');
  });

  it('لا يعرض وصفاً عندما لا يُمرر', () => {
    const { container } = render(<ErrorState />);
    const paragraphs = container.querySelectorAll('p');
    // فقط h2، لا فقرة وصف
    expect(paragraphs.length).toBe(0);
  });

  it('يعرض زر إعادة المحاولة عند onRetry', () => {
    const onRetry = vi.fn();
    const { container } = render(<ErrorState onRetry={onRetry} />);
    expect(container.textContent).toContain('إعادة المحاولة');
    const button = container.querySelector('button');
    expect(button).toBeTruthy();
    fireEvent.click(button!);
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('يعرض action مخصص بدلاً من زر إعادة المحاولة', () => {
    const { container } = render(
      <ErrorState onRetry={() => {}} action={<a href="/home">الرئيسية</a>} />,
    );
    // action يتجاوز onRetry
    expect(container.textContent).toContain('الرئيسية');
    expect(container.textContent).not.toContain('إعادة المحاولة');
  });

  it('يحتوي على role="alert" للوصولية', () => {
    const { container } = render(<ErrorState />);
    expect(container.querySelector('[role="alert"]')).toBeTruthy();
  });

  it('يعرض أيقونة التحذير مخفية عن قارئات الشاشة', () => {
    const { container } = render(<ErrorState />);
    expect(container.querySelector('[aria-hidden="true"]')).toBeTruthy();
  });
});

describe('ErrorBanner', () => {
  it('يعرض رسالة الخطأ', () => {
    const { container } = render(<ErrorBanner message="فشل الحفظ" />);
    expect(container.textContent).toContain('فشل الحفظ');
  });

  it('يحتوي على role="alert"', () => {
    const { container } = render(<ErrorBanner message="خطأ" />);
    expect(container.querySelector('[role="alert"]')).toBeTruthy();
  });
});
