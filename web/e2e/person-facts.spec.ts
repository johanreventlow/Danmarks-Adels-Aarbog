import { expect, test, type Page } from '@playwright/test';
import { PERSONS, SOURCES, TABLE_FIXTURES } from './fixtures';

// 5c-2 + B11 (spec 2026-10-29 §4.3-4.4, §7): koordinater fra public_person_source_coordinates og fakta fra
// public_person_facts. Én hermetisk catch-all for ALLE PostgREST-kald (som family-sources.spec.ts), så intet når
// nettet. Person 1 har placement »15a«; person 3 har ingen prosa, men fakta.
// 6e-1 (spec 2026-11-12 §5.2-5.5): `toUdgaver` giver person 4 en 1939-række (person 9, kilde 3) med fakta og
// biografi, så detaljen viser den valgte udgave forrest og den anden som note. Person 9 foldes ind i 4 ad den
// rigtige vej (final review C8): en afklaret samme_som-kant (subjekt = alias 9, objekt = kanonisk 4), og RPC'erne
// svarer kun for de id'er, detaljen faktisk sender.
type Opts = { factsStatus?: number; toUdgaver?: boolean };

const RECORD_1939 = 'record-07565168-b903-4444-9189-43d62d5c6ed6';
const faktum = (o: Record<string, unknown>) => ({
  conclusion_status: 'afklaret', chosen: true, vaerdi_tekst: null, date_raw: null, date_min: null, date_max: null,
  date_qualifier: null, date_certainty: null, side: null, ...o,
});
const fra2012 = { source_id: 1, source_label: 'DAA 2012-14', record_ref: 'r4', record_label: 'II-4', citation_label: 'DAA 2012-14, s. 40' };
const fra1939 = { source_id: 3, source_label: 'DAA 1939', record_ref: 'r9', record_label: RECORD_1939, citation_label: 'DAA 1939, s. 541' };
const TO_UDGAVER_FAKTA = [
  faktum({ person_id: 4, fact_id: 41, assertion_id: 41, faktatype: 'fødsel', date_raw: '1. maj 1730', ...fra2012 }),
  faktum({ person_id: 9, fact_id: 91, assertion_id: 91, faktatype: 'fødsel', date_raw: '1 Maj 1730', ...fra1939 }),
  faktum({ person_id: 9, fact_id: 92, assertion_id: 92, faktatype: 'død', date_raw: '1790', ...fra1939 }),
];
const bio = (personId: number, sourceId: number, aar: number, label: string, ref: string, recordLabel: string, tekst: string) => ({
  person_id: personId, source_id: sourceId, source_year: aar, record_order: 1, source_record_ref: ref, source_label: label,
  record_label: recordLabel, narrative_text: tekst, citation_label: '', provenance_kind: 'source_record',
});
// Alias-rækken fra 1939: samme levetid som person 4, så foldningen ikke karantæneres.
const PERSON_9 = { ...PERSONS[3], id: 9, visning_navn: 'Person 9', visning_fuldt_navn: 'Person 9 af Testslægten' };
const SAMME_SOM = { id: 900, subjekt_id: 9, objekt_id: 4 };
const TO_UDGAVER_BIO = [
  bio(4, 1, 2012, 'DAA 2012-14', 'r4', 'II-4', 'Biografi fra 2012-14-udgaven.'),
  bio(9, 3, 1939, 'DAA 1939', 'r9', RECORD_1939, 'Biografi fra 1939-udgaven.'),
];

