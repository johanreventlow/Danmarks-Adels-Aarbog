// Redaktøren ser levende (decisions 2026-11-13, trin 2): biografien for en person, gæster ikke kan se, findes kun som
// kladde (udgivelsesreglen tillader aldrig udgivelse af levende). Redaktøren får kladden med kildehenvisning fra
// red_person_narrative_records, mærket kunRedaktion. Læseren får intet ekstra kald.
import { beforeEach, describe, expect, it, vi } from 'vitest';

let personRows: unknown[] = [];
let personError: unknown = null;
const personIn = vi.fn();
let publicBio: unknown[] = [];
const redRows = new Map<number, unknown[]>();
let redError: unknown = null;
const rpcCalls: { name: string; args: unknown }[] = [];

function table(name: string) {
  const res = () => (name === 'person' ? { data: personRows, error: personError } : { data: [], error: null });
  const q: Record<string, unknown> = {};
  const chain = () => q;
  for (const m of ['select', 'eq', 'is', 'order', 'range', 'limit']) q[m] = chain;
  q.in = (...a: unknown[]) => { if (name === 'person') personIn(...a); return q; };
  q.then = (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) => Promise.resolve(res()).then(ok, ko);
  return q;
}
vi.mock('../../supabase', () => ({
  supabase: {
    from: (n: string) => table(n),
    rpc: (n: string, args: unknown) => {
      rpcCalls.push({ name: n, args });
      if (n === 'narrative_record_contract_version') return Promise.resolve({ data: 2, error: null });
      if (n === 'public_person_bio_source_versions_v2') return Promise.resolve({ data: publicBio, error: null });
      if (n === 'red_person_narrative_records') {
        const id = (args as { p_person_id: number }).p_person_id;
        return Promise.resolve(redError ? { data: null, error: redError } : { data: redRows.get(id) ?? [], error: null });
      }
      return Promise.resolve({ data: [], error: null });
    },
  },
}));
vi.mock('../media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => [], signPaths: async () => new Map(), fetchThumbPathByMediaId: async () => new Map() }));
const { fetchPersonDetail } = await import('../public');

const rec = (o: Record<string, unknown>) => ({
  source_id: 1, source_year: 2020, source_label: 'DAA 2018-20', provenance_kind: 'source_record', record_key: 'k1',
  source_record_ref: 'ref-1', legacy_publication_ref: null, narrative_id: 99, record_label: 'V-12',
  citation_label: 'DAA 2018-20, s. 201', narrative_text: 'Kladdetekst.', publication_status: 'draft',
  state_sha256: 'a'.repeat(64), allowed_actions: [], blocking_reason: null, ...o,
});
const pub = (o: Record<string, unknown>) => ({
  person_id: 1, source_id: 1, source_year: 2020, record_order: 1, source_record_ref: 'pub-1', source_label: 'DAA 2018-20',
  record_label: 'V-1', narrative_text: 'Offentlig tekst.', citation_label: 'DAA 2018-20, s. 9', provenance_kind: 'source_record', ...o,
});

beforeEach(() => {
  personRows = []; personError = null; personIn.mockReset(); publicBio = []; redRows.clear(); redError = null; rpcCalls.length = 0;
});

const redCalls = () => rpcCalls.filter((c) => c.name === 'red_person_narrative_records');

describe('fetchPersonDetail: redaktøren ser kladden for en ikke-offentlig person', () => {
  it('levende person: kladden bliver en version mærket kunRedaktion med kildehenvisning', async () => {
    personRows = [{ id: 7, levende: true, privat: false, staged: false }];
    redRows.set(7, [rec({})]);
    const d = await fetchPersonDetail('7', undefined, false, undefined, true);
    expect(d.bioVersions).toHaveLength(1);
    expect(d.bioVersions[0]).toMatchObject({
      narrativeText: 'Kladdetekst.', sourceLabel: 'DAA 2018-20', recordLabel: 'V-12', citationLabel: 'DAA 2018-20, s. 201',
      provenanceKind: 'source_record', kunRedaktion: true, sourceId: 1, sourceYear: 2020,
    });
    expect(d.bio).toBe('Kladdetekst.');
  });

  it('privat og staged person tæller som ikke-offentlig; levende ukendt (NULL) også', async () => {
    personRows = [
      { id: 1, levende: false, privat: true, staged: false },
      { id: 2, levende: false, privat: false, staged: true },
      { id: 3, levende: null, privat: false, staged: false },
    ];
    for (const id of [1, 2, 3]) redRows.set(id, [rec({ source_record_ref: `ref-${id}`, record_key: `k${id}` })]);
    const d = await fetchPersonDetail('1', ['1', '2', '3'], false, undefined, true);
    expect(redCalls().map((c) => (c.args as { p_person_id: number }).p_person_id).sort()).toEqual([1, 2, 3]);
    expect(d.bioVersions).toHaveLength(3);
  });

  it('kun kladde, udgivet og forældet-udgivet med tekst; trukket tilbage, ingen, blokeret og tom udelades', async () => {
    personRows = [{ id: 7, levende: true, privat: false, staged: false }];
    redRows.set(7, [
      rec({ record_key: 'a', source_record_ref: 'a', publication_status: 'draft' }),
      rec({ record_key: 'b', source_record_ref: 'b', publication_status: 'published' }),
      rec({ record_key: 'c', source_record_ref: 'c', publication_status: 'stale_published' }),
      rec({ record_key: 'd', source_record_ref: 'd', publication_status: 'withdrawn' }),
      rec({ record_key: 'e', source_record_ref: 'e', publication_status: 'none' }),
      rec({ record_key: 'f', source_record_ref: 'f', publication_status: 'draft', blocking_reason: 'X' }),
      rec({ record_key: 'g', source_record_ref: 'g', publication_status: 'draft', narrative_text: '   ' }),
    ]);
    const d = await fetchPersonDetail('7', undefined, false, undefined, true);
    expect(d.bioVersions.map((v) => v.recordRef).sort()).toEqual(['a', 'b', 'c']);
  });

  it('offentlig person: ingen redaktørkald, kun den offentlige biografi', async () => {
    personRows = [{ id: 1, levende: false, privat: false, staged: false }];
    publicBio = [pub({})];
    const d = await fetchPersonDetail('1', undefined, false, undefined, true);
    expect(redCalls()).toHaveLength(0);
    expect(d.bioVersions).toHaveLength(1);
    expect(d.bioVersions[0].kunRedaktion).toBeUndefined();
    expect(d.bio).toBe('Offentlig tekst.');
  });

  it('foldet gruppe: offentligt medlems biografi bevares, det levende medlems kladde lægges til', async () => {
    personRows = [{ id: 1, levende: false, privat: false, staged: false }, { id: 2, levende: true, privat: false, staged: false }];
    publicBio = [pub({})];
    redRows.set(2, [rec({ source_id: 3, source_year: 1939, source_label: 'DAA 1939', narrative_text: 'Kladde 1939.' })]);
    const d = await fetchPersonDetail('1', ['1', '2'], false, undefined, true);
    expect(redCalls().map((c) => (c.args as { p_person_id: number }).p_person_id)).toEqual([2]);
    expect(d.bioVersions.map((v) => v.narrativeText)).toEqual(['Offentlig tekst.', 'Kladde 1939.']);
    expect(d.bio).toBe('Offentlig tekst.');
  });

  it('læser (ikke redaktør): hverken personopslag eller redaktørkald', async () => {
    personRows = [{ id: 7, levende: true, privat: false, staged: false }];
    redRows.set(7, [rec({})]);
    const d = await fetchPersonDetail('7');
    expect(personIn).not.toHaveBeenCalled();
    expect(redCalls()).toHaveLength(0);
    expect(d.bioVersions).toEqual([]);
  });

  it('fejl i redaktørkaldet giver ingen kladder, men resten af detaljen står', async () => {
    personRows = [{ id: 7, levende: true, privat: false, staged: false }];
    redError = { message: 'REDAKTION_REQUIRED' };
    const d = await fetchPersonDetail('7', undefined, false, undefined, true);
    expect(d.bioVersions).toEqual([]);
    expect(d.factsError).toBe(false);
  });

  it('fejl i personopslaget giver ingen kladder', async () => {
    personError = { message: 'boom' };
    const d = await fetchPersonDetail('7', undefined, false, undefined, true);
    expect(redCalls()).toHaveLength(0);
    expect(d.bioVersions).toEqual([]);
  });
});
