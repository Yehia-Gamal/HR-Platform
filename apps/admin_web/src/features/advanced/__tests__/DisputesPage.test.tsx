import { render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { DisputesPage } from '../DisputesPage';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockMut = { isPending: false, isError: false, error: null, mutateAsync: vi.fn(), mutate: vi.fn() };
const mockCommands = {
  acceptCase: { ...mockMut },
  transitionCase: { ...mockMut },
  setCommittee: { ...mockMut },
  addStatement: { ...mockMut },
  scheduleSession: { ...mockMut },
  finalizeSession: { ...mockMut },
  issueDecision: { ...mockMut },
  proposeAdminAction: { ...mockMut },
  executeAdminAction: { ...mockMut },
  recordSettlement: { ...mockMut },
  completeAction: { ...mockMut },
  decideAppeal: { ...mockMut },
};

const mockCase = {
  id: 'case-1',
  caseNumber: 'CASE-2026-001',
  title: 'خلاف بين موظفين',
  status: 'submitted',
  priority: 'normal',
  caseType: 'employee_conflict',
  description: 'وصف المشكلة',
  actorName: 'أحمد محمد',
  actorDepartment: 'تقنية المعلومات',
  respondentName: 'محمد علي',
  assignedTo: null,
  assignedName: null,
  quorum: 3,
  incidentAt: '2026-08-01T10:00:00Z',
  incidentLocation: 'المكتب',
  requestedAction: 'حل الخلاف',
  directManagerContacted: false,
  amicableAttempted: false,
  reviewDueAt: null,
  overdue: false,
  proposedAdminAction: null,
  executiveDecision: null,
  executiveDecisionReason: null,
  approvedAdminAction: null,
  executedAt: null,
  executionNotes: null,
  decision: null,
  parties: [],
  members: [],
  sessions: [],
  statements: [],
  actions: [],
  appeals: [],
};
const mockSummary = { new: 1, overdue: 0, waitingStatements: 0, pendingExecution: 0, critical: 0 };

let disputeOpsFn: () => Record<string, unknown>;
let directoryFn: () => Record<string, unknown>;

vi.mock('../useAdvancedOperations', () => ({
  useDisputeOperations: () => disputeOpsFn(),
  useDisputeParticipantDirectory: () => directoryFn(),
  useDisputeCommands: () => mockCommands,
}));

const emptyDirectory = { data: [], isLoading: false, isError: false, error: null };
const emptyQuery = {
  data: { cases: [], summary: mockSummary },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = {
  data: { cases: [mockCase], summary: mockSummary },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('server error'),
  refetch: vi.fn(),
};

describe('DisputesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    disputeOpsFn = () => emptyQuery;
    directoryFn = () => emptyDirectory;
    const { container } = render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    disputeOpsFn = () => emptyQuery;
    directoryFn = () => emptyDirectory;
    render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(screen.getByText('لجنة حل المشكلات والخلافات')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    disputeOpsFn = () => emptyQuery;
    directoryFn = () => emptyDirectory;
    render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(screen.getByText('جديدة')).toBeDefined();
    expect(screen.getByText('تجاوزت 24 ساعة')).toBeDefined();
    expect(screen.getByText('بانتظار إفادات')).toBeDefined();
    expect(screen.getByText('تنفيذات معلقة')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    disputeOpsFn = () => loadingQuery;
    directoryFn = () => emptyDirectory;
    const { container } = render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل التحميل', () => {
    disputeOpsFn = () => errorQuery;
    directoryFn = () => emptyDirectory;
    render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل القضايا')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود قضايا', () => {
    disputeOpsFn = () => emptyQuery;
    directoryFn = () => emptyDirectory;
    render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد قضايا مطابقة')).toBeDefined();
  });

  it('يعرض القضية في القائمة عند وجود بيانات', () => {
    disputeOpsFn = () => dataQuery;
    directoryFn = () => emptyDirectory;
    render(
      <Wrapper>
        <DisputesPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('خلاف بين موظفين').length).toBeGreaterThan(0);
  });
});
