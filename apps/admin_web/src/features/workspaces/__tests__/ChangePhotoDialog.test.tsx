import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ChangePhotoDialog } from '../ChangePhotoDialog';

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({
    isMock: true,
    session: null,
    access: { displayName: 'مستخدم تجريبي' },
    refreshAccess: vi.fn(),
  }),
}));

describe('ChangePhotoDialog', () => {
  it('يعرض العنوان والإرشادات عند الفتح', () => {
    render(<ChangePhotoDialog open currentPhotoUrl={null} onClose={() => {}} />);
    expect(screen.getByText('تغيير صورتي الشخصية')).toBeInTheDocument();
    expect(screen.getByText('اختيار صورة من الجهاز')).toBeInTheDocument();
    expect(screen.getByText('حفظ الصورة')).toBeInTheDocument();
  });

  it('لا يُعرض عند الإغلاق', () => {
    const { container } = render(<ChangePhotoDialog open={false} currentPhotoUrl={null} onClose={() => {}} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('زر الحفظ معطّل قبل اختيار صورة', () => {
    render(<ChangePhotoDialog open currentPhotoUrl={null} onClose={() => {}} />);
    const saveBtn = screen.getByText('حفظ الصورة').closest('button');
    expect(saveBtn?.disabled).toBe(true);
  });

  it('زر الإلغاء يستدعي onClose', () => {
    const onClose = vi.fn();
    render(<ChangePhotoDialog open currentPhotoUrl={null} onClose={onClose} />);
    fireEvent.click(screen.getByText('إلغاء'));
    expect(onClose).toHaveBeenCalledOnce();
  });
});
