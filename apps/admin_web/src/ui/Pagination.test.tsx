import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Pagination } from './Pagination';

describe('Pagination', () => {
  it('renders navigation with aria-label', () => {
    render(<Pagination currentPage={2} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByRole('navigation')).toBeInTheDocument();
  });

  it('disables previous on first page', () => {
    render(<Pagination currentPage={1} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByLabelText('الصفحة السابقة')).toBeDisabled();
  });

  it('enables next on non-last page', () => {
    render(<Pagination currentPage={1} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByLabelText('الصفحة التالية')).not.toBeDisabled();
  });

  it('disables next on last page', () => {
    render(<Pagination currentPage={5} totalPages={5} totalItems={50} pageSize={10} onPageChange={() => {}} />);
    expect(screen.getByLabelText('الصفحة التالية')).toBeDisabled();
  });

  it('calls onPageChange when next is clicked', () => {
    const onPageChange = vi.fn();
    render(<Pagination currentPage={1} totalPages={5} totalItems={50} pageSize={10} onPageChange={onPageChange} />);
    fireEvent.click(screen.getByLabelText('الصفحة التالية'));
    expect(onPageChange).toHaveBeenCalledWith(2);
  });

  it('calls onPageChange when a page button is clicked', () => {
    const onPageChange = vi.fn();
    const { container } = render(<Pagination currentPage={1} totalPages={3} totalItems={30} pageSize={10} onPageChange={onPageChange} />);
    // الصفحات تُعرض بأرقام عربية (ar-EG). نطقّر على ثالث زر صفحة.
    const pageButtons = container.querySelectorAll('button[aria-current], button:not([disabled])');
    // نجد الأزرار التي تحتوي على رقم الصفحة (excl. prev/next which have svg icons)
    const numberButtons = Array.from(pageButtons).filter((b) => !b.querySelector('svg'));
    expect(numberButtons.length).toBeGreaterThanOrEqual(2);
    fireEvent.click(numberButtons[numberButtons.length - 1]);
    expect(onPageChange).toHaveBeenCalled();
  });

  it('renders null when totalPages is 0', () => {
    const { container } = render(<Pagination currentPage={1} totalPages={0} totalItems={0} pageSize={10} onPageChange={() => {}} />);
    expect(container.firstChild).toBeNull();
  });
});
