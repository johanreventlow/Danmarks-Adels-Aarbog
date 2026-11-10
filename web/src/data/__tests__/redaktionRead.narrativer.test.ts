import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fetchOverviewMarks, fetchOverviewMentionSources, fetchOverviewMentions, fetchPersonNarrativeRecords, mapNarrativeRecordRows, mapNarrativer } from '../redaktionRead';
import { supabase } from '../../supabase';

vi.mock('../../supabase', () => ({
  supabase: { rpc: vi.fn(), from: vi.fn(), auth: { onAuthStateChange: vi.fn() } },
}));

beforeEach(() => {
  vi.clearAllMocks();
});

describe('mapNarrativer', () => {
  it('mapper rækker med source-join, ordnet efter source_id så id', () => {
    const rows = [
      { id: 7, source_id: 2, side: null, tekst: 'B', privat: false, source: { titel: 'DAA 1982', udgave: 'DAA 1982-84' } },
      { id: 3, source_id: 1, side: '10', tekst: 'A', privat: true, source: { titel: 'DAA 2018', udgave: 'DAA 2018-20' } },
    ];
    const out = mapNarrativer(rows as any);
    expect(out.map((n) => n.id)).toEqual([3, 7]);
    expect(out[0]).toMatchObject({ sourceId: 1, udgave: 'DAA 2018-20', side: '10', privat: true, tekst: 'A' });
    expect(out[1]).toMatchObject({ sourceId: 2, udgave: 'DAA 1982-84', side: null, privat: false });
  });
  it('håndterer manglende source-join (null)', () => {
    const out = mapNarrativer([{ id: 1, source_id: null, side: null, tekst: 'x', privat: null, source: null }] as any);
    expect(out[0]).toMatchObject({ sourceId: null, sourceTitel: null, udgave: null, privat: false });
  });
});

const recordRow = (overrides: Record<string, unknown> = {}) => ({
  person_id: 5,
  source_id: 19,
  source_year: 1939,
  source_label: 'DAA 1939',
  provenance_kind: 'source_record',
  record_key: 'V-152',
  source_record_ref: '92cccd2e-1731-4db3-bffd-e68c8a686e35',
  legacy_publication_ref: null,
  record_order: 152,
  record_label: 'V-152',
  citation_label: 'DAA 1939, s. 152',
  narrative_id: null,
  narrative_text: null,
  narrative_private: false,
  narrative_side: null,
  publication_status: 'none',
  text_editable: true,
  allowed_actions: ['create_draft'],
  withdrawn_history: [],
  latest_event_version: null,
  published_text_sha256: null,
  eligibility_status: 'eligible',
  blocking_reason: null,
  state_sha256: 'a'.repeat(64),
  ...overrides,
});

const legacyRow = (overrides: Record<string, unknown> = {}) => ({
  ...recordRow({
    provenance_kind: 'grandfathered_legacy',
    record_key: null,
    source_record_ref: null,
    legacy_publication_ref: 'f6f58094-9ed2-4723-ac21-7c0ba25f2cf9',
    narrative_id: 501,
    publication_status: 'published',
    narrative_text: 'Bevaret overgangstekst',
    allowed_actions: ['withdraw_legacy'],
  }),
  ...overrides,
});

