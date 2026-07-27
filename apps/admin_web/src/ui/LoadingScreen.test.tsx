import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { LoadingScreen } from './LoadingScreen';

describe('LoadingScreen', () => {
  it('يعرض نص التحميل الافتراضي', () => {
    const { container } = render(<LoadingScreen />);
    expect(container.textContent).toContain('جارٍ تحميل النظام…');
  });

  it('يعرض نص تحميل مخصص', () => {
    const { container } = render(<LoadingScreen label="جارٍ التحقق…" />);
    expect(container.textContent).toContain('جارٍ التحقق…');
  });

  it('يحتوي على aria-busy للوصولية', () => {
    const { container } = render(<LoadingScreen />);
    expect(container.querySelector('[aria-busy="true"]')).toBeTruthy();
  });

  it('يعرض الشعار', () => {
    const { container } = render(<LoadingScreen />);
    // AppLogo يحتوي على img
    expect(container.querySelector('img')).toBeTruthy();
  });

  it('يعرض مؤشر التحميل الدوار', () => {
    const { container } = render(<LoadingScreen />);
    expect(container.querySelector('.animate-spin')).toBeTruthy();
  });
});
