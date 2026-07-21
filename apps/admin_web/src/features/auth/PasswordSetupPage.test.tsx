import { describe, expect, it } from 'vitest';
import { isPasswordRecoveryLocation } from './PasswordSetupPage';

describe('isPasswordRecoveryLocation', () => {
  it('recognizes the dedicated password setup route', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/auth/setup-password', hash: '' })).toBe(true);
  });

  it('recognizes a Supabase recovery hash on the root route', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/', hash: '#type=recovery&access_token=redacted' })).toBe(true);
  });

  it('does not treat ordinary routes as recovery', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/hr', hash: '' })).toBe(false);
  });
});
