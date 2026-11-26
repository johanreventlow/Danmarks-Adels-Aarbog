// #471: sammenlagte godser skjules i listen, og »hører under« hentes i ét filtreret relation-opslag.
import { describe, expect, it, vi } from 'vitest';

const fejlGodsRels = { paa: false };
const kald: { tabel: string; filtre: Record<string, unknown> }[] = [];
const ESTATES = [
  { id: 5, navn: 'Christianssæde', slags: 'grevskab' },
  { id: 405, navn: 'Christianssæde (gammel)', slags: 'gård' },
  { id: 7, navn: 'Bukkehave', slags: 'gård' },
];
const PERSON_EJER = [{ subjekt_id: 1, objekt_id: 7 }];
const GODS_RELS = [
  { subjekt_id: 405, objekt_id: 5, rolle: 'sammenlagt_i', periode_raw: null },
  { subjekt_id: 7, objekt_id: 5, rolle: 'hører_under', periode_raw: '(1700-1800)' },
  { subjekt_id: 405, objekt_id: 5, rolle: 'hører_under', periode_raw: '' }, // gård = sammenlagt ind i majoratet selv → udelades
];
function table(name: string) {
  const filtre: Record<string, unknown> = {};
  const q: Record<string, unknown> = {};
  q.select = () => q;
  q.eq = (k: string, v: unknown) => { filtre[k] = v; return q; };
  q.in = (k: string, v: unknown) => { filtre[k] = v; return q; };
  q.order = () => q;
  q.range = async () => {
    kald.push({ tabel: name, filtre: { ...filtre } });
    if (name === 'estate') return { data: ESTATES, error: null };
    if (name === 'relation' && filtre.subjekt_type === 'estate' && fejlGodsRels.paa) return { data: null, error: { message: 'timeout', code: '57014' } };
    if (name === 'relation') return { data: filtre.subjekt_type === 'estate' ? GODS_RELS : PERSON_EJER, error: null };
    return { data: [], error: null };
  };
  return q;
}
vi.mock('../../supabase', () => ({ supabase: { auth: { onAuthStateChange: () => {} }, from: (n: string) => table(n), rpc: async () => ({ data: [], error: null }) } }));
vi.mock('../media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => new Map() }));
const { fetchEstates } = await import('../public');
const { soeg } = await import('../soeg');

describe('fetchEstates med sammenlagte godser (#471)', () => {
  it('udelader den sammenlagte række og leverer kantkortet og »hører under«', async () => {
    const d = await fetchEstates();
    expect(d.estates.map((e) => e.id).sort()).toEqual(['5', '7']);
    expect([...d.sammenlagt]).toEqual([['405', '5']]);
    expect(d.hoererUnder).toEqual([{ gaard: '7', majorat: '5', periode: '(1700-1800)' }]);
  });
  it('henter gods→gods-relationerne i ét opslag filtreret på rolle', async () => {
    kald.length = 0;
    await fetchEstates();
    const godsKald = kald.filter((k) => k.tabel === 'relation' && k.filtre.subjekt_type === 'estate');
    expect(godsKald).toHaveLength(1);
    expect(godsKald[0].filtre).toMatchObject({ objekt_type: 'estate', rolle: ['sammenlagt_i', 'hører_under'] });
  });
  it('søgningen finder ikke den sammenlagte række', async () => {
    const d = await fetchEstates();
    const model = { persons: [], byId: {}, lineage: [] } as never;
    const r = soeg(model, d.estates, { q: 'Christianssæde', type: 'alle', sort: 'navn', linje: null, fra: null, til: null, bm: false } as never);
    expect(r.godser.map((g) => g.id)).toEqual(['5']);
  });
  it('en fejl i KUN gods→gods-opslaget lader listen stå som før (ingen skjulte, ingen hører under)', async () => {
    fejlGodsRels.paa = true;
    try {
      const d = await fetchEstates();
      expect(d.estates.map((e) => e.id).sort()).toEqual(['405', '5', '7']);
      expect(d.sammenlagt.size).toBe(0);
      expect(d.hoererUnder).toEqual([]);
    } finally { fejlGodsRels.paa = false; }
  });
});
