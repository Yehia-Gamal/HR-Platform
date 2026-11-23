import { backend, expect, test } from './fixtures';

const identifier = 'employee@example.test';

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
    await expect(page.getByText(/كلمة المرور لا تقل عن 6 أحرف/)).toBeVisible();
  });

  test('يظهر خطأ عند بيانات خاطئة ويتيح استعادة كلمة المرور', async ({ page }) => {
    await page.route(`${backend}/functions/v1/identifier-sign-in`, (route) => route.fulfill({ status: 401, json: { error: 'INVALID_CREDENTIALS' } }));
    const identifierInput = page.getByPlaceholder(/البريد|رقم الموظف|الهوية/i);
    await identifierInput.fill(identifier);

    const passwordInput = page.locator('input[type="password"]');
    await passwordInput.fill('WrongPassword123!');

    const loginButton = page.getByRole('button', { name: /دخول|تسجيل/i });
    const loginRequest = page.waitForRequest(`${backend}/functions/v1/identifier-sign-in`);
    await loginButton.click();

    // يجب أن يظهر رسالة خطأ (ليس تفاصيل تقنية)
    expect((await loginRequest).postDataJSON()).toMatchObject({ identifier });
    await expect(page.getByText('بيانات الدخول غير صحيحة أو الحساب غير متاح.').first()).toBeVisible();

    // التأكد من عدم تسريب معلومات تقنية
    const pageText = await page.textContent('body');
    expect(pageText).not.toContain('SQL');
    expect(pageText).not.toContain('pg_');
    expect(pageText).not.toContain('SQLSTATE');
    await page.getByRole('button', { name: 'نسيت كلمة المرور؟' }).click();
    await expect(page.getByRole('heading', { name: 'استعادة كلمة المرور' })).toBeVisible();

    const recoveryEndpoint = /^https:\/\/supabase\.e2e\.invalid\/auth\/v1\/recover\?/;
    await page.route(recoveryEndpoint, (route) => route.fulfill({ json: {} }));
    await page.getByRole('textbox', { name: 'البريد الإلكتروني' }).fill(identifier);
    const resetRequest = page.waitForRequest(recoveryEndpoint);
    await page.getByRole('button', { name: 'إرسال رابط الاستعادة' }).click();
    const request = await resetRequest;
    expect(request.postDataJSON()).toMatchObject({ email: identifier });
    expect(new URL(request.url()).searchParams.get('redirect_to')).toBe(`${new URL(page.url()).origin}/auth/setup-password`);
    await expect(page.getByText('تم إرسال الرابط')).toBeVisible();
  });
});
