import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  normaliserOcrDato,
  filterKvalitetsark,
  sortKvalitetsark,
  type PersonKvalitetsarkRow,
  type KvalitetsarkFilter,
} from '../ocrKvalitet';

// Kryds-sproglig kontrakt: samme fixture bestås af TypeScript (her) og Python
// (.claude/skills/daa-extract/scripts/test_validate.py). Sti er ikke cwd-afhængig,
// så testen virker uanset om vitest køres fra roden eller fra packages/core.
const fixturePath = fileURLToPath(
  new URL('../../../../tests/fixtures/ocr-date-normalization.json', import.meta.url),
);
const dateFixture: Array<{
  raw: string;
  min: string | null;
  max: string | null;
  qualifier: string | null;
  certainty: string | null;
}> = JSON.parse(readFileSync(fixturePath, 'utf8'));

describe('normaliserOcrDato — paritet med derive_date_info (validate.py)', () => {
  for (const c of dateFixture) {
    test(`"${c.raw}"`, () => {
      const got = normaliserOcrDato(c.raw);
      expect(got.min).toBe(c.min);
      expect(got.max).toBe(c.max);
      expect(got.qualifier).toBe(c.qualifier);
      expect(got.certainty).toBe(c.certainty);
      expect(got.raw).toBe(c.raw);
      expect(got.calendar).toBe('gregoriansk');
    });
  }

  test('uparsebar rå tekst bevares ordret og understood=false', () => {
    const got = normaliserOcrDato('ukendt');
    expect(got.raw).toBe('ukendt');
    expect(got.min).toBeNull();
    expect(got.max).toBeNull();
    expect(got.understood).toBe(false);
  });

  test('forstået dato har understood=true', () => {
    expect(normaliserOcrDato('1698').understood).toBe(true);
  });
});

// Bygger én komplet, gyldig række med alle 42 felter fra red_person_grid(),
// så et glemt felt fejler ved typecheck (`npm run typecheck -w @daa/core`),
// ikke først når web-adapteren rammer et manglende felt i produktion.
function fuldRow(overrides: Partial<PersonKvalitetsarkRow> = {}): PersonKvalitetsarkRow {
  return {
    personId: '1',
    importKey: 'daa:test:1939',
    recordKey: 'I-15a',
    sourceId: '10',
    sourceTitel: 'Danmarks Adels Aarbog',
    sourceUdgave: '1939',
    linje: 'I',
    nr: 15,
    slaegtled: 1,
    personStatus: 'aktiv',
    navn: 'Conrad Reventlow',
    navnAssertionId: '100',
    foedselRaw: '26. juli 1975',
    foedselMin: '1975-07-26',
    foedselMax: '1975-07-26',
    foedselQualifier: null,
    foedselAssertionId: '101',
    doedRaw: null,
    doedMin: null,
    doedMax: null,
    doedQualifier: null,
    doedAssertionId: null,
    koen: 'mand',
    levende: false,
    privat: false,
    staged: false,
    kanoniskPersonId: null,
    sammeSomStatus: null,
    antalTitler: 0,
    antalFamilier: 1,
    antalRelationer: 2,
    antalKildeAssertions: 2,
    qaKoder: [],
    qaAlvor: null,
    reviewStatus: {},
    kanRettes: { navn: true, foedsel: true, doed: true, koen: true },
    blokarsager: {},
    ocrContext: {},
    kildeSide: {},
    importeret: {},
    korrigeret: {},
    inputFingerprint: {},
    ...overrides,
  };
}

