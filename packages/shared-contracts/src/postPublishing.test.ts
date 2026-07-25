import { describe, expect, it } from 'vitest';
import {
  publisherRoleSchema,
  PUBLISHER_CHANNELS,
  postTypeSchema,
  createPostInputSchema,
} from './postPublishing.js';

describe('post publishing contracts — V17 §18', () => {
  it('publisher roles are exactly 3: main_admin, hr_web, executive_mobile', () => {
    expect(publisherRoleSchema.options).toHaveLength(3);
    expect(publisherRoleSchema.parse('main_admin')).toBe('main_admin');
    expect(publisherRoleSchema.parse('hr_web')).toBe('hr_web');
    expect(publisherRoleSchema.parse('executive_mobile')).toBe('executive_mobile');
    expect(() => publisherRoleSchema.parse('employee')).toThrow();
  });

  it('admin and HR publish from web, executive from mobile', () => {
    expect(PUBLISHER_CHANNELS.main_admin).toBe('web');
    expect(PUBLISHER_CHANNELS.hr_web).toBe('web');
    expect(PUBLISHER_CHANNELS.executive_mobile).toBe('mobile');
  });

  it('post types are announcement and decision', () => {
    expect(postTypeSchema.options).toEqual(['announcement', 'decision']);
  });

  it('create post input enforces title 3–300, body 3–5000', () => {
    const valid = createPostInputSchema.parse({
      title: 'إعلان مهم',
      body: 'نص الإعلان الرسمي للجمعية',
    });
    expect(valid.type).toBe('announcement');
    expect(valid.requiresAcknowledgement).toBe(false);

    expect(() => createPostInputSchema.parse({ title: 'ab', body: 'نص كافٍ' })).toThrow();
    expect(() => createPostInputSchema.parse({ title: 'عنوان كافٍ', body: 'ab' })).toThrow();
  });

  it('create post supports acknowledgement and expiry', () => {
    const post = createPostInputSchema.parse({
      title: 'قرار إداري',
      body: 'يجب على جميع الموظفين الاطلاع والتأكيد',
      type: 'decision',
      requiresAcknowledgement: true,
      expiresAt: '2026-08-01T00:00:00.000Z',
    });
    expect(post.type).toBe('decision');
    expect(post.requiresAcknowledgement).toBe(true);
    expect(post.expiresAt).toBeDefined();
  });
});
