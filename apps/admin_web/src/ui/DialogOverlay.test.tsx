import { useState } from 'react';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DialogOverlay } from './DialogOverlay';

afterEach(cleanup);

describe('DialogOverlay', () => {
  it('يعرض العنوان والمحتوى', () => {
    render(
      <DialogOverlay title="تأكيد الحذف" onClose={() => {}}>
        <p>هل أنت متأكد؟</p>
      </DialogOverlay>,
    );
    expect(screen.getByText('تأكيد الحذف')).toBeInTheDocument();
    expect(screen.getByText('هل أنت متأكد؟')).toBeInTheDocument();
  });

  it('يحتوي على role="dialog" و aria-modal', () => {
    render(
      <DialogOverlay title="مودال اختباري" onClose={() => {}}>
        <p>محتوى</p>
      </DialogOverlay>,
    );
    const dialog = screen.getByRole('dialog');
    expect(dialog).toBeInTheDocument();
    expect(dialog).toHaveAttribute('aria-modal', 'true');
  });

  it('يستدعي onClose عند الضغط على زر الإغلاق', () => {
    const onClose = vi.fn();
    render(
      <DialogOverlay title="اختبار" onClose={onClose}>
        <p>محتوى</p>
      </DialogOverlay>,
    );
    fireEvent.click(screen.getByRole('button', { name: 'إغلاق' }));
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('يستدعي onClose عند الضغط على Escape', () => {
    const onClose = vi.fn();
    render(
      <DialogOverlay title="اختبار" onClose={onClose}>
        <p>محتوى</p>
      </DialogOverlay>,
    );
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('يستدعي onClose عند الضغط على الخلفية', () => {
    const onClose = vi.fn();
    render(
      <DialogOverlay title="اختبار" onClose={onClose}>
        <p>محتوى</p>
      </DialogOverlay>,
    );
    const backdrop = screen.getByRole('dialog');
    // Click on the backdrop itself (not a child)
    fireEvent.click(backdrop);
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('يمنع إغلاق عند الضغط داخل المحتوى', () => {
    const onClose = vi.fn();
    render(
      <DialogOverlay title="اختبار" onClose={onClose}>
        <p>محتوى داخلي</p>
      </DialogOverlay>,
    );
    fireEvent.click(screen.getByText('محتوى داخلي'));
    expect(onClose).not.toHaveBeenCalled();
  });

  it('يضبط العنوان بـ aria-labelledby', () => {
    render(
      <DialogOverlay title="عنوان المودال" onClose={() => {}}>
        <p>محتوى</p>
      </DialogOverlay>,
    );
    const dialog = screen.getByRole('dialog');
    const labelledBy = dialog.getAttribute('aria-labelledby');
    expect(labelledBy).toBeTruthy();
    const heading = screen.getByText('عنوان المودال');
    expect(heading.id).toBe(labelledBy);
  });

  it('ينقل التركيز إلى أول حقل إدخال عند الفتح (لا زر الإغلاق)', () => {
    render(
      <DialogOverlay title="نموذج" onClose={() => {}}>
        <input aria-label="حقل الاسم" />
      </DialogOverlay>,
    );
    expect(screen.getByLabelText('حقل الاسم')).toHaveFocus();
  });

  it('إعادة رندر الوالد مع onClose جديد لا تسرق التركيز من حقل الكتابة', () => {
    const { rerender } = render(
      <DialogOverlay title="نموذج" onClose={() => {}}>
        <input aria-label="حقل التعليق" />
      </DialogOverlay>,
    );
    const input = screen.getByLabelText('حقل التعليق');
    input.focus();
    expect(input).toHaveFocus();

    // المحاكاة الفعلية للخلل: كل ضغطة حرف تعيد رندر الوالد بمعرّف onClose جديد
    rerender(
      <DialogOverlay title="نموذج" onClose={() => {}}>
        <input aria-label="حقل التعليق" value="أ" onChange={() => {}} />
      </DialogOverlay>,
    );
    expect(input).toHaveFocus();
  });

  it('الكتابة الفعلية المتتالية (حالة مضبوطة) تبقي التركيز على الحقل لا على زر X', () => {
    function Host() {
      const [value, setValue] = useState('');
      return (
        <DialogOverlay title="طلب إجازة" onClose={() => {}}>
          <input aria-label="السبب" value={value} onChange={(e) => setValue(e.target.value)} />
          <button onClick={() => {}}>حفظ</button>
        </DialogOverlay>
      );
    }
    render(<Host />);
    const input = screen.getByLabelText('السبب');
    expect(input).toHaveFocus();
    // محاكاة ثلاث ضغطات متتالية — كل واحدة تعيد رندر الشجرة بحالة جديدة
    for (const ch of ['أ', 'ب', 'ج']) {
      fireEvent.change(input, { target: { value: ch } });
      expect(document.activeElement).toBe(input);
    }
    expect(screen.getByRole('button', { name: 'إغلاق' })).not.toHaveFocus();
  });

  it('حوار بلا حقول إدخال يركّز أول زر إجراء وليس زر الإغلاق', () => {
    render(
      <DialogOverlay title="تأكيد" onClose={() => {}}>
        <p>هل أنت متأكد من الحذف؟</p>
        <button onClick={() => {}}>إلغاء</button>
        <button onClick={() => {}}>حذف</button>
      </DialogOverlay>,
    );
    expect(screen.getByRole('button', { name: 'إلغاء' })).toHaveFocus();
    expect(screen.getByRole('button', { name: 'إغلاق' })).not.toHaveFocus();
  });

  it('حوار محتواه زر الإغلاق فقط يركّز الحوار نفسه (لا X)', () => {
    render(
      <DialogOverlay title="تنبيه" onClose={() => {}}>
        <p>انتهت الجلسة</p>
      </DialogOverlay>,
    );
    const dialog = screen.getByRole('dialog').parentElement?.querySelector('section');
    expect(document.activeElement).toBe(dialog);
    expect(screen.getByRole('button', { name: 'إغلاق' })).not.toHaveFocus();
  });
});
