// Review 37 Y2: loadModel's samme_som-led. En fejl giver ikke længere en model med tavse dubletpersoner, og
// redaktionen (collapse: false) henter hverken relationer eller konklusioner til collapse.
import { beforeEach, describe, expect, it, vi } from 'vitest';

const hentet: string[] = [];
let relationFejler = false;

const TABELLER: Record<string, unknown[]> = {
  person: [
    { id: 1, visning_navn: 'A', visning_fuldt_navn: 'A', visning_foedt: null, visning_doed: null, visning_titel: null, koen: 'mand', privat: false },
    { id: 2, visning_navn: 'A', visning_fuldt_navn: 'A', visning_foedt: null, visning_doed: null, visning_titel: null, koen: 'mand', privat: false },
  ],
  relation: [{ id: 10, subjekt_id: 2, objekt_id: 1 }],
  conclusion: [{ target_id: 10 }],
};

function kaede(t: string) {
  const svar = () => (t === 'relation' && relationFejler
    ? { data: null, error: { message: 'relation utilgængelig' } }
    : { data: TABELLER[t] ?? [], error: null });
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'in', 'or', 'order', 'not', 'is']) q[m] = () => q;
  q.range = async (a: number, b: number) => {
    const s = svar();
    return s.error ? s : { data: (s.data as unknown[]).slice(a, b + 1), error: null };
  };
  q.then = (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(svar()).then(res, rej);
  return q;
}

vi.mock('../../supabase', () => ({
  supabase: {
    from: (t: string) => { hentet.push(t); return kaede(t); },
    rpc: () => kaede('rpc'),
  },
}));

vi.mock('../sammeSomKanter', async (orig) => {
  const m = await orig<typeof import('../sammeSomKanter')>();
  // Genforsøget uden ventetid i testen.
  return { ...m, hentSammeSomKanter: (sb: Parameters<typeof m.hentSammeSomKanter>[0]) => m.hentSammeSomKanter(sb, 0) };
});

const { loadModel } = await import('../model');

beforeEach(() => { hentet.length = 0; relationFejler = false; });

describe('loadModel samme_som (review 37 Y2)', () => {
  it('folder en afklaret samme_som-alias ind i den kanoniske person', async () => {
    const model = await loadModel();
    expect(model.canonicalIdById?.['2']).toBe('1');
    expect(model.persons.map((p) => p.id)).toEqual(['1']);
  });

  it('en vedvarende fejl afviser loadModel i stedet for at vise dubletter', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    relationFejler = true;
    await expect(loadModel()).rejects.toMatchObject({ message: 'relation utilgængelig' });
    warn.mockRestore();
  });

  it('collapse: false henter hverken relation eller conclusion til collapse', async () => {
    relationFejler = true; // ville afvise, hvis den blev hentet
    const model = await loadModel({ collapse: false });
    expect(model.persons.map((p) => p.id).sort()).toEqual(['1', '2']);
    expect(hentet).not.toContain('relation');
  });
});
