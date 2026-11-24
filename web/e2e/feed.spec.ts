import { expect, test, type Page } from '@playwright/test';
import { PERSONS, TABLE_FIXTURES } from './fixtures';

// Mocker ALLE Supabase-kald på netværksniveau: tabeller fra TABLE_FIXTURES (ukendte → []), med feedets egne
// personer nedenfor, og RPC'er fra RPC nedenfor.
//
// Forsidens minimumskrav (spec docs/superpowers/specs/2026-11-24-forside-minimumskrav-design.md, projektejeren
// 24/11): et personkort kræver noget at fortælle (biografi på mindst 200 tegn, titel, embede, hændelse eller billede),
// »Nævnt i Aarbogen«-kortene er slået fra (19d8c0b5, krav 7), og kortene viser ikke bogens placering (§) (9f07cd70,
// #458). Feedets personer er derfor delt i tre:
//   1-9  titel + biografi → forsideværdige portrætter (ni blade + registeret = to uddelinger à højst seks),
//   10   biografi på 170 tegn uden titel → under minimumskravet, intet kort,
//   11-12 hverken tekst eller titel → intet kort, kun talt med i registeret.
// Egen personliste her, så fixtures.ts' PERSONS (1-8; person-facts bruger id 9 som alias) ikke vokser.
const LANG_BIO = (n: number) =>
  `Person ${n} blev født på slægtens gamle gods og voksede op midt i egnens landbrug og skovbrug. Senere i livet `
  + 'virkede personen som embedsmand ved hoffet og deltog i flere af tidens vigtige forhandlinger om riget.';
const KORT_BIO =
  'Hun overtog godset efter sin fars død og drev det gennem en urolig periode med krig og misvækst. Hendes indsats for slægtens økonomi huskes stadig i egnens lokalhistorie.';

const FEED_PERSONS = Array.from({ length: 12 }, (_, i) => ({
  ...PERSONS[0],
  id: i + 1,
  visning_navn: `Person ${i + 1}`,
  visning_fuldt_navn: `Person ${i + 1} af Testslægten`,
  visning_foedt: String(1700 + i * 10),
  visning_doed: String(1760 + i * 10),
  visning_titel: i < 9 ? 'greve' : '',
  koen: i % 2 === 0 ? 'mand' : 'kvinde',
}));
const MED_KORT = FEED_PERSONS.slice(0, 9).map((p) => p.visning_fuldt_navn);
const UDEN_KORT = FEED_PERSONS.slice(9).map((p) => p.visning_fuldt_navn);

const bioRaekke = (id: number, tekst: string) => ({
  person_id: id, source_id: 1, source_year: 2012, record_order: 1, source_record_ref: `e2e-rec-${id}`,
  source_label: 'DAA 2012-14', record_label: `Post ${id}`, citation_label: 'DAA 2012-14', provenance_kind: 'source_record',
  narrative_text: tekst,
});
const FEED_BIO_ROWS = [...FEED_PERSONS.slice(0, 9).map((p) => bioRaekke(p.id, LANG_BIO(p.id))), bioRaekke(10, KORT_BIO)];
const FEED_COORDINATE_ROWS = FEED_PERSONS.map((p) => ({
  person_id: p.id, source_id: 1, legacy_line_code: 'I', printed_number: p.id, printed_number_label: String(p.id),
  generation_local: null, generation_global: null, kuld_label: null, provenance_kind: 'placement',
}));

const RPC: Record<string, unknown> = {
  narrative_record_contract_version: 2,
  public_person_bio_source_versions_v2: FEED_BIO_ROWS,
  public_person_source_coordinates: FEED_COORDINATE_ROWS,
  public_person_source_coordinates_samlet: FEED_COORDINATE_ROWS, // kodereview 36 P2: klientens ét-kalds-vej
};
const TABELLER: Record<string, unknown[]> = { ...TABLE_FIXTURES, person: FEED_PERSONS, narrative: [] };

async function mockSupabase(page: Page): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1]?.split('?')[0] ?? '';
    const body = sti.startsWith('rpc/') ? (RPC[sti.slice(4)] ?? []) : (TABELLER[sti] ?? []);
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

test('hovedsiden deler feedet ud seks blade ad gangen, kun med forsideværdige personer', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Slå op i Aarbogen' })).toBeVisible({ timeout: 10_000 });

  // Første uddeling: præcis seks blade (ni portrætter + registeret giver mere end seks).
  const foersteBlok = page.getByRole('region', { name: 'Blade 1–6' });
  await expect(foersteBlok).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole('region', { name: /^Blade 7–/ })).toHaveCount(0);

  // Vend blade, til der ikke er flere. Ingen uendelig rulning: kun knappen deler ud, og den skal bruges mindst én gang.
  const knap = page.getByRole('button', { name: 'Vend seks blade mere' });
  await expect(knap).toBeVisible();
  for (let i = 0; i < 5 && await knap.isVisible(); i++) await knap.click();
  await expect(page.getByRole('region', { name: /^Blade 7–\d+$/ })).toBeVisible();
  await expect(page.getByText(/Du har vendt alle dagens blade/)).toBeVisible();
  await expect(knap).toHaveCount(0);

  // Hver forsideværdig person har præcis ét kort (krav 6), og ingen andre har et; rækkefølgen er tilfældig pr. besøg.
  const feed = page.getByRole('region', { name: 'Fra Aarbogen' });
  const profiler = feed.getByRole('link', { name: /^Åbn profil for / });
  await expect(profiler).toHaveCount(MED_KORT.length);
  const navne = (await profiler.evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? e.textContent ?? '')))
    .map((n) => n.replace(/^Åbn profil for /, ''));
  expect([...navne].sort()).toEqual([...MED_KORT].sort());
  for (const navn of UDEN_KORT) await expect(feed.getByRole('link', { name: `Åbn profil for ${navn}` })).toHaveCount(0);

  // De sparsomme personer samles i registeret i stedet for egne blade; ingen »Nævnt i Aarbogen« og ingen §-placering.
  await expect(feed.getByText(`…og ${UDEN_KORT.length} flere personer i registeret`)).toBeVisible();
  await expect(feed.getByText('Nævnt i Aarbogen')).toHaveCount(0);
  await expect(feed.getByText(/§/)).toHaveCount(0);

  const errors = (page as unknown as { __consoleErrors: string[] }).__consoleErrors;
  expect(errors, `Konsol-fejl under kørslen:\n${errors.join('\n')}`).toEqual([]);
});
