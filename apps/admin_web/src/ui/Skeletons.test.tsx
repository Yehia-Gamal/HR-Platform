import { render } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ListSkeleton, MetricSkeletonRow, SkeletonCard } from './Skeletons';

describe('SkeletonCard', () => {
  it('يعرض بطاقة بتأثير النبض', () => {
    const { container } = render(<SkeletonCard />);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يقبل className إضافي', () => {
    const { container } = render(<SkeletonCard className="h-48" />);
    const card = container.querySelector('.animate-pulse');
    expect(card?.classList.contains('h-48')).toBe(true);
  });

  it('مخفي عن قارئات الشاشة', () => {
    const { container } = render(<SkeletonCard />);
    expect(container.querySelector('[aria-hidden="true"]')).toBeTruthy();
  });
});

describe('MetricSkeletonRow', () => {
  it('يعرض 4 بطاقات افتراضياً', () => {
    const { container } = render(<MetricSkeletonRow />);
    const cards = container.querySelectorAll('.metric-card');
    expect(cards.length).toBe(4);
  });

  it('يعرض عدداً مخصصاً من البطاقات', () => {
    const { container } = render(<MetricSkeletonRow count={2} />);
    const cards = container.querySelectorAll('.metric-card');
    expect(cards.length).toBe(2);
  });

  it('مخفي عن قارئات الشاشة', () => {
    const { container } = render(<MetricSkeletonRow />);
    expect(container.querySelector('[aria-hidden="true"]')).toBeTruthy();
  });
});

describe('ListSkeleton', () => {
  it('يعرض 3 صفوف افتراضياً', () => {
    const { container } = render(<ListSkeleton />);
    const rows = container.querySelectorAll('.card');
    expect(rows.length).toBe(3);
  });

  it('يعرض عدداً مخصصاً من الصفوف', () => {
    const { container } = render(<ListSkeleton rows={5} />);
    const rows = container.querySelectorAll('.card');
    expect(rows.length).toBe(5);
  });

  it('يحتوي على aria-busy', () => {
    const { container } = render(<ListSkeleton />);
    expect(container.querySelector('[aria-busy="true"]')).toBeTruthy();
  });

  it('يحتوي على aria-label الافتراضي', () => {
    const { container } = render(<ListSkeleton />);
    const section = container.querySelector('[aria-label]');
    expect(section?.getAttribute('aria-label')).toBe('جارٍ التحميل…');
  });

  it('يقبل aria-label مخصص', () => {
    const { container } = render(<ListSkeleton label="تحميل الموظفين…" />);
    const section = container.querySelector('[aria-label]');
    expect(section?.getAttribute('aria-label')).toBe('تحميل الموظفين…');
  });
});
