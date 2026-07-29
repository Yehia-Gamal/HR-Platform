import { describe, expect, it, vi, afterEach } from 'vitest';
import { safeErrorMessage } from './errorMapper';

// Mock crypto.randomUUID لضمان ثبات رمز التتبع
vi.stubGlobal('crypto', {
  ...globalThis.crypto,
  randomUUID: () => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
});

describe('safeErrorMessage', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('يحوّل أخطاء RLS إلى رسالة صلاحية عربية', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const msg = safeErrorMessage(new Error('row level security violation'));
    expect(msg).toContain('ليس لديك صلاحية');
    expect(msg).toContain('AAAAAAAA');
    spy.mockRestore();
  });

  it('يحوّل permission denied', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('Permission denied for table employees'))).toContain('ليس لديك صلاحية');
    spy.mockRestore();
  });

  it('يحوّل unique constraint violations', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('violates unique constraint "employees_code_key"'))).toContain('موجود بالفعل');
    spy.mockRestore();
  });

  it('يحوّل foreign key violations', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('violates foreign key constraint'))).toContain('سجلات مرتبطة');
    spy.mockRestore();
  });

  it('يحوّل JWT expired', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('JWT expired'))).toContain('انتهت صلاحية الجلسة');
    spy.mockRestore();
  });

  it('يحوّل Invalid login credentials', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('Invalid login credentials'))).toContain('بيانات الدخول غير صحيحة');
    spy.mockRestore();
  });

  it('يحوّل أخطاء الشبكة', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('Failed to fetch'))).toContain('تحقق من اتصال الإنترنت');
    expect(safeErrorMessage(new Error('NetworkError when attempting to fetch'))).toContain('تحقق من اتصال الإنترنت');
    spy.mockRestore();
  });

  it('يحوّل timeout', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('The operation timed out. timeout'))).toContain('انتهت مهلة الاتصال');
    spy.mockRestore();
  });

  it('يحوّل أكواد HTTP في الرسائل', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('Server returned 404'))).toContain('لم يُعثر على المورد');
    expect(safeErrorMessage(new Error('Error 429: rate limited'))).toContain('طلبات كثيرة');
    expect(safeErrorMessage(new Error('HTTP 500 Internal Server Error'))).toContain('خطأ في الخادم');
    spy.mockRestore();
  });

  it('يعيد الرسالة الافتراضية للأخطاء غير المعروفة', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('something completely unknown'))).toContain('حدث خطأ غير متوقع');
    spy.mockRestore();
  });

  it('يتعامل مع أخطاء string بدون Error object', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage('JWT expired')).toContain('انتهت صلاحية الجلسة');
    spy.mockRestore();
  });

  it('يتعامل مع null/undefined', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(null)).toContain('حدث خطأ غير متوقع');
    expect(safeErrorMessage(undefined)).toContain('حدث خطأ غير متوقع');
    spy.mockRestore();
  });

  it('يسجّل الخطأ الأصلي في console.error', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const err = new Error('permission denied');
    safeErrorMessage(err);
    expect(spy).toHaveBeenCalledWith('[خطأ AAAAAAAA]', err);
    spy.mockRestore();
  });
});
