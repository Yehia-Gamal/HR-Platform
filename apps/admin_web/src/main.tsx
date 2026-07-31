import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { App } from './app/App';
import { initSentry, initWebVitals, attachQueryObservability } from './core/sentry';
import { AuthProvider } from './features/auth/AuthProvider';
import { AppErrorBoundary } from './ui/AppErrorBoundary';
import { ToastProvider } from './ui/Toast';
import { initializeTheme } from './ui/theme';
import './styles.css';

initSentry();
initializeTheme();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 1 },
    mutations: { retry: 0 },
  },
});

// Attach observability after queryClient creation (cast for internal API access)
attachQueryObservability(queryClient as unknown as Parameters<typeof attachQueryObservability>[0]);
void initWebVitals();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AppErrorBoundary>
        <ToastProvider>
          <BrowserRouter>
            <AuthProvider>
              <App />
            </AuthProvider>
          </BrowserRouter>
        </ToastProvider>
      </AppErrorBoundary>
    </QueryClientProvider>
  </StrictMode>,
);
