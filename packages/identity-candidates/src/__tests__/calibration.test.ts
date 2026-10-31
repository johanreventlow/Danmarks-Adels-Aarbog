import { describe, expect, test } from 'vitest';
import { partitionPairs, mutateSameAs, clusterCalibrate, yearCoverage, type Pair } from '../calibration';
import type { Candidate } from '../rank';
import type { MatchFrame } from '@daa/core';

describe('partitionPairs', () => {
  test('en eksisterende klynge berøres højst af ét par pr. kopi', () => {
    const sameAs: Pair[] = [[1, 2]];                       // klynge {1,2}
    const pairs: Pair[] = [[1, 10], [2, 11], [3, 10], [4, 5]];
    const parts = partitionPairs(sameAs, pairs);
    expect(parts).toEqual([[[1, 10], [4, 5]], [[2, 11], [3, 10]]]);
    for (const part of parts) {
      // ingen kopi samler mere end to eksisterende klynger pr. par
      const all = mutateSameAs(sameAs, part);
      const parent = new Map<number, number>();
      const find = (x: number): number => (parent.get(x) ?? x) === x ? x : find(parent.get(x)!);
      for (const [a, b] of all) { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(ra, rb); }
      const sizes = new Map<number, number>();
      for (const x of new Set(all.flat())) sizes.set(find(x), (sizes.get(find(x)) ?? 0) + 1);
      expect(Math.max(...sizes.values())).toBeLessThanOrEqual(3);
    }
  });
  test('et par inden for samme eksisterende klynge afvises', () => {
    expect(() => partitionPairs([[1, 2]], [[2, 1]])).toThrow('CALIBRATION_PAIR_ALREADY_SAME_CLUSTER');
  });
  test('deterministisk', () => {
    const pairs: Pair[] = [[5, 6], [6, 7], [7, 8]];
    expect(partitionPairs([], pairs)).toEqual(partitionPairs([], pairs));
  });
});

describe('mutateSameAs', () => {
  test('tilføjer, fjerner dubletter og sorterer', () => {
    expect(mutateSameAs([[3, 4], [1, 2]], [[1, 2], [0, 9]])).toEqual([[0, 9], [1, 2], [3, 4]]);
  });
});

const cand = (p: string, rep: number, members: number[], rank: number, tier: Candidate['tier']): Candidate => ({
  source_persona_id: p, candidate_person_id: rep, rank, score: 0.9, tier,
  basis: { signals: ['name'], name_origin: 'x', birth_origin: null, death_origin: null,
           member_scores: members.map((m) => ({ person_id: m, score_raw: 0.9, signals: ['name'] })) },
});

describe('clusterCalibrate', () => {
  test('facit i rækkens klynge er et træf, også under en anden repræsentant', () => {
    const cands = [cand('a', 1, [1, 7], 1, 'auto'), cand('b', 9, [9], 1, 'review'), cand('b', 2, [2], 2, 'review')];
    const truth = [{ source_persona_id: 'a', canonical_person_id: 7 }, { source_persona_id: 'b', canonical_person_id: 2 },
                   { source_persona_id: 'c', canonical_person_id: 3 }];
    expect(clusterCalibrate(cands, truth)).toEqual({ med_facit: 3, med_kandidat: 2, top1: 1, top3: 2,
      tier: { auto: { n: 1, rigtige: 1 }, review: { n: 1, rigtige: 0 }, none: { n: 0, rigtige: 0 } } });
  });
});

describe('yearCoverage', () => {
  test('tæller fødsel, død og mindst ét år for den valgte mængde', () => {
    const f = (id: number, b: number | null, d: number | null): MatchFrame =>
      ({ id, nameKey: 'x', birthMin: b, birthMax: b, deathMin: d, deathMax: d, sex: 'mand' });
    const frames = [f(1, 1700, null), f(2, null, 1750), f(3, null, null), f(4, 1600, 1650)];
    expect(yearCoverage(frames, new Set([1, 2, 3]))).toEqual({ personer: 3, mindst_et_aar: 2, foedselsaar: 1, doedsaar: 1,
      alle_personer: 4, alle_mindst_et_aar: 3 });
  });
});
