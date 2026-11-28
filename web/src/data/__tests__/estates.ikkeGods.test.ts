// #471 (8b): rækker markeret »ikke et gods« skjules i listen og søgningen, men er stadig hentet (direkte link) og
// slås stadig op på navn; personsidens besiddelser får dem ikke med.
import { describe, expect, it, vi } from 'vitest';

const ESTATES = [
  { id: 5, navn: 'Christianssæde', slags: 'grevskab' },
  { id: 7, navn: 'Bukkehave', slags: 'gård' },
  { id: 9, navn: 'Forlening af Preetz Kloster (1399)', slags: 'ikke_gods' },
];
function table(name: string) {
  const q: Record<string, unknown> = {};
  q.select = () => q;
  q.eq = () => q;
  q.in = () => q;
  q.order = () => q;
  q.range = async () => {
    if (name === 'estate') return { data: ESTATES, error: null };
    if (name === 'relation') return { data: [{ subjekt_id: 1, objekt_id: 9 }, { subjekt_id: 1, objekt_id: 7 }], error: null };
    return { data: [], error: null };
  };
  // resolveOrgEstateNames læser uden range (thenable).
  q.then = (res: (v: unknown) => unknown) => Promise.resolve({ data: name === 'estate' ? ESTATES : [], error: null }).then(res);
  return q;
}
vi.mock('../../supabase', () => ({ supabase: { auth: { onAuthStateChange: () => {} }, from: (n: string) => table(n), rpc: async () => ({ data: [], error: null }) } }));
vi.mock('../media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => new Map() }));
const { fetchEstates, resolveOrgEstateNames } = await import('../public');
const { soeg } = await import('../soeg');

describe('»ikke et gods« i web-data (#471)', () => {
  it('fetchEstates skjuler rækken fra listen, men giver den i ikkeGods', async () => {
    const d = await fetchEstates();
    expect(d.estates.map((e) => e.id).sort()).toEqual(['5', '7']);
    expect(d.ikkeGods.map((e) => e.id)).toEqual(['9']);
    expect(d.ikkeGods[0].slags).toBe('ikke_gods');
  });
  it('søgningen finder ikke rækken', async () => {
    const d = await fetchEstates();
    const model = { persons: [], byId: {}, lineage: [] } as never;
    const r = soeg(model, d.estates, { q: 'Preetz', type: 'alle', sort: 'navn', linje: null, fra: null, til: null, bm: false } as never);
    expect(r.godser).toEqual([]);
  });
  it('resolveOrgEstateNames markerer rækken, så personsiden kan udelade den', async () => {
    const r = await resolveOrgEstateNames([], [7, 9]);
    expect([...r.estateIkkeGods]).toEqual(['9']);
    expect(r.estate.get('9')).toBe('Forlening af Preetz Kloster (1399)');
  });
});
