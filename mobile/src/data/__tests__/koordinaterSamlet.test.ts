// Kodereview 36 P2: loadFromSupabase henter koordinaterne i ÉT kald (public_person_source_coordinates_samlet) og
// falder kun tilbage til den offset-paginerede rækkefunktion, når den nye funktion ikke findes endnu (PGRST202).
type Svar = { data: unknown; error: unknown };
const mockRpcKald: { fn: string; range?: [number, number] }[] = [];
const mockTilstand: { samlet: Svar; sider: unknown[][] } = { samlet: { data: [], error: null }, sider: [] };
const mockKoord = {
  person_id: 1, source_id: 1, legacy_line_code: 'I', printed_number: 15, printed_number_label: '15a',
  generation_local: 3, generation_global: 7, kuld_label: null, provenance_kind: 'placement', printed_page: null,
};
const mockTabeller: Record<string, unknown[]> = {
  person: [{ id: 1, visning_navn: 'A', visning_fuldt_navn: 'A', visning_foedt: null, visning_doed: null, visning_titel: null, koen: 'mand', privat: false }],
};

function mockKaede(rows: unknown[]) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'is', 'maybeSingle']) q[m] = () => q;
  q.range = async (a: number, b: number) => ({ data: rows.slice(a, b + 1), error: null });
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve({ data: rows, error: null }).then(res, rej);
  return q;
}

jest.mock('../../lib/supabase', () => ({
  supabaseEnabled: true,
  supabase: {
    from: (t: string) => mockKaede(mockTabeller[t] ?? []),
    rpc: (fn: string) => {
      if (fn === 'public_person_source_coordinates_samlet') {
        mockRpcKald.push({ fn });
        return { then: (res: (v: Svar) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(mockTilstand.samlet).then(res, rej) };
      }
      if (fn === 'public_person_source_coordinates') {
        let side = 0;
        return {
          range: async (a: number, b: number) => {
            mockRpcKald.push({ fn, range: [a, b] });
            return { data: mockTilstand.sider[side++] ?? [], error: null };
          },
        };
      }
      if (fn === 'narrative_record_contract_version') {
        return { then: (res: (v: Svar) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve({ data: 2, error: null }).then(res, rej) };
      }
      return mockKaede([]);
    },
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
    storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
  },
}));

import { loadFromSupabase } from '../load';

beforeEach(() => {
  mockRpcKald.length = 0;
  mockTilstand.samlet = { data: [], error: null };
  mockTilstand.sider = [];
});

const koordKald = () => mockRpcKald.filter((k) => k.fn.startsWith('public_person_source_coordinates'));

test('ét kald til den samlede funktion; rækkefunktionen kaldes ikke', async () => {
  mockTilstand.samlet = { data: [mockKoord], error: null };
  const res = await loadFromSupabase({ includePrivat: true, collapse: false });
  expect(koordKald()).toEqual([{ fn: 'public_person_source_coordinates_samlet' }]);
  expect(res.genCoordsByPerson['1']).toBeDefined();
});

test('falder tilbage til rækkefunktionen via sider, når den samlede ikke findes (PGRST202)', async () => {
  mockTilstand.samlet = { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } };
  mockTilstand.sider = [[mockKoord]];
  const res = await loadFromSupabase({ includePrivat: true, collapse: false });
  expect(koordKald()).toEqual([
    { fn: 'public_person_source_coordinates_samlet' },
    { fn: 'public_person_source_coordinates', range: [0, 999] },
  ]);
  expect(res.genCoordsByPerson['1']).toBeDefined();
});

test('andre fejl prøves igen én gang og degraderer så til ingen koordinater uden fallback', async () => {
  const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
  mockTilstand.samlet = { data: null, error: { code: '57014', message: 'timeout' } };
  const res = await loadFromSupabase({ includePrivat: true, collapse: false });
  warn.mockRestore();
  expect(koordKald()).toEqual([
    { fn: 'public_person_source_coordinates_samlet' },
    { fn: 'public_person_source_coordinates_samlet' },
  ]);
  expect(res.genCoordsByPerson['1']).toBeUndefined();
});

test('et 57014 på første kald redder sig på genforsøget (prod 25/11, kold start)', async () => {
  const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
  const fejl = { data: null, error: { code: '57014', message: 'timeout' } };
  const ok = { data: [mockKoord], error: null };
  let n = 0;
  Object.defineProperty(mockTilstand, 'samlet', { configurable: true, get: () => (n++ === 0 ? fejl : ok), set: () => {} });
  const res = await loadFromSupabase({ includePrivat: true, collapse: false });
  warn.mockRestore();
  delete (mockTilstand as { samlet?: unknown }).samlet;
  expect(koordKald()).toHaveLength(2);
  expect(res.genCoordsByPerson['1']).toBeDefined();
});
