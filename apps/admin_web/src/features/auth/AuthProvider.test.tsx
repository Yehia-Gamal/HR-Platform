import { render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

const { getSupabaseMock } = vi.hoisted(() => ({
  getSupabaseMock: vi.fn(),
}));

vi.mock('../../core/env', () => ({
  env: { devMocksEnabled: true },
  // Mirrors a developer machine that has a populated .env.local.
  hasSupabaseConfig: true,
}));

vi.mock('../../core/supabase', () => ({
  getSupabase: getSupabaseMock,
}));

vi.mock('../../core/authObservability', () => ({
  attachAuthObservability: () => ({ onAuthChange: vi.fn() }),
}));

vi.mock('./accessService', () => ({
  loadAccessContext: vi.fn(),
}));

import { AuthProvider, useAuth } from './AuthProvider';

function AuthStatusProbe() {
  return <output>{useAuth().status}</output>;
}

describe('AuthProvider local preview initialization', () => {
  it('does not contact Supabase when dev mocks are enabled', async () => {
    render(
      <AuthProvider>
        <AuthStatusProbe />
      </AuthProvider>,
    );

    await waitFor(() => expect(screen.getByText('anonymous')).toBeVisible());
    expect(getSupabaseMock).not.toHaveBeenCalled();
  });
});
