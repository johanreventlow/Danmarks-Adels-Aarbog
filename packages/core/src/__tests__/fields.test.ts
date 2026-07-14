import { fmtYears, parseYear, stripParen } from '../fields';

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
