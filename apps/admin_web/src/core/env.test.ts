import { describe, it, expect } from 'vitest';
import { env, hasSupabaseConfig } from './env';

describe('env', () => {
  it('exports an env object with expected keys', () => {
    expect(env).toBeDefined();
    expect(typeof env.supabaseUrl).toBe('string');
    expect(typeof env.supabasePublishableKey).toBe('string');
    expect(typeof env.devMocksEnabled).toBe('boolean');
    expect(typeof env.appVersion).toBe('string');
    expect(typeof env.appBuild).toBe('number');
    expect(typeof env.appEnvironment).toBe('string');
  });

  it('appVersion falls back to 0.10.0', () => {
    // In test env VITE_APP_VERSION is not set, so default applies
    expect(env.appVersion).toBe('0.10.0');
  });

  it('appBuild falls back to 10', () => {
    expect(env.appBuild).toBe(10);
  });

  it('appEnvironment is one of development | staging | production', () => {
    expect(['development', 'staging', 'production']).toContain(env.appEnvironment);
  });

  it('hasSupabaseConfig is boolean', () => {
    expect(typeof hasSupabaseConfig).toBe('boolean');
  });

  it('hasSupabaseConfig reflects whether URL and key are both present', () => {
    // hasSupabaseConfig = Boolean(url && key), value depends on test .env
    expect(hasSupabaseConfig).toBe(Boolean(env.supabaseUrl && env.supabasePublishableKey));
  });
});
