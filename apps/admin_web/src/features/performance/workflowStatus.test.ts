import { describe, it, expect } from 'vitest';
import {
  kpiWorkflowStatusLabel,
  kpiWorkflowStatusText,
} from './workflowStatus';

describe('kpiWorkflowStatusLabel', () => {
  it('is defined and is an object', () => {
    expect(kpiWorkflowStatusLabel).toBeDefined();
    expect(typeof kpiWorkflowStatusLabel).toBe('object');
  });

  it.each([
    'DRAFT',
    'OPEN_FOR_SELF_EVALUATION',
    'SUBMITTED_TO_DIRECT_MANAGER',
    'MANAGER_REVIEW',
    'HR_REVIEW',
    'CYCLE_CLOSED',
    'ARCHIVED',
    'NOT_STARTED',
    'APPROVED',
    'CLOSED',
  ])('has expected key "%s"', (key) => {
    expect(kpiWorkflowStatusLabel).toHaveProperty(key);
  });

  it('values are all non-empty strings', () => {
    for (const [key, value] of Object.entries(kpiWorkflowStatusLabel)) {
      expect(value, `value for "${key}" should be a non-empty string`).toEqual(
        expect.any(String),
      );
      expect(value.length, `value for "${key}" should not be empty`).toBeGreaterThan(0);
    }
  });

  it('has at least 25 entries', () => {
    expect(Object.keys(kpiWorkflowStatusLabel).length).toBeGreaterThanOrEqual(25);
  });

  it('contains exactly 32 entries', () => {
    expect(Object.keys(kpiWorkflowStatusLabel).length).toBe(32);
  });

  it('every value contains at least one Arabic character', () => {
    for (const [key, value] of Object.entries(kpiWorkflowStatusLabel)) {
      expect(value, `label for "${key}" should contain Arabic`).toMatch(/[؀-ۿ]/);
    }
  });

  describe('V23 parallel flow statuses', () => {
    it.each([
      'PARALLEL_REVIEW_IN_PROGRESS',
      'HR_COMPLETED',
      'MANAGER_COMPLETED',
      'SECRETARY_REVIEW',
      'EXECUTIVE_REVIEW',
      'EXECUTIVE_ACKNOWLEDGED',
      'RETURNED_BY_EXECUTIVE',
    ])('includes V23 status "%s"', (key) => {
      expect(kpiWorkflowStatusLabel).toHaveProperty(key);
      expect(kpiWorkflowStatusLabel[key].length).toBeGreaterThan(0);
    });

    it('kpiWorkflowStatusText resolves V23 codes to Arabic labels', () => {
      expect(kpiWorkflowStatusText('PARALLEL_REVIEW_IN_PROGRESS')).toBe(
        'مراجعة HR والمدير جارية بالتوازي',
      );
      expect(kpiWorkflowStatusText('HR_COMPLETED')).toBe(
        'أنهى HR مراجعته — بانتظار المدير',
      );
      expect(kpiWorkflowStatusText('MANAGER_COMPLETED')).toBe(
        'أنهى المدير مراجعته — بانتظار HR',
      );
      expect(kpiWorkflowStatusText('SECRETARY_REVIEW')).toBe(
        'قيد مراجعة السكرتير التنفيذي',
      );
      expect(kpiWorkflowStatusText('EXECUTIVE_REVIEW')).toBe(
        'بانتظار إقرار المدير التنفيذي',
      );
      expect(kpiWorkflowStatusText('EXECUTIVE_ACKNOWLEDGED')).toBe(
        'أقرّ المدير التنفيذي',
      );
      expect(kpiWorkflowStatusText('RETURNED_BY_EXECUTIVE')).toBe(
        'أعاده المدير التنفيذي للمراجعة',
      );
    });
  });
});

describe('kpiWorkflowStatusText', () => {
  it('returns the Arabic label for DRAFT', () => {
    expect(kpiWorkflowStatusText('DRAFT')).toBe('مسودة قبل فتح الدورة');
  });

  it('returns the Arabic label for MANAGER_REVIEW', () => {
    expect(kpiWorkflowStatusText('MANAGER_REVIEW')).toBe('قيد مراجعة المدير المباشر');
  });

  it('returns the Arabic label for APPROVED', () => {
    expect(kpiWorkflowStatusText('APPROVED')).toBe('معتمد');
  });

  it('returns the Arabic label for additional known codes', () => {
    expect(kpiWorkflowStatusText('OPEN_FOR_SELF_EVALUATION')).toBe('مفتوح للتقييم الذاتي');
    expect(kpiWorkflowStatusText('HR_REVIEW')).toBe('قيد مراجعة الموارد البشرية');
    expect(kpiWorkflowStatusText('CLOSED')).toBe('مؤرشف');
    expect(kpiWorkflowStatusText('OVERDUE')).toBe('متأخر عن الموعد');
  });

  it('passes through an unknown status value as-is', () => {
    expect(kpiWorkflowStatusText('UNKNOWN_STATUS')).toBe('UNKNOWN_STATUS');
    expect(kpiWorkflowStatusText('foo')).toBe('foo');
    expect(kpiWorkflowStatusText('123')).toBe('123');
  });

  it('returns empty string for null', () => {
    expect(kpiWorkflowStatusText(null)).toBe('');
  });

  it('returns empty string for undefined', () => {
    expect(kpiWorkflowStatusText(undefined)).toBe('');
  });

  it('returns empty string for empty string', () => {
    expect(kpiWorkflowStatusText('')).toBe('');
  });

  it('resolves V23 parallel-flow codes to Arabic labels', () => {
    expect(kpiWorkflowStatusText('PARALLEL_REVIEW_IN_PROGRESS')).toBe(
      'مراجعة HR والمدير جارية بالتوازي',
    );
    expect(kpiWorkflowStatusText('HR_COMPLETED')).toBe(
      'أنهى HR مراجعته — بانتظار المدير',
    );
    expect(kpiWorkflowStatusText('MANAGER_COMPLETED')).toBe(
      'أنهى المدير مراجعته — بانتظار HR',
    );
    expect(kpiWorkflowStatusText('SECRETARY_REVIEW')).toBe(
      'قيد مراجعة السكرتير التنفيذي',
    );
    expect(kpiWorkflowStatusText('EXECUTIVE_REVIEW')).toBe(
      'بانتظار إقرار المدير التنفيذي',
    );
    expect(kpiWorkflowStatusText('EXECUTIVE_ACKNOWLEDGED')).toBe(
      'أقرّ المدير التنفيذي',
    );
    expect(kpiWorkflowStatusText('RETURNED_BY_EXECUTIVE')).toBe(
      'أعاده المدير التنفيذي للمراجعة',
    );
  });
});
