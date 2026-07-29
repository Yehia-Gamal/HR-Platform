import { describe, it, expect } from 'vitest';
import { actionCenterItemSchema } from '@ahla/shared-contracts';
import { mockActionCenter } from '../mock/domainMocks';

describe('useActionCenter — mock data schema validation', () => {
  it('parses all mock action center items against actionCenterItemSchema', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    expect(parsed).toHaveLength(mockActionCenter.length);
  });

  it('contains exactly 3 action items', () => {
    expect(mockActionCenter).toHaveLength(3);
  });

  it('kind is a valid enum value', () => {
    const validKinds = ['request', 'kpi', 'decision', 'report', 'case', 'task', 'policy'];
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    for (const item of parsed) {
      expect(validKinds).toContain(item.kind);
    }
  });

  it('has the expected kinds across mock data', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    expect(parsed[0].kind).toBe('request');
    expect(parsed[1].kind).toBe('kpi');
    expect(parsed[2].kind).toBe('decision');
  });

  it('priority is a valid action priority', () => {
    const validPriorities = ['low', 'normal', 'high', 'urgent'];
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    for (const item of parsed) {
      expect(validPriorities).toContain(item.priority);
    }
  });

  it('actionUrl starts with /', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    for (const item of parsed) {
      expect(item.actionUrl.startsWith('/')).toBe(true);
    }
  });

  it('title is a non-empty string', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    for (const item of parsed) {
      expect(item.title.length).toBeGreaterThan(0);
    }
  });

  it('subtitle is string or null', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    for (const item of parsed) {
      expect(item.subtitle === null || typeof item.subtitle === 'string').toBe(true);
    }
  });

  it('first item has urgent priority', () => {
    const parsed = actionCenterItemSchema.array().parse(mockActionCenter);
    expect(parsed[0].priority).toBe('urgent');
  });
});
