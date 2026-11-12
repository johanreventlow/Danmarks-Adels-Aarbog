import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
let byTable: Record<string, FakeRow[]> = {};
let fejlTabel: string | null = null;
const filtre: Array<{ table: string; column: string; value: unknown }> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    from(table: string) {
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

beforeEach(() => {
  fejlTabel = null;
  filtre.length = 0;
  byTable = {
    relation: [
      { subjekt_type: 'person', subjekt_id: 1, objekt_type: 'organisation' },
      { subjekt_type: 'person', subjekt_id: 2, objekt_type: 'estate' },
      { subjekt_type: 'person', subjekt_id: 3, objekt_type: 'person' },
    ],
    haendelse: [{ subjekt_type: 'person', subjekt_id: 4 }],
    story: [
      { subjekt_type: 'person', subjekt_id: 5, status: 'publiceret' },
      { subjekt_type: 'person', subjekt_id: 6, status: 'kladde' },
    ],
  };
});

describe('fetchNaevntGrundlag', () => {
  it('samler personer med embede, gods, hændelse og publiceret historie — kanoniseret', async () => {
    const grundlag = await fetchNaevntGrundlag({ '4': '40' });
    expect([...grundlag.personerMedMereEndNavn].sort()).toEqual(['1', '2', '40', '5']);
  });

  it('kaster ved en fejl i stedet for at give en tom mængde', async () => {
    for (const tabel of ['relation', 'haendelse', 'story']) {
      fejlTabel = tabel;
      await expect(fetchNaevntGrundlag({}), tabel).rejects.toBeTruthy();
    }
  });
});
