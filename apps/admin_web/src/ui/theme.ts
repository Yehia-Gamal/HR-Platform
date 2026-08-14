export type AppTheme = 'light' | 'dark';

export const THEME_STORAGE_KEY = 'ahla-theme';
export const THEME_CHANGE_EVENT = 'ahla-theme-change';

export function getPreferredTheme(): AppTheme {
  if (typeof document !== 'undefined') {
    const active = document.documentElement.dataset.theme;
    if (active === 'light' || active === 'dark') return active;
  }
  if (typeof window === 'undefined') return 'light';
  const saved = (() => {
    try {
      return window.localStorage.getItem(THEME_STORAGE_KEY);
    } catch {
      return null;
    }
  })();
  if (saved === 'light' || saved === 'dark') return saved;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function applyTheme(theme: AppTheme, persist = true) {
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#060B16' : '#0B4FA2');
  if (persist) {
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch {
      /* incognito mode */
    }
  }
  window.dispatchEvent(new CustomEvent<AppTheme>(THEME_CHANGE_EVENT, { detail: theme }));
}

export function initializeTheme() {
  applyTheme(getPreferredTheme(), false);
}
