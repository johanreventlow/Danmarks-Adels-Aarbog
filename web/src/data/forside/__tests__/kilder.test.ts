import { afterEach, describe, expect, it, vi } from 'vitest';

// En lokal mock-klient (ikke vi.mock af ../../supabase): kilder.ts skal kunne køre med enhver klient, også i Vercel-
// funktionen, hvor den env-bundne browserklient ikke findes.
type Svar = { data: unknown; error: unknown };
const klient = (tabeller: Record<string, Svar>, rpc: (navn: string, args: Record<string, unknown>) => Svar = () => ({ data: null, error: { message: 'ingen rpc' } })) => ({
  from(table: string) {
    const b: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'order']) b[m] = () => b;
    b.range = async () => tabeller[table] ?? { data: [], error: null };
    b.then = (resolve: (v: Svar) => void) => resolve(tabeller[table] ?? { data: [], error: null });
    return b;
  },
  async rpc(navn: string, args: Record<string, unknown>) { return rpc(navn, args); },
});

afterEach(() => { vi.unstubAllEnvs(); vi.resetModules(); });

describe('forside/kilder', () => {
  it.each(['../kilder', '../../feedAux', '../../haendelser'])('%s importerer ikke den env-bundne klient', async (modul) => {
    vi.stubEnv('VITE_SUPABASE_URL', '');
    vi.stubEnv('VITE_SUPABASE_ANON_KEY', '');
    await expect(import(/* @vite-ignore */ modul)).resolves.toBeTruthy();
  });

  it('hentLivsdatoRaekker kaster ved fejl (sluger den ikke som browserens loader)', async () => {
    const { hentLivsdatoRaekker } = await import('../kilder');
    const sb = klient({ fact: { data: null, error: { message: 'timeout' } } });
    await expect(hentLivsdatoRaekker(sb as never)).rejects.toBeTruthy();
  });

  it('hentPersonIder giver sorterede tal', async () => {
    const { hentPersonIder } = await import('../kilder');
    const sb = klient({ person: { data: [{ id: 12 }, { id: '3' }, { id: 7 }], error: null } });
    expect(await hentPersonIder(sb as never)).toEqual([3, 7, 12]);
  });

  it('hentPersonerMedBilledeRaa: kun personer bag billeder, gæsten kan se', async () => {
    const { hentPersonerMedBilledeRaa } = await import('../kilder');
    const sb = klient({
      relation: { data: [{ subjekt_id: 17, objekt_id: 1 }, { subjekt_id: 3, objekt_id: 2 }, { subjekt_id: '17', objekt_id: 4 }], error: null },
      // RLS skjuler medie 2 (fx en levende afbildet) og 4 (ikke frigivet): kun medie 1 kommer tilbage.
      media: { data: [{ id: 1 }], error: null },
    });
    expect(await hentPersonerMedBilledeRaa(sb as never)).toEqual(['17']);
  });

  it('hentPersonerMedBilledeRaa kaster ved fejl', async () => {
    const { hentPersonerMedBilledeRaa } = await import('../kilder');
    const sb = klient({ relation: { data: [{ subjekt_id: 1, objekt_id: 1 }], error: null }, media: { data: null, error: { message: 'timeout' } } });
    await expect(hentPersonerMedBilledeRaa(sb as never)).rejects.toBeTruthy();
  });

  it('vaelgFeedBios udelader en kanonisk person med et fejlet alias', async () => {
    const { vaelgFeedBios } = await import('../vaelgBios');
    const row = (id: number, tekst: string) => ({ person_id: id, source_id: 1, source_year: 2018, record_order: 1, source_record_ref: 'r' + id, source_label: 'DAA', record_label: 'Post', narrative_text: tekst, citation_label: '', provenance_kind: 'source_record' });
    const bios = vaelgFeedBios({ kontrakt: 2, rows: [row(1, 'Et'), row(2, 'To')], fejlede: [3] }, { '1': 'canon', '3': 'canon' });
    expect(bios).toEqual({ '2': 'To' });
  });
});
