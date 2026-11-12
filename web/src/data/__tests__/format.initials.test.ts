import { describe, expect, it } from 'vitest';
import { initials } from '../format';

describe('initials', () => {
  it('tager første bogstav af de to første navne', () => {
    expect(initials('Iwan Reventlow')).toBe('IR');
  });
  it('springer parenteser og andre tegn over', () => {
    expect(initials('Adelheid (Lilli)')).toBe('AL');
    expect(initials('Fanny (Franziska) Liane')).toBe('FF');
    expect(initials('(Søn)')).toBe('S');
  });
  it('bevarer danske bogstaver', () => {
    expect(initials('Øllegaard Ågesdatter')).toBe('ØÅ');
    expect(initials('æbelø')).toBe('Æ');
  });
  it('ord uden bogstaver tæller ikke med', () => {
    expect(initials('Christian 3. Reventlow')).toBe('CR');
    expect(initials('— Reventlow')).toBe('R');
  });
  it('navn uden bogstaver giver et neutralt tegn', () => {
    expect(initials('')).toBe('?');
    expect(initials('(—)')).toBe('?');
  });
});
