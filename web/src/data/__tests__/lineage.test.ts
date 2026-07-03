import { buildLineage } from '../lineage';
import type { RawExtId, RawLineage } from '../types';

const x = (person_id: string, linje: string | null, nr: number | null): RawExtId => ({
  person_id, source_id: '1', linje, nr,
});

const extIds: RawExtId[] = [
  x('10', 'I', 3),
  x('11', 'I', 1), // stamfader for I (laveste nr)
  x('12', 'I', 2),
  x('20', 'II', 5),
  x('21', 'II', 1), // stamfader for II
  x('30', 'III', null), // nr mangler → 9999
  x('99', null, 1), // ingen linje → ignoreres
];

const lineageRows: RawLineage[] = [
  { source_id: '1', kode: 'I', navn: 'Den holstenske linje' },
  { source_id: '1', kode: 'II', navn: 'Den danske linje' },
  // III mangler navn → fallback null
];

describe('buildLineage', () => {
  const r = buildLineage(extIds, lineageRows);

  test('byPerson mapper person → linje-kode; personer uden linje udelades', () => {
    expect(r.byPerson['10']).toEqual(['I']);
    expect(r.byPerson['21']).toEqual(['II']);
    expect(r.byPerson['99']).toBeUndefined();
  });

  test('samme_som-kanonisering: foldet grundlægger hører til flere linjer + head kanoniseres', () => {
    // III58 (linje III, nr 58) + V1 (linje V, nr 1) folder til V1.
    const ext: RawExtId[] = [x('III58', 'III', 58), x('V1', 'V', 1)];
    const rc = buildLineage(ext, [], { III58: 'V1' });
    expect(rc.byPerson['V1']?.sort()).toEqual(['III', 'V']);
    expect(rc.byPerson['III58']).toBeUndefined(); // alias-nøgle findes ikke
    expect(rc.list.find((l) => l.linje === 'III')?.headId).toBe('V1'); // head var alias → kanonisk
    expect(rc.list.find((l) => l.linje === 'III')?.count).toBe(1); // distinkt person, ikke ext-række
  });

  test('list er sorteret på kode med korrekt antal', () => {
    expect(r.list.map((l) => l.linje)).toEqual(['I', 'II', 'III']);
    expect(r.list.find((l) => l.linje === 'I')?.count).toBe(3);
    expect(r.list.find((l) => l.linje === 'II')?.count).toBe(2);
  });

  test('headId = medlemmet med laveste nr (stamfader)', () => {
    expect(r.list.find((l) => l.linje === 'I')?.headId).toBe('11');
    expect(r.list.find((l) => l.linje === 'II')?.headId).toBe('21');
  });

  test('manglende nr behandles som 9999 (bliver stamfader hvis eneste)', () => {
    expect(r.list.find((l) => l.linje === 'III')?.headId).toBe('30');
  });

  test('navn fra lineage-tabellen, fallback null når kode mangler navn', () => {
    expect(r.list.find((l) => l.linje === 'I')?.navn).toBe('Den holstenske linje');
    expect(r.list.find((l) => l.linje === 'III')?.navn).toBeNull();
  });

  test('tomme input → tom projektion (graceful)', () => {
    const empty = buildLineage([], []);
    expect(empty.list).toEqual([]);
    expect(empty.byPerson).toEqual({});
  });
});
