import { describe, it, expect } from 'vitest';
import { officialFeedItemSchema } from '@ahla/shared-contracts';
import { mockOfficialFeed } from '../mock/domainMocks';

describe('useOfficialFeed — mock data schema validation', () => {
  it('parses all mock feed items against officialFeedItemSchema', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    expect(parsed).toHaveLength(mockOfficialFeed.length);
  });

  it('contains exactly 2 feed items', () => {
    expect(mockOfficialFeed).toHaveLength(2);
  });

  it('all IDs are valid UUIDs', () => {
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(item.id).toMatch(uuidRe);
    }
  });

  it('kind is decision or announcement', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(['decision', 'announcement']).toContain(item.kind);
    }
  });

  it('has the expected kinds across mock data', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    expect(parsed[0].kind).toBe('decision');
    expect(parsed[1].kind).toBe('announcement');
  });

  it('priority is a valid action priority', () => {
    const validPriorities = ['low', 'normal', 'high', 'urgent'];
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(validPriorities).toContain(item.priority);
    }
  });

  it('title and body are non-empty', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(item.title.length).toBeGreaterThan(0);
      expect(item.body.length).toBeGreaterThan(0);
    }
  });

  it('requiresAcknowledgement is boolean', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(typeof item.requiresAcknowledgement).toBe('boolean');
    }
  });

  it('acknowledgedCount is non-negative', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(item.acknowledgedCount).toBeGreaterThanOrEqual(0);
    }
  });

  it('acknowledgedCount <= targetCount when targetCount is set', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      if (item.targetCount !== null) {
        expect(item.acknowledgedCount).toBeLessThanOrEqual(item.targetCount);
      }
    }
  });

  it('decision requires acknowledgement, announcement does not', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    const decision = parsed.find((i) => i.kind === 'decision');
    const announcement = parsed.find((i) => i.kind === 'announcement');
    expect(decision?.requiresAcknowledgement).toBe(true);
    expect(announcement?.requiresAcknowledgement).toBe(false);
  });

  it('status is published for all mock items', () => {
    const parsed = officialFeedItemSchema.array().parse(mockOfficialFeed);
    for (const item of parsed) {
      expect(item.status).toBe('published');
    }
  });
});
