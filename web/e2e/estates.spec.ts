import { expect, test, type Page } from '@playwright/test';
import { TABLE_FIXTURES } from './fixtures';

// #471: sammenlagte godser skjules og omdirigeres; art og »hører under« vises. Mocker Supabase på netværksniveau;
// gods→gods-relationerne (sammenlagt_i, hører_under) udskilles på forespørgslens subjekt_type=eq.estate.
const ESTATES = [
  { id: 5, navn: 'Christianssæde', slags: 'grevskab', sted_id: null },
  { id: 7, navn: 'Bukkehave', slags: 'gård', sted_id: null },
  { id: 405, navn: 'Christianssæde (gammel række)', slags: 'gård', sted_id: null },
];
const GODS_RELS = [
  { subjekt_id: 405, objekt_id: 5, rolle: 'sammenlagt_i', periode_raw: null },
  { subjekt_id: 7, objekt_id: 5, rolle: 'hører_under', periode_raw: '(1700-1800)' },
];

async function mockSupabase(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1]?.split('?')[0] ?? '';
    let body: unknown;
    if (sti === 'estate') body = ESTATES;
    else if (sti === 'relation') body = url.searchParams.get('subjekt_type') === 'eq.estate' ? GODS_RELS : [];
    else if (sti.startsWith('rpc/')) body = sti === 'rpc/narrative_record_contract_version' ? 2 : [];
    else body = TABLE_FIXTURES[sti] ?? [];
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  });
}

test.beforeEach(async ({ page }) => { await mockSupabase(page); });

test('sammenlagt gods: skjult i listen, link omdirigeres, art og »hører under« vises', async ({ page }) => {
  await page.goto('/slaegt/reventlow/besiddelser');
  await expect(page.getByText('Bukkehave')).toBeVisible({ timeout: 15_000 });
  await expect(page.getByText('Christianssæde (gammel række)')).toHaveCount(0);
  await expect(page.getByText('Grevskab')).toBeVisible();

  // Det sammenlagtes gamle link ender på det overlevende gods.
  await page.goto('/besiddelse/405');
  await expect(page).toHaveURL(/\/besiddelse\/5$/, { timeout: 15_000 });
  await expect(page.getByRole('heading', { name: 'Christianssæde' })).toBeVisible();
  await expect(page.getByText(/Omfattede:/)).toContainText('Bukkehave');

  await page.goto('/besiddelse/7');
  await expect(page.getByText(/Hørte under/)).toHaveText('Hørte under Christianssæde (1700-1800)', { timeout: 15_000 });
});
