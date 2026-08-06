import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { FilterBar } from './FilterBar';

describe('FilterBar', () => {
  it('يعرض حقل البحث مع placeholder', () => {
    render(<FilterBar searchValue="" onSearchChange={() => {}} searchPlaceholder="ابحث عن موظف..." />);
    expect(screen.getByPlaceholderText('ابحث عن موظف...')).toBeDefined();
  });

  it('يستدعي onSearchChange عند الكتابة', () => {
    const onChange = vi.fn();
    render(<FilterBar searchValue="" onSearchChange={onChange} searchPlaceholder="ابحث..." />);
    const input = screen.getByPlaceholderText('ابحث...');
    fireEvent.change(input, { target: { value: 'أحمد' } });
    expect(onChange).toHaveBeenCalledWith('أحمد');
  });

  it('يعرض نص النتائج عند توفره', () => {
    const { container } = render(<FilterBar searchValue="أحمد" onSearchChange={() => {}} searchPlaceholder="ابحث..." resultText="3 نتائج" />);
    expect(container.textContent).toContain('3 نتائج');
  });

  it('يعرض زر "مسح الكل" عند وجود فلاتر نشطة', () => {
    const onClear = vi.fn();
    const { container } = render(<FilterBar searchValue="أحمد" onSearchChange={() => {}} searchPlaceholder="ابحث..." isDirty={true} onClear={onClear} />);
    const clearButton = container.querySelector('.filter-clear');
    expect(clearButton).toBeTruthy();
    fireEvent.click(clearButton as HTMLElement);
    expect(onClear).toHaveBeenCalledOnce();
  });

  it('لا يعرض زر "مسح الكل" عندما isDirty=false', () => {
    const { container } = render(<FilterBar searchValue="" onSearchChange={() => {}} searchPlaceholder="ابحث..." isDirty={false} onClear={() => {}} />);
    expect(container.querySelector('.filter-clear')).toBeNull();
  });

  it('يحتوي على aria-label للوصولية', () => {
    const { container } = render(<FilterBar searchValue="" onSearchChange={() => {}} searchPlaceholder="ابحث..." />);
    const section = container.querySelector('[aria-label]');
    expect(section).toBeTruthy();
  });
});
