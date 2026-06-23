import { buildAux } from '../buildAux';
import type { RawExtId, RawLineage, RawSource } from '../types';

describe('buildAux — linje-stamfader = laveste nr (§9.2 kritisk path)', () => {
  const extIds: RawExtId[] = [
    { person_id: 10, source_id: 1, linje: 'I', nr: 5 },
    { person_id: 11, source_id: 1, linje: 'I', nr: 2 }, // laveste i I → stamfader
    { person_id: 12, source_id: 1, linje: 'I', nr: 9 },
    { person_id: 20, source_id: 1, linje: 'V', nr: 3 },
    { person_id: 21, source_id: 1, linje: 'V', nr: 1 }, // laveste i V → stamfader
  ];
  const aux = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [] });

  test('linjeList har én entry pr. linje, sorteret', () => {
    expect(aux.linjeList.map((l) => l.linje)).toEqual(['I', 'V']);
  });

  test('headId peger på personen med laveste nr', () => {
    const I = aux.linjeList.find((l) => l.linje === 'I');
    const V = aux.linjeList.find((l) => l.linje === 'V');
    expect(I?.headId).toBe('11');
    expect(V?.headId).toBe('21');
  });

  test('count tæller medlemmer pr. linje', () => {
    expect(aux.linjeList.find((l) => l.linje === 'I')?.count).toBe(3);
  });

  test('linjeByPerson mapper person → linje (som streng-id)', () => {
    expect(aux.linjeByPerson['11']).toBe('I');
    expect(aux.linjeByPerson['21']).toBe('V');
  });
});

describe('buildAux — linje-navne fra lineage', () => {
  const extIds: RawExtId[] = [
    { person_id: 10, source_id: 1, linje: 'I', nr: 1 },
    { person_id: 20, source_id: 1, linje: 'V', nr: 1 },
    { person_id: 30, source_id: 1, linje: 'III', nr: 1 }, // ingen lineage-række → fallback
  ];
  const lineage: RawLineage[] = [
    { source_id: 1, kode: 'I', navn: 'Den holstenske linje' },
    { source_id: 1, kode: 'V', navn: 'Den grevelige linje af 1673' },
  ];
  const aux = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [], lineage });

  test('linjeNavn mapper kode → navn', () => {
    expect(aux.linjeNavn['I']).toBe('Den holstenske linje');
    expect(aux.linjeNavn['V']).toBe('Den grevelige linje af 1673');
  });

  test('linjeList bærer navn; manglende lineage → navn null (UI falder tilbage til kode)', () => {
    expect(aux.linjeList.find((l) => l.linje === 'I')?.navn).toBe('Den holstenske linje');
    expect(aux.linjeList.find((l) => l.linje === 'III')?.navn).toBeNull();
  });

  test('uden lineage-arg → alle navne null (bagudkompatibel)', () => {
    const a2 = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [] });
    expect(a2.linjeNavn).toEqual({});
    expect(a2.linjeList.every((l) => l.navn === null)).toBe(true);
  });
});

describe('buildAux — kilder ("Linje X, nr. N" + trykt værk)', () => {
  const extIds: RawExtId[] = [{ person_id: 7, source_id: 1, linje: 'II', nr: 4 }];
  const sources: RawSource[] = [
    { id: 1, slags: 'bog', titel: 'Danmarks Adels Aarbog', udgave: null, ekstern: null },
  ];
  const aux = buildAux({ extIds, sources, relations: [], estates: [], orgs: [], media: [] });

  test('kilde-reference komponeres', () => {
    expect(aux.sourcesBy['7']).toEqual([{ ref: 'Linje II, nr. 4', work: 'Danmarks Adels Aarbog' }]);
  });
});
