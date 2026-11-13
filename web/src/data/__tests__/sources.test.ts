import { buildSources } from '../sources';
import { stamtavleSkemaOpslag } from '../lineage';
import type { RawExtId, RawSource } from '../types';

const x = (person_id: string, source_id: string, linje: string | null, nr: number | null): RawExtId => ({
  person_id, source_id, linje, nr,
});
const src = (id: string, titel: string | null, udgave: string | null = null): RawSource => ({
  id, slags: 'trykt værk', titel, udgave, ekstern: null,
});

const sources: RawSource[] = [
  src('1', 'Danmarks Adels Aarbog 1913'),
  src('2', null, 'DAA 2018-20'), // ingen titel → falder tilbage til udgave
];

describe('buildSources', () => {
  test('kobler person → værk + "Linje X, nr. N"', () => {
    const r = buildSources([x('10', '1', 'III', 103)], sources);
    expect(r['10']).toMatchObject([{ work: 'Danmarks Adels Aarbog 1913', ref: 'Linje III, nr. 103' }]);
  });

  test('værk falder tilbage til udgave, så "Kilde" hvis begge mangler', () => {
    const r = buildSources([x('10', '2', 'I', 1), x('11', '999', 'II', 2)], sources);
    expect(r['10'][0].work).toBe('DAA 2018-20');
    expect(r['11'][0].work).toBe('Kilde'); // ukendt source_id
  });

  test('ref udelader manglende linje/nr', () => {
    expect(buildSources([x('10', '1', null, 5)], sources)['10'][0].ref).toBe('nr. 5');
    expect(buildSources([x('10', '1', 'I', null)], sources)['10'][0].ref).toBe('Linje I');
    expect(buildSources([x('10', '1', null, null)], sources)['10'][0].ref).toBe('');
  });

  test('flere kilder pr. person samles', () => {
    const r = buildSources([x('10', '1', 'I', 1), x('10', '2', 'II', 9)], sources);
    expect(r['10']).toHaveLength(2);
  });

  test('tomme input → tomt', () => {
    expect(buildSources([], [])).toEqual({});
  });
});

describe('buildSources med skemaopslag (6e-2)', () => {
  const srcs: RawSource[] = [src('1', 'DAA 2018-20'), src('3', 'DAA 1939')];
  const skema = stamtavleSkemaOpslag({
    schemes: [
      { id: 10, slaegt_id: 1, source_id: 1, kind: 'stamtavle' },
      { id: 11, slaegt_id: 1, source_id: 1, kind: 'presensliste' },
      { id: 30, slaegt_id: 1, source_id: 3, kind: 'stamtavle' },
    ],
    entries: [
      { id: 1, scheme_id: 10, code: 'V', label: 'Den grevelige linje af 1673' },
      { id: 2, scheme_id: 11, code: 'V', label: 'Presens-etiket' },
      { id: 3, scheme_id: 30, code: 'IV', label: 'IV. Den danske grevelige Linje af 1673.' },
    ],
    mappings: [],
  });
  const e = (person_id: string, source_id: string, linje: string | null, nr: number | null, trykt_side: string | null = null, slaegtled_lokal: number | null = null): RawExtId =>
    ({ person_id, source_id, linje, nr, trykt_side, slaegtled_lokal });

  test('kilde 3 med side', () => {
    const r = buildSources([e('1', '3', 'IV', 3, '49')], srcs, {}, skema)['1'][0];
    expect(r.ref).toBe('IV. Den danske grevelige Linje af 1673, s. 49, nr. 3');
    expect(r.kort).toBe('IV, s. 49, nr. 3');
  });
  test('kilde 1 uden side; presensliste-skema ignoreres', () => {
    const r = buildSources([e('1', '1', 'V', 1, null, 1)], srcs, {}, skema)['1'][0];
    expect(r.ref).toBe('V. Den grevelige linje af 1673, nr. 1');
    expect(r.kort).toBe('V, nr. 1');
    expect(r.slaegtled).toBe(1);
  });
  test('legacy-kode uden for skemaet: kun side', () => {
    expect(buildSources([e('1', '3', '1939', 275, '52')], srcs, {}, skema)['1'][0]).toMatchObject({ ref: 's. 52', kort: 's. 52' });
    expect(buildSources([e('1', '3', '1939', 275)], srcs, {}, skema)['1'][0]).toMatchObject({ ref: '', kort: '' });
    expect(buildSources([e('1', '3', null, null)], srcs, {}, skema)['1'][0].ref).toBe('');
  });
  test('uden skema: dagens form', () => {
    expect(buildSources([e('1', '1', 'V', 1)], srcs)['1'][0].ref).toBe('Linje V, nr. 1');
  });

  test('tom skemaliste → dagens form for kilde 1 og 3', () => {
    const tom = stamtavleSkemaOpslag({ schemes: [], entries: [], mappings: [] });
    const r1 = buildSources([e('1', '1', 'V', 1)], srcs, {}, tom)['1'][0];
    expect(r1).toMatchObject({ ref: 'Linje V, nr. 1', kort: 'Linje V, nr. 1' });
    expect(buildSources([e('2', '3', '1939', 275, '52')], srcs, {}, tom)['2'][0].ref).toBe('Linje 1939, nr. 275');
  });
  test('kilde uden stamtavleindgange men med presensindgang → dagens form', () => {
    const kunPresens = stamtavleSkemaOpslag({
      schemes: [{ id: 11, slaegt_id: 1, source_id: 1, kind: 'presensliste' }],
      entries: [{ id: 2, scheme_id: 11, code: 'V', label: 'Presens-etiket' }],
      mappings: [],
    });
    expect(buildSources([e('1', '1', 'V', 1)], srcs, {}, kunPresens)['1'][0].ref).toBe('Linje V, nr. 1');
  });
  test('kode mangler i et ellers udfyldt skema → kun side', () => {
    expect(buildSources([e('1', '1', 'XX', 5, '7')], srcs, {}, skema)['1'][0]).toMatchObject({ ref: 's. 7', kort: 's. 7' });
  });
});
