import { Moon, Sun } from 'lucide-react';
import { useEffect, useState } from 'react';

type Theme = 'light' | 'dark';

function preferredTheme(): Theme {
  if (typeof window === 'undefined') return 'light';
  const saved = window.localStorage.getItem('ahla-theme');
  if (saved === 'light' || saved === 'dark') return saved;
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>(preferredTheme);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    window.localStorage.setItem('ahla-theme', theme);
  }, [theme]);

  const next = theme === 'light' ? 'dark' : 'light';
  return (
    <button
      type="button"
      className="icon-button"
      aria-label={theme === 'light' ? 'تفعيل الوضع الداكن' : 'تفعيل الوضع الفاتح'}
      title={theme === 'light' ? 'الوضع الداكن' : 'الوضع الفاتح'}
      onClick={() => setTheme(next)}
    >
      {theme === 'light' ? <Moon className="size-4.5" /> : <Sun className="size-4.5" />}
    </button>
  );
}
