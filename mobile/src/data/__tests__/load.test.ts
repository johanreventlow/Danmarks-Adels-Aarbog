import { mapAppPersons } from '../load';

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