async function mockSupabase(page: Page, kald: { coords: number; legacy: number; facts: unknown[] }, opts: Opts = {}): Promise<void> {
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const sti = url.pathname.split('/rest/v1/')[1] ?? '';
    const svar = (body: unknown, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
    if (sti === 'rpc/narrative_record_contract_version') return svar(2);
    if (sti === 'person_source_coordinate_legacy') { kald.legacy++; return svar([]); }
    if (sti === 'rpc/public_person_source_coordinates') {
      kald.coords++;
      const koord = (person_id: number, source_id: number, legacy_line_code: string, printed_number: number, printed_number_label: string) => ({
        person_id, source_id, legacy_line_code, printed_number, printed_number_label,
        generation_local: 3, generation_global: 7, kuld_label: null, provenance_kind: 'placement',
      });
      return svar([koord(1, 1, 'I', 15, '15a'), ...(opts.toUdgaver ? [koord(4, 1, 'II', 4, '4'), koord(9, 3, 'II', 3, '3')] : [])]);
    }
    if (sti === 'rpc/public_person_facts') {
      const body = route.request().postDataJSON();
      kald.facts.push(body);
      if (opts.factsStatus) return svar({ message: 'fejl' }, opts.factsStatus);
      const ids = ((body?.p_person_ids ?? []) as unknown[]).map(String);
      // som RPC'en: kun rækker for de efterspurgte id'er (medlemskontrakten afgør, hvilke id'er detaljen sender)
      if (opts.toUdgaver && ids.some((i) => i === '4' || i === '9')) {
        return svar(TO_UDGAVER_FAKTA.filter((r) => ids.includes(String(r.person_id))));
      }
      return svar(ids.includes('3') ? [{
        person_id: 3, fact_id: 31, faktatype: 'død', conclusion_status: 'afklaret', assertion_id: 31, chosen: true,
        vaerdi_tekst: null, date_raw: '1780', date_min: null, date_max: null, date_qualifier: null, date_certainty: null,
        source_id: 1, source_label: 'DAA 2012-14', side: null, record_ref: 'r3', record_label: 'II-3',
        citation_label: 'DAA 2012-14, s. 12',
      }] : []);
    }
    if (sti === 'rpc/public_person_bio_source_versions_v2' && opts.toUdgaver) {
      const ids = ((route.request().postDataJSON()?.p_person_ids ?? []) as unknown[]).map(String);
      return svar(TO_UDGAVER_BIO.filter((b) => ids.includes(String(b.person_id))));
    }
    if (sti.startsWith('rpc/')) return svar([]);
    if (opts.toUdgaver && sti === 'person') return svar([...PERSONS, PERSON_9]);
    if (opts.toUdgaver && sti === 'relation' && url.searchParams.get('rolle') === 'eq.samme_som') return svar([SAMME_SOM]);
    if (opts.toUdgaver && sti === 'conclusion' && url.searchParams.get('target_type') === 'eq.relation'
      && url.searchParams.get('status') === 'eq.afklaret') return svar([{ target_id: SAMME_SOM.id }]);
    if (sti === 'source' && opts.toUdgaver) {
      return svar([...SOURCES, { id: 3, slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog', udgave: 'DAA 1939', aar: 1939, ekstern: null }]);
    }
    return svar(TABLE_FIXTURES[sti.split('?')[0]] ?? []);
  });
}

test('koordinater fra placement-RPC\'en med bogstavsuffiks; legacy-viewet kaldes aldrig', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald);
  // Koordinaterne bruges af livsrejse-kortet i stamtræets panel (personsiden har intet kort).
  await page.goto('/slaegt/reventlow/stamtrae?fokus=1');
  await expect(page.getByText('Linje I, nr. 15a').first()).toBeVisible({ timeout: 10_000 });
  expect(kald.coords).toBeGreaterThan(0);
  expect(kald.legacy).toBe(0);
});

test('person uden prosa viser fakta med bundet kilde', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald);
  await page.goto('/person/3');
  await expect(page.getByText('Fakta', { exact: true })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByText('1780', { exact: true })).toBeVisible();
  await expect(page.getByText('DAA 2012-14, s. 12 · II-3')).toBeVisible();
  await expect(page.getByText('bundet til bogens post')).toHaveCount(0);
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

test('to udgaver: den valgte forrest, den anden som note; ingen tekniske postnøgler i siden', async ({ page }) => {
  const kald = { coords: 0, legacy: 0, facts: [] as unknown[] };
  await mockSupabase(page, kald, { toUdgaver: true });
  await page.goto('/person/4');
  await expect(page.getByText('✓ også i DAA 1939')).toBeVisible({ timeout: 10_000 });
  // detaljen beder om begge medlems-id'er (medlemskontrakten), ikke kun det kanoniske
  const sendt = (kald.facts as { p_person_ids: unknown[] }[]).map((b) => b.p_person_ids.map(String).sort());
  expect(sendt).toContainEqual(['4', '9']);
  await expect(page.getByText('Biografi fra 2012-14-udgaven.')).toBeVisible();
  await expect(page.getByText('1. maj 1730', { exact: true })).toBeVisible();
  await expect(page.getByText('Kun i DAA 1939')).toBeVisible();
  await expect(page.getByText('Død: 1790')).toBeVisible();
  expect(await page.content()).not.toMatch(/record-[0-9a-f]{8}-|legacy-source:/);

  await page.getByRole('button', { name: 'DAA 1939', exact: true }).click();
  await expect(page.getByText('Biografi fra 1939-udgaven.')).toBeVisible();
  await expect(page.getByText('1 Maj 1730', { exact: true })).toBeVisible();
  await expect(page.getByText('✓ også i DAA 2012-14')).toBeVisible();
  await expect(page.getByText('Tidligere udgave')).toBeVisible();
  await expect(page.getByText('DAA 1939, s. 541', { exact: true }).first()).toBeVisible();
  expect(await page.content()).not.toMatch(/record-[0-9a-f]{8}-|legacy-source:/);
});
