import { describe, expect, test } from 'vitest';
import type { MatchFrame } from '@daa/core';
import { rankCandidates } from '../rank';

const f = (id: string | number, nameKey: string, birth: number | null = null, sex: MatchFrame['sex'] = 'ukendt',
           death: number | null = null): MatchFrame => ({
  id, nameKey, birthMin: birth, birthMax: birth, deathMin: death, deathMax: death, sex,
});
const origins = new Map([['p1', { name: 'accepted_interpretation', birth: 'accepted_interpretation', death: null }],
                         ['p2', { name: 'accepted_interpretation', birth: null, death: null }]]);

describe('rankCandidates', () => {
  test('ikke-injektiv: samme person er kandidat 1 for to personas', () => {
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848), f('p2', 'ludvig reventlow', 1848)],
      [f(7, 'ludvig reventlow', 1848), f(8, 'ludvig reventlau', 1790)], { topK: 3, origins });
    const tops = out.filter((c) => c.rank === 1);
    expect(tops.map((c) => [c.source_persona_id, c.candidate_person_id])).toEqual([['p1', 7], ['p2', 7]]);
  });

  test('rang 1..n pr. persona og højst topK', () => {
    const persons = [1, 2, 3, 4].map((i) => f(i, `anna reventlow${'x'.repeat(i - 1)}`));
    const out = rankCandidates([f('p1', 'anna reventlow')], persons, { topK: 3, origins });
    expect(out.map((c) => c.rank)).toEqual([1, 2, 3]);
    expect(out[0].candidate_person_id).toBe(1);
  });

  test('persona uden navn får ingen kandidater', () => {
    expect(rankCandidates([f('p1', '')], [f(1, 'anna')], { topK: 3, origins })).toEqual([]);
  });

  test('tier: auto kræver cutoff, margin og rang 1 — aldrig automatisk accept', () => {
    // Personaens køn er ukendt i 5a (spec §5): auto kræver navn + fødsels- + dødsår (0,6+0,2+0,1).
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(9, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 3, origins });
    // to identiske kandidater: margin 0 → ingen auto
    expect(out.every((c) => c.tier !== 'auto')).toBe(true);
    const alene = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 3, origins });
    expect(alene[0].tier).toBe('auto');
  });

  test('topK=1 skjuler ikke tvetydighed: margin beregnes før afskæring', () => {
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
      [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(9, 'ludvig reventlow', 1848, 'mand', 1900)], { topK: 1, origins });
    expect(out).toHaveLength(1);
    expect(out[0].tier).not.toBe('auto');
  });

  test('basis bærer signaler og oprindelse, deterministisk', () => {
    const a = rankCandidates([f('p1', 'ludvig reventlow', 1848)], [f(7, 'ludvig reventlow', 1848)], { topK: 3, origins });
    const b = rankCandidates([f('p1', 'ludvig reventlow', 1848)], [f(7, 'ludvig reventlow', 1848)], { topK: 3, origins });
    expect(a).toEqual(b);
    expect(a[0].basis).toEqual({ signals: ['name', 'birth'], name_origin: 'accepted_interpretation', birth_origin: 'accepted_interpretation', death_origin: null });
  });
});
