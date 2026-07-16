import { describe, test, expect } from 'vitest';
import {
  jaroWinkler,
  overlapEvidence,
  scorePair,
  assignTiers,
  matchUdgaver,
  buildMatchFrame,
  defaultCfg,
  evalPrecisionRecall,
  pairsToCsv,
  type MatchFrame,
  type ScoredPair,
} from '../matchUdgaver';

const near = (a: number, b: number, tol = 0.002) => Math.abs(a - b) <= tol;

describe('jaroWinkler — kanoniske referencevektorer (stringdist method="jw", p=0.1)', () => {
  test('identiske strenge → 1.0', () => {
    expect(jaroWinkler('reventlow', 'reventlow')).toBe(1);
  });
  test('MARTHA/MARHTA ≈ 0.9611', () => {
    expect(near(jaroWinkler('martha', 'marhta'), 0.9611)).toBe(true);
  });
  test('DWAYNE/DUANE ≈ 0.8400', () => {
    expect(near(jaroWinkler('dwayne', 'duane'), 0.84)).toBe(true);
  });
  test('DIXON/DICKSONX ≈ 0.8133', () => {
    expect(near(jaroWinkler('dixon', 'dicksonx'), 0.8133)).toBe(true);
  });
  test('ingen fælles → 0; tom streng → 0', () => {
    expect(jaroWinkler('abc', 'xyz')).toBe(0);
    expect(jaroWinkler('', 'reventlow')).toBe(0);
  });
});

describe('overlapEvidence — dato som gensidig evidens (.overlap_evidence)', () => {
  test('begge kendte + overlappende → true', () => {
    expect(overlapEvidence(1910, 1910, 1908, 1912)).toBe(true);
  });
  test('begge kendte + ikke-overlappende → false', () => {
    expect(overlapEvidence(1910, 1910, 1920, 1920)).toBe(false);
  });
  test('én side ukendt → false (manglende evidens, ikke enighed)', () => {
    expect(overlapEvidence(1910, 1910, null, null)).toBe(false);
    expect(overlapEvidence(null, null, 1910, 1910)).toBe(false);
  });
});

describe('scorePair — vægtet sum (0.6/0.2/0.1/0.1)', () => {
  test('fuldt match', () => {
    expect(near(scorePair(1, true, true, true, defaultCfg()), 1.0)).toBe(true);
  });
  test('kun navn (ingen dato/køn-evidens)', () => {
    expect(near(scorePair(1, false, false, false, defaultCfg()), 0.6)).toBe(true);
  });
  test('navn 0.9 + fødsel-overlap', () => {
    expect(near(scorePair(0.9, true, false, false, defaultCfg()), 0.6 * 0.9 + 0.2)).toBe(true);
  });
});

describe('assignTiers — injektiv tildeling + auto/review-gating', () => {
  const A: MatchFrame = { id: 'a1', nameKey: 'ludvig', birthMin: 1848, birthMax: 1848, deathMin: 1916, deathMax: 1916, sex: 'mand' };

  test('to A-personer må ikke begge claime samme B (injektiv)', () => {
    // to næsten-identiske A-personer, én B-kandidat → kun den bedste får B
    const scored: ScoredPair[] = [
      { aId: 'a1', bId: 'b1', nameSim: 1.0, birthOverlap: true, deathOverlap: true, sexEq: true, uniqueBlock: true },
      { aId: 'a2', bId: 'b1', nameSim: 0.95, birthOverlap: true, deathOverlap: true, sexEq: true, uniqueBlock: true },
    ];
    const tiers = assignTiers(scored, defaultCfg());
    const b1claims = tiers.filter((t) => t.bId === 'b1' && t.tier !== 'none');
    expect(b1claims.length).toBe(1);
    expect(b1claims[0].aId).toBe('a1'); // højeste score vinder
  });

  test('auto KUN når score≥0.90 + margin≥0.05 + personens top', () => {
    const scored: ScoredPair[] = [
      { aId: 'a1', bId: 'b1', nameSim: 1.0, birthOverlap: true, deathOverlap: true, sexEq: true, uniqueBlock: true },
    ];
    const tiers = assignTiers(scored, defaultCfg());
    expect(tiers.find((t) => t.aId === 'a1' && t.bId === 'b1')!.tier).toBe('auto');
  });

  test('tvetydig top (margin < 0.05) → review, ikke auto', () => {
    const scored: ScoredPair[] = [
      { aId: 'a1', bId: 'b1', nameSim: 1.0, birthOverlap: true, deathOverlap: true, sexEq: true, uniqueBlock: false },
      { aId: 'a1', bId: 'b2', nameSim: 1.0, birthOverlap: true, deathOverlap: true, sexEq: true, uniqueBlock: false },
    ];
    const tiers = assignTiers(scored, defaultCfg());
    expect(tiers.filter((t) => t.tier === 'auto').length).toBe(0);
    expect(tiers.some((t) => t.tier === 'review')).toBe(true);
  });

  test('score < review_cutoff → none', () => {
    const scored: ScoredPair[] = [
      { aId: 'a1', bId: 'b1', nameSim: 0.5, birthOverlap: false, deathOverlap: false, sexEq: false, uniqueBlock: true },
    ];
    const tiers = assignTiers(scored, defaultCfg());
    expect(tiers.find((t) => t.aId === 'a1')!.tier).toBe('none');
  });
});

