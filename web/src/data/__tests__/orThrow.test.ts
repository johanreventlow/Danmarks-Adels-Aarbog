import { describe, it, expect, vi } from 'vitest';

// public.ts importerer '../supabase' på modul-niveau (kaster uden VITE_SUPABASE_URL/ANON_KEY i
// test-miljøet); public.ts importerer også media.ts, der kalder supabase.auth.onAuthStateChange
// ved modul-load — mockes minimalt, da orThrow selv ikke rører supabase-klienten (samme mønster
// som bookmarks.test.ts).
vi.mock('../../supabase', () => ({ supabase: { auth: { onAuthStateChange: () => {} } } }));

import { mapPublicBioSourceVersions, orThrow } from '../public';

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

describe('mapPublicBioSourceVersions', () => {
  it('bevarer recorde fra samme bog separat og ignorerer ekstra private felter', () => {
    const versions = mapPublicBioSourceVersions([
      { record_ref: 'safe-b', source_label: 'DAA 1939', record_label: 'Linje I, nr. 2', narrative_text: 'B', citation_label: 's. 2', provenance_kind: 'source_record', source_record_id: 'privat-uuid' },
      { record_ref: 'safe-a', source_label: 'DAA 1939', record_label: 'Linje I, nr. 1', narrative_text: 'A', citation_label: 's. 1', provenance_kind: 'source_record' },
      { record_ref: null, source_label: 'DAA 1939', record_label: 'Overgangsdata', narrative_text: 'Gammel', citation_label: '', provenance_kind: 'legacy_narrative' },
    ]);
    expect(versions.map((v) => v.recordRef)).toEqual(['safe-a', 'safe-b', null]);
    expect(versions[0]).not.toHaveProperty('sourceRecordId');
  });
});
