import { describe, expect, it } from 'vitest';
import { ESTATE_SLAGS, MAJORAT_SLAGS, estateArtEtiket } from '../estates';

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
});
