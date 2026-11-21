import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
type Side = { data: unknown; error: unknown };
let byTable: Record<string, FakeRow[]> = {};
let fejlTabel: string | null = null;
let feedSider: Map<string | null, Side> = new Map();
const filtre: Array<{ table: string; column: string; value: unknown }> = [];
const fromKald: string[] = [];

vi.mock('../../supabase', () => ({
  supabase: {
    auth: { async getSession() { return { data: { session: null }, error: null }; } },
    // Review 37 Y3: hændelserne kommer fra feed-RPC'en i bidder, ikke fra tabellen.
    async rpc(fn: string, args: Record<string, unknown>) {
      if (fn !== 'public_haendelse_feed') return { data: null, error: { message: `ukendt rpc ${fn}` } };
      return feedSider.get((args.p_fortsaet as string | null) ?? null)
        ?? { data: null, error: { message: 'ukendt mærke' } };
    },
    from(table: string) {
      fromKald.push(table);
      let rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq(column: string, value: unknown) {
          filtre.push({ table, column, value });
          rows = rows.filter((row) => row[column] === value);
          return builder;
        },
        in(column: string, values: unknown[]) {
          filtre.push({ table, column, value: values });
          rows = rows.filter((row) => values.includes(row[column]));
          return builder;
        },
        order: () => builder,
        range: async (from: number, to: number) => (
          table === fejlTabel
            ? { data: null, error: { message: 'permission denied' } }
            : { data: rows.slice(from, to + 1), error: null }
        ),
      };
      return builder;
    },
  },
}));

const { fetchNaevntGrundlag } = await import('../feedGrundlag');

const hRow = (id: number, subjektId: number) => ({
  id, subjekt_id: subjektId, narrative_id: 10, klausul: 'k', kategori: null, date_min: null, date_max: null,
  date_qualifier: null, date_raw: null, feed_status: 'kandidat', fact_id: null, relation_id: null,
});
const side = (rows: unknown[], naeste: string | null): Side =>
  ({ data: { rows, narrativer: [], sources: [], naeste }, error: null });

beforeEach(() => {
  fejlTabel = null;
  filtre.length = 0;
  fromKald.length = 0;
  byTable = {
    relation: [
      { subjekt_type: 'person', subjekt_id: 1, objekt_type: 'organisation' },
      { subjekt_type: 'person', subjekt_id: 2, objekt_type: 'estate' },
      { subjekt_type: 'person', subjekt_id: 3, objekt_type: 'person' },
    ],
    story: [
      { subjekt_type: 'person', subjekt_id: 5, status: 'publiceret' },
      { subjekt_type: 'person', subjekt_id: 6, status: 'kladde' },
    ],
  };
  // To sider, den første tom (alle kandidater afvist), så begge skal hentes.
  feedSider = new Map([
    [null, side([], 'A')],
    ['A', side([hRow(1, 4), hRow(2, 7)], null)],
  ]);
});

describe('fetchNaevntGrundlag', () => {
  it('samler personer med embede, gods, hændelse og publiceret historie — kanoniseret', async () => {
    const grundlag = await fetchNaevntGrundlag({ '4': '40' });
    expect([...grundlag.personerMedMereEndNavn].sort()).toEqual(['1', '2', '40', '5', '7']);
    expect(fromKald).not.toContain('haendelse');
  });

  it('kaster ved en fejl i stedet for at give en tom mængde', async () => {
    for (const tabel of ['relation', 'story']) {
      fejlTabel = tabel;
      await expect(fetchNaevntGrundlag({}), tabel).rejects.toBeTruthy();
    }
  });

  it('kaster ved en fejl på en senere hændelsesside (fail-closed, intet delvist resultat)', async () => {
    feedSider.set('A', { data: null, error: { message: 'canceling statement due to statement timeout' } });
    await expect(fetchNaevntGrundlag({})).rejects.toBeTruthy();
  });

  it('kaster, når feed-RPC’en mangler', async () => {
    feedSider = new Map([[null, { data: null, error: { message: 'Could not find the function' } }]]);
    await expect(fetchNaevntGrundlag({})).rejects.toBeTruthy();
  });
});
