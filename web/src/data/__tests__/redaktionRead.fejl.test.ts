// W3: en Supabase-fejl i redaktionens læselag skal KASTE, ikke blive til "ingen data".
import { describe, expect, test, vi } from 'vitest';

const res = vi.hoisted(() => ({ error: { message: 'permission denied for table fact' } as { message: string } | null }));

// Kædbar, afventelig builder: ethvert metodekald returnerer builderen; await giver { data: null, error }.
vi.mock('../../supabase', () => {
  const builder: Record<string, unknown> = new Proxy({}, {
    get(_t, prop) {
      if (prop === 'then') return (ok: (v: unknown) => unknown) => Promise.resolve({ data: null, error: res.error }).then(ok);
      return () => builder;
    },
  });
  return { supabase: { from: () => builder, rpc: () => builder, auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } };
});

import { fetchPersonEvidence, fetchSammeSomLinks, fetchForaeldreSlot, fetchBarnFamilie } from '../redaktionRead';
import { fetchMediaFakta } from '../media';
import { orThrow } from '../orThrow';

describe('orThrow', () => {
  test('returnerer data uden fejl og kaster med label ved fejl', () => {
    expect(orThrow({ data: [1], error: null }, 'x')).toEqual([1]);
    expect(() => orThrow({ data: null, error: { message: 'nej' } }, 'lbl')).toThrow('lbl: nej');
  });
});

describe('redaktionRead/media — databasefejl kaster', () => {
  test('fetchPersonEvidence', async () => {
    await expect(fetchPersonEvidence('1')).rejects.toThrow(/fetchPersonEvidence\/fact: permission denied/);
  });
  test('fetchSammeSomLinks', async () => {
    await expect(fetchSammeSomLinks('1')).rejects.toThrow(/fetchSammeSomLinks: permission denied/);
  });
  test('fetchForaeldreSlot', async () => {
    await expect(fetchForaeldreSlot('1')).rejects.toThrow(/fetchForaeldreSlot\/fact/);
  });
  test('fetchBarnFamilie', async () => {
    await expect(fetchBarnFamilie('1')).rejects.toThrow(/fetchBarnFamilie\/family_member/);
  });
  test('fetchMediaFakta', async () => {
    await expect(fetchMediaFakta([1])).rejects.toThrow(/fetchMediaFakta\/fact/);
  });
});