describe('filterKvalitetsark', () => {
  const rows: PersonKvalitetsarkRow[] = [
    fuldRow({ personId: '1', navn: 'Anna', qaKoder: [], reviewStatus: {} }),
    fuldRow({
      personId: '2',
      navn: 'Bo',
      qaKoder: ['navn_mangler'],
      reviewStatus: { navn: 'aaben' },
    }),
    fuldRow({
      personId: '3',
      navn: 'Carl',
      qaKoder: ['dato_ufortolkelig'],
      reviewStatus: { foedsel: 'rettet' },
    }),
    fuldRow({
      personId: '4',
      navn: 'Dora',
      qaKoder: ['dato_ufortolkelig'],
      reviewStatus: { foedsel: 'godkendt' },
    }),
    fuldRow({
      personId: '5',
      navn: 'Erik',
      qaKoder: ['dato_ufortolkelig'],
      reviewStatus: { foedsel: 'udskudt' },
    }),
    fuldRow({
      personId: '6',
      navn: 'Frida',
      qaKoder: ['dato_ufortolkelig'],
      reviewStatus: { foedsel: 'stale' },
    }),
    fuldRow({
      personId: '7',
      navn: 'Gustav',
      qaKoder: ['dato_ufortolkelig'],
      reviewStatus: { foedsel: 'rettet', doed: 'godkendt' },
    }),
  ];

  const basisFilter: KvalitetsarkFilter = {
    preset: 'alle',
    query: '',
    source: null,
    linje: null,
    felt: null,
    reviewStatus: null,
    staged: null,
    sammeSom: null,
  };

  test('alle indeholder altid samtlige rækker', () => {
    expect(filterKvalitetsark(rows, basisFilter)).toHaveLength(rows.length);
  });

  test('aabne kræver aktive QA-koder uden fuldført afgørelse', () => {
    const got = filterKvalitetsark(rows, { ...basisFilter, preset: 'aabne' });
    const ids = got.map((r) => r.personId).sort();
    // person 1: ingen QA-koder -> ude. person 2: åben -> med.
    // person 3/4/7: alle relevante felter rettet/godkendt -> ude.
    // person 5: udskudt -> ude (afgjort, egen preset). person 6: stale -> med (ikke fuldført).
    expect(ids).toEqual(['2', '6']);
  });

  test('rettede/godkendte/udskudte/stale matcher ethvert felt med den status', () => {
    expect(filterKvalitetsark(rows, { ...basisFilter, preset: 'rettede' }).map((r) => r.personId).sort())
      .toEqual(['3', '7']);
    expect(filterKvalitetsark(rows, { ...basisFilter, preset: 'godkendte' }).map((r) => r.personId).sort())
      .toEqual(['4', '7']);
    expect(filterKvalitetsark(rows, { ...basisFilter, preset: 'udskudte' }).map((r) => r.personId))
      .toEqual(['5']);
    expect(filterKvalitetsark(rows, { ...basisFilter, preset: 'stale' }).map((r) => r.personId))
      .toEqual(['6']);
  });

  test('søgning dækker navn, record_key, source, linje og person-id', () => {
    const searchable = [
      fuldRow({ personId: '900', navn: 'Zzz', recordKey: 'ZZZ-1', sourceTitel: 'Zzz', linje: 'Zzz' }),
    ];
    expect(filterKvalitetsark(searchable, { ...basisFilter, query: 'Zzz' })).toHaveLength(1);
    expect(filterKvalitetsark(searchable, { ...basisFilter, query: 'ZZZ-1' })).toHaveLength(1);
    expect(filterKvalitetsark(searchable, { ...basisFilter, query: '900' })).toHaveLength(1);
    expect(filterKvalitetsark(searchable, { ...basisFilter, query: 'findes-ikke' })).toHaveLength(0);
  });

  test('søgning er case-insensitiv', () => {
    const searchable = [fuldRow({ personId: '900', navn: 'ANNA REVENTLOW' })];
    expect(filterKvalitetsark(searchable, { ...basisFilter, query: 'anna' })).toHaveLength(1);
  });

  test('felt/status/staged/samme-som filtre kombineres med AND', () => {
    const combo = [
      fuldRow({
        personId: '10',
        staged: true,
        sammeSomStatus: 'afklaret',
        reviewStatus: { foedsel: 'rettet' },
      }),
      fuldRow({
        personId: '11',
        staged: true,
        sammeSomStatus: null,
        reviewStatus: { foedsel: 'rettet' },
      }),
      fuldRow({
        personId: '12',
        staged: false,
        sammeSomStatus: 'afklaret',
        reviewStatus: { foedsel: 'rettet' },
      }),
    ];
    const got = filterKvalitetsark(combo, {
      ...basisFilter,
      felt: 'foedsel',
      reviewStatus: 'rettet',
      staged: true,
      sammeSom: true,
    });
    expect(got.map((r) => r.personId)).toEqual(['10']);
  });

  test('felt + reviewStatus ser kun på det valgte felt', () => {
    const combo = [
      fuldRow({ personId: '20', reviewStatus: { navn: 'rettet', foedsel: 'aaben' } }),
    ];
    expect(
      filterKvalitetsark(combo, { ...basisFilter, felt: 'foedsel', reviewStatus: 'rettet' }),
    ).toHaveLength(0);
    expect(
      filterKvalitetsark(combo, { ...basisFilter, felt: 'navn', reviewStatus: 'rettet' }),
    ).toHaveLength(1);
  });
});

