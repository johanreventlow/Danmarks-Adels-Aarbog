// Linjernes adelsnavn (plan 2026-11-26): fetchLinjeAdelsnavne mod en lille hukommelses-database — kun afklarede
// konklusioner på lineage-fakta af typen adelsnavn giver regler; en fejl giver ingen regler (siden vises som før).
import { expect, test, vi } from 'vitest';

type Row = Record<string, unknown>;
const db: Record<string, Row[]> = {
  fact: [
    { id: 20, subjekt_type: 'lineage', subjekt_id: 4, faktatype: 'adelsnavn' },
    { id: 21, subjekt_type: 'lineage', subjekt_id: 5, faktatype: 'adelsnavn' },
    { id: 22, subjekt_type: 'lineage', subjekt_id: 7, faktatype: 'adelsnavn' },
    { id: 23, subjekt_type: 'person', subjekt_id: 5, faktatype: 'adelsnavn' },
  ],
  conclusion: [
    { id: 99, target_type: 'fact', target_id: 20, valgt_assertion_id: 199, status: 'afklaret' },
    { id: 100, target_type: 'fact', target_id: 21, valgt_assertion_id: 200, status: 'afklaret' },
    { id: 101, target_type: 'fact', target_id: 22, valgt_assertion_id: 201, status: 'omstridt' },
    { id: 102, target_type: 'fact', target_id: 23, valgt_assertion_id: 202, status: 'afklaret' },
  ],
  assertion: [
    { id: 199, vaerdi_tekst: 'de Reventlou' },
    { id: 200, vaerdi_tekst: 'af Reventlow' },
    { id: 201, vaerdi_tekst: 'omstridt' },
    { id: 202, vaerdi_tekst: 'personfakta tæller ikke' },
  ],
};
const fejl = vi.hoisted(() => ({ v: false }));

function query(table: string) {
  const filtre: ((r: Row) => boolean)[] = [];
  const q = {
    select: () => q,
    eq: (k: string, v: unknown) => { filtre.push((r) => r[k] === v); return q; },
    in: (k: string, vs: unknown[]) => { filtre.push((r) => vs.map(String).includes(String(r[k]))); return q; },
    order: () => q,
    range: async (from: number, to: number) => (fejl.v
      ? { data: null, error: { message: 'netværk' } }
      : { data: (db[table] ?? []).filter((r) => filtre.every((f) => f(r))).slice(from, to + 1), error: null }),
  };
  return q;
}
vi.mock('../../supabase', () => ({ supabase: { from: (t: string) => query(t) } }));
const { fetchLinjeAdelsnavne } = await import('../adelsnavn');

test('kun afklarede adelsnavne på linjer', async () => {
  fejl.v = false;
  expect(await fetchLinjeAdelsnavne()).toEqual({ '4': 'de Reventlou', '5': 'af Reventlow' });
});

test('en fejl giver ingen regler', async () => {
  fejl.v = true;
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  expect(await fetchLinjeAdelsnavne()).toEqual({});
  expect(warn).toHaveBeenCalled();
  warn.mockRestore();
});
