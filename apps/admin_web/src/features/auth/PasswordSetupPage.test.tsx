import { describe, expect, it } from 'vitest';
import { getPasswordRecoveryError, isPasswordRecoveryLocation } from './PasswordSetupPage';

describe('isPasswordRecoveryLocation', () => {
  it('recognizes the dedicated password setup route', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/auth/setup-password', hash: '' })).toBe(true);
  });

  it('recognizes a Supabase recovery hash on the root route', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/', hash: '#type=recovery&access_token=redacted' })).toBe(true);
  });

  it('recognizes an expired Supabase email link on the root route', () => {
    const location = {
      pathname: '/',
      hash: '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired&sb=',
    };

    expect(isPasswordRecoveryLocation(location)).toBe(true);
    expect(getPasswordRecoveryError(location)).toEqual({
      code: 'otp_expired',
      description: 'Email link is invalid or has expired',
    });
  });

  it('does not treat ordinary routes as recovery', () => {
    expect(isPasswordRecoveryLocation({ pathname: '/hr', hash: '' })).toBe(false);
  });
});
