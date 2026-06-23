import { compareDanish, initialOf, sortLetters } from '../collation';

describe('compareDanish — Æ/Ø/Å sorteres EFTER Z', () => {
  test('Å kommer efter B', () => {
    expect(compareDanish('Å', 'B')).toBe(1);
  });
  test('Z kommer før Æ, Ø, Å', () => {
    expect(compareDanish('Z', 'Æ')).toBe(-1);
    expect(compareDanish('Z', 'Ø')).toBe(-1);
    expect(compareDanish('Z', 'Å')).toBe(-1);
  });
  test('intern orden Æ < Ø < Å', () => {
    expect(compareDanish('Æ', 'Ø')).toBe(-1);
    expect(compareDanish('Ø', 'Å')).toBe(-1);
  });
  test('sorterer en blandet liste i dansk orden', () => {
    const input = ['Østergaard', 'Aaberg', 'Bang', 'Ægir', 'Zahle', 'Åkjær'];
    // initialOf bruges ikke her; vi sorterer hele strenge.
    const sorted = [...input].sort(compareDanish);
    expect(sorted).toEqual(['Aaberg', 'Bang', 'Zahle', 'Ægir', 'Østergaard', 'Åkjær']);
  });
  test('case-insensitiv på rang', () => {
    expect(compareDanish('aaberg', 'Bang')).toBe(-1);
  });
});

describe('initialOf — bruger efternavn (sidste token)', () => {
  test('fuldt navn grupperes under efternavnets initial', () => {
    expect(initialOf('Christian Ditlev Reventlow')).toBe('R');
  });
  test('enkelt navn', () => {
    expect(initialOf('Reventlow')).toBe('R');
  });
  test('Æ/Ø/Å bevares som egne bogstaver', () => {
    expect(initialOf('Niels Ærø')).toBe('Æ');
    expect(initialOf('Ове Øster')).toBe('Ø');
    expect(initialOf('Per Åstrup')).toBe('Å');
  });
  test('tomt navn → #', () => {
    expect(initialOf('')).toBe('#');
    expect(initialOf('   ')).toBe('#');
  });
});

describe('sortLetters', () => {
  test('bogstav-nøgler i dansk orden', () => {
    expect(sortLetters(['Å', 'A', 'Ø', 'B', 'Æ', 'Z'])).toEqual(['A', 'B', 'Z', 'Æ', 'Ø', 'Å']);
  });
});
