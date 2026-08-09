import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import { Tooltip } from './Tooltip';

describe('Tooltip', () => {
  it('renders children without tooltip by default', () => {
    render(
      <Tooltip content="تلميح مساعد">
        <button>زر</button>
      </Tooltip>,
    );
    expect(screen.getByText('زر')).toBeInTheDocument();
    expect(screen.queryByText('تلميح مساعد')).not.toBeInTheDocument();
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
    expect(screen.getByText('تلميح مساعد')).toBeInTheDocument();
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
    expect(screen.getByText('تلميح مساعد')).toBeInTheDocument();
    fireEvent.mouseLeave(trigger);
    expect(screen.queryByText('تلميح مساعد')).not.toBeInTheDocument();
    vi.useRealTimers();
  });
});
