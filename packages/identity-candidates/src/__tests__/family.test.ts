import { describe, expect, test } from 'vitest';
import type { MatchFrame } from '@daa/core';
import { clusterMap, evaluateFamily, type FamilyContext } from '../family';
import { rankCandidates } from '../rank';

const f = (id: string | number, nameKey: string): MatchFrame =>
  ({ id, nameKey, birthMin: null, birthMax: null, deathMin: null, deathMax: null, sex: 'ukendt' });
const ctx = (over: Partial<FamilyContext> = {}): FamilyContext => ({
  principal_person_id: 1, marriage_ordinal: 1, marriage_claims_in_post: 1,
  families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7] }], ...over,
});
const origins = new Map([['s1', { name: 'mention', birth: null, death: null }]]);

describe('evaluateFamily', () => {
  test('entydig familie', () => expect(evaluateFamily(ctx())).toMatchObject({ structureOk: true, target: 7, reason: 'ok' }));
  test('count_mismatch', () => expect(evaluateFamily(ctx({ marriage_claims_in_post: 2 })).reason).toBe('count_mismatch'));
  test('NULL-ordenstal ved flere familier', () => expect(evaluateFamily(ctx({ marriage_claims_in_post: 2,
    families: [{ family_id: 10, ordinal: null, konfidens: [], partners: [7] }, { family_id: 11, ordinal: 2, konfidens: [], partners: [8] }] })).reason)
    .toBe('ordinal_null'));
  test('ordenstal vælger familien', () => expect(evaluateFamily(ctx({ marriage_ordinal: 2, marriage_claims_in_post: 2,
    families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7] }, { family_id: 11, ordinal: 2, konfidens: [], partners: [8] }] })).target)
    .toBe(8));
  test('omstridt konfidens', () => expect(evaluateFamily(ctx({ families: [{ family_id: 10, ordinal: 1, konfidens: ['omstridt'], partners: [7] }] })).reason)
    .toBe('konfidens'));
  test('to partnere', () => expect(evaluateFamily(ctx({ families: [{ family_id: 10, ordinal: 1, konfidens: [], partners: [7, 9] }] })).reason)
    .toBe('partner_count'));
});

describe('rankCandidates med familie', () => {
  test('familiepartneren står først og er egnet ved stærkt navn', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo beta'), f(7, 'bo beta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]) });
    expect(out[0]).toMatchObject({ candidate_person_id: 7, rank: 1 });
    expect(out[0].basis).toMatchObject({ family_partner: true, ordinal_match: true, corroboration_eligible: true });
  });
  test('svagt navn er ikke egnet', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(7, 'carl ceta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]) });
    expect(out.find((c) => c.candidate_person_id === 7)?.basis.corroboration_eligible ?? false).toBe(false);
  });
  test('samme_som-klynge slås sammen med familiepartneren som repræsentant', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo beta'), f(7, 'bo beta')],
      { topK: 3, origins, families: new Map([['s1', ctx()]]), clusters: clusterMap([[5, 7]]) });
    expect(out.map((c) => c.candidate_person_id)).toEqual([7]);
    expect(out[0].basis.cluster_members).toEqual([5, 7]);
  });
  test('samme_som-klynge uden familiepartner: laveste id, selv når det højere id scorer bedst', () => {
    const out = rankCandidates([f('s1', 'bo beta')], [f(5, 'bo bxta'), f(7, 'bo beta')],
      { topK: 3, origins, clusters: clusterMap([[5, 7]]) });
    expect(out.map((c) => c.candidate_person_id)).toEqual([5]);
    expect(out[0].basis.cluster_members).toEqual([5, 7]);
  });
});
