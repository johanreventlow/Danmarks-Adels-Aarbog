// #401 (review): fetchPresensNavneDele mod en lille hukommelses-database — låser, at kun afklarede, valgte
// fødenavn-påstande når født-klausulen (en omstridt med lavere conclusion-id må ikke vinde).
import { parSkilsmisse, type Model, type Skilsmisser } from '@daa/core';

type Row = Record<string, unknown>;
const db: Record<string, Row[]> = {
  person: [
    { id: 1, visning_navn: 'Manden', visning_efternavn: 'Reventlow', koen: 'mand' },
    { id: 2, visning_navn: 'Anna Hansen', visning_efternavn: null, koen: 'kvinde' },
    // Par i to familier (2018-20 nr. 40 og 1939-kopien nr. 41, hvor manden står under sit 1939-alias 6).
    { id: 4, visning_navn: 'Berta', visning_efternavn: null, koen: 'kvinde' },
    { id: 5, visning_navn: 'Carl', visning_efternavn: 'Reventlow', koen: 'mand' },
    { id: 6, visning_navn: 'Carl', visning_efternavn: 'Reventlow', koen: 'mand' },
    // Gengift: 7 er gift med 9 (nr. 50) og skilt fra 8 (nr. 51, sidst i family_id-orden).
    { id: 7, visning_navn: 'Dora', visning_efternavn: null, koen: 'kvinde' },
    { id: 8, visning_navn: 'Erik', visning_efternavn: 'Reventlow', koen: 'mand' },
    { id: 9, visning_navn: 'Frits', visning_efternavn: 'Reventlow', koen: 'mand' },
  ],
  family_member: [
    { family_id: 10, person_id: 1, rolle: 'partner' },
    { family_id: 10, person_id: 2, rolle: 'partner' },
    { family_id: 40, person_id: 4, rolle: 'partner' },
    { family_id: 40, person_id: 5, rolle: 'partner' },
    { family_id: 41, person_id: 4, rolle: 'partner' },
    { family_id: 41, person_id: 6, rolle: 'partner' },
    { family_id: 50, person_id: 7, rolle: 'partner' },
    { family_id: 50, person_id: 9, rolle: 'partner' },
    { family_id: 51, person_id: 7, rolle: 'partner' },
    { family_id: 51, person_id: 8, rolle: 'partner' },
  ],
  fact: [
    { id: 20, subjekt_type: 'person', subjekt_id: 1, faktatype: 'titel' },
    { id: 21, subjekt_type: 'person', subjekt_id: 2, faktatype: 'fødenavn' },
    { id: 22, subjekt_type: 'person', subjekt_id: 2, faktatype: 'fødenavn' },
    { id: 23, subjekt_type: 'person', subjekt_id: 5, faktatype: 'titel' },
    { id: 24, subjekt_type: 'person', subjekt_id: 8, faktatype: 'titel' },
    { id: 25, subjekt_type: 'person', subjekt_id: 9, faktatype: 'titel' },
    { id: 26, subjekt_type: 'person', subjekt_id: 6, faktatype: 'titel' },
  ],
  conclusion: [
    { id: 99, target_type: 'fact', target_id: 20, valgt_assertion_id: 199, status: 'afklaret' },
    { id: 100, target_type: 'fact', target_id: 21, valgt_assertion_id: 200, status: 'omstridt' },
    { id: 101, target_type: 'fact', target_id: 22, valgt_assertion_id: 201, status: 'afklaret' },
    { id: 102, target_type: 'fact', target_id: 23, valgt_assertion_id: 202, status: 'afklaret' },
    { id: 103, target_type: 'fact', target_id: 24, valgt_assertion_id: 203, status: 'afklaret' },
    { id: 104, target_type: 'fact', target_id: 25, valgt_assertion_id: 204, status: 'afklaret' },
    { id: 105, target_type: 'fact', target_id: 26, valgt_assertion_id: 202, status: 'afklaret' },
  ],
  assertion: [
    { id: 199, vaerdi_tekst: 'Greve' },
    { id: 200, vaerdi_tekst: 'Forkert' },
    { id: 201, vaerdi_tekst: 'Hansen' },
    { id: 202, vaerdi_tekst: 'Greve' },
    { id: 203, vaerdi_tekst: 'Greve' },
    { id: 204, vaerdi_tekst: 'Baron' },
  ],
};

