import { expect, test } from '@playwright/test';

const acronym = process.env.TEST_ONTOLOGY_ACRONYM;
const term = process.env.TEST_ONTOLOGY_TERM;
const annotatorText = process.env.TEST_ANNOTATOR_TEXT;

const isRequired = ['1', 'true', 'TRUE', 'yes', 'YES', 'on', 'ON'].includes(process.env.SMOKE_REQUIRE_ONTOLOGY || '');

function apiUrl(path, params = {}) {
  const base = process.env.API_BASE_URL;
  if (!base) return null;
  const url = new URL(path, base);
  for (const [key, value] of Object.entries(params)) {
    if (value) url.searchParams.set(key, value);
  }
  return url.toString();
}

function apiHeaders() {
  return {
    Accept: 'application/json',
    ...(process.env.OP_APIKEY ? { Authorization: `apikey token=${process.env.OP_APIKEY}` } : {}),
  };
}

async function expectNonEmptyCollection(response) {
  expect(response.status(), 'API request must not be a server error').toBeLessThan(500);
  expect(response.ok(), await response.text()).toBeTruthy();
  const body = await response.json();
  expect(body.errors?.length || body.error ? 1 : 0, 'API response must not contain errors').toBe(0);
  const collection = Array.isArray(body) ? body : body.collection ?? body.annotations ?? (body.annotatedClass ? [body] : []);
  expect(collection.length, 'API response collection should not be empty').toBeGreaterThan(0);
}

test('loaded ontology is visible in UI', async ({ page }) => {
  if (isRequired) {
    expect(acronym, 'TEST_ONTOLOGY_ACRONYM is required').toBeTruthy();
  } else {
    test.skip(!acronym, 'TEST_ONTOLOGY_ACRONYM is not set');
  }
  const response = await page.goto(`/ontologies/${acronym}`, { waitUntil: 'domcontentloaded' });
  expect(response, 'ontology page should return a response').not.toBeNull();
  expect(response.ok(), `ontology page failed with status ${response.status()}`).toBeTruthy();
  await expect(page.locator('body')).toContainText(new RegExp(acronym, 'i'));
});

test('loaded ontology term is searchable in UI', async ({ page }) => {
  if (isRequired) {
    expect(term, 'TEST_ONTOLOGY_TERM is required').toBeTruthy();
  } else {
    test.skip(!term, 'TEST_ONTOLOGY_TERM is not set');
  }
  const response = await page.goto(`/search?q=${encodeURIComponent(term)}`, { waitUntil: 'domcontentloaded' });
  expect(response, 'search page should return a response').not.toBeNull();
  expect(response.ok(), `search page failed with status ${response.status()}`).toBeTruthy();
  await expect(page.locator('body')).toContainText(new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
});

test('loaded ontology term is searchable via API', async ({ request }) => {
  if (isRequired) {
    expect(process.env.API_BASE_URL, 'API_BASE_URL is required').toBeTruthy();
    expect(term, 'TEST_ONTOLOGY_TERM is required').toBeTruthy();
  } else {
    test.skip(!process.env.API_BASE_URL || !term, 'API_BASE_URL and TEST_ONTOLOGY_TERM are required');
  }
  const url = apiUrl('/search', { q: term, ontologies: acronym });
  await expectNonEmptyCollection(await request.get(url, { headers: apiHeaders() }));
});

test('loaded ontology term is annotatable via API', async ({ request }) => {
  if (isRequired) {
    expect(process.env.API_BASE_URL, 'API_BASE_URL is required').toBeTruthy();
    expect(annotatorText, 'TEST_ANNOTATOR_TEXT is required').toBeTruthy();
  } else {
    test.skip(!process.env.API_BASE_URL || !annotatorText, 'API_BASE_URL and TEST_ANNOTATOR_TEXT are required');
  }
  const url = apiUrl('/annotator', { text: annotatorText, ontologies: acronym, format: 'json' });
  await expectNonEmptyCollection(await request.get(url, { headers: apiHeaders() }));
});
