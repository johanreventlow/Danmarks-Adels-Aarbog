import { fetchStoryRows, loadStorieBy } from '../story';

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

const row = (id: number, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, haendelse_id: null, titel: null, tekst: 'Historie ' + id,
  date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  status: 'publiceret', publiceret_dato: null, privat: false,
});

describe('fetchStoryRows', () => {
  it('henter story → story_kilde → source i tre led', async () => {
    const { sb, fromCalls } = fakeSupabase({
      story: [row(1), row(2)],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await fetchStoryRows(sb as never);
    expect(out.rows).toHaveLength(2);
    expect(out.kilder).toHaveLength(1);
    expect(out.sources).toHaveLength(1);
    expect(fromCalls).toEqual(['story', 'story_kilde', 'source']);
  });

  it('chunker mere end 200 story-id’er', async () => {
    const rows = Array.from({ length: 450 }, (_, i) => row(i, 'p' + i));
    const kilder = rows.map((item) => ({ id: 1000 + item.id, story_id: item.id, source_id: 20, side: null }));
    const { sb, inCalls } = fakeSupabase({ story: rows, story_kilde: kilder, source: [{ id: 20, udgave: '1939' }] });
    const out = await fetchStoryRows(sb as never);
    expect(out.kilder).toHaveLength(450);
    expect(inCalls.filter((call) => call.table === 'story_kilde')).toHaveLength(3);
  });

  it('fejl giver tomt resultat og warn; tom tabel stopper tidligt', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const broken = { from: () => { throw new Error('netværksfejl'); } };
    await expect(fetchStoryRows(broken as never)).resolves.toEqual({ rows: [], kilder: [], sources: [] });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();

    const { sb, fromCalls } = fakeSupabase({ story: [] });
    await expect(fetchStoryRows(sb as never)).resolves.toEqual({ rows: [], kilder: [], sources: [] });
    expect(fromCalls).toEqual(['story']);
  });
});

describe('loadStorieBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    const { sb } = fakeSupabase({
      story: [row(1, 'alias')],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await loadStorieBy(sb as never, { alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 112' })]);
  });
});