function query(table: string) {
  const filtre: ((r: Row) => boolean)[] = [];
  const q = {
    select: () => q,
    eq: (k: string, v: unknown) => { filtre.push((r) => r[k] === v); return q; },
    in: (k: string, vs: unknown[]) => { filtre.push((r) => vs.map(String).includes(String(r[k]))); return q; },
    order: () => q,
    range: async (from: number, to: number) =>
      ({ data: (db[table] ?? []).filter((r) => filtre.every((f) => f(r))).slice(from, to + 1), error: null }),
  };
  return q;
}
jest.mock('../../lib/supabase', () => ({ supabase: { from: (t: string) => mockQuery(t) } }));
const mockQuery = (t: string) => query(t);
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { fetchPresensNavneDele } = require('../presens');

// Det ægte par-prædikat (som PresensView/praesens.tsx): parSkilsmisse over en lille model, hvis unions er familierne
// ovenfor; alias 6 er foldet ind i 5.
function erSkiltPar(skilsmisser: Skilsmisser | null) {
  const unionById: Record<string, { id: string; p1: string; p2: string | null; p2_name: null; year: null }> = {};
  for (const m of db.family_member) {
    const id = `f${m.family_id}`;
    const u = unionById[id];
    if (!u) unionById[id] = { id, p1: String(m.person_id), p2: null, p2_name: null, year: null };
    else u.p2 = String(m.person_id);
  }
  const model = { indexes: { unionById }, canonicalIdById: { '6': '5' }, skilsmisser } as unknown as Model;
  return skilsmisser == null ? null : (a: string, b: string) => parSkilsmisse(model, a, b) != null;
}
const skilteFam = (...fam: string[]): Skilsmisser => Object.fromEntries(fam.map((f) => [f, { dateMin: null, dateMax: null }]));

test('fetchPresensNavneDele: kun den afklarede fødenavn-påstand bruges, og pigenavnet står ikke dobbelt', async () => {
  const r = await fetchPresensNavneDele(['2'], erSkiltPar({}));
  expect(r['2']).toEqual({ navn: 'Anna', titel: 'Grevinde', efternavn: 'Reventlow', fodt: 'Hansen', tilgiftet: true });
});

test('skilt par: ingen tilgiftet titel (heller ikke med ukendt skilsmisseopslag)', async () => {
  const skilt = await fetchPresensNavneDele(['2'], erSkiltPar(skilteFam('10')));
  expect(skilt['2'].tilgiftet).toBeUndefined();
  expect(skilt['2'].titel).toBe('');
  const ukendt = await fetchPresensNavneDele(['2'], null);
  expect(ukendt['2'].tilgiftet).toBeUndefined();
  expect(ukendt['2'].titel).toBe('');
});

test('en anden skilt familie rammer ikke ægteskabet', async () => {
  const r = await fetchPresensNavneDele(['2'], erSkiltPar(skilteFam('99')));
  expect(r['2'].tilgiftet).toBe(true);
});

test('par i to familier, kun den ene skilt: ingen tilgiftet titel (heller ikke via den anden familie)', async () => {
  const r = await fetchPresensNavneDele(['4'], erSkiltPar(skilteFam('41')));
  expect(r['4'].tilgiftet).toBeUndefined();
  expect(r['4'].titel).toBe('');
  const omvendt = await fetchPresensNavneDele(['4'], erSkiltPar(skilteFam('40')));
  expect(omvendt['4'].tilgiftet).toBeUndefined();
  const gift = await fetchPresensNavneDele(['4'], erSkiltPar({}));
  expect(gift['4'].tilgiftet).toBe(true);
  expect(gift['4'].titel).toBe('Grevinde');
});

test('gengift: skilt fra den ene, gift med den anden giver den nuværende ægtefælles titel', async () => {
  const r = await fetchPresensNavneDele(['7'], erSkiltPar(skilteFam('51')));
  expect(r['7'].tilgiftet).toBe(true);
  expect(r['7'].titel).toBe('Baronesse');
});

test('kun skilt: ingen tilgiftet titel', async () => {
  const r = await fetchPresensNavneDele(['7'], erSkiltPar(skilteFam('50', '51')));
  expect(r['7'].tilgiftet).toBeUndefined();
  expect(r['7'].titel).toBe('');
});
