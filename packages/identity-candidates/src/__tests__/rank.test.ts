import { describe, expect, test } from 'vitest';
import type { MatchFrame } from '@daa/core';
import { rankCandidates, runConfig, parseControlMargin } from '../rank';

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
    expect(a[0].basis).toEqual({ signals: ['name', 'birth'], name_origin: 'accepted_interpretation', birth_origin: 'accepted_interpretation', death_origin: null,
      member_scores: [{ person_id: 7, score_raw: a[0].basis.member_scores[0].score_raw, signals: ['name', 'birth'] }] });
  });

  test('enkeltperson: én member_scores-post med uafrundet score', () => {
    const out = rankCandidates([f('p1', 'ludvig reventlow', 1848)], [f(7, 'ludvig reventlowe', 1848)], { topK: 3, origins });
    const ms = out[0].basis.member_scores;
    expect(ms).toHaveLength(1);
    expect(ms[0].person_id).toBe(7);
    expect(ms[0].signals).toEqual(['name', 'birth']);
    expect(ms[0].score_raw).toBe(0.7929411764705883);
    expect(out[0].score).toBe(0.7929);
    expect(ms[0].score_raw).not.toBe(out[0].score);
  });

  test('klynge {A med årstal, B uden}: én række, klyngens score, hvert medlem med egen score og egne signaler', () => {
    const persona = [f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)];
    const persons = [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(8, 'ludvig reventlow', null, 'mand')];
    const ud = rankCandidates(persona, persons, { topK: 3, origins, clusters: new Map([[7, 7], [8, 7]]) });
    expect(ud).toHaveLength(1);
    expect(ud[0].basis.cluster_members).toEqual([7, 8]);
    const ms = ud[0].basis.member_scores;
    expect(ms.map((m) => m.person_id)).toEqual([7, 8]);
    const [a, b] = ms;
    expect(a.signals).toEqual(expect.arrayContaining(['birth', 'death']));
    expect(b.signals).not.toContain('birth');
    expect(b.signals).not.toContain('death');
    expect(a.score_raw).toBeGreaterThan(b.score_raw);
    expect(ud[0].score).toBe(Math.round(Math.min(1, a.score_raw) * 10000) / 10000);
    expect(b.score_raw).toBeLessThan(a.score_raw);
  });
});

describe('runConfig', () => {
  test('--control-margin når ind i config, sammen med autoCutoff og topK', () => {
    const c = runConfig({ topK: 3, familyNameMin: 0.9, controlMargin: 0.05 });
    expect(c.controlMargin).toBe(0.05);
    expect(typeof c.autoCutoff).toBe('number');
    expect(c.topK).toBe(3);
  });
  test('uden flag udelades controlMargin', () => {
    expect('controlMargin' in runConfig({ topK: 3, familyNameMin: 0.9 })).toBe(false);
  });
});

describe('parseControlMargin', () => {
  test('uden flag: undefined; gyldig værdi parses', () => {
    expect(parseControlMargin(['generate'])).toBeUndefined();
    expect(parseControlMargin(['--control-margin', '0.05'])).toBe(0.05);
  });
  test('sidste argument uden værdi, eller værdi uden for (0,1), kaster', () => {
    expect(() => parseControlMargin(['generate', '--control-margin'])).toThrow();
    expect(() => parseControlMargin(['--control-margin', '--top-k', '3'])).toThrow();
    for (const v of ['0', '1', '-0.1', 'abc']) expect(() => parseControlMargin(['--control-margin', v])).toThrow();
  });
});
