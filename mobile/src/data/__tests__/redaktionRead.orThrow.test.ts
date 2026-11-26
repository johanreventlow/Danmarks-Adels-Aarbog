// Læsefejl må ikke ligne tomme data (review 37 M6): spejl af web's orThrow-dækning.
type Res = { data: unknown; error: unknown };
let mockTabelSvar: Record<string, Res> = {};

function mockKaede(tabel: string): unknown {
  const res = () => mockTabelSvar[tabel] ?? { data: [], error: null };
  const proxy: unknown = new Proxy(() => undefined, {
    get: (_t, prop) => {
      if (prop === 'then') return (ok: (v: Res) => unknown) => Promise.resolve(res()).then(ok);
      return () => proxy;
    },
  });
  return proxy;
}

jest.mock('../../lib/supabase', () => ({
  supabase: { from: (t: string) => mockKaede(t), rpc: jest.fn() },
}));

import { fetchPersonEvidence, fetchSammeSomLinks } from '../redaktionRead';

beforeEach(() => { mockTabelSvar = {}; });

describe('redaktionRead — orThrow', () => {
  it('fetchPersonEvidence kaster ved databasefejl i stedet for tom evidens', async () => {
    mockTabelSvar.fact = { data: null, error: { message: 'netfejl' } };
    await expect(fetchPersonEvidence('7')).rejects.toThrow('fetchPersonEvidence/fact: netfejl');
  });

  it('fetchPersonEvidence kaster ved fejl i påstande (efter at fakta er læst)', async () => {
    mockTabelSvar.fact = { data: [{ id: 1, faktatype: 'fødsel' }], error: null };
    mockTabelSvar.assertion = { data: null, error: { message: 'RLS' } };
    await expect(fetchPersonEvidence('7')).rejects.toThrow('fetchPersonEvidence/assertion: RLS');
  });

  it('fetchPersonEvidence returnerer tom evidens, når der reelt ingen fakta er', async () => {
    mockTabelSvar.fact = { data: [], error: null };
    mockTabelSvar.person = { data: { koen: 'M' }, error: null };
    await expect(fetchPersonEvidence('7')).resolves.toEqual({ felter: {}, koen: 'M' });
  });

  it('fetchSammeSomLinks kaster ved fejl i stedet for at melde »ingen links«', async () => {
    mockTabelSvar.relation = { data: null, error: { message: 'timeout' } };
    await expect(fetchSammeSomLinks('7')).rejects.toThrow('fetchSammeSomLinks: timeout');
  });
});
