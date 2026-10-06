import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.hoisted(() => vi.fn());
vi.mock('../../supabase', () => ({ supabase: { rpc } }));

import { buildSourcePersonaDecisionCall, fetchSourcePersonaDetail, fetchSourcePersonaHistory, fetchSourcePersonaQueue } from '../sourcePersona';

const ID = '00000000-0000-0000-0000-000000000001';

describe('mapping fra RPC (snake_case → camelCase)', () => {
  beforeEach(() => rpc.mockReset());

  it('kø: best_tier og reason, null når de mangler', async () => {
    const base = { source_persona_id: ID, source_id: 1, persona_key: 'k', decision_status: 'unresolved', version: 2, canonical_person_id: null, mention_count: 1 };
    rpc.mockResolvedValue({ data: [{ ...base, best_tier: 'review', reason: 'new_person_needed' }, base], error: null });
    const rows = await fetchSourcePersonaQueue('new_person_needed');
    expect(rows.map((r) => [r.bestTier, r.reason])).toEqual([['review', 'new_person_needed'], [null, null]]);
  });

  it('detalje: kandidater og kollisioner', async () => {
    rpc.mockResolvedValue({ data: {
      persona: { source_persona_id: ID, source_id: 1, persona_key: 'k', decision_status: 'proposed', version: 0, canonical_person_id: null },
      mentions: [], placements: [], interpretations: [],
      candidates: [{ candidate_id: 'c1', run_id: 'r1', rank: 1, score: 0.93, tier: 'auto', person_id: 42, person_name: 'X', born: '1800', died: null, basis: { signals: ['name', 'birth'] } }],
      collisions: [{ person_id: 42, persona_key: 'persona-9' }],
    }, error: null });
    const d = await fetchSourcePersonaDetail(ID);
    expect(d.candidates).toEqual([{ candidateId: 'c1', runId: 'r1', rank: 1, score: 0.93, tier: 'auto', personId: 42, personName: 'X', born: '1800', died: null, signals: ['name', 'birth'],
      titles: [], ownPostKey: null, familyId: null, ordinal: null }]);
    expect(d.familyContext).toBeNull();
    expect(d.collisions).toEqual([{ personId: 42, personaKey: 'persona-9' }]);
  });

  it('mapper 5b-felterne: rollefilter, titler, familie og familiekontekst', async () => {
    rpc.mockResolvedValueOnce({ data: [], error: null });
    await fetchSourcePersonaQueue('proposed', 7, null, 'spouse');
    expect(rpc).toHaveBeenLastCalledWith('red_source_persona_queue',
      { p_status: 'proposed', p_source_id: 7, p_cursor: null, p_page_size: 50, p_mention_role: 'spouse' });
    rpc.mockResolvedValueOnce({ data: { persona: { source_persona_id: 's', source_id: 7, persona_key: 'k', decision_status: 'proposed', version: 0 },
      mentions: [], placements: [], interpretations: [], collisions: [],
      family_context: { principal_record_key: 'IX-1', marriage_ordinal: 2 },
      candidates: [{ candidate_id: 'c', run_id: 'r', rank: 1, score: 0.9, tier: 'review', person_id: 5, person_name: 'Mage',
                     born: null, died: null, basis: { signals: ['name'] }, titles: ['kammerherre'], own_post_key: 'II-4', family_id: 30, ordinal: 2 }] },
      error: null });
    const d = await fetchSourcePersonaDetail('s');
    expect(d.familyContext).toEqual({ principalRecordKey: 'IX-1', marriageOrdinal: 2 });
    expect(d.candidates[0]).toMatchObject({ titles: ['kammerherre'], ownPostKey: 'II-4', familyId: 30, ordinal: 2 });
  });

  it('historik: basis, kandidat fulgt og årsag fra evidensen', async () => {
    rpc.mockResolvedValue({ data: [
      { version: 3, decision_status: 'unresolved', canonical_person_id: null, evidence: { basis: 'human_sheet', reason: 'new_person_needed' }, decided_by_name: 'R', decided_at: '2026-10-05T00:00:00Z' },
      { version: 2, decision_status: 'accepted', canonical_person_id: 42, evidence: { basis: 'web_detail', candidate_id: 'c1' }, decided_by_name: null, decided_at: null },
    ], error: null });
    expect(await fetchSourcePersonaHistory(ID)).toEqual([
      { version: 3, decisionStatus: 'unresolved', canonicalPersonId: null, basis: 'human_sheet', candidateId: null, reason: 'new_person_needed', decidedByName: 'R', decidedAt: '2026-10-05T00:00:00Z' },
      { version: 2, decisionStatus: 'accepted', canonicalPersonId: 42, basis: 'web_detail', candidateId: 'c1', reason: null, decidedByName: null, decidedAt: null },
    ]);
  });
});

describe('buildSourcePersonaDecisionCall', () => {
  it('sender person, note og web-basis ved samme identitet', () => {
    expect(buildSourcePersonaDecisionCall(ID, 2, 'same', 42, 'samme ægtefælle og dato')).toEqual({
      fn: 'red_afgoer_source_persona', args: {
        p_source_persona_id: ID, p_expected_version: 2, p_action: 'same', p_canonical_person_id: 42,
        p_note: 'samme ægtefælle og dato', p_context: { basis: 'web_detail' },
      },
    });
  });

  it('binder den fulgte kandidat i konteksten', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'same', 42, 'kandidat', { candidateId: 'cand-1', runId: 'run-1' })?.args.p_context)
      .toEqual({ basis: 'web_detail', candidate_id: 'cand-1', run_id: 'run-1' });
  });

  it('ny person nødvendig sendes uden person', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'new_person_needed', null, 'findes ikke')?.args.p_action).toBe('new_person_needed');
  });

  it.each([
    ['same', null, 'basis'], ['different', 42, 'basis'], ['unresolved', 42, 'basis'], ['new_person_needed', 42, 'basis'],
    ['same', 42, '   '], ['same', 42, 'basis', -1],
  ] as const)('afviser fail-closed ugyldig afgørelse %s', (action, personId, note, version = 0) => {
    expect(buildSourcePersonaDecisionCall('persona', version, action, personId, note)).toBeNull();
  });

  it('kandidat uden samme-handling afvises', () => {
    expect(buildSourcePersonaDecisionCall(ID, 0, 'different', null, 'x', { candidateId: 'cand-1', runId: 'run-1' })).toBeNull();
  });
});
