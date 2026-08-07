// Integrationstest for loadMediaItems' medie-fakta-berigelse (medie-metadata Task 6,
// fix-runde 1/5 — Important-fund fra review af commit 9dbf410). loadMediaItems er den fælles,
// IKKE-eksporterede hale for BÅDE fetchPersonMedia og fetchObjectMedia (jf. media.ts:96) — kun de
// rene byggesten (mediaFaktaFelter, joinMediaFakta) var enhedstestet før denne fil; selve
// Promise.all-wiringen af fetchMediaFakta(mediaIds) og faktaByMediaId.get(String(r.id))-opslaget
// var IKKE exercised. Spejler feedMedia.test.ts's fulde tabel-mockede supabase-konvention, som
// allerede har den tilsvarende test for feed-sporet ("beriger kandidaterne med altTekst fra
// fetchMediaFakta").
//
// Testes via fetchObjectMedia (simplere end fetchPersonMedia — ingen samme_som-fold/dedup — men
// løber gennem PRÆCIS samme fetchMediaByRelation → loadMediaItems-hale). To medier i ÉT kald
// beviser at id-opslaget rammer det RIGTIGE medie hver gang, ikke bare det første.
import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;

let byTable: Record<string, FakeRow[]> = {};

vi.mock('../../supabase', () => ({
  supabase: {
    storage: {
      from: vi.fn(() => ({
        createSignedUrls: vi.fn(async (paths: string[]) => ({
          data: paths.map((p) => ({ path: p, signedUrl: `signed:${p}` })),
          error: null,
        })),
      })),
    },
    auth: { onAuthStateChange: vi.fn() },
    from(table: string) {
      const rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq: () => builder,
        in: () => builder,
        order: () => builder,
        range: async (from: number, to: number) => ({ data: rows.slice(from, to + 1), error: null }),
        then(resolve: (value: { data: FakeRow[]; error: null }) => void) {
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
      };
      return builder;
    },
  },
}));

import { fetchObjectMedia } from '../media';

beforeEach(() => {
  byTable = {
    // To coat_of_arms-medier (501/502) knyttet til samme anker (77) — 'afbildet' fra media-siden
    // (mediaSide='subjekt' for objekt-medier), jf. fetchMediaByRelation's retningskonvention.
    relation: [
      { subjekt_id: 501, objekt_id: 77, kvalifikator: null },
      { subjekt_id: 502, objekt_id: 77, kvalifikator: null },
    ],
    media: [
      { id: 501, slags: 'maleri', titel: 'Portræt A', kunstner: 'K1', datering: '1800', storage_path: 'large/501.jpg' },
      { id: 502, slags: 'foto', titel: 'Portræt B', kunstner: 'K2', datering: '1810', storage_path: 'large/502.jpg' },
    ],
    media_variant: [], // ingen thumb-varianter — thumbUrl falder tilbage til den fulde url
    fact: [
      { id: 10, subjekt_id: 501, faktatype: 'alt_tekst' },
      { id: 11, subjekt_id: 501, faktatype: 'kreditlinje' },
      { id: 12, subjekt_id: 501, faktatype: 'kilde_url' },
      { id: 13, subjekt_id: 501, faktatype: 'datering' },
      { id: 20, subjekt_id: 502, faktatype: 'alt_tekst' },
      { id: 21, subjekt_id: 502, faktatype: 'kreditlinje' },
      { id: 22, subjekt_id: 502, faktatype: 'kilde_url' },
      { id: 23, subjekt_id: 502, faktatype: 'datering' },
    ],
    assertion: [
      { id: 100, target_id: 10, vaerdi_tekst: 'Alt for 501', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      { id: 101, target_id: 11, vaerdi_tekst: 'Kredit for 501', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      { id: 102, target_id: 12, vaerdi_tekst: 'https://example.org/501', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      { id: 103, target_id: 13, vaerdi_tekst: '1850', date_min: '1845-01-01', date_max: '1855-12-31', date_qualifier: 'about', date_raw: 'ca. 1850' },
      { id: 200, target_id: 20, vaerdi_tekst: 'Alt for 502', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      { id: 201, target_id: 21, vaerdi_tekst: 'Kredit for 502', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      { id: 202, target_id: 22, vaerdi_tekst: 'https://example.org/502', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
      // 502's datering-assertion har INGEN date_raw — dateringFakt skal falde tilbage til vaerdi ('1900').
      { id: 203, target_id: 23, vaerdi_tekst: '1900', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
    ],
    conclusion: [
      { target_id: 10, valgt_assertion_id: 100, status: 'afklaret' },
      { target_id: 11, valgt_assertion_id: 101, status: 'afklaret' },
      { target_id: 12, valgt_assertion_id: 102, status: 'afklaret' },
      { target_id: 13, valgt_assertion_id: 103, status: 'afklaret' },
      { target_id: 20, valgt_assertion_id: 200, status: 'afklaret' },
      { target_id: 21, valgt_assertion_id: 201, status: 'afklaret' },
      { target_id: 22, valgt_assertion_id: 202, status: 'afklaret' },
      { target_id: 23, valgt_assertion_id: 203, status: 'afklaret' },
    ],
  };
});

describe('loadMediaItems (via fetchObjectMedia) — medie-fakta-berigelse', () => {
  it('beriger BEGGE medier i ét kald med deres EGNE fakta-værdier (id-opslaget krydskontaminerer ikke)', async () => {
    const byAnker = await fetchObjectMedia('coat_of_arms', [77]);
    const items = byAnker.get('77');
    expect(items).toHaveLength(2);
    const byId = new Map(items!.map((it) => [it.id, it]));

    expect(byId.get('501')).toMatchObject({
      altTekst: 'Alt for 501',
      kreditlinje: 'Kredit for 501',
      kildeUrl: 'https://example.org/501',
      dateringFakt: 'ca. 1850', // dateRaw foretrukket når sat
    });
    expect(byId.get('502')).toMatchObject({
      altTekst: 'Alt for 502',
      kreditlinje: 'Kredit for 502',
      kildeUrl: 'https://example.org/502',
      dateringFakt: '1900', // dateRaw mangler → falder tilbage til vaerdi
    });
  });

  it('medie uden fakta-rækker får alle berigelsesfelter null (RLS-gatet upubliceret medie er normaltilstanden)', async () => {
    byTable.fact = byTable.fact.filter((f) => f.subjekt_id !== 502);
    byTable.assertion = byTable.assertion.filter((a) => ![200, 201, 202, 203].includes(a.id as number));
    byTable.conclusion = byTable.conclusion.filter((c) => ![20, 21, 22, 23].includes(c.target_id as number));

    const byAnker = await fetchObjectMedia('coat_of_arms', [77]);
    const items = byAnker.get('77')!;
    const item502 = items.find((it) => it.id === '502');
    expect(item502).toMatchObject({
      altTekst: null, kreditlinje: null, kildeUrl: null, kildeInstitution: null,
      beskrivelse: null, teknik: null, fysiskeMaal: null, dateringFakt: null,
    });
    // 501 er upåvirket af 502's manglende fakta.
    const item501 = items.find((it) => it.id === '501');
    expect(item501?.altTekst).toBe('Alt for 501');
  });
});
