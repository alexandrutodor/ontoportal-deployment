import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.UI_BASE_URL || 'http://127.0.0.1:3000';
const disableSensitiveArtifacts = Boolean(process.env.OP_APIKEY || process.env.PLAYWRIGHT_DISABLE_SENSITIVE_ARTIFACTS);
const webServer = process.env.PLAYWRIGHT_WEB_SERVER_COMMAND
  ? {
      command: process.env.PLAYWRIGHT_WEB_SERVER_COMMAND,
      url: process.env.PLAYWRIGHT_WEB_SERVER_URL || baseURL,
      reuseExistingServer: !process.env.CI,
      timeout: Number(process.env.PLAYWRIGHT_WEB_SERVER_TIMEOUT || 120_000),
      stdout: 'pipe',
      stderr: 'pipe',
    }
  : undefined;

export default defineConfig({
  testDir: './tests/ui',
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    actionTimeout: 10_000,
    navigationTimeout: 30_000,
    trace: disableSensitiveArtifacts ? 'off' : 'retain-on-failure',
    screenshot: disableSensitiveArtifacts ? 'off' : 'only-on-failure',
    video: disableSensitiveArtifacts ? 'off' : 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer,
});
