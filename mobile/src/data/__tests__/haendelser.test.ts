import { fetchHaendelseRows, loadHaendelserBy } from '../haendelser';

// Review 37 Y3: hændelserne hentes via RPC'en public_haendelse_feed i bidder, til naeste er null.
// Sider simuleres som et kort fra bladremærke (null = første kald) til svar.
type Side = { data: unknown; error: unknown };

function fakeSupabase(sider: Map<string | null, Side>) {
  const rpcKald: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const fromKald: string[] = [];
  const sb = {
    async rpc(fn: string, args: Record<string, unknown>) {
      rpcKald.push({ fn, args });
      const side = sider.get((args.p_fortsaet as string | null) ?? null);
      if (!side) return { data: null, error: { message: `ukendt mærke ${String(args.p_fortsaet)}` } };
      return side;
    },
    from(table: string) {
      // Den gamle direkte tabellæsning må ikke bruges længere.
      fromKald.push(table);
      throw new Error(`direkte tabellæsning af ${table}`);
    },
  };
  return { sb, rpcKald, fromKald };
}

const row = (id: number, narrativeId = 10, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, narrative_id: narrativeId, klausul: 'En historisk klausul.',
  kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  feed_status: 'kandidat', fact_id: null, relation_id: null,
});
const svar = (data: unknown): Side => ({ data, error: null });
const side = (rows: unknown[], narrativer: unknown[], sources: unknown[], naeste: string | null) =>
  svar({ rows, narrativer, sources, naeste });

describe('fetchHaendelseRows', () => {
  it('bladrer over en tom side med naeste sat og stopper først ved naeste=null', async () => {
    const { sb, rpcKald, fromKald } = fakeSupabase(new Map([
      [null, side([], [], [], 'A')],
      ['A', side([row(1)], [{ id: 10, source_id: 20, side: '12' }], [{ id: 20, udgave: '1939' }], 'B')],
      ['B', side([row(2, 10), row(3, 11)],
        [{ id: 10, source_id: 20, side: '12' }, { id: 11, source_id: 20, side: '13' }],
        [{ id: 20, udgave: '1939' }], null)],
    ]));
    const out = await fetchHaendelseRows(sb as never);
    expect(rpcKald.map((k) => k.args.p_fortsaet)).toEqual([null, 'A', 'B']);
    expect(rpcKald.every((k) => k.fn === 'public_haendelse_feed')).toBe(true);
    expect(out.rows.map((r) => r.id)).toEqual([1, 2, 3]);
    // Et narrativ og en kilde, der optræder på flere sider, kommer kun med én gang.
    expect(out.narrativer.map((n) => n.id)).toEqual([10, 11]);
    expect(out.sources.map((s) => s.id)).toEqual([20]);
    expect(out.narrativer[0]).not.toHaveProperty('tekst');
    expect(fromKald).toEqual([]);
  });

  it('tom feed giver tomt resultat med ét kald', async () => {
    const { sb, rpcKald } = fakeSupabase(new Map([[null, side([], [], [], null)]]));
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    expect(rpcKald).toHaveLength(1);
  });

  it('fejl efter første side giver tomt resultat + warn (intet delvist resultat)', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { sb } = fakeSupabase(new Map([
      [null, side([row(1)], [{ id: 10, source_id: null, side: null }], [], 'A')],
      ['A', { data: null, error: { message: 'canceling statement due to statement timeout' } }],
    ]));
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it('et svar uden gyldig form giver tomt resultat', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    for (const data of [{ rows: 'ikke en liste', naeste: null }, { rows: [], narrativer: [], sources: [], naeste: 7 }]) {
      const { sb } = fakeSupabase(new Map([[null, svar(data)]]));
      await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
        rows: [], narrativer: [], sources: [],
      });
    }
    expect(warn).toHaveBeenCalledTimes(2);
    warn.mockRestore();
  });

  it('en bladring, der aldrig slutter, afbrydes', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const { sb, rpcKald } = fakeSupabase(new Map([
      [null, side([], [], [], 'A')],
      ['A', side([], [], [], 'A')],
    ]));
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    expect(rpcKald).toHaveLength(500);
    expect(String(warn.mock.calls[0][1])).toMatch(/sider/);
    warn.mockRestore();
  });

  it('en umigreret base (RPC findes ikke) giver tomt resultat', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const sb = { rpc: async () => ({ data: null, error: { message: 'Could not find the function public.public_haendelse_feed' } }) };
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    warn.mockRestore();
  });
});

describe('loadHaendelserBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    const { sb } = fakeSupabase(new Map([
      [null, side([row(1, 10, 'alias')], [{ id: 10, source_id: 20, side: '12' }],
        [{ id: 20, udgave: '1939' }], null)],
    ]));
    const out = await loadHaendelserBy(sb as never, { alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([
      expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 12' }),
    ]);
  });
});
