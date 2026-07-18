import { describe, expect, it } from 'vitest';
import { epochDay, newSeed, todayISO } from '../feedSession';

describe('todayISO', () => {
  it('formaterer som YYYY-MM-DD', () => {
    expect(todayISO(new Date(2026, 6, 18))).toBe('2026-07-18');
  });
  it('polstrer enkeltcifrede måneder/dage', () => {
    expect(todayISO(new Date(2026, 0, 5))).toBe('2026-01-05');
  });
});

describe('epochDay', () => {
  it('stiger med præcis 1 pr. døgn', () => {
    const a = epochDay(new Date(2026, 6, 18));
    const b = epochDay(new Date(2026, 6, 19));
    expect(b - a).toBe(1);
  });
});

describe('newSeed', () => {
  it('returnerer et usigneret tal og varierer mellem kald', () => {
    const seeds = new Set(Array.from({ length: 10 }, () => newSeed('2026-07-18')));
    expect(seeds.size).toBeGreaterThan(1);
    for (const s of seeds) expect(s).toBeGreaterThanOrEqual(0);
  });
});
