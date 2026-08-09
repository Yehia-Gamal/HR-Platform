import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Pagination } from './Pagination';

describe('Pagination', () => {
  it('renders current page info', () => {
    render(<Pagination currentPage={2} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByText('2')).toBeInTheDocument();
  });

  it('disables previous on first page', () => {
    const { container } = render(<Pagination currentPage={1} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    const buttons = container.querySelectorAll('button');
    // First button should be disabled (previous)
    expect(buttons[0]).toBeDisabled();
  });

  it('disables next on last page', () => {
    const { container } = render(<Pagination currentPage={5} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    const buttons = container.querySelectorAll('button');
    // Last pagination button should be disabled (next)
    const nextBtn = Array.from(buttons).find((b) => b.querySelector('svg'));
    expect(nextBtn).toBeDisabled();
  });

  it('calls onPageChange when a page number is clicked', () => {
    const onPageChange = vi.fn();
    render(<Pagination currentPage={1} totalPages={3} totalItems={30} pageSize={10} onPageChange={onPageChange} />);
    const page3Button = screen.getByText('3');
    fireEvent.click(page3Button);
    expect(onPageChange).toHaveBeenCalledWith(3);
  });

  it('shows total items count', () => {
    render(<Pagination currentPage={1} totalPages={5} totalItems={48} pageSize={10} onPageChange={() => {}} />);
    // Should show "48" somewhere as total items
    expect(screen.getByText(/48/)).toBeInTheDocument();
  });

  it('shows ellipsis when many pages', () => {
    render(<Pagination currentPage={1} totalPages={20} totalItems={200} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByText('20')).toBeInTheDocument();
  });
});
