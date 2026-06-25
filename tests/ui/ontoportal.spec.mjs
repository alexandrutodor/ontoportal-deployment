import { expect, test } from '@playwright/test';

const serverErrorText = /exception|stack trace|traceback|internal server error|application error|rack error|rails root/i;

async function expectNoServerError(page) {
  const bodyText = await page.locator('body').innerText({ timeout: 10_000 });
  expect(bodyText).not.toMatch(serverErrorText);
}

test('public home page renders useful content', async ({ page }) => {
  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(response, 'home page should return a response').not.toBeNull();
  expect(response.ok(), `home page failed with status ${response.status()}`).toBeTruthy();
  await expect(page.locator('body')).toBeVisible();
  await expect(page.locator('body')).not.toHaveText(/^\s*$/);
  await expectNoServerError(page);
});

test('login route is reachable and keyboard focus can move', async ({ page }) => {
  const response = await page.goto('/login', { waitUntil: 'domcontentloaded' });
  expect(response, 'login page should return a response').not.toBeNull();
  expect(response.ok(), `login page failed with status ${response.status()}`).toBeTruthy();
  await expect(page.locator('body')).toBeVisible();
  await expect(page.locator('form, input, button, a[href]').first()).toBeVisible();
  await page.keyboard.press('Tab');
  const focusedTag = await page.evaluate(() => document.activeElement?.tagName || '');
  expect(focusedTag, 'keyboard tab should land on an interactive element').not.toBe('BODY');
  await expectNoServerError(page);
});

test('critical same-origin assets do not fail on the home page', async ({ page }) => {
  const failedAssets = [];
  const baseOrigin = new URL(process.env.UI_BASE_URL || 'http://127.0.0.1:3000').origin;
  page.on('response', (response) => {
    const request = response.request();
    const type = request.resourceType();
    const url = new URL(response.url());
    if (url.origin !== baseOrigin) return;
    if (!['document', 'script', 'stylesheet', 'image', 'font'].includes(type)) return;
    if (response.status() >= 400) failedAssets.push(`${response.status()} ${type} ${url.pathname}`);
  });

  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => undefined);
  expect(failedAssets).toEqual([]);
});

test('public API endpoint does not return a server error when configured', async ({ request }) => {
  const apiBase = process.env.API_BASE_URL;
  test.skip(!apiBase, 'API_BASE_URL is not set');
  const response = await request.get(apiBase);
  expect(response.ok(), `API endpoint failed with status ${response.status()}`).toBeTruthy();
});
