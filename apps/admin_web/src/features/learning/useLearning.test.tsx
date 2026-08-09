import { describe, it, expect } from 'vitest';
import { learningCourseSchema, learningCatalogSchema } from './useLearning';

const validCourse = {
  id: '11111111-1111-4111-8111-111111111111',
  code: 'C001',
  title: 'دورة أمن المعلومات',
  category: 'تقنية',
  deliveryMode: 'online' as const,
  durationMinutes: 120,
  mandatory: true,
  active: true,
  enrollments: 5,
  completed: 2,
};

describe('learning schemas', () => {
  it('parses a valid course', () => {
    const parsed = learningCourseSchema.parse(validCourse);
    expect(parsed.title).toBe('دورة أمن المعلومات');
    expect(parsed.deliveryMode).toBe('online');
    expect(parsed.mandatory).toBe(true);
  });

  it('parses a valid catalog', () => {
    const catalog = learningCatalogSchema.parse({
      courses: [validCourse],
      enrollments: [],
      employees: [],
    });
    expect(catalog.courses).toHaveLength(1);
    expect(catalog.enrollments).toHaveLength(0);
    expect(catalog.courses[0].title).toBe('دورة أمن المعلومات');
  });

  it('rejects invalid deliveryMode', () => {
    expect(() => learningCourseSchema.parse({ ...validCourse, deliveryMode: 'invalid' })).toThrow();
  });

  it('rejects non-uuid id', () => {
    expect(() => learningCourseSchema.parse({ ...validCourse, id: 'not-a-uuid' })).toThrow();
  });

  it('defaults enrollments and completed to 0', () => {
    const { enrollments: _e, completed: _c, ...rest } = validCourse;
    const parsed = learningCourseSchema.parse(rest);
    expect(parsed.enrollments).toBe(0);
    expect(parsed.completed).toBe(0);
  });
});
