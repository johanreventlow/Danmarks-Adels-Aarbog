import { aarSpaend, fmtVisningsAar, fmtYears, kortLivsdato, parseYear, stripParen } from '../fields';
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
  test('begge år → »* født † død«', () => {
    expect(fmtYears('1671', '1738')).toBe('* 1671 † 1738');
    expect(fmtYears('21. juni 1671', '1. okt. 1738')).toBe('* 21. juni 1671 † 1. okt. 1738');
  });
  test('død med ord i stedet for år: ét tegn, aldrig »† †«', () => {
    expect(fmtYears(null, '† ung')).toBe('† ung');
    expect(fmtYears('1688', '† lille')).toBe('* 1688 † lille');
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
    expect(fmtYears('* 1640', '† 1708')).toBe('* 1640 † 1708');
    expect(fmtYears('  1640 ', '1708')).toBe('* 1640 † 1708');
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
    expect(fmtVisningsAar('* 1640', '† 1708', '1660')).toBe('* 1640 † 1708');
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

// Projektejeren 2026-11-24: en sammenfoldet persons overskrift viser kun årstallet, men bogens forbehold skal med.
// »† efter 1575« må ikke blive »† 1575«, og »147(5?)« (usikkert sidste ciffer, person 77) ikke »147«.
describe('kortLivsdato — årstal med bogens forbehold', () => {
  test('dag og måned falder bort', () => {
    expect(kortLivsdato('17. aug. 1840')).toBe('1840');
    expect(kortLivsdato('* 1. april 1603')).toBe('1603');
    expect(kortLivsdato('10 Juni\n1683')).toBe('1683');
  });
  test('forbehold foran årstallet bevares', () => {
    expect(kortLivsdato('† efter 1575')).toBe('efter 1575');
    expect(kortLivsdato('o. 1500')).toBe('o. 1500');
    expect(kortLivsdato('* ca. 1484')).toBe('ca. 1484');
    expect(kortLivsdato('† før 1606')).toBe('før 1606');
    expect(kortLivsdato('† senest 1414')).toBe('senest 1414');
    expect(kortLivsdato('efter 4 Decbr. 1676 (saaret ved Lund)')).toBe('efter 1676');
  });
  test('forbehold om dagen, ikke året, giver rent årstal', () => {
    expect(kortLivsdato('† 1496, før 10. okt.')).toBe('1496');
    expect(kortLivsdato('† før 1261 (22. aug.)')).toBe('før 1261');
  });
  test('usikre og flertydige år bevares', () => {
    expect(kortLivsdato('† 1. aug. 147(5?)')).toBe('147(5?)');
    expect(kortLivsdato('† 1342/1353')).toBe('1342/1353');
    expect(kortLivsdato('1678 (?)')).toBe('1678?');
    expect(kortLivsdato('† mellem 1363 og 1364 (før 14. juni)')).toBe('1363/1364');
  });
  test('tekst uden årstal bevares ordret', () => {
    expect(kortLivsdato('† lille')).toBe('lille');
    expect(kortLivsdato('ung')).toBe('ung');
    expect(kortLivsdato('+ ung')).toBe('ung'); // 1939-OCR'ens † som »+«
  });
});

describe('parseYear/aarSpaend — usikkert sidste ciffer', () => {
  test('»147(5?)« er 1475, ikke 147', () => {
    expect(parseYear('† 1. aug. 147(5?)')).toBe(1475);
    expect(aarSpaend('† 1. aug. 147(5?)')).toEqual([1475, 1475]);
  });
});
