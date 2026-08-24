import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router';
import { describe, expect, it } from 'vitest';
import { CommandPalette } from '../CommandPalette';

/** مسبار يعرض المسار الحالي للتحقق من نتائج التنقل. */
function LocationProbe() {
  const { pathname } = useLocation();
  return <div data-testid="location-probe">{pathname}</div>;
}

function renderPalette(initialPath = '/hr/attendance') {
  return render(
    <MemoryRouter initialEntries={[initialPath]}>
      <LocationProbe />
      <CommandPalette />
    </MemoryRouter>,
  );
}

const open = () => {
  fireEvent.keyDown(window, { ctrlKey: true, key: 'k' });
};

describe('CommandPalette', () => {
  it('مخفية افتراضياً ولا تعرض شيئاً', () => {
    renderPalette();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(screen.queryByPlaceholderText('انتقل إلى صفحة…')).toBeNull();
  });

  it('تُفتح بـ Ctrl+K وتُغلق بـ Escape وتنقلب بـ Ctrl+K مجدداً', () => {
    renderPalette();
    open();
    expect(screen.getByRole('dialog')).toBeTruthy();
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
    open();
    expect(screen.getByRole('dialog')).toBeTruthy();
  });

  it('في /hr تخفي بنود الإدارة الحصرية وتعرض العامة', () => {
    renderPalette('/hr/attendance');
    open();
    // عامة مرئية («الحضور» تظهر كعنصر وكاسم مجموعة متكرر)
    expect(screen.getByText('الإشعارات')).toBeTruthy();
    expect(screen.getAllByText('الحضور').length).toBeGreaterThan(0);
    // إدارية حصرية مخفية
    expect(screen.queryByText('الصلاحيات والوصول')).toBeNull();
    expect(screen.queryByText('المالية')).toBeNull();
    expect(screen.queryByText('دورات KPI')).toBeNull();
  });

  it('في /admin تظهر بنود الإدارة الحصرية أيضاً', () => {
    renderPalette('/admin/access');
    open();
    expect(screen.getByText('الصلاحيات والوصول')).toBeTruthy();
    expect(screen.getByText('دورات KPI')).toBeTruthy();
    // والعامة تبقى
    expect(screen.getByText('الإشعارات')).toBeTruthy();
  });

  it('البحث يفلتر بالاسم العربي ويعرض رسالة عدم المطابقة', () => {
    renderPalette('/hr');
    open();
    const input = screen.getByLabelText('بحث لوحة الأوامر');
    fireEvent.change(input, { target: { value: 'إجازات' } });
    expect(screen.getByText('الإجازات')).toBeTruthy();
    expect(screen.queryByText('الحضور')).toBeNull();

    fireEvent.change(input, { target: { value: 'xyz-لا-يوجد' } });
    expect(screen.getByText('لا توجد صفحات مطابقة.')).toBeTruthy();
  });

  it('Enter ينتقل لمسار البند النشط ويغلق اللوحة', () => {
    renderPalette('/hr');
    open();
    const input = screen.getByLabelText('بحث لوحة الأوامر');
    fireEvent.change(input, { target: { value: 'الإشعارات' } });
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(screen.getByTestId('location-probe').textContent).toBe('/hr/notifications');
  });

  it('الأسهم تحرك التحديد ثم Enter ينقل للمسار الصحيح', () => {
    renderPalette('/hr');
    open();
    const input = screen.getByLabelText('بحث لوحة الأوامر');
    // القائمة الافتراضية تبدأ بالرئيسية ثم الإشعارات…
    fireEvent.keyDown(input, { key: 'ArrowDown' });
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(screen.getByTestId('location-probe').textContent).toBe('/hr/notifications');
  });

  it('النقر على البند ينتقل، والنقر على الخلفية يغلق دون تنقل', () => {
    renderPalette('/hr');
    open();
    fireEvent.click(screen.getByText('الهيكل التنظيمي'));
    expect(screen.getByTestId('location-probe').textContent).toBe('/hr/organization');

    open();
    fireEvent.click(screen.getByRole('presentation'));
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('عدّاد النتائج يعكس عدد البنود بعد التصفية', () => {
    renderPalette('/admin');
    open();
    const before = screen.getByText(/\d+ صفحة/).textContent;
    expect(before).toBeTruthy();

    const input = screen.getByLabelText('بحث لوحة الأوامر');
    fireEvent.change(input, { target: { value: 'finance' } });
    // finance + finance/penalties + finance/instapay داخل /admin
    expect(screen.getByText('3 صفحة')).toBeTruthy();
  });
});
