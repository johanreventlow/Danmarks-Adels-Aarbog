import { expect, test, type Page } from '@playwright/test';
import { TABLE_FIXTURES } from './fixtures';

// Mocker ALLE Supabase PostgREST-kald på netværksniveau (task 11 — "genbrug eksisterende
// fixtures/mocks; opfind ikke ny seed-infrastruktur" er ikke muligt her, da repoet ikke
// havde en Playwright-opsætning forud for denne spec; se playwright.config.ts). PostgREST
// returnerer en ren JSON-array-krop ved success — supabase-js's getAll() afgør selv om der
// er flere sider ud fra array-længden (ikke Content-Range-headeren), så et enkelt 200-svar
// med den fulde fixture er nok.
async function mockSupabase(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const table = url.pathname.split('/rest/v1/')[1]?.split('?')[0] ?? '';
    const rows = TABLE_FIXTURES[table] ?? [];
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(rows) });
  });
}

test.beforeEach(async ({ page }) => {
  await mockSupabase(page);
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  (page as unknown as { __consoleErrors: string[] }).__consoleErrors = errors;
});

test('forsiden viser hero + feed-kort, og scroll udløser flere', async ({ page }) => {
  await page.goto('/');

  // Hero: søgefeltets placeholder-tekst fra HomeView.tsx.
  await expect(page.getByText('Find en person i slægten…')).toBeVisible({ timeout: 10_000 });

  // Feed-sektionen (fase1-design.md §7) — vent til mindst ét kort er rendret.
  const feedHeading = page.getByText('Feed', { exact: true });
  await expect(feedHeading).toBeVisible();

  // Siden scroller IKKE i window/body — Folgesvend.tsx's rodlayout er `height:100vh;
  // overflow:hidden`, med den faktiske scroll i en indre `[data-scroll]`-container (samme
  // container FeedStreamView.tsx's scroll-lytter er hægtet på). Almindelig page.mouse.wheel()
  // ville scrolle hvad end der ligger under markøren (typisk ingenting, da 0,0 rammer den
  // faste header) — scroll DENNE container direkte.
  const scrollContainer = page.locator('[data-scroll]');

  // Kortene har ingen fælles test-id endnu (fase 1-MVP) — tæl "Person N"-forekomster i
  // stedet. BEMÆRK: (a) "Person 1" optræder også i "Redaktionen foreslår" (curatedFounders,
  // synkron fra den allerede indlæste model), som bliver synlig FØR feed'et; (b) feed'ets
  // FØRSTE strøm bygges FØR bio/livsdato er hentet (§7.3) og indeholder derfor kun de
  // bio-uafhængige kort (gods/forbundet/vaaben/samle) — den er ofte allerede udtømt (samle-
  // kortet er terminalt), og portræt-/citat-/dagensperson-kortene kommer først til syne når
  // strømmen genopbygges (resumeStream) EFTER bios ankommer, doseret af NÆSTE scroll-udløste
  // append. Vi scroller derfor gentagne gange, mens vi poller — ikke kun én gang før tjek.
  const personCount = () => page.locator('text=/Person \\d/').count();
  await expect.poll(async () => {
    await scrollContainer.evaluate((el) => { el.scrollTop = el.scrollHeight; el.dispatchEvent(new Event('scroll')); });
    return personCount();
  }, { timeout: 15_000, intervals: [300] }).toBeGreaterThanOrEqual(5);

  // Footeren viser altid én af de to reelle tilstande — aldrig tom/udefineret.
  await expect(
    page.getByText('Henter flere blade fra slægten')
      .or(page.getByText('Du har mødt hele slægten i dag — udforsk registeret')),
  ).toBeVisible();

  const errors = (page as unknown as { __consoleErrors: string[] }).__consoleErrors;
  expect(errors, `Konsol-fejl under kørslen:\n${errors.join('\n')}`).toEqual([]);
});
