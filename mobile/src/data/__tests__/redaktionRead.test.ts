import { joinEvidence, mapKonfliktRow, mapNarrativRow, mapRelationRow } from '../redaktionRead';
import { mapRedPerson } from '../redaktionRead';
import * as load from '../load';
import { fetchRedaktionPersoner } from '../redaktionRead';

jest.mock('../../lib/supabase', () => ({ supabase: { from: () => ({ select: () => ({}) }) } }));

const FACTS = [
  { id: 10, subjekt_type: 'person', subjekt_id: 1, faktatype: 'navn' },
  { id: 11, subjekt_type: 'person', subjekt_id: 1, faktatype: 'fødsel' },
];
const ASSERTS = [
  { id: 100, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Conrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 101, target_type: 'fact', target_id: 10, vaerdi_tekst: 'Konrad', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  { id: 102, target_type: 'fact', target_id: 11, vaerdi_tekst: null, date_min: '1644-01-01', date_max: '1644-12-31', date_qualifier: 'about', date_raw: 'ca. 1644' },
];
const CONCS = [{ target_type: 'fact', target_id: 10, valgt_assertion_id: 100 }];
const CITS = [
  { assertion_id: 100, source_id: 5, side: 's. 12', citat_tekst: 'Conrad', citat_dato: null, source: { titel: 'DAA 2018' } },
];

test('mapKonfliktRow oversætter faktatype → UI-felt + bærer fact_id', () => {
  expect(mapKonfliktRow({ person_id: 7, faktatype: 'navn', antal_vaerdier: 2, fact_id: 42 }))
    .toEqual({ personId: '7', felt: 'navn', antalVaerdier: 2, factId: 42 });
});

test('joinEvidence samler felter (liste pr. felt), markerer konklusion + uenig pr. fact', () => {
  const ev = joinEvidence({ facts: FACTS, assertions: ASSERTS, conclusions: CONCS, citations: CITS, koen: 'M' });
  expect(ev.koen).toBe('M');
  // navn-felt = liste m. ét fact; det fact har to oplysninger m. forskellig værdi → uenig.
  expect(ev.felter.navn).toHaveLength(1);
  expect(ev.felter.navn[0].uenig).toBe(true); // Conrad ≠ Konrad (samme fact)
  expect(ev.felter.navn[0].konklusionAssertionId).toBe(100);
  expect(ev.felter.navn[0].oplysninger.find((o) => o.assertionId === 100)?.erKonklusion).toBe(true);
  expect(ev.felter.navn[0].oplysninger.find((o) => o.assertionId === 100)?.kilder[0].sourceTitel).toBe('DAA 2018');
  expect(ev.felter.foedt[0].uenig).toBe(false); // kun én oplysning
  expect(ev.felter.foedt[0].oplysninger[0].dato?.raw).toBe('ca. 1644');
});

test('joinEvidence: tom-værdi-assertion giver IKKE falsk uenig (cycle 03 H1)', () => {
  // Ét fact med én rigtig værdi + én tom oplysning (null vaerdi_tekst + null date_raw).
  const facts = [{ id: 30, subjekt_type: 'person', subjekt_id: 3, faktatype: 'titel' }];
  const asserts = [
    { id: 300, target_type: 'fact', target_id: 30, vaerdi_tekst: 'kammerherre', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
    { id: 301, target_type: 'fact', target_id: 30, vaerdi_tekst: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  ];
  const ev = joinEvidence({ facts, assertions: asserts, conclusions: [], citations: [], koen: null });
  expect(ev.felter.titel[0].uenig).toBe(false); // tom værdi tæller ikke som konkurrerende
  // To FORSKELLIGE non-tomme værdier på samme fact = ægte uenig.
  const asserts2 = [
    { id: 302, target_type: 'fact', target_id: 30, vaerdi_tekst: 'kammerherre', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
    { id: 303, target_type: 'fact', target_id: 30, vaerdi_tekst: 'greve', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  ];
  const ev2 = joinEvidence({ facts, assertions: asserts2, conclusions: [], citations: [], koen: null });
  expect(ev2.felter.titel[0].uenig).toBe(true);
});

test('joinEvidence: flere facts af samme type = liste, hver uenig=false (fact-kardinalitet)', () => {
  // To separate titel-facts (fx "kammerherre" + "greve") — legitime distinkte facts, IKKE konflikt.
  const facts = [
    { id: 20, subjekt_type: 'person', subjekt_id: 2, faktatype: 'titel' },
    { id: 21, subjekt_type: 'person', subjekt_id: 2, faktatype: 'titel' },
  ];
  const asserts = [
    { id: 200, target_type: 'fact', target_id: 20, vaerdi_tekst: 'kammerherre', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
    { id: 201, target_type: 'fact', target_id: 21, vaerdi_tekst: 'greve', date_min: null, date_max: null, date_qualifier: null, date_raw: null },
  ];
  const ev = joinEvidence({ facts, assertions: asserts, conclusions: [], citations: [], koen: null });
  expect(ev.felter.titel).toHaveLength(2); // begge titler vises
  expect(ev.felter.titel.map((f) => f.oplysninger[0].vaerdi)).toEqual(['kammerherre', 'greve']);
  expect(ev.felter.titel.every((f) => f.uenig === false)).toBe(true); // ingen falsk konflikt
});

test('mapRedPerson: born fra visning_foedt, IKKE dødsår (cycle 2A M1)', () => {
  // Kun dødsår — born skal være null, ikke 1708.
  expect(mapRedPerson({ id: 5, visning_navn: 'Conrad', visning_foedt: null, visning_doed: '1708', levende: false, privat: false }).born)
    .toBeNull();
  expect(mapRedPerson({ id: 6, visning_navn: 'Anne', visning_foedt: '1680', visning_doed: '1740', levende: false, privat: false }).born)
    .toBe(1680);
});

test('mapRedPerson: navn-fallback + bools', () => {
  const r = mapRedPerson({ id: 7, visning_navn: null, visning_foedt: null, visning_doed: null, levende: true, privat: null });
  expect(r).toEqual({ id: '7', navn: '(uden navn)', aar: '', born: null, levende: true, privat: false });
});

test('mapNarrativRow: første række uanset privat (skrive-mål == prefill)', () => {
  // red_upsert_narrativ redigerer FØRSTE narrativ by id — prefill skal læse SAMME.
  expect(mapNarrativRow([{ tekst: 'Privat bio', privat: true }, { tekst: 'Offentlig', privat: false }]))
    .toEqual({ tekst: 'Privat bio', privat: true });
});

test('mapNarrativRow: tom liste → null', () => {
  expect(mapNarrativRow([])).toBeNull();
});

test('mapNarrativRow: null-tekst → tom streng, privat-bool', () => {
  expect(mapNarrativRow([{ tekst: null, privat: null }])).toEqual({ tekst: '', privat: false });
});

const AUX = { orgListe: [{ id: '1', navn: 'Hæren', slags: '' }], godsListe: [{ id: '5', navn: 'Brahetrolleborg', slags: '', ownerCount: 1 }] } as never;

test('mapRelationRow: art + navn-opslag fra aux', () => {
  const rows = [
    { id: 100, objekt_type: 'organisation', objekt_id: 1, rolle: 'oberst', periode_raw: '1700–1710' },
    { id: 101, objekt_type: 'estate', objekt_id: 5, rolle: 'ejer', periode_raw: null },
    { id: 102, objekt_type: 'historical_event', objekt_id: 9, rolle: 'deltager', periode_raw: null },
  ];
  expect(mapRelationRow(rows as never, AUX)).toEqual([
    { relationId: 100, art: 'hverv', objektType: 'organisation', objektId: '1', navn: 'Hæren', rolle: 'oberst', periode: '1700–1710' },
    { relationId: 101, art: 'gods', objektType: 'estate', objektId: '5', navn: 'Brahetrolleborg', rolle: 'ejer', periode: '' },
    { relationId: 102, art: 'event', objektType: 'historical_event', objektId: '9', navn: 'Begivenhed #9', rolle: 'deltager', periode: '' },
  ]);
});

test('mapRelationRow: ukendt objekt-id → fallback-navn', () => {
  expect(mapRelationRow([{ id: 1, objekt_type: 'estate', objekt_id: 99, rolle: null, periode_raw: null }] as never, AUX)[0].navn)
    .toBe('#99');
});

test('fetchRedaktionPersoner samler alle sider (ingen trunkering)', async () => {
  const page1 = Array.from({ length: 1000 }, (_, i) => ({ id: i + 1, visning_navn: `P${i}`, visning_foedt: '1700', visning_doed: null, levende: false, privat: false }));
  const page2 = [{ id: 1001, visning_navn: 'Sidste', visning_foedt: '1800', visning_doed: null, levende: false, privat: false }];
  const spy = jest.spyOn(load, 'getAll').mockResolvedValue([...page1, ...page2] as never);
  const res = await fetchRedaktionPersoner();
  expect(res).toHaveLength(1001);
  expect(res[1000].navn).toBe('Sidste');
  spy.mockRestore();
});
