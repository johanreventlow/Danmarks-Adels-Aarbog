import { describe, expect, test } from 'vitest';
import { bogensNummer, buildProvenanceSources, citationRowsTilProveniens, flettKilder, optraederSom } from '../kildeProveniens';
import type { SourceRef } from '../types';

// Baggrund: `sourcesBy` bygges af person_external_id, som kun findes for personer bogen gav et
// nummer. De 627 ægtefæller har ingen — men deres proveniens står i citation→source. Denne modul
// udleder "Kilde i Aarbogen" af evidenslaget, som faldback.

describe('buildProvenanceSources', () => {
  test('udleder værk + sidetal pr. person', () => {
    expect(buildProvenanceSources([
      { person_id: '1690', work: 'Dansk Adels Aarbog – DAA 1939', side: '578' },
    ])).toEqual({ '1690': [{ work: 'Dansk Adels Aarbog – DAA 1939', ref: 's. 578' }] });
  });

  test('uden sidetal bliver ref tom — værket alene er stadig sandt', () => {
    expect(buildProvenanceSources([
      { person_id: '841', work: 'Dansk Adels Aarbog – DAA 2018-20', side: null },
    ])).toEqual({ '841': [{ work: 'Dansk Adels Aarbog – DAA 2018-20', ref: '' }] });
  });

  test('dedupliker: fire fakta fra samme udgave og side giver ÉN kilde', () => {
    const rows = ['navn', 'fødsel', 'dåb', 'død'].map(() => ({
      person_id: '841', work: 'DAA 2018-20', side: null,
    }));
    expect(buildProvenanceSources(rows)['841']).toHaveLength(1);
  });

  test('forskellige sider i samme værk er forskellige kilder', () => {
    const ud = buildProvenanceSources([
      { person_id: '5', work: 'DAA 1939', side: '578' },
      { person_id: '5', work: 'DAA 1939', side: '12' },
    ]);
    // Sorteret numerisk på side, så rækkefølgen er deterministisk — ikke indsættelsesorden.
    expect(ud['5']).toEqual([
      { work: 'DAA 1939', ref: 's. 12' },
      { work: 'DAA 1939', ref: 's. 578' },
    ]);
  });

  test('rækker uden værk springes over — ingen tom "Kilde"-boks', () => {
    expect(buildProvenanceSources([{ person_id: '7', work: null, side: '3' }])).toEqual({});
  });

  test('nøglen kanoniseres, så en samme_som-foldet person samler begge udgaver', () => {
    // Ada: 1690 (1939) er alias for 841 (2018-20). Begge skal ende under 841.
    const ud = buildProvenanceSources([
      { person_id: '841', work: 'DAA 2018-20', side: null },
      { person_id: '1690', work: 'DAA 1939', side: '578' },
    ], { '1690': '841' });
    expect(Object.keys(ud)).toEqual(['841']);
    expect(ud['841']).toEqual([
      { work: 'DAA 1939', ref: 's. 578' },
      { work: 'DAA 2018-20', ref: '' },
    ]);
  });

  test('tåler tomt input', () => {
    expect(buildProvenanceSources([])).toEqual({});
  });
});

describe('citationRowsTilProveniens', () => {
  const personAfAssertion = new Map([[4154, '841'], [7902, '1690']]);

  test('nestet source som OBJEKT (det PostgREST faktisk returnerer)', () => {
    expect(citationRowsTilProveniens(
      [{ assertion_id: 4154, side: null, source: { titel: 'DAA 2018-20', udgave: 'DAA 2018-20' } }],
      personAfAssertion,
    )).toEqual([{ person_id: '841', work: 'DAA 2018-20', side: null }]);
  });

  test('nestet source som ARRAY (det de genererede typer påstår)', () => {
    expect(citationRowsTilProveniens(
      [{ assertion_id: 7902, side: '578', source: [{ titel: 'DAA 1939', udgave: 'DAA 1939' }] }],
      personAfAssertion,
    )).toEqual([{ person_id: '1690', work: 'DAA 1939', side: '578' }]);
  });

  test('titel foretrækkes, udgave er faldback', () => {
    expect(citationRowsTilProveniens(
      [{ assertion_id: 4154, side: null, source: { titel: null, udgave: 'DAA 2018-20' } }],
      personAfAssertion,
    )[0].work).toBe('DAA 2018-20');
  });

  test('citation uden kendt assertion droppes — ingen kilde på en tom person', () => {
    expect(citationRowsTilProveniens(
      [{ assertion_id: 999, side: '1', source: { titel: 'DAA 1939', udgave: null } }],
      personAfAssertion,
    )).toEqual([]);
  });

  test('source helt fraværende giver work null (filtreres senere)', () => {
    expect(citationRowsTilProveniens(
      [{ assertion_id: 4154, side: null, source: null }],
      personAfAssertion,
    )).toEqual([{ person_id: '841', work: null, side: null }]);
  });
});

