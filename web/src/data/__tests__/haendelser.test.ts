import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
let byTable: Record<string, FakeRow[]> = {};
let shouldThrow = false;
const fromCalls: string[] = [];
const inCalls: Array<{ table: string; ids: unknown[] }> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    from(table: string) {
      if (shouldThrow) throw new Error('netværksfejl');
      fromCalls.push(table);
      let rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq: () => builder,
        in(column: string, ids: unknown[]) {
          inCalls.push({ table, ids });
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

const { fetchHaendelseRows, loadHaendelserBy } = await import('../haendelser');

const row = (id: number, narrativeId = 10, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, narrative_id: narrativeId, klausul: 'En historisk klausul.',
  kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  feed_status: 'kandidat', fact_id: null, relation_id: null,
});

beforeEach(() => {
  byTable = {};
  shouldThrow = false;
  fromCalls.length = 0;
  inCalls.length = 0;
});

describe('fetchHaendelseRows', () => {
  it('henter hændelser → narrativer → sources uden narrativtekst', async () => {
    byTable = {
      haendelse: [row(1), row(2, 11)],
      narrative: [{ id: 10, source_id: 20, side: '12' }, { id: 11, source_id: 20, side: '13' }],
      source: [{ id: 20, udgave: '1939' }],
    };
    const out = await fetchHaendelseRows();
    expect(out.rows).toHaveLength(2);
    expect(out.narrativer).toHaveLength(2);
    expect(out.sources).toHaveLength(1);
    expect(fromCalls).toEqual(['haendelse', 'narrative', 'source']);
    expect(out.narrativer[0]).not.toHaveProperty('tekst');
  });

  it('chunker mere end 200 narrative-id’er', async () => {
    const rows = Array.from({ length: 450 }, (_, i) => row(i, 1000 + i, 'p' + i));
    byTable = {
      haendelse: rows,
      narrative: rows.map((r) => ({ id: r.narrative_id, source_id: null, side: null })),
    };
    const out = await fetchHaendelseRows();
    expect(out.narrativer).toHaveLength(450);
    expect(inCalls.filter((call) => call.table === 'narrative')).toHaveLength(3);
  });

  it('fejl giver tomt resultat + warn', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    shouldThrow = true;
    await expect(fetchHaendelseRows()).resolves.toEqual({ rows: [], narrativer: [], sources: [] });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it('tom hændelsestabel stopper uden følgequeries', async () => {
    byTable = { haendelse: [] };
    await expect(fetchHaendelseRows()).resolves.toEqual({ rows: [], narrativer: [], sources: [] });
    expect(fromCalls).toEqual(['haendelse']);
  });
});

describe('loadHaendelserBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    byTable = {
      haendelse: [row(1, 10, 'alias')],
      narrative: [{ id: 10, source_id: 20, side: '12' }],
      source: [{ id: 20, udgave: '1939' }],
    };
    const out = await loadHaendelserBy({ alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([
      expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 12' }),
    ]);
  });
});
