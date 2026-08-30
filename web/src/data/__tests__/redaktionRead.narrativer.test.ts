import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fetchPersonNarrativeRecords, mapNarrativeRecordRows, mapNarrativer } from '../redaktionRead';
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
      status: 'legacy_active',
      stateSha256: 'a'.repeat(64),
      text: 'Bevaret overgangstekst',
      allowedActions: ['withdraw_legacy'],
      blockingReason: null,
    }]);
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
