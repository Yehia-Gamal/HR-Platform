import { Moon, Sun } from 'lucide-react';
import { useEffect, useState } from 'react';
import { applyTheme, getPreferredTheme, THEME_CHANGE_EVENT, type AppTheme } from './theme';

export function ThemeToggle() {
  const [theme, setTheme] = useState<AppTheme>(getPreferredTheme);

  useEffect(() => {
    const syncTheme = (event: Event) => setTheme((event as CustomEvent<AppTheme>).detail);
    window.addEventListener(THEME_CHANGE_EVENT, syncTheme);
    return () => window.removeEventListener(THEME_CHANGE_EVENT, syncTheme);
  }, []);

  const next = theme === 'light' ? 'dark' : 'light';
  return (
    <button
      type="button"
      className="icon-button"
      aria-label={theme === 'light' ? 'تفعيل الوضع الداكن' : 'تفعيل الوضع الفاتح'}
      title={theme === 'light' ? 'الوضع الداكن' : 'الوضع الفاتح'}
      onClick={() => applyTheme(next)}
    >
      {theme === 'light' ? <Moon className="size-4.5" /> : <Sun className="size-4.5" />}
    </button>
  );
}
