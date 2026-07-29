import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  applyTheme,
  getPreferredTheme,
  THEME_CHANGE_EVENT,
  THEME_STORAGE_KEY,
} from './theme';

describe('getPreferredTheme', () => {
  beforeEach(() => {
    delete document.documentElement.dataset.theme;
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('يعيد القيمة من data-theme إذا كانت موجودة', () => {
    document.documentElement.dataset.theme = 'dark';
    expect(getPreferredTheme()).toBe('dark');
  });

  it('يعيد القيمة من localStorage إذا لم يكن data-theme', () => {
    window.localStorage.setItem(THEME_STORAGE_KEY, 'dark');
    expect(getPreferredTheme()).toBe('dark');
  });

  it('يعيد light كقيمة افتراضية', () => {
    // jsdom matchMedia returns false by default
    expect(getPreferredTheme()).toBe('light');
  });

  it('يتجاهل القيم غير الصالحة في data-theme', () => {
    document.documentElement.dataset.theme = 'auto';
    expect(getPreferredTheme()).toBe('light');
  });

  it('يتجاهل القيم غير الصالحة في localStorage', () => {
    window.localStorage.setItem(THEME_STORAGE_KEY, 'blue');
    expect(getPreferredTheme()).toBe('light');
  });
});

describe('applyTheme', () => {
  beforeEach(() => {
    delete document.documentElement.dataset.theme;
    document.documentElement.style.colorScheme = '';
    window.localStorage.clear();
    // Ensure a meta theme-color element exists
    let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'theme-color';
      document.head.appendChild(meta);
    }
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('يضبط data-theme على العنصر الجذر', () => {
    applyTheme('dark');
    expect(document.documentElement.dataset.theme).toBe('dark');
  });

  it('يضبط colorScheme', () => {
    applyTheme('dark');
    expect(document.documentElement.style.colorScheme).toBe('dark');
  });

  it('يحفظ في localStorage عند persist=true', () => {
    applyTheme('dark', true);
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe('dark');
  });

  it('لا يحفظ في localStorage عند persist=false', () => {
    applyTheme('dark', false);
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBeNull();
  });

  it('يغيّر meta theme-color حسب الثيم', () => {
    applyTheme('dark');
    const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    expect(meta?.content).toBe('#060B16');

    applyTheme('light');
    expect(meta?.content).toBe('#0B4FA2');
  });

  it('يطلق حدث تغيير الثيم', () => {
    const handler = vi.fn();
    window.addEventListener(THEME_CHANGE_EVENT, handler);
    applyTheme('dark');
    expect(handler).toHaveBeenCalledOnce();
    window.removeEventListener(THEME_CHANGE_EVENT, handler);
  });

  it('يمرّر قيمة الثيم في detail الحدث', () => {
    let receivedDetail: string | undefined;
    const handler = (e: Event) => {
      receivedDetail = (e as CustomEvent).detail;
    };
    window.addEventListener(THEME_CHANGE_EVENT, handler);
    applyTheme('dark');
    expect(receivedDetail).toBe('dark');
    window.removeEventListener(THEME_CHANGE_EVENT, handler);
  });
});
