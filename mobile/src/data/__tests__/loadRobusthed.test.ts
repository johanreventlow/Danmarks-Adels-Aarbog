// Loader-robusthed (paritetsaudit batch 2): navneproveniens i bidder, og en fejlet person-relationslæsning
// (57014 under gæsteloftet) må ikke vælte hele indlæsningen til offline-seedet.
type Ark = { tabel: string; ids?: unknown[]; filtre: Record<string, unknown> };

const mock: {
  rows: Record<string, unknown[]>;
  fejlRelationPerson: boolean;
  fejlSkema: boolean;
  koord: unknown[];
  inKald: { tabel: string; kol: string; antal: number }[];
} = { rows: {}, fejlRelationPerson: false, fejlSkema: false, koord: [], inKald: [] };

jest.mock('../../lib/supabase', () => {
  const lav = (tabel: string) => {
    const ark: Ark = { tabel, filtre: {} };
    const q: Record<string, unknown> = {};
    const kæde = () => q;
    q.select = (kolonner: string) => { ark.filtre.__sel = kolonner; return q; };
    for (const m of ['order', 'neq', 'is', 'not', 'gte', 'lte', 'or', 'limit']) q[m] = kæde;
    q.eq = (k: string, v: unknown) => { ark.filtre[k] = v; return q; };
    q.in = (k: string, v: unknown[]) => { ark.ids = v; mock.inKald.push({ tabel, kol: k, antal: v.length }); return q; };
    q.range = async (from: number) => {
      if (tabel === 'relation' && ark.filtre.subjekt_type === 'person' && String(ark.filtre.__sel).includes('kvalifikator') && mock.fejlRelationPerson) {
        return { data: null, error: { code: '57014' } };
      }
      if (tabel.startsWith('lineage_scheme') && mock.fejlSkema) return { data: null, error: { code: '42501', message: 'permission denied' } };
      const alle = (mock.rows[tabel] ?? []) as Record<string, unknown>[];
      const filtreret = alle.filter((r) => Object.entries(ark.filtre).filter(([k]) => k !== '__sel').every(([k, v]) => r[k] === v)
        && (!ark.ids || ark.ids.includes(r.target_id) || ark.ids.includes(r.assertion_id)));
      return { data: filtreret.slice(from, from + 1000), error: null };
    };
    q.then = (res: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(res);
    return q;
  };
  return {
    supabaseEnabled: true,
    supabase: { from: lav, rpc: async (fn: string) => ({ data: fn === 'public_person_source_coordinates_samlet' ? mock.koord : [], error: null }), auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } },
  };
});

import { fetchNavnProveniens, loadFromSupabase, PROVENIENS_IN_CHUNK } from '../load';
import { supabase } from '../../lib/supabase';

beforeEach(() => {
  mock.inKald = [];
  mock.fejlRelationPerson = false;
  mock.fejlSkema = false;
  mock.koord = [];
  mock.rows = {};
  jest.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => jest.restoreAllMocks());

test('fetchNavnProveniens: .in()-lister deles i bidder à højst 200 id', async () => {
  const n = 450;
  mock.rows.fact = Array.from({ length: n }, (_, i) => ({ id: i + 1, subjekt_id: 1000 + i, subjekt_type: 'person', faktatype: 'navn' }));
  mock.rows.assertion = Array.from({ length: n }, (_, i) => ({ id: 5000 + i, target_id: i + 1, target_type: 'fact' }));
  mock.rows.citation = [];
  await fetchNavnProveniens(supabase as never);
  expect(mock.inKald.length).toBeGreaterThanOrEqual(6); // 3 bidder til assertion + 3 til citation
  expect(Math.max(...mock.inKald.map((k) => k.antal))).toBeLessThanOrEqual(PROVENIENS_IN_CHUNK);
  expect(mock.inKald.filter((k) => k.tabel === 'assertion').reduce((a, k) => a + k.antal, 0)).toBe(n);
});

test('fetchNavnProveniens: en fejlet bid degraderer til ingen proveniens i stedet for at kaste', async () => {
  mock.rows.fact = [{ id: 1, subjekt_id: 7, subjekt_type: 'person', faktatype: 'navn' }];
  const sb = {
    from: (t: string) => {
      const q: Record<string, unknown> = {};
      for (const m of ['select', 'eq', 'order']) q[m] = () => q;
      q.in = () => q;
      q.range = async () => (t === 'assertion' ? { data: null, error: { code: '57014' } } : { data: t === 'fact' ? mock.rows.fact : [], error: null });
      return q;
    },
  };
  await expect(fetchNavnProveniens(sb as never)).resolves.toEqual([]);
});

test('loadFromSupabase: 57014 på person-relationerne giver en degraderet model, ikke en kastet fejl', async () => {
  mock.rows.person = [{ id: 1, visning_navn: 'Rod', visning_foedt: '1600', visning_doed: null, privat: false }];
  mock.fejlRelationPerson = true;
  const r = await loadFromSupabase();
  expect(r.db.persons.length).toBe(1);
  expect(console.warn).toHaveBeenCalledWith(expect.stringContaining('person-relationer utilgængelige'), expect.anything());
});

// 6e (batch 4): fejler stamtavleskemaerne, falder linjerne tilbage til de trykte koder — indlæsningen fejler ikke.
test('loadFromSupabase: utilgængelige lineage_scheme-tabeller giver trykte koder, ikke offline-seed', async () => {
  mock.rows.person = [{ id: 446, visning_navn: 'A', visning_foedt: '1900', visning_doed: null, privat: false }];
  mock.rows.source = [{ id: 2, slags: 'DAA-udgave', titel: 'DAA 2018-20', udgave: 'DAA 2018-20', aar: 2018, ekstern: null }];
  mock.koord = [{
    person_id: 446, source_id: 2, legacy_line_code: 'V', printed_number: 148, printed_number_label: null,
    generation_local: 9, generation_global: null, kuld_label: null, provenance_kind: 'placement', printed_page: '512',
  }];
  mock.fejlSkema = true;
  const r = await loadFromSupabase();
  expect(r.db.persons.map((p) => p.id)).toEqual(['446']);
  expect(r.udgaveLag.lineage.list.map((l) => l.linje)).toEqual(['V']);
  expect(r.udgaveLag.sourcesBy['446']?.[0]?.ref).toBe('Linje V, nr. 148');
  expect(r.aux.sourcesBy['446']?.[0]?.ref).toBe('Linje V, nr. 148');
  expect(console.warn).toHaveBeenCalledWith(expect.stringContaining('lineage_scheme utilgængelig'), expect.anything());
});
