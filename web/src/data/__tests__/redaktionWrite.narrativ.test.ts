import { describe, it, expect, vi } from 'vitest';

vi.mock('../../supabase', () => ({
  supabase: { rpc: vi.fn(), auth: { onAuthStateChange: vi.fn() } },
}));

import { buildRpcCall, narrativeRecordErrorState, planCall, type Change } from '../redaktionWrite';

describe('narrativ arg-builder (source-nøglet)', () => {
  it('sender p_source_id + p_side fra payload', () => {
    const call = buildRpcCall({
      art: 'narrativ', subjektType: 'person', subjektId: '5', vaerdi: 'bio',
      payload: { privat: false, sourceId: 2, side: '12' },
    });
    expect(call).toMatchObject({
      fn: 'red_upsert_narrativ',
      args: { p_subjekt_type: 'person', p_subjekt_id: 5, p_tekst: 'bio', p_privat: false, p_source_id: 2, p_side: '12' },
    });
  });
  it('defaulter source_id/side til null når payload mangler dem', () => {
    const call = buildRpcCall({ art: 'narrativ', subjektType: 'person', subjektId: '5', vaerdi: 'bio', payload: { privat: true } });
    expect(call?.args).toMatchObject({ p_privat: true, p_source_id: null, p_side: null });
  });
});

const stateSha256 = 'b'.repeat(64);
const recordChange = (action: string, overrides: Record<string, unknown> = {}): Change => ({
  art: 'narrativRecord', subjektType: 'person', subjektId: '5',
  payload: {
    action,
    sourceId: 19,
    recordKey: 'V-152',
    expectedStateSha256: stateSha256,
    tekst: 'Kildetekst',
    privat: true,
    ...overrides,
  },
});

describe('record-nøglet narrativ arg-builder', () => {
  it.each([
    ['create_draft', 'red_upsert_person_narrative_record', { p_tekst: 'Kildetekst', p_privat: true }],
    ['save_draft', 'red_upsert_person_narrative_record', { p_tekst: 'Kildetekst', p_privat: true }],
    ['discard_draft', 'red_kasser_person_narrative_record', {}],
    ['publish', 'red_publicer_person_narrative_record', {}],
    ['publish_revision', 'red_revider_publiceret_person_narrative_record', { p_tekst: 'Kildetekst' }],
    ['revalidate', 'red_revalider_person_narrative_record', {}],
    ['withdraw', 'red_tilbagetraek_person_narrative_record', {}],
  ])('routes %s with the record locator and concurrency hash only', (action, fn, extraArgs) => {
    expect(buildRpcCall(recordChange(action))).toEqual({
      fn,
      args: {
        p_person_id: 5,
        p_source_id: 19,
        p_record_key: 'V-152',
        ...extraArgs,
        p_expected_state_sha256: stateSha256,
      },
    });
  });

  it('routes legacy withdrawal and event reversal to their dedicated RPCs', () => {
    expect(buildRpcCall(recordChange('withdraw_legacy', {
      legacyPublicationRef: '4c97b6bc-408e-49de-96ae-21ca916d82f5', begrundelse: 'Forkert offentlig synlighed',
    }))).toEqual({
      fn: 'red_tilbagetraek_legacy_narrative',
      args: {
        p_legacy_publication_ref: '4c97b6bc-408e-49de-96ae-21ca916d82f5',
        p_expected_state_sha256: stateSha256,
        p_begrundelse: 'Forkert offentlig synlighed',
      },
    });
    expect(buildRpcCall({ art: 'fortrydNarrativPublicering', subjektType: 'person', subjektId: '5', payload: {
      eventId: '4c97b6bc-408e-49de-96ae-21ca916d82f5', expectedStateSha256: stateSha256,
    } })).toEqual({
      fn: 'red_fortryd_person_narrative_publication_event',
      args: { p_event_id: '4c97b6bc-408e-49de-96ae-21ca916d82f5', p_expected_state_sha256: stateSha256 },
    });
  });

  it('does not degrade a v2 record mutation to the legacy generic writer or a suggestion', () => {
    expect(() => planCall(recordChange('publish') as never, 'medlem')).toThrow('Narrativ-publicering kræver redaktør-rettigheder');
    expect(buildRpcCall({ art: 'narrativ', subjektType: 'slaegt', subjektId: '5', vaerdi: 'Generisk', payload: { privat: false } }))
      .toMatchObject({ fn: 'red_upsert_narrativ' });
  });
});

describe('narrative record error states', () => {
  it.each([
    ['NARRATIVE_RECORD_STATE_STALE', 'stale_state'],
    ['NARRATIVE_RECORD_PUBLICATION_STALE', 'stale_state'],
    ['NARRATIVE_RECORD_IDENTITY_REQUIRED', 'identity_required'],
    ['NARRATIVE_RECORD_IDENTITY_CONFLICT', 'identity_conflict'],
    ['NARRATIVE_RECORD_ANCHOR_REQUIRED', 'anchor_required'],
    ['NARRATIVE_RECORD_DERIVED_EVENTS_PRESENT', 'derived_events'],
    ['NARRATIVE_RECORD_TRANSITION_INVALID', 'illegal_transition'],
    ['NARRATIVE_RECORD_DEDICATED_REVERSAL_REQUIRED', 'dedicated_reversal_required'],
    ['NARRATIVE_LEGACY_BASELINE_DRIFT', 'legacy_drift'],
    ['NARRATIVE_PUBLICATION_HISTORY', 'person_delete_publication_history'],
  ])('classifies %s as an explicit UI state', (message, expected) => {
    expect(narrativeRecordErrorState(message)).toBe(expected);
  });
});

describe('opretKilde arg-builder', () => {
  it('mapper ny DAA-udgave → red_opret_kilde med p_aar', () => {
    const call = buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '',
      payload: { titel: 'DAA 1982-84', slags: 'DAA-udgave', udgave: 'DAA 1982-84', aar: 1982 } });
    expect(call).toMatchObject({ fn: 'red_opret_kilde', args: { p_titel: 'DAA 1982-84', p_slags: 'DAA-udgave', p_udgave: 'DAA 1982-84', p_aar: 1982, p_ekstern: false } });
  });
  it('uden titel → null', () => {
    expect(buildRpcCall({ art: 'opretKilde', subjektType: 'source', subjektId: '', payload: {} })).toBeNull();
  });
});
