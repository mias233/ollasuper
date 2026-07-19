import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  // Serial so account creation in test 01 is visible to tests 02-09.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    // Hotwire dashboard is server-rendered by Loco at :5150. No separate
    // frontend dev server now (rsbuild + React were retired in Phase 6).
    baseURL: process.env.QWRITER_APP ?? 'http://localhost:5150',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
