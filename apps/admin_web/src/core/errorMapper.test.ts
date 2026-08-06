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

  it('يترجم 42501 (SQLSTATE صلاحية) إلى رسالة صلاحية عربية', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('permission denied for function create_kpi_cycle_admin (SQLSTATE 42501)'))).toContain('ليس لديك صلاحية');
    spy.mockRestore();
  });

  it('يترجم PGRST202 / schema cache إلى رسالة تحديث مخزن الخدمة', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('Could not find the function public.create_kpi_cycle_admin in the schema cache'))).toContain('لم تُحدَّث بعد آخر تغيير');
    expect(safeErrorMessage(new Error('PGRST202'))).toContain('لم تُحدَّث بعد آخر تغيير');
    spy.mockRestore();
  });

  it('يترجم أخطاء قيود DB الموسّعة', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('null value in column "policy_version_id" violates not-null constraint'))).toContain('حقل مطلوب');
    expect(safeErrorMessage(new Error('column "use_parallel_flow" does not exist'))).toContain('عمود في قاعدة البيانات');
    expect(safeErrorMessage(new Error('relation "kpi_cycles" does not exist'))).toContain('جدول في قاعدة البيانات');
    spy.mockRestore();
  });

  it('يترجم أخطاء إجراء KPI المخزن إلى العربية', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'))).toContain('القالب الرسمي');
    expect(safeErrorMessage(new Error('INVALID_CYCLE_STATE'))).toContain('حالة الدورة');
    expect(safeErrorMessage(new Error('CONTROL_REASON_REQUIRED'))).toContain('سبب الإجراء الإداري');
    expect(safeErrorMessage(new Error('CYCLE_ALREADY_STARTED'))).toContain('إلغاء فتح الدورة');
    expect(safeErrorMessage(new Error('CYCLE_MUST_BE_CLOSED'))).toContain('إغلاق الدورة');
    expect(safeErrorMessage(new Error('APPEAL_ALREADY_DECIDED'))).toContain('الاعتراض');
    expect(safeErrorMessage(new Error('CYCLE_NOT_FOUND'))).toContain('دورة KPI');
    expect(safeErrorMessage(new Error('INVALID_SCHEDULE'))).toContain('تواريخ الجدولة');
    spy.mockRestore();
  });

  it('يترجم أخطاء أرشفة/حذف الموظف المخزّنة إلى العربية', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(safeErrorMessage(new Error('delete_confirmation_mismatch'))).toContain('رمز التأكيد');
    expect(safeErrorMessage(new Error('employee_history_requires_archive'))).toContain('أرشِف الموظف');
    expect(safeErrorMessage(new Error('manager_has_direct_reports'))).toContain('مرؤوسون');
    expect(safeErrorMessage(new Error('main_admin_required'))).toContain('ليست لديك صلاحية حذف');
    expect(safeErrorMessage(new Error('self_delete_not_allowed'))).toContain('حسابك الحالي');
    expect(safeErrorMessage(new Error('delete_reason_required'))).toContain('سبب الحذف');
    expect(safeErrorMessage(new Error('self_archive_not_allowed'))).toContain('حسابك الحالي');
    expect(safeErrorMessage(new Error('archive_reason_required'))).toContain('سبب الأرشفة');
    expect(safeErrorMessage(new Error('employee_not_found'))).toContain('لم يُعثر على الموظف');
    spy.mockRestore();
  });
});
