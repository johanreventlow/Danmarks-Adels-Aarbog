import { describe, expect, it } from 'vitest';
import { interleave, mulberry32, stableHash } from '../prng';

describe('mulberry32', () => {
  it('er deterministisk pr. seed', () => {
    const a = mulberry32(42);
    const b = mulberry32(42);
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
  });
  it('forskellige seeds → forskellige sekvenser', () => {
    expect(mulberry32(1)()).not.toBe(mulberry32(2)());
  });
  it('output i [0,1)', () => {
    const r = mulberry32(7);
    for (let i = 0; i < 1000; i++) {
      const v = r();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });
  it('seed 0 fungerer (ikke degenereret)', () => {
    const r = mulberry32(0);
    const vals = [r(), r(), r()];
    expect(new Set(vals).size).toBeGreaterThan(1);
  });
});

describe('stableHash', () => {
  it('er deterministisk og usigneret', () => {
    expect(stableHash('p1')).toBe(stableHash('p1'));
    expect(stableHash('p1')).toBeGreaterThanOrEqual(0);
    expect(stableHash('p1')).not.toBe(stableHash('p2'));
  });
});

describe('interleave', () => {
  it('fletter grupper round-robin og springer tomme over', () => {
    expect(interleave([['a1', 'a2', 'a3'], ['b1'], [], ['c1', 'c2']]))
      .toEqual(['a1', 'b1', 'c1', 'a2', 'c2', 'a3']);
  });
  it('tom input → tom liste', () => {
    expect(interleave([])).toEqual([]);
    expect(interleave([[], []])).toEqual([]);
  });
});
