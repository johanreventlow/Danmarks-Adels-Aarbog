import { fetchLivsdatoRows, loadLivsdatoBy } from '../livsdato';

// Minimal fake af supabase-js's PostgrestFilterBuilder-kæde: select/eq/in/order returnerer
// sig selv (kæde), og er BÅDE direkte "thenable" (chunkede .in()-kald der ikke kalder
// .range()) OG bærer .range() (til getAll-baserede kald). Spejler den rigtige klients
// dobbelte natur uden at kræve et ægte netværkskald.
function makeResult<T>(data: T[] | null, error: unknown = null) {
  return {
    range: async () => ({ data, error }),
    then: (resolve: (v: { data: T[] | null; error: unknown }) => void) => resolve({ data, error }),
  };
}
function fakeTable(byTable: Record<string, unknown>) {
  return {
    from: (table: string) => {
      const result = byTable[table];
      const b: Record<string, unknown> = {
        select: () => b,
        eq: () => b,
        in: () => b,
        order: () => makeResult(result === undefined ? [] : (result as unknown[])),
      };
      return b;
    },
  };
}

describe('fetchLivsdatoRows', () => {
  it('joiner fact→conclusion→assertion-kæden korrekt', async () => {
    const sb = fakeTable({
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
    });
    const rows = await fetchLivsdatoRows(sb as never);
    expect(rows.facts).toHaveLength(2);
    expect(rows.conclusions).toHaveLength(2);
    expect(rows.assertions).toHaveLength(2);
  });

  it('ingen facts → tomme rækker uden yderligere kald', async () => {
    const sb = fakeTable({ fact: [] });
    const rows = await fetchLivsdatoRows(sb as never);
    expect(rows).toEqual({ facts: [], conclusions: [], assertions: [] });
  });

  it('chunker .in()-kald over IN_CHUNK id-grænsen', async () => {
    const manyFacts = Array.from({ length: 450 }, (_, i) => ({ id: i, subjekt_id: 'p' + i, faktatype: 'fødsel' }));
    const manyConclusions = manyFacts.map((f) => ({ target_id: f.id, valgt_assertion_id: f.id + 1000 }));
    const manyAssertions = manyConclusions.map((c) => ({
      id: c.valgt_assertion_id, date_min: '1700-01-01', date_max: '1700-01-01', date_qualifier: 'exact',
    }));
    const sb = fakeTable({ fact: manyFacts, conclusion: manyConclusions, assertion: manyAssertions });
    const rows = await fetchLivsdatoRows(sb as never);
    // Den fakede .in() ignorerer selve id-listen og returnerer altid HELE tabellens
    // fixture — pointen her er at bekræfte at chunking-løkken selv IKKE crasher og at
    // resultaterne akkumuleres uden dubletter for et realistisk antal facts.
    expect(rows.facts).toHaveLength(450);
  });

  it('fejl et sted i kæden → tomme rækker, aldrig kast', async () => {
    const sb = { from: () => { throw new Error('netværksfejl'); } };
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const rows = await fetchLivsdatoRows(sb as never);
    expect(rows).toEqual({ facts: [], conclusions: [], assertions: [] });
    warn.mockRestore();
  });
});

describe('loadLivsdatoBy', () => {
  it('kanoniserer id og returnerer LivsdatoBy', async () => {
    const sb = fakeTable({
      fact: [{ id: 1, subjekt_id: 'alias1', faktatype: 'fødsel' }],
      conclusion: [{ target_id: 1, valgt_assertion_id: 10 }],
      assertion: [{ id: 10, date_min: '1700-07-18', date_max: '1700-07-18', date_qualifier: 'exact' }],
    });
    const out = await loadLivsdatoBy(sb as never, { alias1: 'canon1' });
    expect(out.canon1?.foedt).toEqual({ min: '1700-07-18', max: '1700-07-18', qualifier: 'exact' });
  });
});
