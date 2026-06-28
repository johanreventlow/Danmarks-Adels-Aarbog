import { buildAux } from '../buildAux';
import type { RawExtId, RawLineage, RawSource } from '../types';

// --- Task 1: flade entitets-lister (2C-1) ---

const base = { extIds: [], sources: [], relations: [], estates: [], orgs: [], media: [], lineage: [], arms: [] };

test('buildAux: kildeListe fra sources (felt-map + sort)', () => {
  const aux = buildAux({ ...base, sources: [
    { id: 2, slags: 'kirkebog', titel: 'Øster', udgave: '1700', ekstern: null },
    { id: 1, slags: 'bog', titel: 'Aarbog', udgave: 'DAA 2018', ekstern: null },
  ] as never });
  expect(aux.kildeListe.map((k) => k.titel)).toEqual(['Aarbog', 'Øster']); // dansk sort, Ø sidst
  expect(aux.kildeListe[0]).toEqual({ id: '1', titel: 'Aarbog', slags: 'bog', udgave: 'DAA 2018' });
});

test('buildAux: vaabenListe fra arms (null-fallback + dansk-sorteret)', () => {
  const aux = buildAux({ ...base, arms: [
    { id: 5, blasonering: null, note: 'x' },
    { id: 6, blasonering: 'Ørn', note: '' },
    { id: 7, blasonering: 'Bjørn', note: '' },
  ] as never });
  expect(aux.vaabenListe[0]).toEqual({ id: '5', blasonering: '', note: 'x' }); // tom streng = mindst
  expect(aux.vaabenListe.map((v) => v.blasonering)).toEqual(['', 'Bjørn', 'Ørn']); // dansk sort: Ø sidst
});

test('buildAux: godsListe komplet (inkl. ejerløse) m. ownerCount', () => {
  const aux = buildAux({ ...base,
    estates: [{ id: 1, navn: 'Brahetrolleborg', slags: null }, { id: 2, navn: 'Ejerløs', slags: null }] as never,
    relations: [{ subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null }] as never,
  });
  const brahe = aux.godsListe.find((g) => g.id === '1');
  const ejerloes = aux.godsListe.find((g) => g.id === '2');
  expect(brahe?.ownerCount).toBe(1);
  expect(ejerloes?.ownerCount).toBe(0); // ejerløs gods er MED (modsat estateList)
});

test('buildAux: orgListe + medieListe felt-map', () => {
  const aux = buildAux({ ...base,
    orgs: [{ id: 1, navn: 'Hæren', slags: 'myndighed' }] as never,
    media: [{ id: 1, slags: 'foto', titel: 'Portræt', kunstner: 'NN', datering: '1900' }] as never });
  expect(aux.orgListe[0]).toEqual({ id: '1', navn: 'Hæren', slags: 'myndighed' });
  expect(aux.medieListe[0]).toEqual({ id: '1', titel: 'Portræt', slags: 'foto', kunstner: 'NN', datering: '1900' });
});

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
