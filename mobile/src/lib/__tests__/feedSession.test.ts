import { epochDay, newSeed, todayISO } from '../feedSession';

describe('todayISO', () => {
  it('formaterer som YYYY-MM-DD', () => {
    expect(todayISO(new Date(2026, 6, 18))).toBe('2026-07-18'); // JS-måned er 0-indekseret
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
  it('er et heltal', () => {
    expect(Number.isInteger(epochDay(new Date()))).toBe(true);
  });
});

describe('newSeed', () => {
  it('returnerer et usigneret 32-bit-agtigt tal', () => {
    const s = newSeed('2026-07-18');
    expect(Number.isFinite(s)).toBe(true);
    expect(s).toBeGreaterThanOrEqual(0);
  });
  it('varierer mellem kald (nonce-drevet — det ENESTE sted Math.random bruges)', () => {
    const seeds = new Set(Array.from({ length: 10 }, () => newSeed('2026-07-18')));
    expect(seeds.size).toBeGreaterThan(1);
  });
});
