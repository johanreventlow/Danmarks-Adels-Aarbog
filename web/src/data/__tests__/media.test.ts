import { describe, expect, it, vi } from 'vitest';

vi.mock('../../supabase', () => ({
  supabase: {
    storage: { from: vi.fn() },
    auth: { onAuthStateChange: vi.fn() },
    from: vi.fn(),
  },
}));

import { dedupPreferPrimaer, pickPortrait, type MediaItem } from '../media';

const m = (id: number, slags: string, url: string | null, primaer?: boolean): MediaItem =>
  ({ id: String(id), slags, titel: '', kunstner: '', datering: '', url, thumbUrl: url, primaer });

describe('pickPortrait med primaer-flag (fase 4)', () => {
  it('primaer vinder over slags-heuristikken', () => {
    expect(pickPortrait([m(1, 'maleri', 'u1'), m(2, 'segl', 'u2', true)])?.id).toBe('2');
  });

  it('usignerbar primaer ignoreres (fallback til heuristik)', () => {
    expect(pickPortrait([m(1, 'segl', null, true), m(2, 'maleri', 'u2')])?.id).toBe('2');
  });

  it('uden primaer gælder den gamle heuristik uændret', () => {
    expect(pickPortrait([m(1, 'segl', 'u1'), m(2, 'maleri', 'u2')])?.id).toBe('2');
    expect(pickPortrait([m(1, 'segl', 'u1'), m(2, 'dokument', 'u2')])?.id).toBe('1');
  });
});

describe('dedupPreferPrimaer (fetchPersonMedia foldet dedup, fase 4 review-fund)', () => {
  // Reproducerer Codex-fundet: to foldede samme_som-aliaser kan hver have deres egen
  // 'afbildet'-relation til det SAMME medie-id, én med primaer=true, én uden — og der er ingen
  // ORDER BY der garanterer hvilken der behandles først. Et naivt "første forekomst vinder"-filter
  // taber primaer=true, hvis den ikke-primaer kopi tilfældigvis kommer først. Testes i BEGGE
  // rækkefølger, netop fordi den oprindelige bug kun viste sig i den ene.
  it('primaer:true overlever uanset rækkefølge (primaer først)', () => {
    const primaerFoerst = [m(5, 'maleri', 'u5', true), m(5, 'maleri', 'u5', false)];
    const result = dedupPreferPrimaer(primaerFoerst);
    expect(result).toHaveLength(1);
    expect(result[0].primaer).toBe(true);
  });

  it('primaer:true overlever uanset rækkefølge (primaer sidst)', () => {
    const primaerSidst = [m(5, 'maleri', 'u5', false), m(5, 'maleri', 'u5', true)];
    const result = dedupPreferPrimaer(primaerSidst);
    expect(result).toHaveLength(1);
    expect(result[0].primaer).toBe(true);
  });

  it('ingen duplikater påvirkes ikke', () => {
    const result = dedupPreferPrimaer([m(1, 'maleri', 'u1'), m(2, 'segl', 'u2', true)]);
    expect(result.map((r) => r.id)).toEqual(['1', '2']);
  });
});
