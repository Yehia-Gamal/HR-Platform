import { describe, expect, it } from 'vitest';
import { fixIntlPhoneOrder, splitIntlPhone } from './phoneDisplay';

describe('fixIntlPhoneOrder', () => {
  it('يعيد ترتيب رقم انعكس بفعل bidi (2010…+ ← +2010…)', () => {
    expect(fixIntlPhoneOrder('201099505229+')).toBe('+201099505229');
  });

  it('يُبقي الرقم الصحيح كما هو', () => {
    expect(fixIntlPhoneOrder('+201099505229')).toBe('+201099505229');
  });

  it('يُبقي الرقم المحلي كما هو', () => {
    expect(fixIntlPhoneOrder('01099505229')).toBe('01099505229');
  });

  it('يزيل علامات الاتجاه المخفية قبل المعالجة', () => {
    expect(fixIntlPhoneOrder('\u200E201099505229+\u200F')).toBe('+201099505229');
  });

  it('يحافظ على ما بعد الرقم المُعاد ترتيبه', () => {
    expect(fixIntlPhoneOrder('201099505229+ —')).toBe('+201099505229 —');
  });
});

describe('splitIntlPhone', () => {
  it('يقص الرقم الدولي من نص عربي', () => {
    expect(splitIntlPhone('مصطفى أحمد — +201099505229')).toEqual({ phone: '+201099505229', rest: 'مصطفى أحمد —' });
  });

  it('يعيد null عند غياب رقم دولي', () => {
    expect(splitIntlPhone('مصطفى أحمد')).toBeNull();
  });

  it('يتجاهل المسافات داخل الرقم', () => {
    expect(splitIntlPhone('هاتف: +20 109 950 5229')?.phone).toBe('+201099505229');
  });
});
