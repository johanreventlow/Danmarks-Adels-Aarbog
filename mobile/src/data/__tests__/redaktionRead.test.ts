import { buildTidslinje, joinEvidence, mapHaendelser, mapKonfliktRow, mapNarrativer, mapRelationRow } from '../redaktionRead';
import { mapRedPerson, mapSammeSomLinks } from '../redaktionRead';
import { getAll } from '@daa/core';

// getAll flyttet til @daa/core (single source, se packages/core/src/getAll.ts) — mockes her via
// jest.mock (ikke jest.spyOn) fordi re-exports/wildcard-exports kompileres til non-configurable
// getters, som jest.spyOn ikke kan redefinere.
jest.mock('@daa/core', () => ({
  ...jest.requireActual('@daa/core'),
  getAll: jest.fn(),
}));

describe('mapSammeSomLinks — klassificér retning', () => {
  it('personen som subjekt = alias, som objekt = kanonisk', () => {
    const rows = [
      { id: 972, subjekt_id: 255, objekt_id: 392 }, // 255 er alias for 392
      { id: 5, subjekt_id: 40, objekt_id: 255 }, // 40 er alias for 255 → 255 er kanonisk her
    ];
    expect(mapSammeSomLinks('255', rows)).toEqual([
      { relationId: '972', retning: 'alias', modpartId: '392' },
      { relationId: '5', retning: 'kanonisk', modpartId: '40' },
    ]);
  });
});
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
  expect(mapRedPerson({ id: 5, visning_navn: 'Conrad', visning_efternavn: null, visning_foedt: null, visning_doed: '1708', levende: false, privat: false }).born)
    .toBeNull();
  expect(mapRedPerson({ id: 6, visning_navn: 'Anne', visning_efternavn: null, visning_foedt: '1680', visning_doed: '1740', levende: false, privat: false }).born)
    .toBe(1680);
});

test('mapRedPerson: navn-fallback + bools', () => {
  const r = mapRedPerson({ id: 7, visning_navn: null, visning_efternavn: null, visning_foedt: null, visning_doed: null, levende: true, privat: null });
  expect(r).toEqual({ id: '7', navn: '(uden navn)', aar: '', born: null, levende: true, privat: false, efternavnAfledt: false });
});

test('mapRedPerson: efternavnAfledt afspejler visning_efternavn (udledt-slægtsnavn)', () => {
  const r = mapRedPerson({ id: 8, visning_navn: 'Conrad', visning_efternavn: 'Reventlow', visning_foedt: null, visning_doed: null, levende: false, privat: false });
  expect(r.navn).toBe('Conrad');       // rå visning_navn, IKKE overskrevet
  expect(r.efternavnAfledt).toBe(true);
});

test('mapNarrativer: rækker med source-join, ordnet efter source_id så id', () => {
  const rows = [
    { id: 7, source_id: 2, side: null, tekst: 'B', privat: false, source: { titel: 'DAA 1982', udgave: 'DAA 1982-84' } },
    { id: 3, source_id: 1, side: '10', tekst: 'A', privat: true, source: { titel: 'DAA 2018', udgave: 'DAA 2018-20' } },
  ];
  const out = mapNarrativer(rows as never);
  expect(out.map((n) => n.id)).toEqual([3, 7]);
  expect(out[0]).toMatchObject({ sourceId: 1, udgave: 'DAA 2018-20', side: '10', privat: true, tekst: 'A' });
  expect(out[1]).toMatchObject({ sourceId: 2, udgave: 'DAA 1982-84', side: null, privat: false });
});

test('mapNarrativer: håndterer manglende source-join (null)', () => {
  const out = mapNarrativer([{ id: 1, source_id: null, side: null, tekst: 'x', privat: null, source: null }] as never);
  expect(out[0]).toMatchObject({ sourceId: null, sourceTitel: null, udgave: null, privat: false });
});

