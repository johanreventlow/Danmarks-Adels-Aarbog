import { test, expect } from 'vitest';
import { buildGeo, EMPTY_GEO } from '../buildGeo';
import type { AppPerson, RawEstate, RawFact, RawPlace, Union } from '../types';

// Hjælpere ---------------------------------------------------------------
const person = (id: string, born: number | null = null, died: number | null = null): AppPerson => ({
  id,
  name: 'P' + id,
  born,
  died,
  years: '',
  title: '',
  bio: '',
  privat: false,
});
const base = {
  facts: [] as RawFact[],
  estates: [] as RawEstate[],
  places: [] as RawPlace[],
  persons: [] as AppPerson[],
  unions: [] as Union[],
};
// To kendte steder MED koordinater + ét uden (skal filtreres fra).
const places: RawPlace[] = [
  { id: 1, navn: 'Christianssæde', lat: 54.86, lon: 11.28 },
  { id: 2, navn: 'København', lat: 55.68, lon: 12.57 },
  { id: 3, navn: 'Uberiget sted', lat: null, lon: null },
];

test('buildGeo: gods-punkt fra estate.sted_id (byEstate + points)', () => {
  const geo = buildGeo({
    ...base,
    places,
    estates: [{ id: 10, navn: 'Christianssæde', slags: 'gods', sted_id: 1 }],
  });
  expect(geo.points).toHaveLength(1);
  expect(geo.byEstate['10']).toMatchObject({
    kind: 'estate',
    estateId: '10',
    navn: 'Christianssæde',
    lat: 54.86,
    lon: 11.28,
    personId: null,
  });
});

test('buildGeo: koordinatløst sted filtreres fra (uberiget)', () => {
  const geo = buildGeo({
    ...base,
    places,
    estates: [{ id: 11, navn: 'Ukendt', slags: 'gods', sted_id: 3 }], // sted 3 mangler lat/lon
  });
  expect(geo.points).toHaveLength(0);
  expect(geo.byEstate['11']).toBeUndefined();
});

test('buildGeo: fødsel/død-punkter på person med år fra born/died; ikke-geo-fakta ignoreres', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [person('p1', 1644, 1708)],
    facts: [
      { subjekt_type: 'person', subjekt_id: 'p1', faktatype: 'fødsel', sted_id: 1 },
      { subjekt_type: 'person', subjekt_id: 'p1', faktatype: 'død', sted_id: 2 },
      { subjekt_type: 'person', subjekt_id: 'p1', faktatype: 'titel', sted_id: 2 }, // ikke geo-type
    ],
  });
  const kinds = geo.byPerson['p1'].map((pt) => pt.kind).sort();
  expect(kinds).toEqual(['død', 'fødsel']);
  const fodsel = geo.byPerson['p1'].find((pt) => pt.kind === 'fødsel');
  const dod = geo.byPerson['p1'].find((pt) => pt.kind === 'død');
  expect(fodsel).toMatchObject({ year: 1644, navn: 'Christianssæde', personId: 'p1' });
  expect(dod).toMatchObject({ year: 1708, navn: 'København' });
});

test('buildGeo: RLS — fakta for person UDEN for synlig db.persons giver intet punkt', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [person('p1')], // p2 (privat/filtreret) er IKKE med
    facts: [{ subjekt_type: 'person', subjekt_id: 'p2', faktatype: 'fødsel', sted_id: 1 }],
  });
  expect(geo.points).toHaveLength(0);
  expect(geo.byPerson['p2']).toBeUndefined();
});

test('buildGeo: samme_som-collapse — alias-fakta havner på kanonisk person', () => {
  const geo = buildGeo(
    {
      ...base,
      places,
      persons: [person('canon', 1644)],
      facts: [{ subjekt_type: 'person', subjekt_id: 'alias', faktatype: 'fødsel', sted_id: 1 }],
    },
    { alias: 'canon' }, // canonicalIdById
  );
  expect(geo.byPerson['canon']).toHaveLength(1);
  expect(geo.byPerson['canon'][0]).toMatchObject({ personId: 'canon', year: 1644 });
  expect(geo.byPerson['alias']).toBeUndefined();
});

test('buildGeo: vielse (family-fakta) indekseres på begge synlige partnere', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [person('a'), person('b')],
    unions: [{ id: 'f7', p1: 'a', p2: 'b', p2_name: null, year: 1670 }],
    facts: [{ subjekt_type: 'family', subjekt_id: '7', faktatype: 'vielse', sted_id: 2 }],
  });
  expect(geo.points).toHaveLength(1);
  expect(geo.points[0]).toMatchObject({ kind: 'vielse', unionId: 'f7', year: 1670, personId: null });
  expect(geo.byPerson['a'][0].kind).toBe('vielse');
  expect(geo.byPerson['b'][0].kind).toBe('vielse');
});

test('buildGeo: vielse — begge partnere private → intet punkt (RLS, ingen læk i points)', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [], // både a og b er private/filtreret fra
    unions: [{ id: 'f7', p1: 'a', p2: 'b', p2_name: null, year: null }],
    facts: [{ subjekt_type: 'family', subjekt_id: '7', faktatype: 'vielse', sted_id: 2 }],
  });
  expect(geo.points).toHaveLength(0);
  expect(geo.byPerson['a']).toBeUndefined();
  expect(geo.byPerson['b']).toBeUndefined();
});

test('buildGeo: vielse — p1===p2 (foldet til én person) afdupliceres i byPerson', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [person('a')],
    unions: [{ id: 'f7', p1: 'a', p2: 'a', p2_name: null, year: null }],
    facts: [{ subjekt_type: 'family', subjekt_id: '7', faktatype: 'vielse', sted_id: 2 }],
  });
  expect(geo.points).toHaveLength(1);
  expect(geo.byPerson['a']).toHaveLength(1); // ikke 2
});

test('buildGeo: vielse — usynlig partner udelades af byPerson, men punktet består', () => {
  const geo = buildGeo({
    ...base,
    places,
    persons: [person('a')], // b er privat/filtreret
    unions: [{ id: 'f7', p1: 'a', p2: 'b', p2_name: null, year: null }],
    facts: [{ subjekt_type: 'family', subjekt_id: '7', faktatype: 'vielse', sted_id: 2 }],
  });
  expect(geo.points).toHaveLength(1);
  expect(geo.byPerson['a']).toHaveLength(1);
  expect(geo.byPerson['b']).toBeUndefined();
});

test('buildGeo: EMPTY_GEO er tomt', () => {
  expect(EMPTY_GEO.points).toHaveLength(0);
  expect(Object.keys(EMPTY_GEO.byPerson)).toHaveLength(0);
  expect(Object.keys(EMPTY_GEO.byEstate)).toHaveLength(0);
});
