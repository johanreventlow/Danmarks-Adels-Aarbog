import { buildSources } from '../sources';
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
    expect(r['10']).toEqual([{ work: 'Danmarks Adels Aarbog 1913', ref: 'Linje III, nr. 103' }]);
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