describe('narrative record read-adapter', () => {
  it('maps record and legacy rows without exposing an internal record identity', () => {
    const mapped = mapNarrativeRecordRows([recordRow(), legacyRow()]);

    expect(mapped.records).toEqual([{
      sourceId: 19,
      sourceYear: 1939,
      sourceLabel: 'DAA 1939',
      recordKey: 'V-152',
      sourceRecordRef: '92cccd2e-1731-4db3-bffd-e68c8a686e35',
      status: 'none',
      stateSha256: 'a'.repeat(64),
      text: '',
      recordLabel: 'V-152',
      citationLabel: 'DAA 1939, s. 152',
      allowedActions: ['create_draft'],
      blockingReason: null,
    }]);
    expect(mapped.legacyPublications).toEqual([{
      legacyPublicationRef: 'f6f58094-9ed2-4723-ac21-7c0ba25f2cf9',
      sourceId: 19,
      narrativeId: 501,
      status: 'legacy_active',
      stateSha256: 'a'.repeat(64),
      text: 'Bevaret overgangstekst',
      allowedActions: ['withdraw_legacy'],
      blockingReason: null,
    }]);
  });

  it('legacy-række: source_id NULL giver sourceId null; ugyldig narrative_id er kontraktfejl', () => {
    expect(mapNarrativeRecordRows([legacyRow({ source_id: null })]).legacyPublications[0]).toMatchObject({ sourceId: null, narrativeId: 501 });
    expect(() => mapNarrativeRecordRows([legacyRow({ narrative_id: null })])).toThrow('NARRATIVE_RECORD_EDITOR_RESPONSE_INVALID');
    expect(() => mapNarrativeRecordRows([legacyRow({ narrative_id: 'x' })])).toThrow('NARRATIVE_RECORD_EDITOR_RESPONSE_INVALID');
    expect(() => mapNarrativeRecordRows([legacyRow({ source_id: 0 })])).toThrow('NARRATIVE_RECORD_EDITOR_RESPONSE_INVALID');
  });

  it('maps server record blocking and legacy publication statuses to the explicit client states', () => {
    const mapped = mapNarrativeRecordRows([
      recordRow({ publication_status: 'none', blocking_reason: 'NARRATIVE_RECORD_IDENTITY_REQUIRED', allowed_actions: [] }),
      legacyRow({ publication_status: 'stale_published', blocking_reason: 'NARRATIVE_LEGACY_BASELINE_DRIFT', allowed_actions: [] }),
      legacyRow({ legacy_publication_ref: 'e267a2e7-8e18-4205-831c-c74d71b294c5', publication_status: 'withdrawn', allowed_actions: [] }),
    ]);

    expect(mapped.records[0]).toMatchObject({ status: 'blocked', blockingReason: 'NARRATIVE_RECORD_IDENTITY_REQUIRED' });
    expect(mapped.legacyPublications).toEqual(expect.arrayContaining([
      expect.objectContaining({ status: 'legacy_active', blockingReason: 'NARRATIVE_LEGACY_BASELINE_DRIFT' }),
      expect.objectContaining({ status: 'legacy_withdrawn', blockingReason: null }),
    ]));
  });

  it('uses the v2 editor RPC and does not fall back when that RPC fails', async () => {
    const rpc = supabase.rpc as ReturnType<typeof vi.fn>;
    rpc.mockResolvedValueOnce({ data: 2, error: null });
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'NARRATIVE_RECORD_ROLE_FORBIDDEN' } });

    await expect(fetchPersonNarrativeRecords(5)).rejects.toThrow('NARRATIVE_RECORD_ROLE_FORBIDDEN');
    expect(rpc).toHaveBeenNthCalledWith(1, 'narrative_record_contract_version', {});
    expect(rpc).toHaveBeenNthCalledWith(2, 'red_person_narrative_records', { p_person_id: 5 });
    expect(supabase.from).not.toHaveBeenCalled();
  });

  it('uses the record RPC only at contract version 2 and maps its complete response', async () => {
    const rpc = supabase.rpc as ReturnType<typeof vi.fn>;
    rpc.mockResolvedValueOnce({ data: 2, error: null });
    rpc.mockResolvedValueOnce({ data: [recordRow(), legacyRow()], error: null });

    await expect(fetchPersonNarrativeRecords(5)).resolves.toMatchObject({
      records: [{ sourceId: 19, recordKey: 'V-152', allowedActions: ['create_draft'] }],
      legacyPublications: [{ status: 'legacy_active', allowedActions: ['withdraw_legacy'] }],
    });
  });
});

describe('fetchOverviewMentions', () => {
  it('kalder red_overview_mentions og mapper narrative_id til detail_person_id', async () => {
    (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({
      data: [{ narrative_id: 11, detail_person_id: 4 }, { narrative_id: 12, detail_person_id: 9 }], error: null,
    });
    const out = await fetchOverviewMentions([3, 5]);
    expect(supabase.rpc).toHaveBeenCalledWith('red_overview_mentions', { p_person_ids: [3, 5] });
    expect([...out.entries()]).toEqual([[11, 4], [12, 9]]);
  });
  it('kalder ikke RPC ved tom liste', async () => {
    const out = await fetchOverviewMentions([]);
    expect(out.size).toBe(0);
    expect(supabase.rpc).not.toHaveBeenCalled();
  });
  it('kaster ved RPC-fejl og ved ugyldigt svar', async () => {
    (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ data: null, error: { message: 'REDAKTION_REQUIRED' } });
    await expect(fetchOverviewMentions([3])).rejects.toThrow('REDAKTION_REQUIRED');
    (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValueOnce({ data: [{ narrative_id: 'x', detail_person_id: 1 }], error: null });
    await expect(fetchOverviewMentions([3])).rejects.toThrow('OVERVIEW_MENTIONS_RESPONSE_INVALID');
  });
});

describe('fetchOverviewMentionSources', () => {
  it('oversætter markerede narrativer til source_id for personen', async () => {
    (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({ data: [{ narrative_id: 11, detail_person_id: 4 }], error: null });
    const result = {
      data: [
        { id: 10, source_id: 1, side: null, tekst: 'a', privat: false, source: null },
        { id: 11, source_id: 2, side: null, tekst: 'b', privat: false, source: null },
      ], error: null,
    };
    const chain: any = {};
    for (const m of ['select', 'eq', 'order']) chain[m] = vi.fn(() => chain);
    chain.then = (resolve: (v: unknown) => unknown) => resolve(result);
    (supabase.from as ReturnType<typeof vi.fn>).mockReturnValue(chain);
    const out = await fetchOverviewMentionSources(5);
    expect([...out.entries()]).toEqual([[2, 4]]);
    (supabase.rpc as ReturnType<typeof vi.fn>).mockClear();
    const marks = await fetchOverviewMarks(5);
    expect([...marks.bySource.entries()]).toEqual([[2, 4]]);
    expect([...marks.byNarrative.entries()]).toEqual([[11, 4]]);
    expect(supabase.rpc).toHaveBeenCalledTimes(1);
  });
  it('henter ikke narrativer, når intet er markeret', async () => {
    (supabase.rpc as ReturnType<typeof vi.fn>).mockResolvedValue({ data: [], error: null });
    const out = await fetchOverviewMentionSources(5);
    expect(out.size).toBe(0);
    expect(supabase.from).not.toHaveBeenCalled();
  });
});
