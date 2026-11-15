import { expect, test, type Page } from '@playwright/test';
import { BIO_ROWS, COORDINATE_ROWS, TABLE_FIXTURES } from './fixtures';

// Mocker ALLE Supabase-kald på netværksniveau: tabeller fra TABLE_FIXTURES (ukendte → []),
// RPC'er fra RPC nedenfor. Biografier (personer 1-4) og bog-numre (alle) gør, at feedet kan
// vise både portrætter og »Nævnt i Aarbogen«-kort (personer uden tekst, titel eller børn).
const RPC: Record<string, unknown> = {
  narrative_record_contract_version: 2,
  public_person_bio_source_versions_v2: BIO_ROWS,
  public_person_source_coordinates: COORDINATE_ROWS,
  public_person_source_coordinates_samlet: COORDINATE_ROWS, // kodereview 36 P2: klientens ét-kalds-vej
};

async function mockSupabase(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1]?.split('?')[0] ?? '';
    const body = sti.startsWith('rpc/') ? (RPC[sti.slice(4)] ?? []) : (TABLE_FIXTURES[sti] ?? []);
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  });
}

test.beforeEach(async ({ page }) => {
  await mockSupabase(page);
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  (page as unknown as { __consoleErrors: string[] }).__consoleErrors = errors;
});

test('et blad tæller først som set, når det har været på skærmen', async ({ page }) => {
  // Lav skærm: feedet ligger under kanten, til læseren ruller.
  await page.setViewportSize({ width: 390, height: 500 });
  await page.goto('/');
  const foersteKort = page.locator('[data-kort-id]').first();
  await expect(foersteKort).toBeAttached({ timeout: 15_000 });
  await page.waitForTimeout(500);
  const set = () => page.evaluate(() => Object.keys(JSON.parse(localStorage.getItem('daa_feed_seen') ?? '{}')));
  expect(await set()).toEqual([]);

  await foersteKort.scrollIntoViewIfNeeded();
  const id = await foersteKort.getAttribute('data-kort-id');
  await expect.poll(set).toContain(id);
});

test('hovedsiden deler feedet ud seks blade ad gangen, med et nævnt-kort og kilde', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Slå op i Aarbogen' })).toBeVisible({ timeout: 10_000 });

  // Første uddeling: én blok med højst seks blade.
  const foersteBlok = page.getByRole('region', { name: /^Blade 1–\d$/ });
  await expect(foersteBlok).toBeVisible({ timeout: 15_000 });
  expect(await foersteBlok.getByRole('article').count()).toBeLessThanOrEqual(6);

  // Vend blade, til der ikke er flere. Ingen uendelig rulning: kun knappen deler ud.
  const knap = page.getByRole('button', { name: 'Vend seks blade mere' });
  for (let i = 0; i < 5 && await knap.isVisible(); i++) await knap.click();
  await expect(page.getByText(/Du har vendt alle dagens blade/)).toBeVisible();

  // Et nævnt-kort med bogens nummer som kilde — og intet om, at bogen ikke skriver mere.
  const naevnt = page.getByRole('article').filter({ hasText: 'Nævnt i Aarbogen' });
  await expect(naevnt.first()).toBeVisible();
  await expect(naevnt.first()).toContainText(/§ Linje I, nr\. \d/);

  const errors = (page as unknown as { __consoleErrors: string[] }).__consoleErrors;
  expect(errors, `Konsol-fejl under kørslen:\n${errors.join('\n')}`).toEqual([]);
});
