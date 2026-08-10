import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import { Tooltip } from './Tooltip';

describe('Tooltip', () => {
  it('renders children', () => {
    render(
      <Tooltip content="تلميح مساعد">
        <button>زر</button>
      </Tooltip>,
    );
    expect(screen.getByText('زر')).toBeInTheDocument();
  });

  it('does not show tooltip text before hover', () => {
    render(
      <Tooltip content="تلميح مساعد" delay={0}>
        <button>زر</button>
      </Tooltip>,
    );
    // Tooltip content is aria-hidden=true initially
    const tooltip = screen.queryByText('تلميح مساعد');
    // It might be in DOM but hidden — check it's not visible
    if (tooltip) {
      expect(tooltip.closest('[aria-hidden="true"]')).toBeTruthy();
    }
  });

  it('shows tooltip on hover after delay', () => {
    vi.useFakeTimers();
    render(
      <Tooltip content="تلميح مساعد" delay={100}>
        <button>زر</button>
      </Tooltip>,
    );
    fireEvent.mouseEnter(screen.getByText('زر'));
    act(() => vi.advanceTimersByTime(200));
    const tooltip = screen.getByText('تلميح مساعد');
    // After delay, tooltip should be visible (aria-hidden=false)
    expect(tooltip.closest('[aria-hidden="false"]')).toBeTruthy();
    vi.useRealTimers();
  });

  it('hides tooltip on mouse leave', () => {
    vi.useFakeTimers();
    render(
      <Tooltip content="تلميح مساعد" delay={100}>
        <button>زر</button>
      </Tooltip>,
    );
    const trigger = screen.getByText('زر');
    fireEvent.mouseEnter(trigger);
    act(() => vi.advanceTimersByTime(200));
    const tooltip = screen.getByText('تلميح مساعد');
    expect(tooltip.closest('[aria-hidden="false"]')).toBeTruthy();
    fireEvent.mouseLeave(trigger);
    const tooltipAfter = screen.queryByText('تلميح مساعد');
    if (tooltipAfter) {
      expect(tooltipAfter.closest('[aria-hidden="true"]')).toBeTruthy();
    }
    vi.useRealTimers();
  });
});
