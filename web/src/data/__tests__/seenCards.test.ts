// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createSeenStore, SEEN_KEY, toSeenWeights } from '../seenCards';

beforeEach(() => { localStorage.clear(); });

describe('toSeenWeights', () => {
  it('decay-tærskler: <3 dage → 0.25, <7 → 0.5, <14 → 0.75, ældre udelades', () => {
    const seen = { a: 100, b: 98, c: 94, d: 90, e: 50 };
    const weights = toSeenWeights(seen, 100);
    expect(weights.a).toBe(0.25);
    expect(weights.b).toBe(0.25);
    expect(weights.c).toBe(0.5);
    expect(weights.d).toBe(0.75);
    expect(weights.e).toBeUndefined();
  });
  it('tomt input → tomt objekt', () => {
    expect(toSeenWeights({}, 100)).toEqual({});
  });
});

describe('createSeenStore — load', () => {
  it('tomt lager → {}', async () => {
    expect(await createSeenStore().load()).toEqual({});
  });
  it('korrupt lagerindhold → {} uden crash', async () => {
    localStorage.setItem(SEEN_KEY, 'ikke-json{');
    expect(await createSeenStore().load()).toEqual({});
  });
  it('ikke-objekt-JSON (fx array) → {}', async () => {
    localStorage.setItem(SEEN_KEY, '[1,2,3]');
    expect(await createSeenStore().load()).toEqual({});
  });
});

describe('createSeenStore — markSeen', () => {
  it('skriver synkront og flettes ved næste markSeen-kald', () => {
    const store = createSeenStore();
    store.markSeen(['a', 'b'], 10);
    store.markSeen(['c'], 12);
    const stored = JSON.parse(localStorage.getItem(SEEN_KEY) ?? '{}');
    expect(stored).toEqual({ a: 10, b: 10, c: 12 });
  });

  it('flettes med eksisterende indhold i stedet for at overskrive', () => {
    localStorage.setItem(SEEN_KEY, JSON.stringify({ old: 1 }));
    createSeenStore().markSeen(['new'], 5);
    const stored = JSON.parse(localStorage.getItem(SEEN_KEY) ?? '{}');
    expect(stored).toEqual({ old: 1, new: 5 });
  });

  it('tom id-liste er en no-op', () => {
    createSeenStore().markSeen([], 10);
    expect(localStorage.getItem(SEEN_KEY)).toBeNull();
  });

  it('LRU-cap: beskærer til 300 nyeste poster, ældste epoch-dage ryger først', () => {
    const old: Record<string, number> = {};
    for (let i = 0; i < 300; i++) old['old' + i] = 1;
    localStorage.setItem(SEEN_KEY, JSON.stringify(old));

    createSeenStore().markSeen(['new1', 'new2'], 50);

    const stored = JSON.parse(localStorage.getItem(SEEN_KEY) ?? '{}');
    expect(Object.keys(stored)).toHaveLength(300);
    expect(stored.new1).toBe(50);
    expect(stored.new2).toBe(50);
    expect(Object.keys(stored).filter((k) => k.startsWith('old'))).toHaveLength(298);
  });

  it('localStorage-skrivefejl sluges — ingen kastet fejl', () => {
    const spy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('quota'); });
    expect(() => createSeenStore().markSeen(['a'], 10)).not.toThrow();
    spy.mockRestore();
  });
});
