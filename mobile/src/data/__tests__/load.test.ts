import { compareParentOrder, mapAppPersons } from '../load';

const RAW = [
  { id: 1, visning_navn: 'Conrad', visning_foedt: '1644', visning_doed: '1708', visning_titel: 'greve', privat: false },
  { id: 2, visning_navn: 'Levende', visning_foedt: '1980', visning_doed: null, visning_titel: '', privat: true },
];

test('mapAppPersons: includePrivat=false filtrerer private fra', () => {
  const r = mapAppPersons(RAW as never, {}, false);
  expect(r.map((p) => p.id)).toEqual(['1']);
});

test('mapAppPersons: includePrivat=true beholder private + sætter privat-flag', () => {
  const r = mapAppPersons(RAW as never, {}, true);
  expect(r.map((p) => p.id)).toEqual(['1', '2']);
  expect(r.find((p) => p.id === '2')?.privat).toBe(true);
  expect(r.find((p) => p.id === '1')?.privat).toBe(false);
});

test('mapAppPersons: bio fra bioBy, navn-fallback', () => {
  const r = mapAppPersons([{ id: 3, visning_navn: null, visning_foedt: null, visning_doed: null, visning_titel: null, privat: false }] as never,
    { '3': 'En biografi' }, false);
  expect(r[0]).toMatchObject({ id: '3', name: '(uden navn)', bio: 'En biografi', privat: false });
});

// Regressionstest for brugerfund 2026-07-01: to forældre med SAMME ordinal (begge i deres
// eget 1. ægteskab) viste mor i stedet for far i stamtræets forælder-slot, fordi ordinal
// (ægteskabs-nummer) blev brugt som far/mor-markør. compareParentOrder skal rangere far
// (koen='mand') før mor uafhængigt af ordinal.
test('compareParentOrder: far før mor selv med identisk ordinal (Christian Ditlev Ludvig-sagen)', () => {
  const koenById = { '887': 'kvinde', '457': 'mand' };
  const mor = { person_id: 887, ordinal: 1 };
  const far = { person_id: 457, ordinal: 1 };
  const sorted = [mor, far].sort((a, b) => compareParentOrder(a, b, koenById));
  expect(sorted.map((p) => p.person_id)).toEqual([457, 887]);
});

test('compareParentOrder: falder tilbage til ordinal ved samme/ukendt køn', () => {
  const koenById: Record<string, string | null> = {};
  const a = { person_id: 1, ordinal: 2 };
  const b = { person_id: 2, ordinal: 1 };
  const sorted = [a, b].sort((x, y) => compareParentOrder(x, y, koenById));
  expect(sorted.map((p) => p.person_id)).toEqual([2, 1]);
});

test('compareParentOrder: mand rangeres altid før kvinde, uanset ordinal-rækkefølge', () => {
  const koenById = { '1': 'kvinde', '2': 'mand' };
  const kvinde = { person_id: 1, ordinal: 1 };
  const mand = { person_id: 2, ordinal: 5 };
  const sorted = [kvinde, mand].sort((a, b) => compareParentOrder(a, b, koenById));
  expect(sorted.map((p) => p.person_id)).toEqual([2, 1]);
});
