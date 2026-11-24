import { describe, expect, it } from 'vitest';
import { fmtDagDato, fmtVielse, vielsePraecision } from '../vielse';

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

describe('fmtVielse — »ca.« bevares (prod: »Gift ca. 1688«, kvalifikatoren er tom)', () => {
  it('rå tekst med »ca.« → »⚭ ca. ÅÅÅÅ«', () => {
    expect(fmtVielse('1688-01-01', '1688-12-31', { raw: 'Gift ca. 1688' })).toBe('⚭ ca. 1688');
    expect(fmtVielse('1632-01-01', '1632-12-31', { raw: 'Gift omkring 1632' })).toBe('⚭ ca. 1632');
  });
  it('kvalifikator about → »ca.«, aldrig en dag', () => {
    expect(fmtVielse('1700-05-05', '1700-05-05', { qualifier: 'about' })).toBe('⚭ ca. 1700');
  });
  it('anden kvalifikator end exact (før/efter) → intet, aldrig en for præcis dato', () => {
    expect(fmtVielse('1618-01-01', '1618-12-31', { qualifier: 'after' })).toBe('');
    expect(fmtVielse('1759-09-25', '1759-09-25', { qualifier: 'exact' })).toBe('⚭ 25. sept. 1759');
  });
  it('stednavn med »før« i sig er ikke en kvalifikator', () => {
    expect(fmtVielse('1759-09-25', '1759-09-25', { raw: 'Gift 25. sept. 1759 i Egernførde' })).toBe('⚭ 25. sept. 1759');
  });
});

describe('vielsePraecision — dag slår år slår ca.-år', () => {
  it('rangerer formaterede tekster', () => {
    expect(vielsePraecision('⚭ 21. juli 1667')).toBeGreaterThan(vielsePraecision('⚭ 1667'));
    expect(vielsePraecision('⚭ 1667')).toBeGreaterThan(vielsePraecision('⚭ ca. 1667'));
    expect(vielsePraecision('⚭ ca. 1667')).toBeGreaterThan(vielsePraecision(''));
  });
});

describe('fmtDagDato — ISO-dag som i Aarbogen', () => {
  it('»26. nov. 1943«, dag uden foranstillet nul', () => {
    expect(fmtDagDato('1943-11-26')).toBe('26. nov. 1943');
    expect(fmtDagDato('1936-11-02')).toBe('2. nov. 1936');
  });
  it('ugyldig eller tom → tom streng', () => {
    expect(fmtDagDato('1943')).toBe('');
    expect(fmtDagDato('')).toBe('');
    expect(fmtDagDato('1943-13-01')).toBe('');
  });
});
