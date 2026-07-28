import React from 'react';
import type { ReactNode } from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { RouteErrorBoundary } from './RouteErrorBoundary';

function Bomb(): ReactNode {
  throw new Error('render explosion');
}

describe('RouteErrorBoundary', () => {
  it('يعرض المحتوى عند عدم وجود خطأ', () => {
    render(
      <RouteErrorBoundary>
        <p>محتوى عادي</p>
      </RouteErrorBoundary>,
    );
    expect(screen.getByText('محتوى عادي')).toBeInTheDocument();
  });

  it('يعرض رسالة الخطأ عند انهيار المحتوى', () => {
    // Suppress console.error from React's error boundary logging.
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    render(
      <RouteErrorBoundary>
        <Bomb />
      </RouteErrorBoundary>,
    );
    expect(screen.getByRole('alert')).toBeInTheDocument();
    expect(screen.getByText('تعذر عرض هذه الصفحة')).toBeInTheDocument();
    expect(screen.getByText(/Error ID:/)).toBeInTheDocument();
    spy.mockRestore();
  });

  it('يعيد المحاولة عند الضغط على الزر', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    let shouldThrow = true;
    function MaybeBomb() {
      if (shouldThrow) throw new Error('boom');
      return <p>تم التعافي</p>;
    }
    const { rerender } = render(
      <RouteErrorBoundary>
        <MaybeBomb />
      </RouteErrorBoundary>,
    );
    expect(screen.getByText('تعذر عرض هذه الصفحة')).toBeInTheDocument();
    // Fix the error, then retry.
    shouldThrow = false;
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }));
    rerender(
      <RouteErrorBoundary>
        <MaybeBomb />
      </RouteErrorBoundary>,
    );
    expect(screen.getByText('تم التعافي')).toBeInTheDocument();
    spy.mockRestore();
  });

  it('يحتوي على role="alert" للوصولية', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    render(
      <RouteErrorBoundary>
        <Bomb />
      </RouteErrorBoundary>,
    );
    expect(screen.getByRole('alert')).toBeInTheDocument();
    spy.mockRestore();
  });
});