describe('buildMatchFrame — adapter fra udtræks-person til frame', () => {
  test('navn→foldet nøgle, dato→år-interval, køn', () => {
    const f = buildMatchFrame({
      id: 'x', navn: 'Ludvig Alexander Eduard', koen: 'mand',
      foedsel: { date_min: '1848-11-05', date_max: '1848-11-05' },
      doed: { date_min: '1916-06-19', date_max: '1916-06-19' },
    });
    expect(f.birthMin).toBe(1848);
    expect(f.deathMin).toBe(1916);
    expect(f.sex).toBe('mand');
    expect(f.nameKey.length).toBeGreaterThan(0);
  });
  test('manglende dato → null-interval', () => {
    const f = buildMatchFrame({ id: 'y', navn: 'Alexander', koen: 'mand' });
    expect(f.birthMin).toBe(null);
    expect(f.deathMin).toBe(null);
  });
});

describe('matchUdgaver — facit-genfinding + populationsafgrænsning', () => {
  // 1939-udgave (kildeA) mod 2018-20-basen (kildeB). Historiske (afdøde) ankre + stavevariant.
  const kildeA: MatchFrame[] = [
    buildMatchFrame({ id: 'A-lud', navn: 'Ludvig Alexander Eduard', koen: 'mand', foedsel: { date_min: '1848-11-05', date_max: '1848-11-05' }, doed: { date_min: '1916-06-19', date_max: '1916-06-19' } }),
    buildMatchFrame({ id: 'A-otto', navn: 'Otto Carl Ferdinand', koen: 'mand', foedsel: { date_min: '1887-12-14', date_max: '1887-12-14' }, doed: { date_min: '1929-03-02', date_max: '1929-03-02' } }),
    // 1939 staver 'Benedicta'
    buildMatchFrame({ id: 'A-ben', navn: 'Comtesse Benedicta Adelheid Louise', koen: 'kvinde', foedsel: { date_min: '1930-06-26', date_max: '1930-06-26' } }),
  ];
  const kildeB: MatchFrame[] = [
    buildMatchFrame({ id: 'B-lud', navn: 'Ludvig Alexander Eduard', koen: 'mand', foedsel: { date_min: '1848-11-05', date_max: '1848-11-05' }, doed: { date_min: '1916-06-19', date_max: '1916-06-19' } }),
    buildMatchFrame({ id: 'B-otto', navn: 'Otto Carl Ferdinand', koen: 'mand', foedsel: { date_min: '1887-12-14', date_max: '1887-12-14' }, doed: { date_min: '1929-03-02', date_max: '1929-03-02' } }),
    // 2018-20 staver 'Benedicte' (+ Komtesse)
    buildMatchFrame({ id: 'B-ben', navn: 'Komtesse Benedicte Adelheid Louise', koen: 'kvinde', foedsel: { date_min: '1930-06-26', date_max: '1930-06-26' } }),
  ];

  test('eksakt-navn+dato-ankre genfindes som auto', () => {
    const pairs = matchUdgaver(kildeA, kildeB);
    const lud = pairs.find((p) => p.aId === 'A-lud' && p.tier !== 'none');
    expect(lud?.bId).toBe('B-lud');
    expect(lud?.tier).toBe('auto');
  });

  test('stavevariant Benedicta↔Benedicte genfindes trods forskellig stavning', () => {
    const pairs = matchUdgaver(kildeA, kildeB);
    const ben = pairs.find((p) => p.aId === 'A-ben' && p.tier !== 'none');
    expect(ben?.bId).toBe('B-ben');
  });

  test('NN/tom nøgle udelukkes fra kandidat-generering', () => {
    const withNN = [...kildeA, buildMatchFrame({ id: 'A-nn', navn: 'NN', koen: 'ukendt' })];
    const pairs = matchUdgaver(withNN, kildeB);
    expect(pairs.some((p) => p.aId === 'A-nn' && p.tier !== 'none')).toBe(false);
  });
});

describe('kalibrerings-harness (§3.5)', () => {
  test('evalPrecisionRecall: precision = korrekte/crosswalk, recall = korrekte/facit', () => {
    const crosswalk = [
      { aId: 'a1', bId: 'b1' }, // korrekt
      { aId: 'a2', bId: 'bX' }, // forkert (facit siger b2)
    ];
    const truth = [
      { aId: 'a1', bId: 'b1' },
      { aId: 'a2', bId: 'b2' },
      { aId: 'a3', bId: 'b3' }, // ikke i crosswalk (tabt recall)
    ];
    const r = evalPrecisionRecall(crosswalk, truth);
    expect(r.correct).toBe(1);
    expect(r.precision).toBe(1 / 2);
    expect(r.recall).toBe(1 / 3);
  });

  test('evalPrecisionRecall: tomt crosswalk → precision 0, recall 0 (ingen division-fejl)', () => {
    const r = evalPrecisionRecall([], [{ aId: 'a1', bId: 'b1' }]);
    expect(r.precision).toBe(0);
    expect(r.recall).toBe(0);
  });

  test('pairsToCsv: header + én række pr. par, tier/score med', () => {
    const pairs: ScoredPair[] = [
      { aId: 'a1', bId: 'b1', nameSim: 1, birthOverlap: true, deathOverlap: false, sexEq: true, uniqueBlock: true, score: 0.9, tier: 'auto' },
    ];
    const csv = pairsToCsv(pairs);
    const lines = csv.trim().split('\n');
    expect(lines[0]).toBe('aId,bId,nameSim,birthOverlap,deathOverlap,sexEq,uniqueBlock,score,tier');
    expect(lines).toHaveLength(2);
    expect(lines[1]).toContain('a1,b1,');
    expect(lines[1]).toContain('auto');
  });
});
