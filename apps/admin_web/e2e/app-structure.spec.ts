import { test, expect } from '@playwright/test';

/**
 * E2E: التنقل والهيكل العام للتطبيق
 */

test.describe('التنقل والهيكل', () => {
  test('الصفحة الرئيسية تحمل بدون أخطاء', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));

    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // لا أخطاء JavaScript
    expect(errors).toHaveLength(0);
  });

  test('الصفحة تستخدم RTL', async ({ page }) => {
    await page.goto('/');
    const dir = await page.locator('html').getAttribute('dir');
    expect(dir).toBe('rtl');
  });

  test('لا تسريبات أمنية في الـ HTML', async ({ page }) => {
    await page.goto('/');
    const html = await page.content();

    // لا أسرار
    expect(html).not.toMatch(/service_role/i);
    expect(html).not.toMatch(/eyJhbG/); // JWT prefix
    expect(html).not.toMatch(/sk_live_/); // Stripe
    expect(html).not.toMatch(/AKIA[A-Z0-9]{16}/); // AWS

    // لا PII في المصدر
    expect(html).not.toMatch(/password.*=.*["'][^"']+["']/i);
  });

  test('الأصول الثابتة تستجيب بشكل صحيح', async ({ page }) => {
    const response = await page.goto('/');
    expect(response?.status()).toBe(200);

    // Content-Type صحيح
    const contentType = response?.headers()['content-type'];
    expect(contentType).toContain('text/html');
  });

  test('SPA fallback يعمل — مسار غير موجود يعود للصفحة الرئيسية', async ({ page }) => {
    const response = await page.goto('/nonexistent-route-12345');
    // SPA: يجب أن يرد 200 ويحمل التطبيق (الذي يعالج الـ routing)
    expect(response?.status()).toBe(200);
  });
});