describe('sortKvalitetsark', () => {
  test('tekst sorteres dansk (Æ/Ø/Å efter Z)', () => {
    const rows = [
      fuldRow({ personId: '1', navn: 'Ærø' }),
      fuldRow({ personId: '2', navn: 'Bang' }),
      fuldRow({ personId: '3', navn: 'Zahle' }),
    ];
    const got = sortKvalitetsark(rows, 'navn', 'asc').map((r) => r.navn);
    expect(got).toEqual(['Bang', 'Zahle', 'Ærø']);
  });

  test('datoer sorteres kronologisk med null sidst — også i desc', () => {
    const rows = [
      fuldRow({ personId: '1', foedselMin: '1975-01-01' }),
      fuldRow({ personId: '2', foedselMin: null }),
      fuldRow({ personId: '3', foedselMin: '1600-01-01' }),
    ];
    expect(sortKvalitetsark(rows, 'foedsel', 'asc').map((r) => r.personId)).toEqual(['3', '1', '2']);
    expect(sortKvalitetsark(rows, 'foedsel', 'desc').map((r) => r.personId)).toEqual(['1', '3', '2']);
  });

  test('qa_alvor sorteres efter alvorsrang (fejl < advarsel < info < null), null sidst i begge retninger', () => {
    const rows = [
      fuldRow({ personId: '1', qaAlvor: 'info' }),
      fuldRow({ personId: '2', qaAlvor: 'fejl' }),
      fuldRow({ personId: '3', qaAlvor: null }),
      fuldRow({ personId: '4', qaAlvor: 'advarsel' }),
    ];
    expect(sortKvalitetsark(rows, 'qa_alvor', 'asc').map((r) => r.personId)).toEqual(['2', '4', '1', '3']);
    expect(sortKvalitetsark(rows, 'qa_alvor', 'desc').map((r) => r.personId)).toEqual(['1', '4', '2', '3']);
  });

  test('deterministisk person_id-tiebreak ved lige nøgler', () => {
    const rows = [
      fuldRow({ personId: '20', navn: 'Samme' }),
      fuldRow({ personId: '3', navn: 'Samme' }),
      fuldRow({ personId: '100', navn: 'Samme' }),
    ];
    // Numerisk (BigInt) tiebreak, ikke leksikografisk streng ("100" < "20" < "3" ville være forkert).
    expect(sortKvalitetsark(rows, 'navn', 'asc').map((r) => r.personId)).toEqual(['3', '20', '100']);
  });

  test('sortering er stabil og muterer ikke input', () => {
    const rows = [fuldRow({ personId: '1' }), fuldRow({ personId: '2' })];
    const copy = [...rows];
    sortKvalitetsark(rows, 'navn', 'asc');
    expect(rows).toEqual(copy);
  });
});
