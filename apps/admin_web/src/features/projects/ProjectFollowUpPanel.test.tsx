import { fireEvent, render, screen } from '@testing-library/react';
import { expect, it, vi } from 'vitest';
import { ProjectFollowUpPanel } from './ProjectFollowUpPanel';
import { projectFollowUpReasons } from './projectFollowUp';
import { MOCK_PROJECTS } from './projectMocks';

it('يميّز المشاريع المتوقفة عن التي لم تُحدّث ويتجاهل المغلقة', () => {
  expect(projectFollowUpReasons(MOCK_PROJECTS[1]!)).toEqual(['inactive']);
  expect(projectFollowUpReasons(MOCK_PROJECTS[3]!)).toEqual(['paused']);
  expect(projectFollowUpReasons(MOCK_PROJECTS[4]!)).toEqual([]);
});

it('يحسب المشروع مرة واحدة في الإجمالي ويتيح فتحه وتصفيته بأسبابه المتعددة', () => {
  const overdue = MOCK_PROJECTS[2]!;
  const onFilter = vi.fn();
  const onOpen = vi.fn();
  render(<ProjectFollowUpPanel projects={[overdue, MOCK_PROJECTS[4]!]} filter="all" onFilter={onFilter} onOpen={onOpen} />);
  expect(screen.getByText('1 من 2 مشروع معتمد يحتاج مراجعة')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /بها خطوات متعثرة 1/ }));
  expect(onFilter).toHaveBeenCalledWith('blocked');
  fireEvent.click(screen.getByRole('button', { name: /تجهيز مخزن المساعدات الجديد/ }));
  expect(onOpen).toHaveBeenCalledWith(overdue.id);
});
