import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { ForbiddenState } from './ForbiddenState';

describe('ForbiddenState', () => {
  afterEach(cleanup);
  it('renders the default forbidden message', () => {
    render(<ForbiddenState />);
    expect(screen.getByText('لا تملك صلاحية الوصول')).toBeDefined();
    expect(screen.getByText('هذه الصفحة تتطلب صلاحية غير متاحة لحسابك.')).toBeDefined();
  });

  it('has role="alert"', () => {
    render(<ForbiddenState />);
    expect(screen.getByRole('alert')).toBeDefined();
  });

  it('renders custom title and description', () => {
    render(<ForbiddenState title="ممنوع" description="لا يمكنك الوصول." />);
    expect(screen.getByText('ممنوع')).toBeDefined();
    expect(screen.getByText('لا يمكنك الوصول.')).toBeDefined();
  });

  it('renders an action when provided', () => {
    render(<ForbiddenState action={<button>طلب صلاحية</button>} />);
    expect(screen.getByText('طلب صلاحية')).toBeDefined();
  });
});
