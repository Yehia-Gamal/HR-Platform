import { fireEvent, render, screen } from '@testing-library/react';
import { expect, it, vi } from 'vitest';
import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { ProjectCard } from './ProjectCard';
import { ProjectClosureDialog } from './ProjectClosureDialog';
import { QuickUpdateDialog } from './QuickUpdateDialog';
import { projectProgressPercent } from './projectLedStatus';
import { MOCK_PROJECTS } from './projectMocks';

const { mutate, close } = vi.hoisted(() => ({ mutate: vi.fn(), close: vi.fn() }));
vi.mock('./useAssociationProjects', () => ({
  useAddProjectUpdate: () => ({ mutate, isPending: false }),
  useCloseAssociationProject: () => ({ mutate: close, isPending: false }),
}));

const oneStepDone: AssociationProjectListItem = {
  ...MOCK_PROJECTS[0]!,
  status: 'active',
  approvalStatus: 'approved',
  ledStatus: 'critical',
  totalSteps: 1,
  completedSteps: 1,
  remainingSteps: 0,
  currentStepTitle: null,
  progress: 100,
  planRevision: 7,
  canReviewClosure: true,
};

const doneStep = {
  id: 'reviewed-step', title: 'مراجعة عروض الأسعار', description: null,
  sortOrder: 1, status: 'done' as const, dueDate: null,
  assigneeId: null, assigneeName: null, completedAt: null, updatedAt: null,
};

it('يصف إتمام الخطوة الوحيدة من دون عرض اكتمال المشروع', () => {
  render(<ProjectCard project={oneStepDone} onOpen={vi.fn()} />);
  expect(screen.getByText('تمت خطوة واحدة')).toBeInTheDocument();
  expect(screen.getByText('قيد التنفيذ')).toBeInTheDocument();
  expect(screen.getByText(/بانتظار مراجعة خطة التنفيذ/)).toBeInTheDocument();
  expect(screen.queryByText('100%')).not.toBeInTheDocument();
  expect(screen.queryByText(/لم تُحدَّد خطوات/)).not.toBeInTheDocument();
});

it('يبقي 100% للمشروع المغلق ويحسب النسبة الجزئية من عدد خطواته', () => {
  expect(projectProgressPercent({ ...oneStepDone, status: 'completed' })).toBe(100);
  expect(projectProgressPercent({ ...oneStepDone, totalSteps: 4 })).toBe(25);
  expect(projectProgressPercent({ ...oneStepDone, totalSteps: 200, completedSteps: 199 })).toBe(99);
  expect(projectProgressPercent({ ...oneStepDone, totalSteps: 0, completedSteps: 0 })).toBeNull();
});

it('يرسل اعتماد الإغلاق بنسخة الخطة بعد مراجعة الخطوات وتدوين النتيجة', () => {
  close.mockClear();
  render(<ProjectClosureDialog project={oneStepDone} steps={[doneStep]} onClose={vi.fn()} />);
  expect(screen.getByText(doneStep.title)).toBeInTheDocument();
  fireEvent.change(screen.getByRole('textbox'), { target: { value: 'اكتمل نطاق العمل' } });
  const save = screen.getByRole('button', { name: 'اعتماد إغلاق المشروع' });
  expect(save).toBeDisabled();
  fireEvent.click(screen.getByRole('checkbox', { name: /راجعت خطة التنفيذ/ }));
  fireEvent.click(save);
  expect(close).toHaveBeenCalledWith(
    { projectId: oneStepDone.id, planRevision: 7, reviewNote: 'اكتمل نطاق العمل' },
    expect.objectContaining({ onSuccess: expect.any(Function) }),
  );
});

it('يحصر التحديث السريع في تقدم العمل والتوقف', () => {
  render(<QuickUpdateDialog project={oneStepDone} onClose={vi.fn()} />);
  expect(screen.queryByRole('button', { name: 'مكتمل' })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'متوقف' }));
  expect(screen.getByRole('textbox', { name: /سبب توقف المشروع/ })).toBeInTheDocument();
});

it('يعطّل اعتماد الإغلاق عندما تبقى خطوة مفتوحة', () => {
  render(<ProjectClosureDialog project={oneStepDone} steps={[{ ...doneStep, status: 'pending' }]} onClose={vi.fn()} />);
  fireEvent.change(screen.getByRole('textbox'), { target: { value: 'ملاحظة' } });
  fireEvent.click(screen.getByRole('checkbox'));
  expect(screen.getByRole('button', { name: 'اعتماد إغلاق المشروع' })).toBeDisabled();
});

it('يسمح بملاحظة على مشروع مكتمل من دون إعادة تسجيل الاكتمال', () => {
  mutate.mockClear();
  render(<QuickUpdateDialog project={{ ...oneStepDone, status: 'completed' }} onClose={vi.fn()} />);
  fireEvent.change(screen.getByRole('textbox'), { target: { value: 'ملاحظة متابعة' } });
  expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: 'حفظ التحديث' }));
  expect(mutate).toHaveBeenCalledWith(
    { projectId: oneStepDone.id, note: 'ملاحظة متابعة', progress: null, statusChange: null },
    expect.objectContaining({ onSuccess: expect.any(Function) }),
  );
});
