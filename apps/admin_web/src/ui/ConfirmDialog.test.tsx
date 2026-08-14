import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConfirmDialog } from './ConfirmDialog';

describe('ConfirmDialog', () => {
  it('renders title and message when open', () => {
    render(<ConfirmDialog open title="تأكيد الحذف" message="هل أنت متأكد؟" onConfirm={() => {}} onCancel={() => {}} />);
    expect(screen.getByText('تأكيد الحذف')).toBeInTheDocument();
    expect(screen.getByText('هل أنت متأكد؟')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<ConfirmDialog open={false} title="تأكيد" message="رسالة" onConfirm={() => {}} onCancel={() => {}} />);
    expect(screen.queryByText('تأكيد')).not.toBeInTheDocument();
  });

  it('calls onConfirm when confirm button clicked', () => {
    const onConfirm = vi.fn();
    render(<ConfirmDialog open title="تأكيد" message="رسالة" onConfirm={onConfirm} onCancel={() => {}} />);
    // The confirm button has the default label "تأكيد"
    const buttons = screen.getAllByRole('button');
    // Find the confirm button (it's the one with the danger/tone class, last in the action row)
    const confirmBtn = buttons.find((b) => b.textContent === 'تأكيد' && !(b instanceof HTMLButtonElement && b.disabled));
    expect(confirmBtn).toBeTruthy();
    if (confirmBtn) fireEvent.click(confirmBtn);
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it('calls onCancel when cancel button clicked', () => {
    const onCancel = vi.fn();
    render(<ConfirmDialog open title="تأكيد" message="رسالة" onConfirm={() => {}} onCancel={onCancel} />);
    const cancelBtn = screen.getByText('إلغاء');
    fireEvent.click(cancelBtn);
    expect(onCancel).toHaveBeenCalledOnce();
  });

  it('renders alert icon for danger tone', () => {
    render(<ConfirmDialog open title="حذف" message="رسالة" tone="danger" onConfirm={() => {}} onCancel={() => {}} />);
    // The danger icon should be present (AlertTriangle has a specific role/path)
    const icons = document.querySelectorAll('svg');
    expect(icons.length).toBeGreaterThan(0);
  });
});
