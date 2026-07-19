import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
let byTable: Record<string, FakeRow[]> = {};
let shouldThrow = false;
const fromCalls: string[] = [];
const inCalls: Array<{ table: string; column: string; ids: unknown[] }> = [];
const eqCalls: Array<{ table: string; column: string; value: unknown }> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    from(table: string) {
      if (shouldThrow) throw new Error('netværksfejl');
      fromCalls.push(table);
      let rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq(column: string, value: unknown) {
          eqCalls.push({ table, column, value });
          return builder;
        },
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
  },
}));

const { fetchStoryRows, loadStorieBy } = await import('../story');

const row = (id: number, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, haendelse_id: null, titel: null, tekst: 'Historie ' + id,
  date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  status: 'publiceret', publiceret_dato: null, privat: false,
});

beforeEach(() => {
  byTable = {};
  shouldThrow = false;
  fromCalls.length = 0;
  inCalls.length = 0;
  eqCalls.length = 0;
});

describe('fetchStoryRows', () => {
  it('henter tre led og filtrerer publiceret status i query-kæden', async () => {
    byTable = {
      story: [row(1), row(2)],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    };
    const out = await fetchStoryRows();
    expect(out.rows).toHaveLength(2);
    expect(out.kilder).toHaveLength(1);
    expect(out.sources).toHaveLength(1);
    expect(fromCalls).toEqual(['story', 'story_kilde', 'source']);
    expect(eqCalls).toContainEqual({ table: 'story', column: 'status', value: 'publiceret' });
  });

  it('chunker mere end 200 story-id’er', async () => {
    const rows = Array.from({ length: 450 }, (_, i) => row(i, 'p' + i));
    byTable = {
      story: rows,
      story_kilde: rows.map((item) => ({ id: 1000 + item.id, story_id: item.id, source_id: 20, side: null })),
      source: [{ id: 20, udgave: '1939' }],
    };
    expect((await fetchStoryRows()).kilder).toHaveLength(450);
    expect(inCalls.filter((call) => call.table === 'story_kilde')).toHaveLength(3);
  });

  it('fejl giver tomt resultat og warn', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    shouldThrow = true;
    await expect(fetchStoryRows()).resolves.toEqual({ rows: [], kilder: [], sources: [] });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});

describe('loadStorieBy', () => {
  it('joiner og kanoniserer', async () => {
    byTable = {
      story: [row(1, 'alias')],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    };
    const out = await loadStorieBy({ alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 112' })]);
  });
});
