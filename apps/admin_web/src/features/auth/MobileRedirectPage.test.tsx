import { describe, expect, it } from 'vitest';
import { buildAppLink, buildSetupUrl } from './MobileRedirectPage';

describe('buildAppLink', () => {
  it('keeps a PKCE ?code= query so the app can exchange it', () => {
    expect(buildAppLink({ search: '?code=abc123', hash: '' })).toBe(
      'ahlashabab://action?code=abc123',
    );
  });

  it('keeps an implicit-flow hash', () => {
    expect(buildAppLink({ search: '', hash: '#access_token=t&type=recovery' })).toBe(
      'ahlashabab://action#access_token=t&type=recovery',
    );
  });

  it('keeps both query and hash when present', () => {
    expect(buildAppLink({ search: '?code=abc123', hash: '#type=recovery' })).toBe(
      'ahlashabab://action?code=abc123#type=recovery',
    );
  });

  it('emits a bare scheme when the URL carries no auth params', () => {
    expect(buildAppLink({ search: '', hash: '' })).toBe('ahlashabab://action');
  });
});

describe('buildSetupUrl', () => {
  it('keeps a PKCE ?code= query on the browser fallback', () => {
    expect(buildSetupUrl({ search: '?code=abc123', hash: '' })).toBe(
      '/auth/setup-password?code=abc123',
    );
  });

  it('keeps an implicit-flow hash on the browser fallback', () => {
    expect(buildSetupUrl({ search: '', hash: '#access_token=t&type=recovery' })).toBe(
      '/auth/setup-password#access_token=t&type=recovery',
    );
  });

  it('keeps both query and hash when present', () => {
    expect(buildSetupUrl({ search: '?code=abc123', hash: '#type=recovery' })).toBe(
      '/auth/setup-password?code=abc123#type=recovery',
    );
  });

  it('points at the setup route when the URL carries no auth params', () => {
    expect(buildSetupUrl({ search: '', hash: '' })).toBe('/auth/setup-password');
  });
});
