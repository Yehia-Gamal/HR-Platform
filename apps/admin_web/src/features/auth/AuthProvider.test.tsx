import type { AccessContext } from '@ahla/shared-contracts';
import type { AuthChangeEvent, Session } from '@supabase/supabase-js';
import { act, render, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

const { getSupabaseMock, loadAccessMock, mockEnv } = vi.hoisted(() => ({
  getSupabaseMock: vi.fn(),
  loadAccessMock: vi.fn(),
  mockEnv: { devMocksEnabled: true },
}));

vi.mock('../../core/env', () => ({
  env: mockEnv,
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
  loadAccessContext: loadAccessMock,
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

it('clears session data and ignores a late access response after sign-out', async () => {
  mockEnv.devMocksEnabled = false;
  const session = { user: { id: 'employee-a' } } as Session;
  let notifyAuth: (event: AuthChangeEvent, nextSession: Session | null) => void = () => {};
  let resolveAccess: (context: AccessContext) => void = () => {};
  const pendingAccess = new Promise<AccessContext>((resolve) => {
    resolveAccess = resolve;
  });
  loadAccessMock.mockReturnValueOnce(pendingAccess);
  getSupabaseMock.mockResolvedValueOnce({
    auth: {
      onAuthStateChange: (callback: typeof notifyAuth) => {
        notifyAuth = callback;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      },
      getSession: async () => ({ data: { session }, error: null }),
    },
  });
  const clearSessionData = vi.fn();
  try {
    render(
      <AuthProvider clearSessionData={clearSessionData}>
        <AuthStatusProbe />
      </AuthProvider>,
    );
    await waitFor(() => expect(loadAccessMock).toHaveBeenCalledTimes(1));
    clearSessionData.mockClear();
    act(() => notifyAuth('SIGNED_OUT', null));
    await act(async () => resolveAccess({} as AccessContext));
    expect(screen.getByText('anonymous')).toBeVisible();
    expect(clearSessionData).toHaveBeenCalledOnce();
  } finally {
    mockEnv.devMocksEnabled = true;
  }
});
