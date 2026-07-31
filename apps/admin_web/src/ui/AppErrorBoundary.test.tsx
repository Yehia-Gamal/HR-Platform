import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { AppErrorBoundary } from './AppErrorBoundary';

function Broken(): null {
  throw new Error('render failure');
}

describe('AppErrorBoundary', () => {
  it('shows a safe recovery screen when a child fails', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    render(
      <AppErrorBoundary>
        <Broken />
      </AppErrorBoundary>,
    );
    expect(screen.getByRole('alert')).toHaveTextContent('حدث خطأ غير متوقع');
    expect(screen.getByRole('button', { name: 'إعادة تحميل المنصة' })).toBeInTheDocument();
    spy.mockRestore();
  });
});
