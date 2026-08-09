import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Tabs, type TabItem } from './Tabs';

const tabs: TabItem[] = [
  { id: 'all', label: 'الكل', count: 10 },
  { id: 'active', label: 'نشط', count: 5 },
  { id: 'inactive', label: 'غير نشط' },
];

describe('Tabs', () => {
  it('renders all tab labels', () => {
    render(
      <Tabs tabs={tabs} activeTab="all" onTabChange={() => {}}>
        <div>المحتوى</div>
      </Tabs>,
    );
    expect(screen.getByText('الكل')).toBeInTheDocument();
    expect(screen.getByText('نشط')).toBeInTheDocument();
    expect(screen.getByText('غير نشط')).toBeInTheDocument();
  });

  it('renders children content', () => {
    render(
      <Tabs tabs={tabs} activeTab="all" onTabChange={() => {}}>
        <div>المحتوى</div>
      </Tabs>,
    );
    expect(screen.getByText('المحتوى')).toBeInTheDocument();
  });

  it('calls onTabChange when a tab is clicked', () => {
    const onTabChange = vi.fn();
    render(
      <Tabs tabs={tabs} activeTab="all" onTabChange={onTabChange}>
        <div>content</div>
      </Tabs>,
    );
    fireEvent.click(screen.getByText('نشط'));
    expect(onTabChange).toHaveBeenCalledWith('active');
  });

  it('marks active tab with aria-selected', () => {
    render(
      <Tabs tabs={tabs} activeTab="active" onTabChange={() => {}}>
        <div>content</div>
      </Tabs>,
    );
    const activeTab = screen.getByRole('tab', { selected: true });
    expect(activeTab).toHaveTextContent('نشط');
  });

  it('renders count badge when provided', () => {
    render(
      <Tabs tabs={tabs} activeTab="all" onTabChange={() => {}}>
        <div>content</div>
      </Tabs>,
    );
    expect(screen.getByText('10')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
  });
});
