import { describe, it, expect, vi } from 'vitest';
import { render, screen, act, fireEvent } from '@testing-library/react';
import { ToastProvider, useToast } from './Toast';

function TestComponent({ message, tone }: { message: string; tone: 'success' | 'error' | 'warning' | 'info' }) {
  const { toast } = useToast();
  return <button onClick={() => toast({ message, tone })}>إظهار</button>;
}

describe('Toast', () => {
  it('renders toast when triggered', () => {
    render(
      <ToastProvider>
        <TestComponent message="تم الحفظ" tone="success" />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('تم الحفظ')).toBeInTheDocument();
  });

  it('renders different tones', () => {
    const { rerender } = render(
      <ToastProvider>
        <TestComponent message="خطأ" tone="error" />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('خطأ')).toBeInTheDocument();
  });

  it('auto-dismisses after duration', () => {
    vi.useFakeTimers();
    render(
      <ToastProvider>
        <TestComponent message="مؤقت" tone="info" />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('مؤقت')).toBeInTheDocument();
    act(() => vi.advanceTimersByTime(5000));
    expect(screen.queryByText('مؤقت')).not.toBeInTheDocument();
    vi.useRealTimers();
  });

  it('can be dismissed manually', () => {
    render(
      <ToastProvider>
        <TestComponent message="يدوي" tone="warning" />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('يدوي')).toBeInTheDocument();
    const closeBtn = screen.getByLabelText('إغلاق');
    fireEvent.click(closeBtn);
    expect(screen.queryByText('يدوي')).not.toBeInTheDocument();
  });
});
