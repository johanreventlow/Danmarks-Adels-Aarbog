// Skilsmisser: fetchSkilsmisser mod en lille hukommelses-database — kun afklarede skilsmisse-fakta på familier;
// en fejl giver null (ukendt, fail-closed), ingen rækker giver {}.
import { expect, test, vi } from 'vitest';

type Row = Record<string, unknown>;
const db: Record<string, Row[]> = {
  fact: [
    { id: 30, subjekt_type: 'family', subjekt_id: 10, faktatype: 'skilsmisse' },
    { id: 31, subjekt_type: 'family', subjekt_id: 11, faktatype: 'skilsmisse' },
    { id: 32, subjekt_type: 'family', subjekt_id: 12, faktatype: 'vielse' },
    { id: 33, subjekt_type: 'person', subjekt_id: 13, faktatype: 'skilsmisse' },
  ],
  conclusion: [
    { id: 1, target_type: 'fact', target_id: 30, valgt_assertion_id: 300, status: 'afklaret' },
    { id: 2, target_type: 'fact', target_id: 31, valgt_assertion_id: 301, status: 'omstridt' },
  ],
  assertion: [
    { id: 300, date_min: '1970-01-01', date_max: '1970-12-31' },
    { id: 301, date_min: null, date_max: null },
  ],
};
const mode = vi.hoisted(() => ({ fejlPaa: '' as string, tom: false }));

function query(table: string) {
  const filtre: ((r: Row) => boolean)[] = [];
  const q = {
    select: () => q,
    eq: (k: string, v: unknown) => { filtre.push((r) => r[k] === v); return q; },
    in: (k: string, vs: unknown[]) => { filtre.push((r) => vs.map(String).includes(String(r[k]))); return q; },
    order: () => q,
    range: async (from: number, to: number) => {
      if (mode.fejlPaa === table) return { data: null, error: { message: 'netværk' } };
      const rows = mode.tom ? [] : (db[table] ?? []);
      return { data: rows.filter((r) => filtre.every((f) => f(r))).slice(from, to + 1), error: null };
    },
  };
  return q;
}
vi.mock('../../supabase', () => ({ supabase: { from: (t: string) => query(t) } }));
const { fetchSkilsmisser } = await import('../skilsmisser');

test('kun afklarede skilsmisser på familier giver indeks', async () => {
  mode.fejlPaa = ''; mode.tom = false;
  expect(await fetchSkilsmisser()).toEqual({ '10': { dateMin: '1970-01-01', dateMax: '1970-12-31' } });
});

test('ingen rækker giver tom indeks, ikke null', async () => {
  mode.fejlPaa = ''; mode.tom = true;
  expect(await fetchSkilsmisser()).toEqual({});
});

test('en fejl (også i andet kald) giver null — ukendt, ikke ingen', async () => {
  mode.fejlPaa = 'conclusion'; mode.tom = false;
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  expect(await fetchSkilsmisser()).toBeNull();
  expect(warn).toHaveBeenCalled();
  warn.mockRestore();
});
