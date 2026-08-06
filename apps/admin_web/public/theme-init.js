(() => {
  try {
    const saved = localStorage.getItem('ahla-theme');
    const theme = saved === 'light' || saved === 'dark'
      ? saved
      : matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#060B16' : '#2563eb');
  } catch { /* The application bootstrap applies the default theme. */ }
})();
