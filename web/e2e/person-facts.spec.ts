import { expect, test, type Page } from '@playwright/test';
import { TABLE_FIXTURES } from './fixtures';

// 5c-2 + B11 (spec 2026-10-29 §4.3-4.4, §7): koordinater fra public_person_source_coordinates og fakta fra
// public_person_facts. Én hermetisk catch-all for ALLE PostgREST-kald (som family-sources.spec.ts), så intet når
// nettet. Person 1 har placement »15a«; person 3 har ingen prosa, men fakta.
type Opts = { factsStatus?: number };

async function mockSupabase(page: Page, kald: { coords: number; legacy: number; facts: unknown[] }, opts: Opts = {}): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1] ?? '';
    const svar = (body: unknown, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
    if (sti === 'rpc/narrative_record_contract_version') return svar(2);
    if (sti === 'person_source_coordinate_legacy') { kald.legacy++; return svar([]); }
    if (sti === 'rpc/public_person_source_coordinates') {
      kald.coords++;
      return svar([{
        person_id: 1, source_id: 1, legacy_line_code: 'I', printed_number: 15, printed_number_label: '15a',
        generation_local: 3, generation_global: 7, kuld_label: null, provenance_kind: 'placement',
      }]);
    }
    if (sti === 'rpc/public_person_facts') {
      const body = route.request().postDataJSON();
      kald.facts.push(body);
      if (opts.factsStatus) return svar({ message: 'fejl' }, opts.factsStatus);
      const ids = ((body?.p_person_ids ?? []) as unknown[]).map(String);
      return svar(ids.includes('3') ? [{
        person_id: 3, fact_id: 31, faktatype: 'død', conclusion_status: 'afklaret', assertion_id: 31, chosen: true,
        vaerdi_tekst: null, date_raw: '1780', date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
        source_id: 1, source_label: 'DAA 2012-14', side: null, record_ref: 'r3', record_label: 'II-3',
        citation_label: 'DAA 2012-14, s. 12',
      }] : []);
    }
    if (sti.startsWith('rpc/')) return svar([]);
    return svar(TABLE_FIXTURES[sti.split('?')[0]] ?? []);
  });
}

test('koordinater fra placement-RPC\'en med bogstavsuffiks; legacy-viewet kaldes aldrig', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald);
  await page.goto('/person/1');
  await expect(page.getByText('Linje I, nr. 15a')).toBeVisible({ timeout: 10_000 });
  expect(kald.coords).toBeGreaterThan(0);
  expect(kald.legacy).toBe(0);
});

test('person uden prosa viser fakta med bundet kilde', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald);
  await page.goto('/person/3');
  await expect(page.getByText('Fakta', { exact: true })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText('1780', { exact: true })).toBeVisible();
  await expect(page.getByText('bundet til bogens post')).toBeVisible();
  await expect(page.getByText('DAA 2012-14, s. 12 · II-3')).toBeVisible();
  const ids = (kald.facts[0] as { p_person_ids: unknown[] }).p_person_ids.map(String);
  expect(ids).toContain('3');
});

test('fejl fra fakta-RPC\'en giver »Fakta kunne ikke hentes«, resten af detaljen står', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald, { factsStatus: 500 });
  await page.goto('/person/3');
  await expect(page.getByText('Fakta kunne ikke hentes')).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText('Person 3', { exact: false }).first()).toBeVisible();
});
