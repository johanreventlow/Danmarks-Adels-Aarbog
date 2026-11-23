import { beforeEach, describe, expect, it, vi } from 'vitest';

// Vielsesdatoer læses fact → conclusion → assertion direkte fra tabellerne (gæster må læse dem). Tabellernes svar
// simuleres pr. tabelnavn; hvert kald noteres med sine filtre, så testen kan se, hvad der blev spurgt om.
type Svar = { data: unknown[] | null; error: unknown };
let svar: Record<string, Svar> = {};
let kald: Array<{ table: string; filtre: Array<[string, string, unknown]> }> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    from(table: string) {
      const post = { table, filtre: [] as Array<[string, string, unknown]> };
      kald.push(post);
      const b = {
        select: () => b,
        eq: (k: string, v: unknown) => (post.filtre.push(['eq', k, v]), b),
        in: (k: string, v: unknown) => (post.filtre.push(['in', k, v]), b),
        order: () => b,
        range: async () => svar[table] ?? { data: [], error: null },
      };
      return b;
    },
  },
}));

const { hentVielsesDatoer } = await import('../vielser');

beforeEach(() => {
  kald = [];
  svar = {
    fact: { data: [{ id: 1, subjekt_id: 265 }, { id: 2, subjekt_id: 266 }, { id: 3, subjekt_id: 267 }], error: null },
    conclusion: {
      data: [
        { target_id: 1, valgt_assertion_id: 11 },
        { target_id: 2, valgt_assertion_id: 12 },
        { target_id: 3, valgt_assertion_id: 13 },
      ],
      error: null,
    },
    assertion: {
      data: [
        { id: 11, date_min: '1667-07-21', date_max: '1667-07-21' },
        { id: 12, date_min: '1681-05-01', date_max: '1681-05-01' },
        { id: 13, date_min: null, date_max: null },
      ],
      error: null,
    },
  };
});

describe('hentVielsesDatoer', () => {
  it('returnerer ⚭-tekst pr. familie; familie uden brugbar dato udelades', async () => {
    expect(await hentVielsesDatoer(['265', '266', '267'])).toEqual({ '265': '⚭ 21. juli 1667', '266': '⚭ 1. maj 1681' });
    const fact = kald.find((k) => k.table === 'fact')!;
    expect(fact.filtre).toContainEqual(['eq', 'subjekt_type', 'family']);
    expect(fact.filtre).toContainEqual(['eq', 'faktatype', 'vielse']);
    const konkl = kald.find((k) => k.table === 'conclusion')!;
    expect(konkl.filtre).toContainEqual(['eq', 'target_type', 'fact']);
    expect(konkl.filtre).toContainEqual(['in', 'status', ['afklaret', 'omstridt']]);
  });

  it('tom liste kalder ikke databasen', async () => {
    expect(await hentVielsesDatoer([])).toEqual({});
    expect(kald).toEqual([]);
  });

  it('fejl giver tomt resultat', async () => {
    svar.conclusion = { data: null, error: { message: 'nede' } };
    expect(await hentVielsesDatoer(['265'])).toEqual({});
  });
});
