import { beforeEach, describe, expect, it, vi } from 'vitest';

// In-memory fake af supabase-js's PostgrestFilterBuilder-kæde (spejler mobile-testens
// mønster): select/eq/in/order returnerer sig selv; .order() er BÅDE thenable (chunkede
// .in()-kald) OG bærer .range() (til getAll-baserede kald).
let byTable: Record<string, unknown[]> = {};
let shouldThrow = false;

function makeResult<T>(data: T[] | null, error: unknown = null) {
  return {
    range: async () => ({ data, error }),
    then: (resolve: (v: { data: T[] | null; error: unknown }) => void) => resolve({ data, error }),
  };
}
vi.mock('../../supabase', () => ({
  supabase: {
    from: (table: string) => {
      if (shouldThrow) throw new Error('netværksfejl');
      const b: Record<string, unknown> = {
        select: () => b,
        eq: () => b,
        in: () => b,
        order: () => makeResult(byTable[table] ?? []),
      };
      return b;
    },
  },
}));

const { fetchLivsdatoRows, loadLivsdatoBy } = await import('../livsdato');

beforeEach(() => { byTable = {}; shouldThrow = false; });

describe('fetchLivsdatoRows', () => {
  it('joiner fact→conclusion→assertion-kæden korrekt', async () => {
    byTable = {
      fact: [
        { id: 1, subjekt_id: 'a', faktatype: 'fødsel' },
        { id: 2, subjekt_id: 'a', faktatype: 'død' },
      ],
      conclusion: [
        { target_id: 1, valgt_assertion_id: 10 },
        { target_id: 2, valgt_assertion_id: 11 },
      ],
      assertion: [
        { id: 10, date_min: '1700-07-18', date_max: '1700-07-18', date_qualifier: 'exact' },
        { id: 11, date_min: '1780-01-01', date_max: '1780-01-01', date_qualifier: 'exact' },
      ],
    };
    const rows = await fetchLivsdatoRows();
    expect(rows.facts).toHaveLength(2);
    expect(rows.conclusions).toHaveLength(2);
    expect(rows.assertions).toHaveLength(2);
  });

  it('ingen facts → tomme rækker uden yderligere kald', async () => {
    byTable = { fact: [] };
    const rows = await fetchLivsdatoRows();
    expect(rows).toEqual({ facts: [], conclusions: [], assertions: [] });
  });

  it('fejl et sted i kæden → tomme rækker, aldrig kast', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    shouldThrow = true;
    const rows = await fetchLivsdatoRows();
    expect(rows).toEqual({ facts: [], conclusions: [], assertions: [] });
    spy.mockRestore();
  });
});

describe('loadLivsdatoBy', () => {
  it('kanoniserer id og returnerer LivsdatoBy', async () => {
    byTable = {
      fact: [{ id: 1, subjekt_id: 'alias1', faktatype: 'fødsel' }],
      conclusion: [{ target_id: 1, valgt_assertion_id: 10 }],
      assertion: [{ id: 10, date_min: '1700-07-18', date_max: '1700-07-18', date_qualifier: 'exact' }],
    };
    const out = await loadLivsdatoBy({ alias1: 'canon1' });
    expect(out.canon1?.foedt).toEqual({ min: '1700-07-18', max: '1700-07-18', qualifier: 'exact' });
  });
});
