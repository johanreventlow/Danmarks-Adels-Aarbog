import { aarSpaend, fletFloruit, fmtVisningsAar, fmtYears, parseYear, stripParen } from '../fields';
import { oploesRelativDato } from '../relativeDates';

// Rene felt-hjælpere (port fra design-HTML). Datalag-dækning: årstals-udtræk og
// leveår-formatering rammer mange rå-felter, så randtilfældene skal være fastlåst.

describe('parseYear — første 3-4-cifrede årstal', () => {
  test('rent årstal', () => {
    expect(parseYear('1640')).toBe(1640);
    expect(parseYear('999')).toBe(999);
  });
  test('årstal indlejret i tekst (præfiks/suffiks ignoreres)', () => {
    expect(parseYear('* 1640')).toBe(1640);
    expect(parseYear('født ca. 1640 i København')).toBe(1640);
    expect(parseYear('1640–1708')).toBe(1640); // første match
  });
  test('for kort til at være årstal → null', () => {
    expect(parseYear('85')).toBeNull();
    expect(parseYear('')).toBeNull();
    expect(parseYear('uden tal')).toBeNull();
  });
  test('null/undefined → null', () => {
    expect(parseYear(null)).toBeNull();
    expect(parseYear(undefined)).toBeNull();
  });
  test('5-cifret klump: tager de første 4 cifre', () => {
    expect(parseYear('12345')).toBe(1234);
  });
});

describe('fmtYears — leveår-visning', () => {
  test('begge år → interval med en-dash', () => {
    expect(fmtYears('1640', '1708')).toBe('1640–1708');
  });
  test('kun fødsel → "* år"', () => {
    expect(fmtYears('1640', null)).toBe('* 1640');
  });
  test('kun død → "† år"', () => {
    expect(fmtYears(null, '1708')).toBe('† 1708');
  });
  test('begge tomme → tom streng', () => {
    expect(fmtYears(null, null)).toBe('');
    expect(fmtYears('', '')).toBe('');
  });
  test('eksisterende symboler/whitespace renses bort før formatering', () => {
    expect(fmtYears('* 1640', '† 1708')).toBe('1640–1708');
    expect(fmtYears('  1640 ', '1708')).toBe('1640–1708');
  });
});

describe('stripParen — fjern omkransende parenteser/whitespace', () => {
  test('parenteser fjernes', () => {
    expect(stripParen('(1640–1708)')).toBe('1640–1708');
    expect(stripParen('  (ejer 1690) ')).toBe('ejer 1690');
  });
  test('uden parenteser bevares ordret', () => {
    expect(stripParen('ejer')).toBe('ejer');
  });
  test('null/undefined → tom streng', () => {
    expect(stripParen(null)).toBe('');
    expect(stripParen(undefined)).toBe('');
  });
});

describe('aarSpaend', () => {
  it('alle årstal i datoen; dage og måneder tæller ikke', () => {
    expect(aarSpaend('† 1406/1410')).toEqual([1406, 1410]);
    expect(aarSpaend('17. aug. 1840 på Aalstrup')).toEqual([1840, 1840]);
    expect(aarSpaend('mellem 1. og 4. juni 1697')).toEqual([1697, 1697]);
    expect(aarSpaend('† s.å.')).toBeNull();
    expect(aarSpaend(null)).toBeNull();
  });
  it('»s.å.« opløst mod fødslen giver fødselsåret', () => {
    expect(aarSpaend(oploesRelativDato('† s.å.', '* 12. maj 1650'))).toEqual([1650, 1650]);
  });
});

describe('fmtVisningsAar — livsdatoer vinder over floruit', () => {
  test('livsdatoer vises som fmtYears, floruit ignoreres', () => {
    expect(fmtVisningsAar('* 1640', '† 1708', '1660')).toBe('1640–1708');
  });
  test('kun floruit-interval → Nævnes', () => {
    expect(fmtVisningsAar(null, null, '1349–1391')).toBe('Nævnes 1349–1391');
  });
  test('kun floruit-år → Nævnes', () => {
    expect(fmtVisningsAar(null, null, '1671')).toBe('Nævnes 1671');
  });
  test('intet → tom streng', () => {
    expect(fmtVisningsAar(null, null, null)).toBe('');
    expect(fmtVisningsAar(undefined, undefined, undefined)).toBe('');
  });
  test('delvis livsdato vinder også over floruit', () => {
    expect(fmtVisningsAar(null, '(-1358)', '1319–1363')).toBe(fmtYears(null, '(-1358)'));
  });
});

describe('fletFloruit — forening af floruit-spænd', () => {
  test('forener spænd og enkeltår', () => {
    expect(fletFloruit(['1349–1391', '1400', null])).toBe('1349–1400');
  });
  test('enkelt år bevares', () => {
    expect(fletFloruit(['1657'])).toBe('1657');
  });
  test('kun tomme → null', () => {
    expect(fletFloruit([null, undefined])).toBeNull();
  });
});
