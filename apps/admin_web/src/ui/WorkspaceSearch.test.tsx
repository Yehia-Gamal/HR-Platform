import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { describe, expect, it } from 'vitest';
import { WorkspaceSearch } from './WorkspaceSearch';

const destinations = [
  { label: 'الموظفون', to: '/employees', group: 'الأفراد' },
  { label: 'الحضور', to: '/attendance', group: 'الوقت' },
];

describe('WorkspaceSearch', () => {
  it('filters destinations and navigates to the selected page', () => {
    render(
      <MemoryRouter initialEntries={['/']}>
        <WorkspaceSearch destinations={destinations} />
        <Routes>
          <Route path="/" element={<p>الرئيسية</p>} />
          <Route path="/employees" element={<p>صفحة الموظفين</p>} />
        </Routes>
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole('button', { name: /بحث سريع/ }));
    fireEvent.change(screen.getByLabelText('البحث في الوحدات'), { target: { value: 'موظف' } });
    fireEvent.click(screen.getByRole('button', { name: /الموظفون/ }));
    expect(screen.getByText('صفحة الموظفين')).toBeInTheDocument();
  });
});
