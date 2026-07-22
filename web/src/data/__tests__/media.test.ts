import { describe, expect, it, vi } from 'vitest';

vi.mock('../../supabase', () => ({
  supabase: {
    storage: { from: vi.fn() },
    auth: { onAuthStateChange: vi.fn() },
    from: vi.fn(),
  },
}));

import { pickPortrait, type MediaItem } from '../media';

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
