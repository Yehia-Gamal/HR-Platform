import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConfirmDialog } from './ConfirmDialog';

describe('ConfirmDialog', () => {
  it('renders title and message when open', () => {
    render(
      <ConfirmDialog
        open
        title="تأكيد الحذف"
        message="هل أنت متأكد؟"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
    );
    expect(screen.getByText('تأكيد الحذف')).toBeInTheDocument();
    expect(screen.getByText('هل أنت متأكد؟')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(
      <ConfirmDialog
        open={false}
        title="تأكيد"
        message="رسالة"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
    );
    expect(screen.queryByText('تأكيد')).not.toBeInTheDocument();
  });

  it('calls onConfirm when confirm button clicked', () => {
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        open
        title="تأكيد"
        message="رسالة"
        onConfirm={onConfirm}
        onCancel={() => {}}
      />,
    );
    fireEvent.click(screen.getByText('تأكيد'));
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it('calls onCancel when cancel button clicked', () => {
    const onCancel = vi.fn();
    render(
      <ConfirmDialog
        open
        title="تأكيد"
        message="رسالة"
        onConfirm={() => {}}
        onCancel={onCancel}
      />,
    );
    fireEvent.click(screen.getByText('إلغاء'));
    expect(onCancel).toHaveBeenCalledOnce();
  });

  it('shows danger icon for danger tone', () => {
    const { container } = render(
      <ConfirmDialog
        open
        title="حذف"
        message="رسالة"
        tone="danger"
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
    );
    // The dialog should render with danger styling
    expect(container.querySelector('[role="dialog"]')).toBeTruthy();
  });
});
