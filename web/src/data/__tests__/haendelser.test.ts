import { beforeEach, describe, expect, it, vi } from 'vitest';

// Review 37 Y3: hændelserne hentes via RPC'en public_haendelse_feed i bidder, til naeste er null.
// Sider simuleres som et kort fra bladremærke (null = første kald) til svar.
type Side = { data: unknown; error: unknown };
let sider: Map<string | null, Side> = new Map();
let rpcKald: Array<{ fn: string; args: Record<string, unknown> }> = [];
// Bladremærker, hvis første kald fejler med gæsteloftet (57014); næste kald med samme mærke lykkes.
let fejlFoerst = new Set<string | null>();
const fromKald: string[] = [];
let brugerId: string | null = null;

vi.mock('../../supabase', () => ({
  supabase: {
    auth: {
      async getSession() {
        return { data: { session: brugerId ? { user: { id: brugerId } } : null }, error: null };
      },
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      rpcKald.push({ fn, args });
      const maerke = (args.p_fortsaet as string | null) ?? null;
      if (fejlFoerst.delete(maerke)) return { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } };
      const side = sider.get((args.p_fortsaet as string | null) ?? null);
      if (!side) return { data: null, error: { message: `ukendt mærke ${String(args.p_fortsaet)}` } };
      return side;
    },
    from(table: string) {
      // Den gamle direkte tabellæsning må ikke bruges længere.
      fromKald.push(table);
      throw new Error(`direkte tabellæsning af ${table}`);
    },
  },
}));

const { fetchHaendelseRows, fetchHaendelseFeed, loadHaendelserBy } = await import('../haendelser');

const row = (id: number, narrativeId = 10, subjektId: string | number = 'p1') => ({
  id, subjekt_id: subjektId, narrative_id: narrativeId, klausul: 'En historisk klausul.',
  kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  feed_status: 'kandidat', fact_id: null, relation_id: null,
});
const svar = (data: unknown): Side => ({ data, error: null });
const side = (rows: unknown[], narrativer: unknown[], sources: unknown[], naeste: string | null) =>
  svar({ rows, narrativer, sources, naeste });

beforeEach(() => {
  sider = new Map();
  rpcKald = [];
  fromKald.length = 0;
  brugerId = null;
  fejlFoerst = new Set();
});

