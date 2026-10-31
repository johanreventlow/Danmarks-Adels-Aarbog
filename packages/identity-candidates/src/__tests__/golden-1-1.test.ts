import { describe, expect, test } from 'vitest';
import { rankCandidates } from '../rank';
import { SCENARIOS } from './golden-scenarios';

// Literaler genereret fra 1.1-koden (commit 15061332, rank.ts) på scenarierne i golden-scenarios.ts.
// Testen låser hele kandidatoutputtet MINUS basis.member_scores.
const GOLDEN_1_1: Record<string, unknown[]> = {
  enkeltperson: [
    {"source_persona_id": "p1", "candidate_person_id": 7, "rank": 1, "score": 0.7929, "tier": "review", "basis": {"signals": ["name", "birth"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null}},
  ],
  klynge: [
    {"source_persona_id": "p1", "candidate_person_id": 7, "rank": 1, "score": 0.9, "tier": "auto", "basis": {"signals": ["name", "birth", "death"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null, "cluster_members": [7, 8]}},
  ],
  familie_repraesentant_ombytning: [
    {"source_persona_id": "p1", "candidate_person_id": 9, "rank": 1, "score": 0.6, "tier": "auto", "basis": {"signals": ["name", "family_partner", "ordinal_match"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null, "family_partner": true, "ordinal_match": true, "corroboration_eligible": true, "eligibility_reason": "ok", "cluster_members": [7, 9]}},
    {"source_persona_id": "p1", "candidate_person_id": 11, "rank": 2, "score": 0.77, "tier": "review", "basis": {"signals": ["name", "birth"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null, "family_partner": false, "ordinal_match": false, "corroboration_eligible": false, "eligibility_reason": "name_or_rank"}},
  ],
  topk_afskaering: [
    {"source_persona_id": "p1", "candidate_person_id": 1, "rank": 1, "score": 0.8, "tier": "review", "basis": {"signals": ["name", "birth"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null}},
    {"source_persona_id": "p1", "candidate_person_id": 2, "rank": 2, "score": 0.7657, "tier": "review", "basis": {"signals": ["name", "birth"], "name_origin": "accepted_interpretation", "birth_origin": "accepted_interpretation", "death_origin": null}},
    {"source_persona_id": "p2", "candidate_person_id": 1, "rank": 1, "score": 0.6, "tier": "none", "basis": {"signals": ["name"], "name_origin": "accepted_interpretation", "birth_origin": null, "death_origin": null}},
    {"source_persona_id": "p2", "candidate_person_id": 3, "rank": 2, "score": 0.592, "tier": "none", "basis": {"signals": ["name"], "name_origin": "accepted_interpretation", "birth_origin": null, "death_origin": null}},
  ],
};

const udenMemberScores = (cs: ReturnType<typeof rankCandidates>) => cs.map((c) => {
  const { member_scores: _ms, ...basis } = c.basis;
  return { ...c, basis };
});

describe('golden mod 1.1', () => {
  for (const [navn, s] of Object.entries(SCENARIOS)) {
    test(navn, () => {
      const nu = rankCandidates(s.personas, s.persons, s.opts);
      expect(JSON.parse(JSON.stringify(udenMemberScores(nu)))).toEqual(GOLDEN_1_1[navn]);
      expect(nu.every((c) => c.basis.member_scores.length >= 1)).toBe(true);
    });
  }
});
