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
  (supabase.rpc as ReturnType<typeof vi.fn>).mockImplementation((name: string) => {
    if (name === 'hist_for_subjekt') return Promise.resolve({ data: [
      raw({ id: 2, operation: 'fortryd', reverterer_id: 1, summary: 'Fortrød: Rettede fødselsdato' }),
      raw({ id: 1 }),
    ], error: null });
    if (name === 'red_person_narrative_publication_history') return Promise.resolve({ data: [], error: null });
    throw new Error(`uventet RPC: ${name}`);
  });
  const poster = await fetchHistorik('7');
  expect(supabase.rpc).toHaveBeenCalledWith('hist_for_subjekt', { p_type: 'person', p_id: 7 });
  expect(poster.map((p) => [p.id, p.reverteret, p.erFortryd])).toEqual([
    ['2', false, true],
    ['1', true, false],
  ]);
});

test('fetchHistorik merges publication events and marks reversal events without an undo action', async () => {
  (supabase.rpc as ReturnType<typeof vi.fn>).mockImplementation((name: string) => {
    if (name === 'hist_for_subjekt') return Promise.resolve({ data: [raw({ id: 44 }), raw({ id: 1 })], error: null });
    if (name === 'red_person_narrative_publication_history') return Promise.resolve({ data: [{
      event_id: 'f6f58094-9ed2-4723-ac21-7c0ba25f2cf9', change_set_id: 44, stream_version: 3,
      event_type: 'reversal', source_record_ref: '92cccd2e-1731-4db3-bffd-e68c8a686e35', legacy_publication_ref: null,
      before_state_sha256: 'a'.repeat(64), after_state_sha256: 'b'.repeat(64), before_text: 'Før', after_text: 'Efter',
      decided_by_name: 'Johan', created_at: '2026-08-06T11:00:00Z', can_reverse: false,
      blocking_reason: 'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE',
    }], error: null });
    throw new Error(`uventet RPC: ${name}`);
  });

  const posts = await fetchHistorik('7');
  expect(supabase.rpc).toHaveBeenNthCalledWith(1, 'hist_for_subjekt', { p_type: 'person', p_id: 7 });
  expect(supabase.rpc).toHaveBeenNthCalledWith(2, 'red_person_narrative_publication_history', { p_person_id: 7 });
  expect(posts).toEqual(expect.arrayContaining([
    expect.objectContaining({ id: '1', undoKind: 'change_set', canReverse: true }),
    expect.objectContaining({
      id: 'f6f58094-9ed2-4723-ac21-7c0ba25f2cf9', undoKind: 'publication_event',
      erFortryd: true, canReverse: false,
      blockingReason: 'NARRATIVE_PUBLICATION_REVERSAL_NOT_REVERSIBLE',
      changeSetId: '44',
      sourceRecordRef: '92cccd2e-1731-4db3-bffd-e68c8a686e35',
    }),
  ]));
  expect(posts).not.toEqual(expect.arrayContaining([
    expect.objectContaining({ id: '44', undoKind: 'change_set' }),
  ]));
});

test('fetchHistorik kaster på RPC-fejl', async () => {
  (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({ data: null, error: { message: 'Kun redaktion' } });
  await expect(fetchHistorik('7')).rejects.toThrow('Kun redaktion');
});
