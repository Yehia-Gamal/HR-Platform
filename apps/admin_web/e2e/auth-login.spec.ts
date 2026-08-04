import { test, expect } from '@playwright/test';

/**
 * E2E: مسار تسجيل الدخول — المسار الأكثر أهمية في التطبيق
 */

test.describe('تسجيل الدخول', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('يعرض صفحة تسجيل الدخول بشكل صحيح', async ({ page }) => {
    // يجب أن تكون الصفحة بالعربية RTL
    const html = page.locator('html');
    await expect(html).toHaveAttribute('dir', 'rtl');

    // يجب أن تحتوي على حقول الإدخال
    const identifierInput = page.getByPlaceholder(/البريد|رقم الموظف|الهوية/i);
    await expect(identifierInput).toBeVisible();

    const passwordInput = page.locator('input[type="password"]');
    await expect(passwordInput).toBeVisible();

    // زر تسجيل الدخول
    const loginButton = page.getByRole('button', { name: /دخول|تسجيل/i });
    await expect(loginButton).toBeVisible();
  });

  test('لا تتجاوز صفحة تسجيل الدخول عرض الشاشة', async ({ page }) => {
    const card = page.locator('.login-card');
    await expect(card).toBeVisible();

    const layout = await page.evaluate(() => {
      const loginCard = document.querySelector<HTMLElement>('.login-card');
      const bounds = loginCard?.getBoundingClientRect();

      return {
        viewportWidth: document.documentElement.clientWidth,
        pageWidth: document.documentElement.scrollWidth,
        cardLeft: bounds?.left ?? -1,
        cardRight: bounds?.right ?? Number.POSITIVE_INFINITY,
      };
    });

    expect(layout.pageWidth).toBeLessThanOrEqual(layout.viewportWidth);
    expect(layout.cardLeft).toBeGreaterThanOrEqual(0);
    expect(layout.cardRight).toBeLessThanOrEqual(layout.viewportWidth);
  });

  test('يظهر خطأ عند إرسال نموذج فارغ', async ({ page }) => {
    const loginButton = page.getByRole('button', { name: /دخول|تسجيل/i });
    await loginButton.click();

    // React Hook Form يعرض رسالتي التحقق تحت الحقلين ولا يرسل الطلب.
    await expect(page.getByText(/أدخل البريد أو الهاتف أو كود الموظف/)).toBeVisible();
    await expect(page.getByText(/كلمة المرور لا تقل عن 8 أحرف/)).toBeVisible();
  });

  test('يظهر خطأ عند بيانات خاطئة', async ({ page }) => {
    const identifierInput = page.getByPlaceholder(/البريد|رقم الموظف|الهوية/i);
    await identifierInput.fill('wrong@test.com');

    const passwordInput = page.locator('input[type="password"]');
    await passwordInput.fill('WrongPassword123!');

    const loginButton = page.getByRole('button', { name: /دخول|تسجيل/i });
    await loginButton.click();

    // يجب أن يظهر رسالة خطأ (ليس تفاصيل تقنية)
    const error = page.locator('[role="alert"], .text-red-500, .text-destructive');
    await expect(error.first()).toBeVisible({ timeout: 10000 });

    // التأكد من عدم تسريب معلومات تقنية
    const pageText = await page.textContent('body');
    expect(pageText).not.toContain('SQL');
    expect(pageText).not.toContain('pg_');
    expect(pageText).not.toContain('SQLSTATE');
  });

  test('رابط نسيت كلمة المرور يعمل', async ({ page }) => {
    const forgotLink = page.getByRole('link', { name: /نسيت|استعادة/i });
    if (await forgotLink.isVisible()) {
      await forgotLink.click();
      // يجب أن ينتقل لصفحة استعادة كلمة المرور أو يظهر نموذج
      await expect(page).toHaveURL(/reset|forgot|password/i, { timeout: 5000 });
    }
  });
});
