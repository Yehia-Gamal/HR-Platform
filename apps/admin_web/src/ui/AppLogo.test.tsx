import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { AppLogo } from './AppLogo';

describe('AppLogo', () => {
  it('يعرض اسم الجمعية في الوضع الكامل', () => {
    const { container } = render(<AppLogo />);
    expect(container.textContent).toContain('جمعية خواطر أحلى شباب');
    expect(container.textContent).toContain('منظومة الإدارة المؤسسية');
  });

  it('يخفي النص في الوضع المدمج (compact)', () => {
    const { container } = render(<AppLogo compact />);
    expect(container.textContent).not.toContain('جمعية خواطر أحلى شباب');
    expect(container.textContent).not.toContain('منظومة الإدارة المؤسسية');
  });

  it('يستخدم الشعار الأزرق افتراضياً', () => {
    const { container } = render(<AppLogo />);
    const img = container.querySelector('img');
    expect(img?.getAttribute('src')).toContain('blue');
  });

  it('يستخدم الشعار الأبيض في الوضع المعكوس', () => {
    const { container } = render(<AppLogo inverse />);
    const img = container.querySelector('img');
    expect(img?.getAttribute('src')).toContain('white');
  });

  it('يطبق class المعكوس عند inverse=true', () => {
    const { container } = render(<AppLogo inverse />);
    expect(container.querySelector('.is-inverse')).toBeTruthy();
  });

  it('لا يطبق class المعكوس افتراضياً', () => {
    const { container } = render(<AppLogo />);
    expect(container.querySelector('.is-inverse')).toBeNull();
  });
});
