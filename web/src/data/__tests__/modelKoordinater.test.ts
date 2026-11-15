// Kodereview 36 P2: loadModel henter koordinaterne i ÉT kald (public_person_source_coordinates_samlet) og falder kun
// tilbage til den offset-paginerede rækkefunktion, når den nye funktion ikke findes endnu (PGRST202).
import { beforeEach, describe, expect, it, vi } from 'vitest';

type Svar = { data: unknown; error: unknown };
const rpcKald: { fn: string; range?: [number, number] }[] = [];
let samletSvar: Svar = { data: [], error: null };
let raekkeSider: unknown[][] = [];

const KOORD = {
  person_id: 1, source_id: 1, legacy_line_code: 'I', printed_number: 15, printed_number_label: '15a',
  generation_local: 3, generation_global: 7, kuld_label: null, provenance_kind: 'placement', printed_page: null,
};
const TABELLER: Record<string, unknown[]> = {
  person: [{ id: 1, visning_navn: 'A', visning_fuldt_navn: 'A', visning_foedt: null, visning_doed: null, visning_titel: null, koen: 'mand', privat: false }],
  source: [{ id: 1, slags: 'DAA-udgave', titel: 'DAA', udgave: '2018-20', aar: 2018, ekstern: false }],
};

function kaede(rows: unknown[]) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'is']) q[m] = () => q;
  q.range = async (a: number, b: number) => ({ data: rows.slice(a, b + 1), error: null });
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve({ data: rows, error: null }).then(res, rej);
  return q;
}

vi.mock('../../supabase', () => ({
  supabase: {
    from: (t: string) => kaede(TABELLER[t] ?? []),
    rpc: (fn: string) => {
      if (fn === 'public_person_source_coordinates_samlet') {
        rpcKald.push({ fn });
        return { then: (res: (v: Svar) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(samletSvar).then(res, rej) };
      }
      if (fn === 'public_person_source_coordinates') {
        let side = 0;
        return {
          range: async (a: number, b: number) => { rpcKald.push({ fn, range: [a, b] }); return { data: raekkeSider[side++] ?? [], error: null }; },
        };
      }
      return kaede([]);
    },
  },
}));

const { loadModel } = await import('../model');

beforeEach(() => { rpcKald.length = 0; samletSvar = { data: [], error: null }; raekkeSider = []; });

describe('loadModel koordinater (kodereview 36 P2)', () => {
  it('ét kald til den samlede funktion; rækkefunktionen kaldes ikke', async () => {
    samletSvar = { data: [KOORD], error: null };
    const model = await loadModel({ collapse: false });
    expect(rpcKald).toEqual([{ fn: 'public_person_source_coordinates_samlet' }]);
    expect(model.genCoordsByPerson['1']).toBeDefined();
  });

  it('falder tilbage til rækkefunktionen via sider, når den samlede ikke findes (PGRST202)', async () => {
    samletSvar = { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } };
    raekkeSider = [[KOORD]];
    const model = await loadModel({ collapse: false });
    expect(rpcKald).toEqual([
      { fn: 'public_person_source_coordinates_samlet' },
      { fn: 'public_person_source_coordinates', range: [0, 999] },
    ]);
    expect(model.genCoordsByPerson['1']).toBeDefined();
  });

  it('andre fejl degraderer til ingen koordinater uden fallback', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    samletSvar = { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } };
    const model = await loadModel({ collapse: false });
    warn.mockRestore();
    expect(rpcKald).toEqual([{ fn: 'public_person_source_coordinates_samlet' }]);
    expect(model.genCoordsByPerson['1']).toBeUndefined();
  });
});