describe('citationRowsTilProveniens: trykt side', () => {
  const kilde = { titel: 'DAA 1939', udgave: null };
  const am = new Map<number | string, string>([[1, '7']]);
  it('side_trykt vinder, null giver kun værket, fravær falder tilbage til side', () => {
    expect(citationRowsTilProveniens([{ assertion_id: 1, side: '541', side_trykt: '52', source: kilde }], am)[0].side).toBe('52');
    expect(citationRowsTilProveniens([{ assertion_id: 1, side: '541', side_trykt: null, source: kilde }], am)[0].side).toBeNull();
    expect(citationRowsTilProveniens([{ assertion_id: 1, side: '541', source: kilde }], am)[0].side).toBe('541');
    expect(buildProvenanceSources(citationRowsTilProveniens([{ assertion_id: 1, side: '541', side_trykt: '52', source: kilde }], am))['7'])
      .toEqual([{ work: 'DAA 1939', ref: 's. 52' }]);
    expect(buildProvenanceSources(citationRowsTilProveniens([{ assertion_id: 1, side: '541', side_trykt: null, source: kilde }], am))['7'])
      .toEqual([{ work: 'DAA 1939', ref: '' }]);
  });
});

describe('flettKilder', () => {
  const bog: SourceRef[] = [{ work: 'DAA 2018-20', ref: 'Linje II, nr. 4' }];
  const evidens: SourceRef[] = [{ work: 'DAA 2018-20', ref: '' }];

  test('bog-nummeret vinder når det findes — faldbacket må ikke fortrænge det', () => {
    expect(flettKilder({ '4': bog }, { '4': evidens })).toEqual({ '4': bog });
  });

  test('faldbacket bruges kun hvor der intet bog-nummer er', () => {
    expect(flettKilder({}, { '841': evidens })).toEqual({ '841': evidens });
  });

  test('tom primær-liste tæller som fraværende', () => {
    expect(flettKilder({ '841': [] }, { '841': evidens })).toEqual({ '841': evidens });
  });

  test('personer der hverken har det ene eller det andet udelades', () => {
    expect(flettKilder({ '9': [] }, {})).toEqual({});
  });
});

describe('bogensNummer og optraederSom (6e-2)', () => {
  const conrad: Record<string, SourceRef[]> = {
    c: [
      { work: 'DAA 2018-20', ref: 'III. Linjen Gallentin, nr. 58', kort: 'III, nr. 58', personId: '255', sourceId: '1', aar: 2018, slaegtled: 12 },
      { work: 'DAA 2018-20', ref: 'V. Den grevelige linje af 1673, nr. 1', kort: 'V, nr. 1', personId: '392', sourceId: '1', aar: 2018, slaegtled: 1 },
      { work: 'DAA 1939', ref: 's. 52', kort: 's. 52', personId: '1198', sourceId: '3', aar: 1939, slaegtled: null },
    ],
  };
  test('nyeste udgave, derefter laveste slægtled', () => {
    expect(bogensNummer(conrad, 'c')).toBe('V, nr. 1');
  });
  test('slægtled lig → laveste personId numerisk; NULL slægtled sidst', () => {
    const r: Record<string, SourceRef[]> = { p: [
      { work: 'W', ref: 'x', kort: 'B', personId: '100', aar: 2018, slaegtled: 3 },
      { work: 'W', ref: 'x', kort: 'A', personId: '99', aar: 2018, slaegtled: 3 },
      { work: 'W', ref: 'x', kort: 'N', personId: '1', aar: 2018, slaegtled: null },
    ] };
    expect(bogensNummer(r, 'p')).toBe('A');
  });
  test('uden nye felter: dagens adfærd (første ref)', () => {
    expect(bogensNummer({ p: [{ work: 'W', ref: 'Linje V, nr. 1' }] }, 'p')).toBe('Linje V, nr. 1');
    expect(bogensNummer({ p: [{ work: 'W', ref: '' }] }, 'p')).toBeNull();
    expect(bogensNummer(undefined, 'p')).toBeNull();
  });
  test('tom kort i nyeste udgave falder videre til næste ref', () => {
    const r: Record<string, SourceRef[]> = { p: [
      { work: 'DAA 2018-20', ref: '', kort: '', personId: '1', aar: 2018, slaegtled: 1 },
      { work: 'DAA 1939', ref: 's. 52', kort: 's. 52', personId: '2', aar: 1939 },
    ] };
    expect(bogensNummer(r, 'p')).toBe('DAA 1939, s. 52');
  });
  test('et nummer, der kun er en side, får udgaven foran (M-3); linje eller nr. gør ikke', () => {
    const ref = (kort: string, udgave?: string): Record<string, SourceRef[]> =>
      ({ p: [{ work: 'Dansk Adels Aarbog – DAA 1939', udgave, ref: kort, kort, personId: '1', aar: 1939 }] });
    expect(bogensNummer(ref('s. 52', 'DAA 1939'), 'p')).toBe('DAA 1939, s. 52');
    expect(bogensNummer(ref('s. 52-53', 'DAA 1939'), 'p')).toBe('DAA 1939, s. 52-53');
    // Uden udgave: værket (ældre producent, fx mobilens buildAux).
    expect(bogensNummer(ref('s. 52'), 'p')).toBe('Dansk Adels Aarbog – DAA 1939, s. 52');
    expect(bogensNummer(ref('II, s. 52, nr. 4', 'DAA 1939'), 'p')).toBe('II, s. 52, nr. 4');
    expect(bogensNummer(ref('s. 52, nr. 4', 'DAA 1939'), 'p')).toBe('s. 52, nr. 4');
  });
  test('Optræder i Aarbogen som', () => {
    expect(optraederSom(conrad.c)).toBe('DAA 2018-20, V, nr. 1 og DAA 2018-20, III, nr. 58 og DAA 1939, s. 52');
    expect(optraederSom([{ work: 'DAA 1939', ref: '', kort: '' }])).toBe('DAA 1939');
  });
});
