// "Sammenlign udgaver" (mobil): fetchMatchPersoner henter via RPC'en red_match_personer + linjerne,
// som web — ikke fem hele tabeller — og sender linjerne videre, så udenforMatchning sættes.
const mockRpc = jest.fn();
const mockFrom = jest.fn();
jest.mock('../../lib/supabase', () => ({ supabase: {
  rpc: (...args: unknown[]) => mockRpc(...args),
  from: (...args: unknown[]) => mockFrom(...args),
} }));

import { fetchLineages, fetchMatchPersoner } from '../redaktionRead';

// Kædbar PostgREST-attrap: alle filter-/ordensmetoder returnerer kæden; await giver resultatet.
function kaede(result: { data: unknown; error: unknown }) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'range']) q[m] = jest.fn(() => q);
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(result).then(res, rej);
  return q;
}

const LINJER = [
  { id: 1, source_id: 10, kode: 'I', navn: 'Den holstenske linje' },
  { id: 2, source_id: 10, kode: 'F', navn: 'Den fyenske linje' },
];

function opsaetFrom(grenResult: { data: unknown; error: unknown } = { data: [{ subjekt_id: 2 }], error: null }) {
  mockFrom.mockImplementation((tabel: string) => {
    if (tabel === 'lineage') return kaede({ data: LINJER, error: null });
    if (tabel === 'relation') return kaede(grenResult);
    throw new Error(`uventet tabel ${tabel}`);
  });
}

const RPC_DATA = {
  persons: [
    { id: 100, visning_navn: 'Conrad', koen: 'mand', staged: false },
    { id: 101, visning_navn: 'Frederik', koen: 'mand', staged: false },
  ],
  facts: [], concs: [], assertions: [],
  extIds: [
    { person_id: 100, source_id: 10, linje: 'I', nr: 1 },
    { person_id: 101, source_id: 10, linje: 'F', nr: 2 },
  ],
};

beforeEach(() => { mockRpc.mockReset(); mockFrom.mockReset(); });

describe('fetchLineages — source_id + udenforMatchning (spejl af web)', () => {
  it('markerer linjer med omstridt gren_af som udenfor matchning', async () => {
    opsaetFrom();
    const rows = await fetchLineages();
    expect(rows).toEqual([
      { ...LINJER[0], udenforMatchning: false },
      { ...LINJER[1], udenforMatchning: true },
    ]);
  });
  it('fejlet gren_af-opslag undtager ingen linjer (hellere for mange kandidater end datatab)', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    opsaetFrom({ data: null, error: { message: 'RLS' } });
    const rows = await fetchLineages();
    expect(rows.every((l) => l.udenforMatchning === false)).toBe(true);
    warn.mockRestore();
  });
});

describe('fetchMatchPersoner — RPC + linjer', () => {
  it('kalder red_match_personer (ikke fem tabeller) og sætter udenforMatchning via linjerne', async () => {
    opsaetFrom();
    mockRpc.mockResolvedValue({ data: RPC_DATA, error: null });
    const personer = await fetchMatchPersoner();
    expect(mockRpc).toHaveBeenCalledWith('red_match_personer');
    // Kun linje-opslagene rører tabeller — ingen person/fact/conclusion/assertion/person_external_id.
    expect(mockFrom.mock.calls.map((c) => c[0]).sort()).toEqual(['lineage', 'relation']);
    const byId = Object.fromEntries(personer.map((p) => [p.id, p]));
    expect(byId['100'].udenforMatchning).toBe(false);
    expect(byId['101'].udenforMatchning).toBe(true);
  });
  it('kaster ved RPC-fejl og ved tomt datasæt', async () => {
    opsaetFrom();
    mockRpc.mockResolvedValueOnce({ data: null, error: { message: 'permission denied' } });
    await expect(fetchMatchPersoner()).rejects.toThrow('permission denied');
    mockRpc.mockResolvedValueOnce({ data: null, error: null });
    await expect(fetchMatchPersoner()).rejects.toThrow(/intet datasæt/);
  });
});
