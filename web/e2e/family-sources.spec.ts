import { expect, test, type Page } from '@playwright/test';
import { TABLE_FIXTURES } from './fixtures';

// Trin 5b 2a (spec §5.2, §7.5): kildelinjen ved ægteskabet i detaljepanelet. Én hermetisk catch-all for
// ALLE PostgREST-kald (som feed.spec.ts), så intet kan nå nettet. Kontrakt 2: bio-versionen kommer fra
// v2-RPC'en og kun for person 1; familie 1 (partnerne 1 og 2 i TABLE_FIXTURES) har én ægteskabskilde.
const REF = '0f8c2a3e-5b2a-4c1d-9e7f-2a5b00000001';

async function mockSupabase(page: Page, familieKald: unknown[]): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1] ?? '';
    const svar = (body: unknown) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    if (sti === 'rpc/narrative_record_contract_version') return svar(2);
    if (sti === 'rpc/public_person_bio_source_versions_v2') {
      const ids = (route.request().postDataJSON()?.p_person_ids ?? []) as unknown[];
      return svar(ids.map(String).includes('1') ? [{
        person_id: 1, source_id: 1, source_year: 2012, record_order: 1, source_record_ref: REF,
        source_label: 'DAA 2012-14', record_label: 'Post 1', narrative_text: 'Biografi fra posten.',
        citation_label: '', provenance_kind: 'source_record',
      }] : []);
    }
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

test('kildelinjen vises ved ægteskabet: knap hos hovedpersonen, tekst hos ægtefællen', async ({ page }) => {
  const familieKald: unknown[] = [];
  await mockSupabase(page, familieKald);

  await page.goto('/person/1');
  await expect(page.getByRole('button', { name: 'Kilde: DAA 2012-14 · Post 1' })).toBeVisible({ timeout: 10_000 });

  await page.goto('/person/2');
  await expect(page.getByText('Kilde: DAA 2012-14 · Post 1')).toBeVisible({ timeout: 10_000 });
  await expect(page.getByRole('button', { name: 'Kilde: DAA 2012-14 · Post 1' })).toHaveCount(0);

  // Decimalstrengkravet over netværksgrænsen: id'erne sendes som strenge.
  expect(familieKald.length).toBeGreaterThan(0);
  for (const kald of familieKald) {
    const ids = (kald as { p_family_ids: unknown[] }).p_family_ids;
    expect(ids.every((id) => typeof id === 'string')).toBe(true);
  }
});
