import { describe, it, expect, vi } from 'vitest';

// public.ts importerer '../supabase' på modul-niveau (kaster uden VITE_SUPABASE_URL/ANON_KEY i
// test-miljøet); public.ts importerer også media.ts, der kalder supabase.auth.onAuthStateChange
// ved modul-load — mockes minimalt, da orThrow selv ikke rører supabase-klienten (samme mønster
// som bookmarks.test.ts).
vi.mock('../../supabase', () => ({ supabase: { auth: { onAuthStateChange: () => {} } } }));

import { orThrow } from '../public';

describe('orThrow', () => {
  it('returnerer data når error er null', () => {
    expect(orThrow({ data: [1, 2, 3], error: null }, 'label')).toEqual([1, 2, 3]);
  });

  it('returnerer data når error er undefined', () => {
    expect(orThrow({ data: 'x', error: undefined }, 'label')).toBe('x');
  });

  it('kaster når error er tilstede', () => {
    expect(() => orThrow({ data: null, error: { message: 'boom' } }, 'mit-label')).toThrow(/mit-label/);
  });

  it('den kastede fejls .cause er det oprindelige error-objekt', () => {
    const originalError = { message: 'boom', code: '42P01' };
    try {
      orThrow({ data: null, error: originalError }, 'label');
      expect.unreachable('skulle have kastet');
    } catch (e) {
      expect((e as Error).cause).toBe(originalError);
    }
  });
});
