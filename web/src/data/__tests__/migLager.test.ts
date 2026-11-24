// @vitest-environment jsdom
// Review 37 W11: »Det er mig«-markeringen ligger i localStorage, som kan kaste (privat vindue,
// blokerede site-data, fuld kvote). Læsning og skrivning må aldrig vælte siden.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { gemMigId, laesMigId, MIG_KEY } from '../migLager';

afterEach(() => {
  vi.restoreAllMocks();
  window.localStorage.clear();
});

describe('migLager (W11)', () => {
  it('læser og skriver den gemte markering', () => {
    gemMigId('42');
    expect(window.localStorage.getItem(MIG_KEY)).toBe('42');
    expect(laesMigId()).toBe('42');
    gemMigId(null);
    expect(window.localStorage.getItem(MIG_KEY)).toBeNull();
    expect(laesMigId()).toBeNull();
  });

  it('en kastende getItem giver ingen markering i stedet for en fejl', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('SecurityError'); });
    expect(laesMigId()).toBeNull();
  });

  it('en kastende setItem/removeItem sluges (markeringen huskes blot ikke)', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('QuotaExceededError'); });
    vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(() => { throw new Error('SecurityError'); });
    expect(() => gemMigId('42')).not.toThrow();
    expect(() => gemMigId(null)).not.toThrow();
  });
});
