import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { ArabicDateInput, formatArabicDateDisplay } from './ArabicDateInput';

describe('ArabicDateInput', () => {
  it('ينسق تاريخ ISO إلى yyyy/mm/dd بالأرقام الغربية', () => {
    expect(formatArabicDateDisplay('2026-11-27')).toBe('2026/11/27');
    expect(formatArabicDateDisplay('2026-11-27T14:30')).toBe('2026/11/27 14:30');
    expect(formatArabicDateDisplay('')).toBe('');
    expect(formatArabicDateDisplay(undefined)).toBe('');
  });

  it('يعرض التاريخ بصيغة yyyy/mm/dd مع الإبقاء على input[type=date] للوصولية والتغيير', () => {
    const onChange = vi.fn();
    render(<ArabicDateInput aria-label="تاريخ الحضور" value="2026-11-27" onChange={onChange} />);

    expect(screen.getByText('2026/11/27')).toBeInTheDocument();
    const input = screen.getByLabelText('تاريخ الحضور') as HTMLInputElement;
    expect(input.type).toBe('date');
    expect(input.value).toBe('2026-11-27');

    fireEvent.change(input, { target: { value: '2026-12-01' } });
    expect(onChange).toHaveBeenCalledTimes(1);
  });

  it('يعرض النص البديل عند خلو القيمة ويدعم الوضع غير المتحكم', () => {
    render(<ArabicDateInput aria-label="تاريخ البداية" defaultValue="" />);
    expect(screen.getByText('yyyy/mm/dd')).toBeInTheDocument();

    const input = screen.getByLabelText('تاريخ البداية') as HTMLInputElement;
    fireEvent.change(input, { target: { value: '2026-05-03' } });
    expect(screen.getByText('2026/05/03')).toBeInTheDocument();
  });
});
