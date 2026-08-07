import { describe, expect, it } from 'vitest';
import { extractAvatarPath, toAuthenticatedAvatarUrl } from './avatarUrl';

const PUBLIC = '/storage/v1/object/public/employee-avatars/';
const AUTH = '/storage/v1/object/authenticated/employee-avatars/';

describe('extractAvatarPath', () => {
  it('يستخرج المسار من رابط public', () => {
    const url = `https://xyz.supabase.co${PUBLIC}admin/abc.webp`;
    expect(extractAvatarPath(url)).toBe('admin/abc.webp');
  });

  it('يستخرج المسار من رابط authenticated', () => {
    const url = `https://xyz.supabase.co${AUTH}user123/avatar.png`;
    expect(extractAvatarPath(url)).toBe('user123/avatar.png');
  });

  it('يتجاهل query params ويفك ترميز المسار', () => {
    const url = `https://xyz.supabase.co${PUBLIC}u/%D8%A3.webp?v=123&x=1`;
    expect(extractAvatarPath(url)).toBe('u/أ.webp');
  });

  it('يعيد null للروابط الخارجية', () => {
    expect(extractAvatarPath('https://example.com/mock-avatar.webp')).toBeNull();
    expect(extractAvatarPath('')).toBeNull();
  });

  it('لا يلتقط روابط buckets أخرى', () => {
    const url = 'https://x.supabase.co/storage/v1/object/public/other-bucket/a.png';
    expect(extractAvatarPath(url)).toBeNull();
  });
});

describe('toAuthenticatedAvatarUrl', () => {
  it('يحوّل public إلى authenticated', () => {
    const input = `https://xyz.supabase.co${PUBLIC}admin/abc.webp`;
    expect(toAuthenticatedAvatarUrl(input)).toBe(`https://xyz.supabase.co${AUTH}admin/abc.webp`);
  });

  it('يترك الروابط الأخرى دون تغيير', () => {
    const input = 'https://example.com/x.jpg';
    expect(toAuthenticatedAvatarUrl(input)).toBe(input);
  });
});
