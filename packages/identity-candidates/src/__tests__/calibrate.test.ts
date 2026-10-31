import { describe, expect, test } from 'vitest';
import { calibrate } from '../calibrate';
import type { Candidate } from '../rank';

const c = (p: string, person: number, rank: number, tier: Candidate['tier']): Candidate => ({
  source_persona_id: p, candidate_person_id: person, rank, score: 0.8, tier,
  basis: { signals: ['name'], name_origin: 'accepted_interpretation', birth_origin: null, death_origin: null,
    member_scores: [{ person_id: person, score_raw: 0.8, signals: ['name'] }] },
});

describe('calibrate', () => {
  test('top-1, top-3, uden kandidat og præcision pr. tier', () => {
    const cands = [c('a', 1, 1, 'auto'), c('b', 9, 1, 'review'), c('b', 2, 2, 'review'), c('c', 9, 1, 'none')];
    const truth = [{ source_persona_id: 'a', canonical_person_id: 1 }, { source_persona_id: 'b', canonical_person_id: 2 },
                   { source_persona_id: 'c', canonical_person_id: 3 }, { source_persona_id: 'd', canonical_person_id: 4 }];
    const nul = { auto: { n: 0, rigtige: 0 }, review: { n: 0, rigtige: 0 }, none: { n: 0, rigtige: 0 } };
    expect(calibrate(cands, truth, 4, 1)).toEqual({
      personas: 4, med_facit: 4, uden_navn: 1, uden_kandidat: 1, top1: 1, top3: 2,
      tier: { auto: { n: 1, rigtige: 1 }, review: { n: 1, rigtige: 0 }, none: { n: 1, rigtige: 0 } },
      uden_aarstal: { med_facit: 0, uden_kandidat: 0, top1: 0, top3: 0, tier: nul },
    });
  });

  test('samme tal særskilt for personas uden årstal', () => {
    const cands = [c('a', 1, 1, 'auto'), c('b', 9, 1, 'review'), c('b', 2, 2, 'review')];
    const truth = [{ source_persona_id: 'a', canonical_person_id: 1 }, { source_persona_id: 'b', canonical_person_id: 2 },
                   { source_persona_id: 'd', canonical_person_id: 4 }];
    expect(calibrate(cands, truth, 3, 0, new Set(['b', 'd'])).uden_aarstal).toEqual({
      med_facit: 2, uden_kandidat: 1, top1: 0, top3: 1,
      tier: { auto: { n: 0, rigtige: 0 }, review: { n: 1, rigtige: 0 }, none: { n: 0, rigtige: 0 } },
    });
  });
});
