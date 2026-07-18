import { fetchHaendelseRows, loadHaendelserBy } from '../haendelser';

type FakeRow = Record<string, unknown>;

function fakeSupabase(byTable: Record<string, FakeRow[]>) {
  const fromCalls: string[] = [];
  const inCalls: Array<{ table: string; column: string; ids: unknown[] }> = [];
  const sb = {
    from(table: string) {
      fromCalls.push(table);
      let rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq: () => builder,
        in(column: string, ids: unknown[]) {
          inCalls.push({ table, column, ids });
          const wanted = new Set(ids.map(String));
          rows = rows.filter((row) => wanted.has(String(row[column])));
          return builder;
        },
        order: () => builder,
        range: async (from: number, to: number) => ({ data: rows.slice(from, to + 1), error: null }),
        then(resolve: (value: { data: FakeRow[]; error: null }) => void) {
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
      };
      return builder;
    },
  };
  return { sb, fromCalls, inCalls };
}

const row = (id: number, narrativeId = 10, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, narrative_id: narrativeId, klausul: 'En historisk klausul.',
  kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  feed_status: 'kandidat', fact_id: null, relation_id: null,
});

describe('fetchHaendelseRows', () => {
  it('henter hændelser → narrativer → sources uden narrativtekst', async () => {
    const { sb, fromCalls } = fakeSupabase({
      haendelse: [row(1), row(2, 11)],
      narrative: [{ id: 10, source_id: 20, side: '12' }, { id: 11, source_id: 20, side: '13' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await fetchHaendelseRows(sb as never);
    expect(out.rows).toHaveLength(2);
    expect(out.narrativer).toHaveLength(2);
    expect(out.sources).toHaveLength(1);
    expect(fromCalls).toEqual(['haendelse', 'narrative', 'source']);
    expect(out.narrativer[0]).not.toHaveProperty('tekst');
  });

  it('chunker mere end 200 narrative-id’er', async () => {
    const rows = Array.from({ length: 450 }, (_, i) => row(i, 1000 + i, 'p' + i));
    const narrativer = rows.map((r) => ({ id: r.narrative_id, source_id: null, side: null }));
    const { sb, inCalls } = fakeSupabase({ haendelse: rows, narrative: narrativer });
    const out = await fetchHaendelseRows(sb as never);
    expect(out.narrativer).toHaveLength(450);
    expect(inCalls.filter((call) => call.table === 'narrative')).toHaveLength(3);
  });

  it('fejl i et vilkårligt led giver tomt resultat + warn', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const sb = { from: () => { throw new Error('netværksfejl'); } };
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it('tom hændelsestabel stopper uden følgequeries', async () => {
    const { sb, fromCalls } = fakeSupabase({ haendelse: [] });
    await expect(fetchHaendelseRows(sb as never)).resolves.toEqual({
      rows: [], narrativer: [], sources: [],
    });
    expect(fromCalls).toEqual(['haendelse']);
  });
});

describe('loadHaendelserBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    const { sb } = fakeSupabase({
      haendelse: [row(1, 10, 'alias')],
      narrative: [{ id: 10, source_id: 20, side: '12' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await loadHaendelserBy(sb as never, { alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([
      expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 12' }),
    ]);
  });
});
