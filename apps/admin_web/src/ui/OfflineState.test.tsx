import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { OfflineState } from './OfflineState';

describe('OfflineState', () => {
  afterEach(cleanup);
  it('renders the default offline message', () => {
    render(<OfflineState />);
    expect(screen.getByText('لا يوجد اتصال بالإنترنت')).toBeDefined();
    expect(screen.getByText('تحقق من اتصالك بالشبكة ثم أعد المحاولة.')).toBeDefined();
  });

  it('has role="status"', () => {
    render(<OfflineState />);
    expect(screen.getByRole('status')).toBeDefined();
  });

  it('calls onRetry when retry button is clicked', () => {
    const onRetry = vi.fn();
    render(<OfflineState onRetry={onRetry} />);
    fireEvent.click(screen.getByText('إعادة المحاولة'));
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('renders custom title and description', () => {
    render(<OfflineState title="انقطع الاتصال" description="الشبكة غير متاحة حاليًا." />);
    expect(screen.getByText('انقطع الاتصال')).toBeDefined();
    expect(screen.getByText('الشبكة غير متاحة حاليًا.')).toBeDefined();
  });
});
