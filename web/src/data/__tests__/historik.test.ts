// Issue #144: ændringshistorik pr. person i web-redaktøren.
// mapHistRow er PORTERET fra mobile/src/data/redaktionRead.ts (hold i sync) og udvidet
// med erFortryd: et fortryd-sæt logger bevidst ingen child-events (schema.sql,
// red_fortryd_change_set), så det kan ikke selv fortrydes — UI'et skal skjule knappen.
import { beforeEach, expect, test, vi } from 'vitest';
import { fetchHistorik, mapHistRow } from '../historik';
import { supabase } from '../../supabase';

vi.mock('../../supabase', () => ({
  supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } },
}));

beforeEach(() => {
  vi.clearAllMocks();
});

const raw = (over: Record<string, unknown> = {}) => ({
  id: 42, actor_navn: 'Johan', created_at: '2026-08-06T10:00:00Z',
  operation: 'red_upsert_fakta', summary: 'Rettede fødselsdato', reverterer_id: null,
  ...over,
});

test('mapHistRow mapper felter og defaulter tomme', () => {
  const post = mapHistRow(raw());
  expect(post.id).toBe('42');
  expect(post.hvem).toBe('Johan');
  expect(post.resume).toBe('Rettede fødselsdato');
  expect(post.reverteret).toBe(false);
  expect(post.erFortryd).toBe(false);
  expect(mapHistRow(raw({ actor_navn: null, summary: null })).hvem).toBe('ukendt');
  expect(mapHistRow(raw({ actor_navn: null, summary: null })).resume).toBe('(uden beskrivelse)');
});

test('mapHistRow markerer reverteret via listens reverterer_id-mængde, ikke rækken selv', () => {
  expect(mapHistRow(raw(), new Set([42])).reverteret).toBe(true);
  expect(mapHistRow(raw(), new Set([7])).reverteret).toBe(false);
});

test('mapHistRow markerer fortryd-sæt (operation=fortryd) som erFortryd', () => {
  expect(mapHistRow(raw({ operation: 'fortryd' })).erFortryd).toBe(true);
});

test('fetchHistorik kalder hist_for_subjekt med rå person-id og afleder reverted-mængden', async () => {
  (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({
    data: [
      raw({ id: 2, operation: 'fortryd', reverterer_id: 1, summary: 'Fortrød: Rettede fødselsdato' }),
      raw({ id: 1 }),
    ],
    error: null,
  });
  const poster = await fetchHistorik('7');
  expect(supabase.rpc).toHaveBeenCalledWith('hist_for_subjekt', { p_type: 'person', p_id: 7 });
  expect(poster.map((p) => [p.id, p.reverteret, p.erFortryd])).toEqual([
    ['2', false, true],
    ['1', true, false],
  ]);
});

test('fetchHistorik kaster på RPC-fejl', async () => {
  (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({ data: null, error: { message: 'Kun redaktion' } });
  await expect(fetchHistorik('7')).rejects.toThrow('Kun redaktion');
});
