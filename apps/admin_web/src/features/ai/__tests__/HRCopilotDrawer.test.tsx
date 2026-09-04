import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { HRCopilotDrawer } from '../HRCopilotDrawer';
import { ToastProvider } from '../../../ui/Toast';

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'authenticated',
    access: {
      displayName: 'محمد محمود',
      employeeCode: 'EMP-01',
      permissions: ['*'],
      workspaces: ['main_admin'],
    },
  }),
}));

describe('HRCopilotDrawer', () => {
  it('does not render when isOpen is false', () => {
    render(
      <ToastProvider>
        <HRCopilotDrawer isOpen={false} onClose={() => {}} />
      </ToastProvider>,
    );

    expect(screen.queryByText('المساعد الإداري الذكي')).not.toBeInTheDocument();
  });

  it('renders drawer header and default tabs when isOpen is true', () => {
    render(
      <ToastProvider>
        <HRCopilotDrawer isOpen={true} onClose={() => {}} />
      </ToastProvider>,
    );

    expect(screen.getByText('المساعد الإداري الذكي')).toBeInTheDocument();
    expect(screen.getByText('Copilot AI')).toBeInTheDocument();
    expect(screen.getByText('المحادثة واللوائح')).toBeInTheDocument();
    expect(screen.getByText('صانع الخطابات')).toBeInTheDocument();
    expect(screen.getByText('حاسبة الجزاءات')).toBeInTheDocument();
  });

  it('switches to letters generator mode', () => {
    render(
      <ToastProvider>
        <HRCopilotDrawer isOpen={true} onClose={() => {}} />
      </ToastProvider>,
    );

    fireEvent.click(screen.getByText('صانع الخطابات'));
    expect(screen.getByText('بيانات الخطاب الإداري المطلوب')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /توليد الخطاب الإداري/i })).toBeInTheDocument();
  });

  it('switches to penalty calculator mode and shows calculated deduction', () => {
    render(
      <ToastProvider>
        <HRCopilotDrawer isOpen={true} onClose={() => {}} />
      </ToastProvider>,
    );

    fireEvent.click(screen.getByText('حاسبة الجزاءات'));
    expect(screen.getByText('محاكي احتساب الخصم والجزاء القانوني')).toBeInTheDocument();
    expect(screen.getByText('قيمة الخصم المالي المقترح')).toBeInTheDocument();
  });
});
