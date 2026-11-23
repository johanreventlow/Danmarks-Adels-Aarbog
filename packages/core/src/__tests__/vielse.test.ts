import { describe, expect, it } from 'vitest';
import { fmtVielse } from '../vielse';

describe('fmtVielse — vielsesdato med ⚭', () => {
  it('kendt dag → »⚭ D. måned ÅÅÅÅ«, dag uden foranstillet nul', () => {
    expect(fmtVielse('1670-11-18', '1670-11-18')).toBe('⚭ 18. nov. 1670');
    expect(fmtVielse('1681-05-01', '1681-05-01')).toBe('⚭ 1. maj 1681');
    expect(fmtVielse('1754-09-12', '1754-09-12')).toBe('⚭ 12. sept. 1754');
    expect(fmtVielse('1667-07-21', '1667-07-21')).toBe('⚭ 21. juli 1667');
  });
  it('alle tolv månedsnavne som i Aarbogen', () => {
    const navne = ['jan.', 'feb.', 'marts', 'april', 'maj', 'juni', 'juli', 'aug.', 'sept.', 'okt.', 'nov.', 'dec.'];
    navne.forEach((n, i) => {
      const d = `1700-${String(i + 1).padStart(2, '0')}-05`;
      expect(fmtVielse(d, d)).toBe(`⚭ 5. ${n} 1700`);
    });
  });
  it('interval inden for ét år → kun året, aldrig en forkert dag', () => {
    expect(fmtVielse('1652-01-01', '1652-12-31')).toBe('⚭ 1652');
  });
  it('interval over flere år eller manglende ende → intet', () => {
    expect(fmtVielse('1652-03-01', '1653-02-28')).toBe('');
    expect(fmtVielse(null, null)).toBe('');
    expect(fmtVielse('1670-11-18', null)).toBe('');
    expect(fmtVielse(null, '1670-11-18')).toBe('');
  });
  it('ugyldig streng → intet', () => {
    expect(fmtVielse('ukendt', 'ukendt')).toBe('');
  });
});
