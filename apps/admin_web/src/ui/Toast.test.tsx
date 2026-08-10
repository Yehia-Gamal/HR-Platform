import { describe, it, expect, vi } from 'vitest';
import { render, screen, act, fireEvent } from '@testing-library/react';
import { ToastProvider, useToast } from './Toast';

function TestComponent({ message, tone, duration }: { message: string; tone: 'success' | 'error' | 'warning' | 'info'; duration?: number }) {
  const { toast } = useToast();
  return <button onClick={() => toast({ message, tone, duration })}>إظهار</button>;
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

  it('renders error tone', () => {
    render(
      <ToastProvider>
        <TestComponent message="فشل" tone="error" />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('فشل')).toBeInTheDocument();
  });

  it('can be dismissed manually via close button', () => {
    vi.useFakeTimers();
    render(
      <ToastProvider>
        <TestComponent message="يدوي" tone="warning" duration={99999} />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('يدوي')).toBeInTheDocument();
    const closeBtn = screen.getByLabelText('إغلاق');
    fireEvent.click(closeBtn);
    // Toast passes through exit phase then removal after EXIT_MS + 50 = 350ms
    act(() => vi.advanceTimersByTime(500));
    expect(screen.queryByText('يدوي')).not.toBeInTheDocument();
    vi.useRealTimers();
  });

  it('auto-dismisses after duration', () => {
    vi.useFakeTimers();
    render(
      <ToastProvider>
        <TestComponent message="مؤقت" tone="info" duration={1000} />
      </ToastProvider>,
    );
    fireEvent.click(screen.getByText('إظهار'));
    expect(screen.getByText('مؤقت')).toBeInTheDocument();
    // duration timer (1000ms) → exit phase, then EXIT_MS+50 (350ms) → removal
    act(() => vi.advanceTimersByTime(500));
    act(() => vi.advanceTimersByTime(600));
    act(() => vi.advanceTimersByTime(500));
    expect(screen.queryByText('مؤقت')).not.toBeInTheDocument();
    vi.useRealTimers();
  });
});
