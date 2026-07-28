import { describe, expect, test } from 'vitest';
import { buildProvenanceSources, citationRowsTilProveniens, flettKilder } from '../kildeProveniens';
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
