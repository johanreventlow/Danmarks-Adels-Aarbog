import { buildModel } from '@daa/core';
import { compareParentOrder, mapAppPersons, mapPublicBioVersionsByPersonV2 } from '../load';

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

test('mapAppPersons: floruit giver Nævnes når livsdatoer mangler, ellers ikke', () => {
  const raw = [
    { id: 5, visning_navn: 'A', visning_foedt: null, visning_doed: null, visning_floruit: '1349–1391', visning_titel: null, privat: false },
    { id: 6, visning_navn: 'B', visning_foedt: '1644', visning_doed: null, visning_floruit: null, visning_titel: null, privat: false },
  ];
  const r = mapAppPersons(raw as never, {}, false);
  expect(r[0]).toMatchObject({ years: 'Nævnes 1349–1391', floruit: '1349–1391', born: null });
  expect(r[1].years).not.toContain('Nævnes');
  expect(r[1].floruit).toBeNull();
});

test('mapAppPersons: bio fra bioBy, navn-fallback', () => {
  const r = mapAppPersons([{ id: 3, visning_navn: null, visning_foedt: null, visning_doed: null, visning_titel: null, privat: false }] as never,
    { '3': 'En biografi' }, false);
  expect(r[0]).toMatchObject({ id: '3', name: '(uden navn)', bio: 'En biografi', privat: false });
});

test('mapAppPersons: barn uden navn vises som »Unavngivet barn« (#388), andre beholder »(uden navn)«', () => {
  const raw = [3, 4].map((id) => ({ id, visning_navn: null, visning_foedt: null, visning_doed: null, visning_titel: null, privat: false }));
  const r = mapAppPersons(raw as never, {}, false, new Set(['3']));
  expect(r.map((p) => p.name)).toEqual(['Unavngivet barn', '(uden navn)']);
});

test('mapPublicBioVersionsByPersonV2: vælger den første bundne eventtekst uden direkte narrativ-fallback', () => {
  expect(mapPublicBioVersionsByPersonV2([
    { person_id: 1, source_id: 9, source_year: 1939, record_order: 2, source_record_ref: 's2', source_label: 'DAA', record_label: 'Post 2', narrative_text: 'Anden post', citation_label: '', provenance_kind: 'source_record' },
    { person_id: 1, source_id: 9, source_year: 1939, record_order: 1, source_record_ref: 's1', source_label: 'DAA', record_label: 'Post 1', narrative_text: 'Første post', citation_label: '', provenance_kind: 'source_record' },
    { person_id: 2, source_id: 1, source_year: 2012, record_order: null, source_record_ref: null, source_label: 'DAA', record_label: 'Overgangsdata', narrative_text: 'Legacy', citation_label: '', provenance_kind: 'legacy_narrative' },
    { person_id: 3, source_id: 3, source_year: 2020, record_order: null, source_record_ref: null, source_label: 'DAA', record_label: 'Overgangsdata', narrative_text: 'Ny legacy-alias', citation_label: '', provenance_kind: 'legacy_narrative' },
    { person_id: 4, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'bound-alias', source_label: 'DAA', record_label: 'Post 1', narrative_text: 'Bundet alias-post', citation_label: '', provenance_kind: 'source_record' },
  ], { '1': '10', '3': '20', '4': '20' })).toEqual({ '10': 'Første post', '2': 'Legacy', '20': 'Bundet alias-post' });
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

test('mapAppPersons: årsspænd sættes, så buildModel beholder forældrelink når dødsåret er et spænd († 1570/1580)', () => {
  const raw = [
    { id: 1, visning_navn: 'Far', visning_foedt: '1540', visning_doed: '† 1570/1580', visning_titel: '', privat: false },
    { id: 2, visning_navn: 'Barn', visning_foedt: '1580', visning_doed: null, visning_titel: '', privat: false },
  ];
  const persons = mapAppPersons(raw as never, {}, false);
  expect(persons[0].doedSpaend).toEqual([1570, 1580]);
  expect(persons[0].foedtSpaend).toEqual([1540, 1540]);
  const db = { persons, unions: [], parentChild: [{ parent: '1', child: '2', union: 'u1' }] };
  expect(buildModel(db as never).indexes.parentsByChild['2']).toEqual(['1']);
  // uden spænd (punktår = første årstal) droppes linket: det var fejlen
  const punkt = persons.map((p) => ({ ...p, foedtSpaend: undefined, doedSpaend: undefined }));
  expect(buildModel({ ...db, persons: punkt } as never).indexes.parentsByChild['2'] ?? []).toHaveLength(0);
});
