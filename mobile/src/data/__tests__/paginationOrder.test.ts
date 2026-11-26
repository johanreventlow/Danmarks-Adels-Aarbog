// Offset-paginering (getAll) kræver fast rækkefølge på en ENTYDIG nøgle — ellers kan rækker
// springes over/gentages mellem siderne. Optag de byggede forespørgsler og tjek .order(...).
type Kald = { tabel: string; metoder: [string, unknown[]][] };
const mockOptaget: Kald[] = [];

function mockKaede(tabel: string) {
  const kald: Kald = { tabel, metoder: [] };
  mockOptaget.push(kald);
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'range', 'is', 'maybeSingle']) {
    q[m] = (...a: unknown[]) => { kald.metoder.push([m, a]); return q; };
  }
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) =>
    Promise.resolve({ data: [], error: null }).then(res, rej);
  return q;
}

jest.mock('../../lib/supabase', () => ({
  supabaseEnabled: true,
  supabase: {
    from: (t: string) => mockKaede(t),
    rpc: (fn: string) => mockKaede(`rpc:${fn}`),
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
    storage: { from: () => ({ createSignedUrls: async () => ({ data: [], error: null }) }) },
  },
}));

import { fetchRedaktionPersoner } from '../redaktionRead';
import { fetchPresensGrundlag } from '../presens';
import { loadFromSupabase } from '../load';

const orden = (k: Kald) => k.metoder.filter(([m]) => m === 'order').map(([, a]) => a[0]);
const forTabel = (t: string, select?: string) =>
  mockOptaget.filter((k) => k.tabel === t && (select == null || k.metoder.some(([m, a]) => m === 'select' && a[0] === select)));

beforeEach(() => { mockOptaget.length = 0; });

test('fetchRedaktionPersoner sorterer person på id', async () => {
  await fetchRedaktionPersoner();
  const [k] = forTabel('person');
  expect(orden(k)).toEqual(['id']);
});

test('fetchPresensGrundlag sorterer person på id', async () => {
  await fetchPresensGrundlag();
  const [k] = forTabel('person');
  expect(orden(k)).toEqual(['id']);
});

test('loadFromSupabase: person og family_member sorteres på entydig nøgle; RPC uden .order', async () => {
  const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
  await loadFromSupabase({ includePrivat: true, collapse: false }).catch(() => undefined);
  warn.mockRestore();
  const person = forTabel('person', 'id,visning_navn,visning_fuldt_navn,visning_foedt,visning_doed,visning_floruit,visning_titel,koen,privat,levende');
  expect(person.length).toBeGreaterThan(0);
  expect(orden(person[0])).toEqual(['id']);
  const fm = forTabel('family_member', 'family_id,person_id,rolle,ordinal,konfidens');
  expect(fm.length).toBeGreaterThan(0);
  expect(orden(fm[0])).toEqual(['family_id', 'person_id', 'rolle']);
  for (const k of forTabel('rpc:public_person_source_coordinates')) expect(orden(k)).toEqual([]);
  // Hver læsning der pagineres (har .range) over de store tabeller har en .order.
  const store = ['person', 'family_member', 'relation', 'text_mention', 'media', 'media_variant', 'conclusion'];
  for (const k of mockOptaget.filter((x) => store.includes(x.tabel) && x.metoder.some(([m]) => m === 'range'))) {
    expect({ tabel: k.tabel, orden: orden(k).length > 0 }).toEqual({ tabel: k.tabel, orden: true });
  }
});
