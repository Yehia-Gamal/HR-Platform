import type { AccessContext } from '@ahla/shared-contracts';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { mockContexts } from '../features/auth/mockContexts';
import { App } from './App';

const auth = vi.hoisted(() => ({ access: null as AccessContext | null, signOut: vi.fn() }));
vi.mock('../features/auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', access: auth.access, signOut: auth.signOut }),
}));
vi.mock('../features/auth/useWebReleasePolicy', () => ({
  useWebReleasePolicy: () => ({}),
  useRegisterWebDevice: () => {},
}));
vi.mock('../features/projects/ProjectsDisplayPage', () => ({
  ProjectsDisplayPage: ({ displayOnly }: { displayOnly?: boolean }) => (
    <h1>{displayOnly ? 'الشاشة التنفيذية' : 'عرض المشاريع الإداري'}</h1>
  ),
}));

function Location() {
  return <output aria-label="المسار">{useLocation().pathname}</output>;
}

describe('web surface for mobile and executive accounts', () => {
  it.each(['employee', 'manager', 'committee', 'field_operations'] as const)(
    'blocks a direct web link for the %s workspace',
    (workspace) => {
      auth.access = { ...mockContexts.admin, roles: [], permissions: [], workspaces: [workspace], defaultWorkspace: workspace };
      render(<MemoryRouter initialEntries={['/projects/display']}><App /></MemoryRouter>);
      expect(screen.getByRole('heading', { name: 'مساحة عملك على الموبايل' })).toBeInTheDocument();
      expect(screen.queryByRole('heading', { name: 'الشاشة التنفيذية' })).not.toBeInTheDocument();
    },
  );

  it('redirects executive accounts from admin URLs to the display', async () => {
    auth.access = { ...mockContexts.admin, roles: ['executive-director'], permissions: [], workspaces: ['executive'], defaultWorkspace: 'executive' };
    render(<MemoryRouter initialEntries={['/admin/hr/requests']}><App /><Location /></MemoryRouter>);

    expect(await screen.findByRole('heading', { name: 'الشاشة التنفيذية' })).toBeInTheDocument();
    expect(screen.getByLabelText('المسار')).toHaveTextContent('/projects/display');
  });
});
