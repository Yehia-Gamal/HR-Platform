import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { DialogPortal } from './DialogPortal';

describe('DialogPortal', () => {
  it('يعرض المحتوى في document.body عبر Portal', () => {
    render(
      <div data-testid="parent">
        <DialogPortal>
          <p>محتوى المودال</p>
        </DialogPortal>
      </div>,
    );
    // المحتوى يظهر في الصفحة
    expect(screen.getByText('محتوى المودال')).toBeDefined();
  });

  it('يعرض المحتوى خارج العنصر الأب (Portal)', () => {
    const { container } = render(
      <div data-testid="parent">
        <DialogPortal>
          <p data-testid="portal-content">محتوى خارجي</p>
        </DialogPortal>
      </div>,
    );
    // المحتوى لا يكون داخل العنصر الأب بل في document.body
    expect(container.querySelector('[data-testid="portal-content"]')).toBeNull();
    expect(document.body.querySelector('[data-testid="portal-content"]')).not.toBeNull();
  });
});