test('mapHaendelser medtager skjulte og mapper null/source-felter', () => {
  const out = mapHaendelser([{ id: 9, klausul: 'I 1580 rejste han.', kategori: null,
    date_min: '1580-01-01', date_max: '1580-12-31', date_qualifier: 'about', date_raw: 'ca. 1580',
    feed_status: 'skjult', narrative_id: 4, span_start: null, span_laengde: null,
    fact_id: null, relation_id: 8, narrative: { side: '12', source: { titel: null, udgave: 'DAA 1939' } } }] as never);
  expect(out[0]).toMatchObject({ id: 9, feedStatus: 'skjult', narrativeId: 4,
    sourceTitel: 'DAA 1939', side: '12', factId: null, relationId: 8,
    dato: { min: '1580-01-01', raw: 'ca. 1580' } });
});

test('buildTidslinje fletter fact-kobling, sorterer NULL sidst og undgår dublet', () => {
  const hs = mapHaendelser([
    { id: 1, klausul: 'Tidlig', kategori: 'rejse', date_min: '1500-01-01', date_max: '1500-12-31', date_qualifier: null, date_raw: '1500', feed_status: 'kandidat', narrative_id: 1, span_start: 0, span_laengde: 6, fact_id: null, relation_id: null, narrative: null },
    { id: 2, klausul: 'Født her', kategori: 'familie', date_min: '1600-01-01', date_max: '1600-12-31', date_qualifier: null, date_raw: '1600', feed_status: 'interessant', narrative_id: 1, span_start: 8, span_laengde: 8, fact_id: 7, relation_id: null, narrative: null },
    { id: 3, klausul: 'Udateret', kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null, feed_status: 'kandidat', narrative_id: 1, span_start: null, span_laengde: null, fact_id: null, relation_id: null, narrative: null },
  ] as never);
  const evidence = { koen: null, felter: { foedt: [{ felt: 'foedt', faktatype: 'fødsel', factId: 7,
    konklusionAssertionId: 70, uenig: false, oplysninger: [{ assertionId: 70, vaerdi: '1600', erKonklusion: true,
      dato: { min: '1600-01-01', max: '1600-12-31', qualifier: null, raw: '1600' }, kilder: [] }] }] } };
  const out = buildTidslinje(hs, evidence);
  expect(out.map((p) => p.id)).toEqual(['h:1', 'f:7', 'h:3']);
  expect(out[1]).toMatchObject({ art: 'rygrad', klausul: 'Født her', factId: 7 });
  expect(out.filter((p) => p.id === 'h:2')).toHaveLength(0);
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

// --- mapFamilieRows ---

import { mapFamilieRows } from '../redaktionRead';

const MODEL = { byId: {
  '1': { name: 'Far', years: '1620–1680' }, '2': { name: 'Mor', years: '1625–1690' },
  '3': { name: 'Barn A', years: '* 1650' }, '7': { name: 'Fokus' },
} } as never;

test('mapFamilieRows: union m. partnere+børn, og person som barn', () => {
  const families = [{ id: 10, type: 'vielse' }, { id: 20, type: 'vielse' }];
  const members = [
    // family 10: fokus(7) + far(1) partnere, barn A(3)
    { family_id: 10, person_id: 7, rolle: 'partner', ordinal: 1, konfidens: null },
    { family_id: 10, person_id: 1, rolle: 'partner', ordinal: 1, konfidens: 'sikker' },
    { family_id: 10, person_id: 3, rolle: 'barn', ordinal: null, konfidens: null },
    // family 20: fokus(7) er barn af far(1)+mor(2)
    { family_id: 20, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 20, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 20, person_id: 7, rolle: 'barn', ordinal: null, konfidens: 'formodet' },
  ];
  const r = mapFamilieRows('7', families as never, members as never, MODEL);
  expect(r.somPartner).toEqual([{ familyId: '10', type: 'vielse',
    partnere: [{ personId: '1', navn: 'Far', aar: '1620–1680', konfidens: 'sikker', ordinal: 1 }],
    boern: [{ personId: '3', navn: 'Barn A', aar: '* 1650', rolle: 'barn', konfidens: null, ordinal: null }] }]);
  expect(r.somBarn).toEqual([{ familyId: '20', rolle: 'barn', konfidens: 'formodet',
    foraeldre: [{ personId: '1', navn: 'Far' }, { personId: '2', navn: 'Mor' }] }]);
});

test('mapFamilieRows: boern bærer ordinal videre (søskende-rækkefølge, brugerfund 2026-07-02)', () => {
  const members = [
    { family_id: 10, person_id: 7, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 3, rolle: 'barn', ordinal: 2, konfidens: null },
    { family_id: 10, person_id: 4, rolle: 'barn', ordinal: 1, konfidens: null },
  ];
  const r = mapFamilieRows('7', [{ id: 10, type: 'vielse' }] as never, members as never, MODEL);
  expect(r.somPartner[0].boern.map((b) => [b.personId, b.ordinal])).toEqual([['3', 2], ['4', 1]]);
});

// --- nudgeOrdinal (søskende-rækkefølge, brugerfund 2026-07-02) ---
import { nudgeOrdinal } from '../redaktionRead';

test('nudgeOrdinal: op flytter til lige under naboens eksplicitte ordinal', () => {
  const boern = [{ ordinal: 1 }, { ordinal: 2 }, { ordinal: 3 }];
  expect(nudgeOrdinal(boern, 2, 'op')).toBe(1); // naboen (index 1) har ordinal=2 -> 2-1=1
});

test('nudgeOrdinal: ned flytter til lige over naboens eksplicitte ordinal', () => {
  const boern = [{ ordinal: 1 }, { ordinal: 2 }, { ordinal: 3 }];
  expect(nudgeOrdinal(boern, 0, 'ned')).toBe(3); // naboen (index 1) har ordinal=2 -> 2+1=3
});

test('nudgeOrdinal: bruger index-baseret fallback (i+1)*10 når ordinal er NULL', () => {
  const boern = [{ ordinal: null }, { ordinal: null }, { ordinal: null }];
  // Flyt index 2 op: naboen (index 1) har ingen ordinal -> effektiv (1+1)*10=20 -> 19
  expect(nudgeOrdinal(boern, 2, 'op')).toBe(19);
});

test('nudgeOrdinal: kan ikke flytte det første barn op', () => {
  const boern = [{ ordinal: 1 }, { ordinal: 2 }];
  expect(nudgeOrdinal(boern, 0, 'op')).toBeNull();
});

test('nudgeOrdinal: kan ikke flytte det sidste barn ned', () => {
  const boern = [{ ordinal: 1 }, { ordinal: 2 }];
  expect(nudgeOrdinal(boern, 1, 'ned')).toBeNull();
});

test('mapFamilieRows: ukendt person → #id-fallback', () => {
  const r = mapFamilieRows('7', [{ id: 10, type: 'vielse' }] as never,
    [{ family_id: 10, person_id: 7, rolle: 'partner', ordinal: null, konfidens: null },
     { family_id: 10, person_id: 99, rolle: 'barn', ordinal: null, konfidens: null }] as never, MODEL);
  expect(r.somPartner[0].boern[0].navn).toBe('#99');
});

test('mapFamilieRows: fokus-barn under to roller i samme familie → begge i somBarn (cycle 07 H2)', () => {
  // Person 7 er både 'barn' og 'adopteret_barn' i familie 30 (PK tillader det). Begge links skal
  // vises, så begge kan redigeres/afkobles — find-first ville have skjult det ene.
  const members = [
    { family_id: 30, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 30, person_id: 7, rolle: 'barn', ordinal: null, konfidens: 'sikker' },
    { family_id: 30, person_id: 7, rolle: 'adopteret_barn', ordinal: null, konfidens: 'formodet' },
  ];
  const r = mapFamilieRows('7', [{ id: 30, type: 'vielse' }] as never, members as never, MODEL);
  expect(r.somBarn.map((b) => b.rolle).sort()).toEqual(['adopteret_barn', 'barn']);
  expect(r.somBarn.find((b) => b.rolle === 'adopteret_barn')?.konfidens).toBe('formodet');
});

test('mapFamilieRows: fokus-person ekskluderet fra egen unions boern (data-fejl-guard)', () => {
  // Person 7 fejlagtigt både partner OG barn i familie 40 → må IKKE fremstå som sit eget barn.
  const members = [
    { family_id: 40, person_id: 7, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 40, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 40, person_id: 7, rolle: 'barn', ordinal: null, konfidens: null },
    { family_id: 40, person_id: 3, rolle: 'barn', ordinal: null, konfidens: null },
  ];
  const r = mapFamilieRows('7', [{ id: 40, type: 'vielse' }] as never, members as never, MODEL);
  expect(r.somPartner[0].boern.map((b) => b.personId)).toEqual(['3']); // 7 ekskluderet
  expect(r.somBarn).toHaveLength(1); // 7's egen barn-rolle dukker op i somBarn (uafhængigt)
});

test('fetchRedaktionPersoner samler alle sider (ingen trunkering)', async () => {
  const page1 = Array.from({ length: 1000 }, (_, i) => ({ id: i + 1, visning_navn: `P${i}`, visning_foedt: '1700', visning_doed: null, levende: false, privat: false }));
  const page2 = [{ id: 1001, visning_navn: 'Sidste', visning_foedt: '1800', visning_doed: null, levende: false, privat: false }];
  (getAll as jest.Mock).mockResolvedValue([...page1, ...page2]);
  const res = await fetchRedaktionPersoner();
  expect(res).toHaveLength(1001);
  expect(res[1000].navn).toBe('Sidste');
  (getAll as jest.Mock).mockReset();
});

import { mapHistRow } from '../redaktionRead';

describe('mapHistRow', () => {
  it('mapper change_set-række til HistPost (ingen revertedIds → reverteret=false)', () => {
    const r = { id: 12, actor_navn: 'Johan', created_at: '2026-06-30T10:00:00Z',
                summary: 'Rettede dødsdato', reverterer_id: null } as any;
    expect(mapHistRow(r)).toMatchObject({ id: '12', hvem: 'Johan', resume: 'Rettede dødsdato', reverteret: false });
  });
  // review10 H2: reverterer_id peger FRA fortrydelsen TIL den fortrudte — så status
  // afhænger af om rækkens EGET id er i revertedIds (samlet fra hele listen), IKKE af
  // rækkens eget reverterer_id-felt (det felt betyder "dette sæt fortrød X", ikke
  // "dette sæt blev fortrudt").
  it('rækkens id er i revertedIds → reverteret=true (den ORIGINALE, fortrudte handling)', () => {
    const original = { id: 12, actor_navn: 'Johan', created_at: '2026-06-30T10:00:00Z',
                        summary: 'Original handling', reverterer_id: null } as any;
    expect(mapHistRow(original, new Set([12]))).toMatchObject({ reverteret: true });
  });
  it('rækken er selv en fortrydelse (reverterer_id sat) → reverteret afhænger IKKE af eget felt', () => {
    const reversal = { id: 13, actor_navn: 'Johan', created_at: '2026-06-30T10:00:00Z',
                        summary: 'Fortrød noget', reverterer_id: 12 } as any;
    // reversal-rækken selv er ikke i revertedIds (ingen har fortrudt DEN) → false,
    // selvom dens eget reverterer_id-felt er sat (den gamle, forkerte logik ville sige true).
    expect(mapHistRow(reversal, new Set([12]))).toMatchObject({ reverteret: false });
  });
  it('manglende actor_navn/summary → fallback', () => {
    const r = { id: 14, actor_navn: null, created_at: '2026-06-30T10:00:00Z',
                summary: null, reverterer_id: null } as any;
    expect(mapHistRow(r)).toMatchObject({ hvem: 'ukendt', resume: '(uden beskrivelse)' });
  });
});

import { mapDoedLinkRow } from '../redaktionRead';

describe('mapDoedLinkRow', () => {
  it('mapper text_mention-række til DoedLink', () => {
    const r = { kilde_type: 'narrative', kilde_id: 3, maal_type: 'person', maal_id: 999 } as any;
    expect(mapDoedLinkRow(r)).toEqual({ kilde: 'narrative#3', maalType: 'person', maalId: '999' });
  });
});

import { mapPersonMediaRows } from '../redaktionRead';


describe('mapPersonMediaRows (mediehåndtering fase 1)', () => {
  const rich = {
    kunstner: 'Jens Juel', datering: 'ca. 1780', rettigheder_status: 'public_domain',
    mime_type: 'image/jpeg', byte_size: 1234, bredde: 800, hoejde: 1000, original_filnavn: 'portraet.jpg',
  };
  it('mapper alle filside-felter og relationId', () => {
    const rows = [{ id: 91, slags: 'foto', titel: 'Portræt', storage_path: 'redaktor/a.jpg',
      upload_status: 'klar', maa_publiceres: true, ...rich }];
    expect(mapPersonMediaRows(rows, new Map([['91', '501']]))).toEqual([{
      id: '91', relationId: '501', slags: 'foto', titel: 'Portræt', storagePath: 'redaktor/a.jpg',
      kunstner: 'Jens Juel', datering: 'ca. 1780', rettighederStatus: 'public_domain',
      mimeType: 'image/jpeg', byteSize: 1234, bredde: 800, hoejde: 1000, originalFilnavn: 'portraet.jpg',
      uploadStatus: 'klar', maaPubliceres: true, thumbStoragePath: null,
    }]);
  });
  it('manglende felter får fail-closed defaults', () => {
    const rows = [{ id: 92, slags: null, titel: null, kunstner: null, datering: null, storage_path: null,
      upload_status: null, maa_publiceres: null, rettigheder_status: null, mime_type: null,
      byte_size: null, bredde: null, hoejde: null, original_filnavn: null }];
    expect(mapPersonMediaRows(rows)).toEqual([{
      id: '92', relationId: '', slags: '', titel: null, storagePath: null, kunstner: null, datering: null,
      rettighederStatus: 'ukendt', mimeType: null, byteSize: null, bredde: null, hoejde: null,
      originalFilnavn: null, uploadStatus: 'kladde', maaPubliceres: false, thumbStoragePath: null,
    }]);
  });
  it('thumb udfyldes, og fjernet bevares til genopret', () => {
    const rows = [{ id: 93, slags: 'foto', titel: 'Fjernet', storage_path: 'large.jpg',
      upload_status: 'fjernet', maa_publiceres: true, ...rich }];
    const out = mapPersonMediaRows(rows, new Map(), new Map([['93', 'thumb.jpg']]));
    expect(out[0]).toMatchObject({ id: '93', uploadStatus: 'fjernet', thumbStoragePath: 'thumb.jpg' });
  });
});

import {
  klassificerMedie,
  mapMediaAnvendelse,
  mapMediaBibliotekRows,
} from '../redaktionRead';

describe('mediebibliotek fase 2', () => {
  describe('klassificerMedie', () => {
    const uploadStatuses = ['klar', 'kladde', 'fejlet', 'fjernet'] as const;
    const rettighederStatuses = ['ukendt', 'licenseret'] as const;
    for (const uploadStatus of uploadStatuses) {
      for (const rettighederStatus of rettighederStatuses) {
        for (const maaPubliceres of [false, true]) {
          for (const antalAfbildet of [0, 1]) {
            for (const antalMentions of [0, 1]) {
              it(`${uploadStatus}/${rettighederStatus}/public=${maaPubliceres}/afbildet=${antalAfbildet}/mentions=${antalMentions}`, () => {
                const expected = [];
                if (uploadStatus === 'klar' && (rettighederStatus === 'ukendt' || !maaPubliceres)) expected.push('rettigheder');
                if (uploadStatus === 'klar' && antalAfbildet === 0 && antalMentions === 0) expected.push('loese');
                if (uploadStatus === 'kladde' || uploadStatus === 'fejlet') expected.push('strandede');
                if (uploadStatus === 'fjernet') expected.push('papirkurv');
                expect(klassificerMedie({ uploadStatus, rettighederStatus, maaPubliceres }, antalAfbildet, antalMentions))
                  .toEqual(expected);
              });
            }
          }
        }
      }
    }

    it('tillader flere køer samtidig', () => {
      expect(klassificerMedie({ uploadStatus: 'klar', rettighederStatus: 'ukendt', maaPubliceres: false }, 0, 0))
        .toEqual(['rettigheder', 'loese']);
    });
  });

  it('joiner tællinger og thumb på alle media, også uden anvendelser', () => {
    const media = [
      { id: 91, slags: 'foto', titel: 'Brugt', kunstner: null, datering: null, storage_path: 'a.jpg',
        upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'public_domain', mime_type: 'image/jpeg',
        byte_size: 1, bredde: 10, hoejde: 20, original_filnavn: 'a.jpg' },
      { id: 92, slags: 'foto', titel: 'Løst', kunstner: null, datering: null, storage_path: 'b.jpg',
        upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'public_domain', mime_type: 'image/jpeg',
        byte_size: 2, bredde: 10, hoejde: 20, original_filnavn: 'b.jpg' },
    ];
    const relationer = [
      { subjekt_type: 'person', subjekt_id: 7, objekt_type: 'media', objekt_id: 91, rolle: 'afbildet' },
      { subjekt_type: 'media', subjekt_id: 91, objekt_type: 'estate', objekt_id: 3, rolle: 'afbildet' },
    ];
    const mentions = [
      { kilde_type: 'narrative', kilde_id: 4, maal_type: 'media', maal_id: 91 },
      { kilde_type: 'note', kilde_id: 5, maal_type: 'media', maal_id: 91 },
    ];
    const out = mapMediaBibliotekRows(media, relationer, mentions, new Map([['91', 'thumb/a.jpg']]));
    expect(out[0]).toMatchObject({ id: '91', antalAfbildet: 2, antalMentions: 2,
      koeer: [], thumbStoragePath: 'thumb/a.jpg' });
    expect(out[0]).not.toHaveProperty('relationId');
    expect(out[1]).toMatchObject({ id: '92', antalAfbildet: 0, antalMentions: 0, koeer: ['loese'],
      thumbStoragePath: null });
  });

  it('opløser afbildet-retninger og narrativets subjektNavn', () => {
    const out = mapMediaAnvendelse(
      '91',
      [
        { id: 501, subjekt_type: 'person', subjekt_id: 7, objekt_type: 'media', objekt_id: 91, rolle: 'afbildet' },
        { id: 502, subjekt_type: 'media', subjekt_id: 91, objekt_type: 'estate', objekt_id: 3, rolle: 'afbildet' },
      ],
      [{ kilde_type: 'narrative', kilde_id: 40, maal_type: 'media', maal_id: 91 }],
      [{ id: 40, subjekt_type: 'lineage', subjekt_id: 8 }],
      new Map([
        ['person:7', 'Anna Reventlow'],
        ['estate:3', 'Pederstrup'],
        ['lineage:8', 'Den grevelige linje'],
      ]),
    );
    expect(out).toEqual({
      afbildet: [
        { type: 'person', id: '7', navn: 'Anna Reventlow', relationId: '501' },
        { type: 'estate', id: '3', navn: 'Pederstrup', relationId: '502' },
      ],
      mentions: [{ kildeType: 'narrative', kildeId: '40', subjektNavn: 'Den grevelige linje' }],
    });
  });

  it('falder lukket tilbage ved ukendt mention-kilde eller subjekt', () => {
    const out = mapMediaAnvendelse(
      '91',
      [],
      [
        { kilde_type: 'note', kilde_id: 99, maal_type: 'media', maal_id: 91 },
        { kilde_type: 'narrative', kilde_id: 302, maal_type: 'media', maal_id: 91 },
      ],
      [{ id: 302, subjekt_type: 'lineage', subjekt_id: 8 }],
      new Map(),
    );
    expect(out.mentions).toEqual([
      { kildeType: 'note', kildeId: '99', subjektNavn: '(ukendt subjekt)' },
      { kildeType: 'narrative', kildeId: '302', subjektNavn: 'lineage #8' },
    ]);
  });
});
