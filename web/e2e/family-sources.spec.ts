import { expect, test, type Page } from '@playwright/test';
import { COORDINATE_ROWS, TABLE_FIXTURES } from './fixtures';

// Ægteskabet på personsiden. Trin 5b 2a (spec §5.2) viste en kildelinje »Kilde: ‹udgave› · ‹post›« ved ægteskabet;
// projektejeren fjernede kildelinjerne i Familie 21/11 (9c1577a0 »Gift med«, c82dc67d forældre og børn) — kilden står
// kun i »Kilde i Aarbogen« nederst — og hentningen via public_family_sources blev fjernet (670ef2a2). Testen holder nu
// fast i det, der er tilbage: ægteskabet vises hos begge parter som link til den anden, uden kildelinje, og
// familiekilderne hentes ikke. Én hermetisk catch-all for ALLE PostgREST-kald (som feed.spec.ts), så intet kan nå
// nettet. Kontrakt 2: bio-versionen kommer fra v2-RPC'en og kun for person 1; familie 1 (partnerne 1 og 2 i
// TABLE_FIXTURES) er ægteskabet.
const REF = '0f8c2a3e-5b2a-4c1d-9e7f-2a5b00000001';
const GAMMEL_KILDELINJE = 'Kilde: DAA 2012-14 · Post 1';

async function mockSupabase(page: Page, familieKald: unknown[]): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1] ?? '';
    const svar = (body: unknown) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    if (sti === 'rpc/narrative_record_contract_version') return svar(2);
    // Bogens nummer giver »Kilde i Aarbogen« nederst — dér står kilden nu, ikke ved ægteskabet.
    if (sti === 'rpc/public_person_source_coordinates_samlet' || sti === 'rpc/public_person_source_coordinates') {
      return svar(COORDINATE_ROWS);
    }
    if (sti === 'rpc/public_person_bio_source_versions_v2') {
      const ids = (route.request().postDataJSON()?.p_person_ids ?? []) as unknown[];
      return svar(ids.map(String).includes('1') ? [{
        person_id: 1, source_id: 1, source_year: 2012, record_order: 1, source_record_ref: REF,
        source_label: 'DAA 2012-14', record_label: 'Post 1', narrative_text: 'Biografi fra posten.',
        citation_label: '', provenance_kind: 'source_record',
      }] : []);
    }
    // Svarer stadig med en ægteskabskilde, så en genindført kildelinje ville blive vist — og fanget nedenfor.
    if (sti === 'rpc/public_family_sources') {
      const body = route.request().postDataJSON();
      familieKald.push(body);
      const ids = ((body?.p_family_ids ?? []) as unknown[]).map(String);
      return svar(ids.includes('1') ? [{
        family_id: 1, slags: 'aegteskab', counterpart_person_id: 2, source_record_ref: REF,
        source_label: 'DAA 2012-14', record_label: 'Post 1', citation_label: '',
      }] : []);
    }
    if (sti.startsWith('rpc/')) return svar([]);
    return svar(TABLE_FIXTURES[sti.split('?')[0]] ?? []);
  });
}

test('ægteskabet vises hos begge parter uden kildelinje; familiekilderne hentes ikke', async ({ page }) => {
  const familieKald: unknown[] = [];
  await mockSupabase(page, familieKald);

  const aegtefaelle = (navn: string) => page.getByRole('definition').getByRole('link', { name: navn });
  const kilde = page.locator('footer').filter({ hasText: 'Kilde i Aarbogen' });

  await page.goto('/person/1');
  await expect(page.getByText('Biografi fra posten.')).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole('term').filter({ hasText: /^Gift med$/ })).toBeVisible();
  await expect(aegtefaelle('Person 2 af Testslægten')).toHaveAttribute('href', '/person/2');
  await expect(kilde).toContainText('Linje I, nr. 1');
  await expect(kilde.getByText('Ingen kildehenvisning registreret.')).toHaveCount(0);
  await expect(page.getByText(GAMMEL_KILDELINJE)).toHaveCount(0);
  await expect(page.getByRole('button', { name: GAMMEL_KILDELINJE })).toHaveCount(0);

  await page.goto('/person/2');
  await expect(page.getByRole('heading', { level: 1, name: 'Person 2 af Testslægten' })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole('term').filter({ hasText: /^Gift med$/ })).toBeVisible();
  await expect(aegtefaelle('Person 1 af Testslægten')).toHaveAttribute('href', '/person/1');
  await expect(kilde).toContainText('Linje I, nr. 2');
  await expect(page.getByText(GAMMEL_KILDELINJE)).toHaveCount(0);

  // Ingen af siderne henter familiekilderne længere (670ef2a2).
  expect(familieKald).toEqual([]);
});
