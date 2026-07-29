import { describe, expect, it, vi, afterEach } from 'vitest';
import { getShortName, getTimeGreeting } from './formatDisplayName';

describe('getShortName', () => {
  it('يعيد الاسم كاملاً إذا كان كلمة أو كلمتين', () => {
    expect(getShortName('أحمد')).toBe('أحمد');
    expect(getShortName('أحمد محمود')).toBe('أحمد محمود');
  });

  it('يأخذ أول كلمتين فقط من الاسم الطويل', () => {
    expect(getShortName('أحمد محمود السيد')).toBe('أحمد محمود');
    expect(getShortName('سارة عادل حسن محمد')).toBe('سارة عادل');
  });

  it('يتعامل مع المسافات الزائدة', () => {
    expect(getShortName('  أحمد  محمود  السيد  ')).toBe('أحمد محمود');
  });

  it('يعيد سلسلة فارغة للمدخل الفارغ', () => {
    expect(getShortName('')).toBe('');
    expect(getShortName('   ')).toBe('');
  });
});

describe('getTimeGreeting', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('يقول صباح الخير بين 5 و 11', () => {
    vi.spyOn(Date.prototype, 'getHours').mockReturnValue(8);
    expect(getTimeGreeting()).toBe('صباح الخير');
  });

  it('يقول مساء الخير بين 12 و 20', () => {
    vi.spyOn(Date.prototype, 'getHours').mockReturnValue(15);
    expect(getTimeGreeting()).toBe('مساء الخير');

    vi.spyOn(Date.prototype, 'getHours').mockReturnValue(19);
    expect(getTimeGreeting()).toBe('مساء الخير');
  });

  it('يقول أهلاً في الليل', () => {
    vi.spyOn(Date.prototype, 'getHours').mockReturnValue(2);
    expect(getTimeGreeting()).toBe('أهلاً');

    vi.spyOn(Date.prototype, 'getHours').mockReturnValue(23);
    expect(getTimeGreeting()).toBe('أهلاً');
  });
});
