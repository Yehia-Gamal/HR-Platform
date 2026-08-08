import { describe, it, expect } from 'vitest';
import { dailyReportFeedItemSchema } from '@ahla/shared-contracts';
import { mockDailyReportFeed } from '../mock/domainMocks';

describe('useDailyReportsFeed — mock data schema validation', () => {
  it('parses all mock feed items against dailyReportFeedItemSchema', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    expect(parsed).toHaveLength(mockDailyReportFeed.length);
  });

  it('contains exactly 2 feed items', () => {
    expect(mockDailyReportFeed).toHaveLength(2);
  });

  it('all IDs are valid UUIDs', () => {
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      expect(item.id).toMatch(uuidRe);
    }
  });

  it('achievements is non-empty', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      expect(item.achievements.length).toBeGreaterThan(0);
    }
  });

  it('likesCount is non-negative', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      expect(item.likesCount).toBeGreaterThanOrEqual(0);
    }
  });

  it('isLikedByMe is boolean', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      expect(typeof item.isLikedByMe).toBe('boolean');
    }
  });

  it('comments is an array', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      expect(Array.isArray(item.comments)).toBe(true);
    }
  });

  it('every comment references a valid UUID and has a name', () => {
    const parsed = dailyReportFeedItemSchema.array().parse(mockDailyReportFeed);
    for (const item of parsed) {
      for (const comment of item.comments) {
        expect(comment.employeeName.length).toBeGreaterThan(0);
      }
    }
  });
});
