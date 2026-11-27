// #401 (review): fetchPresensNavneDele mod en lille hukommelses-database — låser, at kun afklarede, valgte
// fødenavn-påstande når født-klausulen (en omstridt med lavere conclusion-id må ikke vinde).

type Row = Record<string, unknown>;
const db: Record<string, Row[]> = {
  person: [
    { id: 1, visning_navn: 'Manden', visning_efternavn: 'Reventlow', koen: 'mand' },
    { id: 2, visning_navn: 'Anna Hansen', visning_efternavn: null, koen: 'kvinde' },
  ],
  family_member: [
    { family_id: 10, person_id: 1, rolle: 'partner' },
    { family_id: 10, person_id: 2, rolle: 'partner' },
  ],
  fact: [
    { id: 20, subjekt_type: 'person', subjekt_id: 1, faktatype: 'titel' },
    { id: 21, subjekt_type: 'person', subjekt_id: 2, faktatype: 'fødenavn' },
    { id: 22, subjekt_type: 'person', subjekt_id: 2, faktatype: 'fødenavn' },
  ],
  conclusion: [
    { id: 99, target_type: 'fact', target_id: 20, valgt_assertion_id: 199, status: 'afklaret' },
    { id: 100, target_type: 'fact', target_id: 21, valgt_assertion_id: 200, status: 'omstridt' },
    { id: 101, target_type: 'fact', target_id: 22, valgt_assertion_id: 201, status: 'afklaret' },
  ],
  assertion: [
    { id: 199, vaerdi_tekst: 'Greve' },
    { id: 200, vaerdi_tekst: 'Forkert' },
    { id: 201, vaerdi_tekst: 'Hansen' },
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

test('fetchPresensNavneDele: kun den afklarede fødenavn-påstand bruges, og pigenavnet står ikke dobbelt', async () => {
  const r = await fetchPresensNavneDele(['2'], new Set());
  expect(r['2']).toEqual({ navn: 'Anna', titel: 'Grevinde', efternavn: 'Reventlow', fodt: 'Hansen', tilgiftet: true });
});

test('skilt familie: ingen tilgiftet titel (heller ikke med ukendt skilsmisseopslag)', async () => {
  const skilt = await fetchPresensNavneDele(['2'], new Set(['10']));
  expect(skilt['2'].tilgiftet).toBeUndefined();
  expect(skilt['2'].titel).toBe('');
  const ukendt = await fetchPresensNavneDele(['2'], null);
  expect(ukendt['2'].tilgiftet).toBeUndefined();
  expect(ukendt['2'].titel).toBe('');
});

test('en anden skilt familie rammer ikke ægteskabet', async () => {
  const r = await fetchPresensNavneDele(['2'], new Set(['99']));
  expect(r['2'].tilgiftet).toBe(true);
});
