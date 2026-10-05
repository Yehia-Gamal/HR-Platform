import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { mockMyTasks } from './projectMocks';
import { MyTasksTab } from './MyTasksTab';

const mutate = vi.fn();
const tasks = vi.hoisted(() => ({ current: {} as Record<string, unknown> }));
vi.mock('./useAssociationProjects', () => ({
  useMyProjectTasks: () => tasks.current,
  useSetProjectStepStatus: () => ({ mutate, isPending: false }),
}));

describe('تبويب «مهامي» (0647)', () => {
  it('يجمّع المهام: المتأخرة ثم القريبة ثم اللاحقة، ويعلّمها «تمت»', () => {
    tasks.current = { data: mockMyTasks(), isLoading: false, error: null, refetch: vi.fn() };
    render(<MyTasksTab onOpenProject={() => {}} />);
    const headings = screen.getAllByRole('heading').map((h) => h.textContent);
    expect(headings).toEqual(['متأخرة عن موعدها (1)', 'موعدها خلال يومين (1)', 'لاحقاً / بلا موعد (1)']);
    fireEvent.click(screen.getAllByRole('button', { name: /تمت/ }).at(0) as HTMLElement);
    expect(mutate).toHaveBeenCalledWith({ stepId: mockMyTasks()[0]?.stepId, status: 'done' });
  });

  it('يفتح المشروع من اسمه', () => {
    const onOpen = vi.fn();
    tasks.current = { data: mockMyTasks(), isLoading: false, error: null, refetch: vi.fn() };
    render(<MyTasksTab onOpenProject={onOpen} />);
    fireEvent.click(screen.getAllByRole('button', { name: /تطبيق إدارة الحضور/ }).at(0) as HTMLElement);
    expect(onOpen).toHaveBeenCalledWith(mockMyTasks()[0]?.projectId);
  });

  it('بلا مهام', () => {
    tasks.current = { data: [], isLoading: false, error: null, refetch: vi.fn() };
    render(<MyTasksTab onOpenProject={() => {}} />);
    expect(screen.getByText('لا توجد مهام مكلَّف بها')).toBeInTheDocument();
  });
});
