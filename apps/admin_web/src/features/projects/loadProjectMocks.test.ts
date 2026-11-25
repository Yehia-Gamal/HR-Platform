import { describe, it, expect } from 'vitest';
import { loadProjectMocks } from './loadProjectMocks';

describe('loadProjectMocks', () => {
  it('يعيد بيانات المعاينة لمشاريع الجمعية في وضع التطوير', async () => {
    const mocks = await loadProjectMocks();
    expect(typeof mocks.mockCatalog).toBe('function');
    expect(typeof mocks.mockDetail).toBe('function');
    expect(typeof mocks.mockPickers).toBe('function');
    expect(typeof mocks.mockMyTasks).toBe('function');
    const catalog = mocks.mockCatalog();
    expect(catalog.projects.length).toBeGreaterThan(0);
  });
});
