import { describe, it, expect } from 'vitest';
import { notificationItemSchema, MOBILE_ONLY_ENTITY_TYPES } from '@ahla/shared-contracts';
import { mockNotifications } from '../mock/domainMocks';

describe('useNotifications — filter logic & schema validation', () => {
  describe('mockNotifications schema validation', () => {
    it('parses all mock notifications against notificationItemSchema', () => {
      const parsed = notificationItemSchema.array().parse(mockNotifications);
      expect(parsed).toHaveLength(mockNotifications.length);
    });

    it('each notification has required fields', () => {
      const parsed = notificationItemSchema.array().parse(mockNotifications);
      for (const n of parsed) {
        expect(n.id).toBeDefined();
        expect(typeof n.id).toBe('string');
        // entityType is z.string().nullable().optional() — may be undefined or null
        expect(n.entityType === undefined || n.entityType === null || typeof n.entityType === 'string').toBe(true);
        expect(typeof n.isRead).toBe('boolean');
      }
    });
  });

  describe('MOBILE_ONLY_ENTITY_TYPES', () => {
    it('includes punch_reminder', () => {
      expect(MOBILE_ONLY_ENTITY_TYPES).toContain('punch_reminder');
    });

    it('includes live_location_request', () => {
      expect(MOBILE_ONLY_ENTITY_TYPES).toContain('live_location_request');
    });

    it('has exactly 2 entries', () => {
      expect(MOBILE_ONLY_ENTITY_TYPES).toHaveLength(2);
    });
  });

  describe('web notification filter logic', () => {
    // Recreate the filter from useNotifications.ts line 59
    const filterForWeb = (items: Array<{ entityType?: string | null }>) =>
      items.filter(
        (n) => !n.entityType || !MOBILE_ONLY_ENTITY_TYPES.includes(n.entityType as typeof MOBILE_ONLY_ENTITY_TYPES[number]),
      );

    it('passes through non-mobile entity types', () => {
      const items = [
        { entityType: 'request_approved' },
        { entityType: 'kpi_assigned' },
        { entityType: 'decision_published' },
      ];
      expect(filterForWeb(items)).toHaveLength(3);
    });

    it('filters out punch_reminder', () => {
      const items = [
        { entityType: 'request_approved' },
        { entityType: 'punch_reminder' },
      ];
      expect(filterForWeb(items)).toHaveLength(1);
      expect(filterForWeb(items)[0].entityType).toBe('request_approved');
    });

    it('filters out live_location_request', () => {
      const items = [
        { entityType: 'live_location_request' },
        { entityType: 'kpi_assigned' },
      ];
      expect(filterForWeb(items)).toHaveLength(1);
      expect(filterForWeb(items)[0].entityType).toBe('kpi_assigned');
    });

    it('filters out all mobile-only types at once', () => {
      const items = [
        { entityType: 'punch_reminder' },
        { entityType: 'live_location_request' },
        { entityType: 'request_approved' },
      ];
      const result = filterForWeb(items);
      expect(result).toHaveLength(1);
      expect(result[0].entityType).toBe('request_approved');
    });

    it('returns empty array when all items are mobile-only', () => {
      const items = [
        { entityType: 'punch_reminder' },
        { entityType: 'live_location_request' },
      ];
      expect(filterForWeb(items)).toHaveLength(0);
    });

    it('returns empty array for empty input', () => {
      expect(filterForWeb([])).toHaveLength(0);
    });

    it('mock notifications survive web filter (none are mobile-only)', () => {
      const parsed = notificationItemSchema.array().parse(mockNotifications);
      const filtered = filterForWeb(parsed);
      // Mock notifications should not contain mobile-only types
      expect(filtered.length).toBe(parsed.length);
    });
  });
});
