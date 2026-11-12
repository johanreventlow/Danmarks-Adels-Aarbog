import { beforeEach, describe, expect, it, vi } from 'vitest';

const rel = { data: [] as unknown[], error: null as unknown };
const citation = { data: [] as unknown[], error: null as unknown };
const citationIn = vi.fn();
let factRows: unknown[] = [];

function table(name: string) {
  const res = () => (name === 'citation' ? citation : name === 'relation' ? rel : name === 'organisation' ? { data: [{ id: 7, navn: 'greve' }], error: null } : { data: [], error: null });
  const q: Record<string, unknown> = {};
  const chain = () => q;
  for (const m of ['select', 'eq', 'is', 'order', 'range', 'limit']) q[m] = chain;
  q.in = (...a: unknown[]) => { if (name === 'citation') citationIn(...a); return q; };
  q.then = (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) => Promise.resolve(res()).then(ok, ko);
  return q;
}
vi.mock('../../supabase', () => ({
  supabase: {
    from: (n: string) => table(n),
    rpc: (n: string) => {
      if (n === 'narrative_record_contract_version') return Promise.resolve({ data: 2, error: null });
      if (n === 'public_person_facts') return Promise.resolve({ data: factRows, error: null });
      return Promise.resolve({ data: [], error: null });
    },
  },
}));
vi.mock('../media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => [] }));
const { fetchPersonDetail } = await import('../public');

const row = (o: Record<string, unknown>) => ({ person_id: 1, fact_id: 1, faktatype: 'fødsel', conclusion_status: 'afklaret', assertion_id: 10, chosen: true, vaerdi_tekst: 'x', date_raw: null, date_min: null, date_max: null, date_qualifier: null, date_certainty: null, source_id: null, source_label: null, side: null, record_ref: null, record_label: null, citation_label: null, ...o });

beforeEach(() => {
  rel.data = []; rel.error = null; citation.data = []; citation.error = null; citationIn.mockReset(); factRows = [];
});

describe('fetchPersonDetail udgaveoplysninger', () => {
  it('henter citat_tekst kun for valgte påstande uden source_id', async () => {
    factRows = [row({ assertion_id: 10 }), row({ assertion_id: 11, source_id: 5, fact_id: 2 })];
    citation.data = [{ assertion_id: 10, citat_tekst: 'Redaktørens tekst' }, { assertion_id: 10, citat_tekst: '  ' }];
    const d = await fetchPersonDetail('1', undefined, false, { udgaver: [], udgaveForPersonRaekke: {} });
    expect(citationIn).toHaveBeenCalledTimes(1);
    expect(citationIn).toHaveBeenCalledWith('assertion_id', [10]);
    expect(d.faktaInput?.fritekstKilde).toEqual({ '10': ['Redaktørens tekst'] });
  });
  it('fejl i citation-opslaget giver tom fritekstKilde, ikke faktafejl', async () => {
    factRows = [row({})];
    citation.error = { message: 'boom' };
    const d = await fetchPersonDetail('1');
    expect(d.factsError).toBe(false);
    expect(d.faktaInput?.fritekstKilde).toEqual({});
    expect(d.faktaInput?.rows).toHaveLength(1);
  });
  it('embede uden organisationsnavn ud over rollen vises kun som rollen', async () => {
    rel.data = [{ subjekt_id: 1, objekt_type: 'organisation', objekt_id: 7, rolle: 'Greve', periode_raw: null }];
    const d = await fetchPersonDetail('1');
    expect(d.offices[0].label).toBe('Greve');
  });
  it('samme gods fra to medlemmer i hver sin udgave bevares som to rækker med hver sin personId', async () => {
    rel.data = [
      { subjekt_id: 1, objekt_type: 'estate', objekt_id: 3, rolle: 'ejer', periode_raw: null },
      { subjekt_id: 2, objekt_type: 'estate', objekt_id: 3, rolle: 'ejer', periode_raw: null },
      { subjekt_id: 2, objekt_type: 'estate', objekt_id: 3, rolle: 'ejer', periode_raw: null },
    ];
    const d = await fetchPersonDetail('1', ['1', '2']);
    expect(d.estates.map((e) => e.personId).sort()).toEqual(['1', '2']);
  });
});
