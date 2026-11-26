import { describe, expect, it } from 'vitest';
import { ESTATE_SLAGS, MAJORAT_SLAGS, estateArtEtiket, estateKanonisk } from '../estates';

describe('estates', () => {
  it('ESTATE_SLAGS er præcis de fire koder', () => {
    expect([...ESTATE_SLAGS]).toEqual(['gård', 'grevskab', 'baroni', 'stamhus']);
  });
  it('MAJORAT_SLAGS er grevskab, baroni og stamhus — ikke gård', () => {
    expect([...MAJORAT_SLAGS].sort()).toEqual(['baroni', 'grevskab', 'stamhus']);
    expect(MAJORAT_SLAGS.has('gård')).toBe(false);
  });
  it('estateArtEtiket giver label, og null for NULL og ukendt', () => {
    expect(estateArtEtiket('grevskab')).toBe('Grevskab');
    expect(estateArtEtiket('gård')).toBe('Gård');
    expect(estateArtEtiket(null)).toBeNull();
    expect(estateArtEtiket('ukendt')).toBeNull();
    expect(estateArtEtiket('toString')).toBeNull();
  });
  it('estateKanonisk følger sammenlagt_i og lader andre id uberørte', () => {
    const m = new Map([['405', '5']]);
    expect(estateKanonisk('405', m)).toBe('5');
    expect(estateKanonisk('5', m)).toBe('5');
    expect(estateKanonisk('9', new Map())).toBe('9');
  });
  it('estateKanonisk hænger ikke på cyklus og stopper efter 10 skridt', () => {
    expect(estateKanonisk('a', new Map([['a', 'b'], ['b', 'a']]))).toBe('b');
    const kaede = new Map(Array.from({ length: 30 }, (_, i) => [`k${i}`, `k${i + 1}`] as [string, string]));
    expect(estateKanonisk('k0', kaede)).toBe('k10');
  });
});