describe('fetchHaendelseFeed (bladring)', () => {
  it('bladrer over en tom side med naeste sat og stopper først ved naeste=null', async () => {
    sider.set(null, side([], [], [], 'A'));
    sider.set('A', side([row(1)], [{ id: 10, source_id: 20, side: '12' }], [{ id: 20, udgave: '1939' }], 'B'));
    sider.set('B', side([row(2, 10), row(3, 11)],
      [{ id: 10, source_id: 20, side: '12' }, { id: 11, source_id: 20, side: '13' }],
      [{ id: 20, udgave: '1939' }], null));
    const out = await fetchHaendelseFeed();
    expect(rpcKald.map((k) => k.args.p_fortsaet)).toEqual([null, 'A', 'B']);
    expect(rpcKald.every((k) => k.fn === 'public_haendelse_feed')).toBe(true);
    expect(out.rows.map((r) => r.id)).toEqual([1, 2, 3]);
    // Et narrativ og en kilde, der optræder på flere sider, kommer kun med én gang.
    expect(out.narrativer.map((n) => n.id)).toEqual([10, 11]);
    expect(out.sources.map((s) => s.id)).toEqual([20]);
    expect(fromKald).toEqual([]);
  });

  it('en fejl på en senere side kastes (intet delvist resultat)', async () => {
    sider.set(null, side([row(1)], [], [], 'A'));
    sider.set('A', { data: null, error: { message: 'canceling statement due to statement timeout' } });
    await expect(fetchHaendelseFeed()).rejects.toBeTruthy();
  });

  it('en side, der rammer gæsteloftet én gang, hentes igen med samme mærke (prod 24/11: 8 af 36 kald fejlede)', async () => {
    sider.set(null, side([row(1)], [], [], 'A'));
    sider.set('A', side([row(2)], [], [], null));
    fejlFoerst = new Set(['A']);
    const out = await fetchHaendelseFeed();
    expect(rpcKald.map((k) => k.args.p_fortsaet)).toEqual([null, 'A', 'A']);
    expect(out.rows.map((r) => r.id)).toEqual([1, 2]);
  });

  it('et svar uden gyldig form kastes', async () => {
    sider.set(null, svar({ rows: 'ikke en liste', naeste: null }));
    await expect(fetchHaendelseFeed()).rejects.toThrow(/form/);
    sider.set(null, svar({ rows: [], narrativer: [], sources: [], naeste: 7 }));
    await expect(fetchHaendelseFeed()).rejects.toThrow(/form/);
  });

  it('samtidige kald deler én bladring; et senere kald henter forfra (ingen cache)', async () => {
    sider.set(null, side([], [], [], 'A'));
    sider.set('A', side([row(1)], [], [], null));
    const [a, b] = await Promise.all([fetchHaendelseFeed(), fetchHaendelseFeed()]);
    expect(rpcKald).toHaveLength(2);
    expect(a.rows.map((r) => r.id)).toEqual([1]);
    expect(b.rows.map((r) => r.id)).toEqual([1]);
    await fetchHaendelseFeed();
    expect(rpcKald).toHaveLength(4);
  });

  it('en bladring deles aldrig på tværs af brugere (fx logud midt i indlæsningen)', async () => {
    sider.set(null, side([row(1)], [], [], null));
    brugerId = 'redaktoer';
    const redaktoer = fetchHaendelseFeed();
    // Kalderen efter logud må ikke arve redaktørens igangværende bladring.
    await Promise.resolve();
    brugerId = null;
    const gaest = fetchHaendelseFeed();
    await Promise.all([redaktoer, gaest]);
    expect(rpcKald).toHaveLength(2);
  });

  it('en delt bladring, der fejler, afvises for begge kaldere', async () => {
    sider.set(null, side([row(1)], [], [], 'A'));
    sider.set('A', { data: null, error: { message: 'timeout' } });
    const [a, b] = await Promise.allSettled([fetchHaendelseFeed(), fetchHaendelseFeed()]);
    expect(a.status).toBe('rejected');
    expect(b.status).toBe('rejected');
    // Én delt bladring: første side + den fejlende side + dens ene genforsøg (uden deling ville det være 6).
    expect(rpcKald.map((k) => k.args.p_fortsaet)).toEqual([null, 'A', 'A']);
  });

  it('en bladring, der aldrig slutter, afbrydes', async () => {
    sider.set(null, side([], [], [], 'A'));
    sider.set('A', side([], [], [], 'A'));
    await expect(fetchHaendelseFeed()).rejects.toThrow(/sider/);
  });
});

describe('fetchHaendelseRows (hændelseskort: tolerant)', () => {
  it('tom feed giver tomt resultat med ét kald', async () => {
    sider.set(null, side([], [], [], null));
    await expect(fetchHaendelseRows()).resolves.toEqual({ rows: [], narrativer: [], sources: [] });
    expect(rpcKald).toHaveLength(1);
  });

  it('fejl efter første side giver tomt resultat + warn', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    sider.set(null, side([row(1)], [{ id: 10, source_id: null, side: null }], [], 'A'));
    sider.set('A', { data: null, error: { message: 'Could not find the function public.public_haendelse_feed' } });
    await expect(fetchHaendelseRows()).resolves.toEqual({ rows: [], narrativer: [], sources: [] });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});

describe('loadHaendelserBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    sider.set(null, side([row(1, 10, 'alias')], [{ id: 10, source_id: 20, side: '12' }],
      [{ id: 20, udgave: '1939' }], null));
    const out = await loadHaendelserBy({ alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([
      expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 12' }),
    ]);
  });
});
