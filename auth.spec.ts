import { test, expect } from '@playwright/test';

test.describe('Auth and Dashboard', () => {
  test('should register, login and access dashboard', async ({ page }) => {
    // 1. Go to app
    await page.goto('/');
    await page.waitForTimeout(2000); // Wait for CSS to load
    await page.screenshot({ path: 'screenshot-1-login.png' });

    // 2. Switch to Register
    const toggleBtn = page.getByTestId('toggle-btn');
    await expect(toggleBtn).toBeVisible();
    await toggleBtn.click();
    await expect(page.getByTestId('auth-title')).toHaveText('Create a new account');
    await page.screenshot({ path: 'screenshot-2-register.png' });

    // 3. Fill registration form
    const uniqueEmail = `test${Date.now()}@example.com`;
    await page.getByTestId('input-name').fill('Test User');
    await page.getByTestId('input-email').fill(uniqueEmail);
    await page.getByTestId('input-password').fill('password123');
    
    // Intercept alert for registration
    page.once('dialog', dialog => {
      expect(dialog.message()).toContain('Registered');
      dialog.accept();
    });

    await page.getByTestId('submit-btn').click();

    // 4. Should switch to login
    await expect(page.getByTestId('auth-title')).toHaveText('Sign in to your account');

    // 5. Fill login form
    await page.getByTestId('input-email').fill(uniqueEmail);
    await page.getByTestId('input-password').fill('password123');
    await page.getByTestId('submit-btn').click();
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'screenshot-3-dashboard.png' });

    // 6. Should navigate to dashboard
    await expect(page.getByTestId('dashboard-title')).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId('dashboard-title')).toHaveText('Dashboard - AI Copywriter');

    // 7. Test Logout
    await page.getByTestId('logout-btn').click();
    await expect(page.getByTestId('auth-title')).toHaveText('Sign in to your account');
  });
});
