import { parseOverhovedVaerdi, sortAnkre, stiOverskrift } from '../presensLabels';

describe('parseOverhovedVaerdi', () => {
  test('linje + gren', () => {
    expect(parseOverhovedVaerdi('42', 'II linje, 1. gren')).toEqual({ personId: '42', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' });
  });
  test('kun linje', () => {
    expect(parseOverhovedVaerdi('7', 'I linje')).toEqual({ personId: '7', linje: 'I', gren: null, raaVaerdi: 'I linje' });
  });
  test('tolerant for kasse/mellemrum', () => {
    expect(parseOverhovedVaerdi('9', '  ii Linje ,  3 . gren ')?.gren).toBe(3);
  });
  test('ugyldig værdi → null', () => {
    expect(parseOverhovedVaerdi('1', 'hovedlinjen')).toBeNull();
    expect(parseOverhovedVaerdi('1', '')).toBeNull();
    expect(parseOverhovedVaerdi('1', 'XIIX linje')).toBeNull();
  });
});

describe('sortAnkre', () => {
  test('romertals-orden, så gren-nummer', () => {
    const a = (personId: string, linje: string, gren: number | null) => ({ personId, linje, gren, raaVaerdi: '' });
    const sorted = sortAnkre([a('c', 'II', 2), a('b', 'II', 1), a('d', 'I', null)]);
    expect(sorted.map((x) => x.personId)).toEqual(['d', 'b', 'c']);
  });
});

describe('stiOverskrift — søskende-terminaler', () => {
  const s = (maend: number, kvinder: number, ukendt = 0) => ({ slags: 'soeskende' as const, sammensaetning: { maend, kvinder, ukendt } });
  test('ankerens egne søskende: ental/flertal/blandet', () => {
    expect(stiOverskrift([], s(0, 1))).toBe('Søster');
    expect(stiOverskrift([], s(0, 2))).toBe('Søstre');
    expect(stiOverskrift([], s(1, 0))).toBe('Bror');
    expect(stiOverskrift([], s(2, 0))).toBe('Brødre');
    expect(stiOverskrift([], s(1, 1))).toBe('Søskende');
    expect(stiOverskrift([], s(1, 0, 1))).toBe('Søskende'); // ukendt køn → neutral
  });
  test('fars niveau: farbror-komposit, fars søster uden komposit', () => {
    expect(stiOverskrift(['mand'], s(1, 0))).toBe('Farbror');
    expect(stiOverskrift(['mand'], s(2, 0))).toBe('Farbrødre');
    expect(stiOverskrift(['mand'], s(0, 1))).toBe('Fars søster');
    expect(stiOverskrift(['mand'], s(0, 2))).toBe('Fars søstre');
    expect(stiOverskrift(['mand'], s(1, 1))).toBe('Fars søskende');
    expect(stiOverskrift(['kvinde'], s(1, 0))).toBe('Morbror');
  });
  test('længere kæder: chunk-par + genitiv (bogens FARFARS BROR / FARFARS FARBROR)', () => {
    expect(stiOverskrift(['mand', 'mand'], s(1, 0))).toBe('Farfars bror');
    expect(stiOverskrift(['mand', 'mand', 'mand'], s(1, 0))).toBe('Farfars farbror');
    expect(stiOverskrift(['mand', 'kvinde'], s(0, 1))).toBe('Farmors søster');
    expect(stiOverskrift(['kvinde', 'mand'], s(1, 1))).toBe('Morfars søskende');
  });
  test('kønssymmetri via mor-linjen', () => {
    expect(stiOverskrift(['kvinde', 'kvinde', 'mand'], s(1, 0))).toBe('Mormors farbror');
  });
  test('ukendt køn i kæden → neutralt led', () => {
    expect(stiOverskrift([null], s(1, 0))).toBe('Forælders bror');
  });
});

describe('stiOverskrift — forælder- og enke-terminaler', () => {
  test('gift-ind-forælder', () => {
    expect(stiOverskrift([], { slags: 'foraelder', koen: 'kvinde' })).toBe('Mor');
    expect(stiOverskrift([], { slags: 'foraelder', koen: 'mand' })).toBe('Far');
    expect(stiOverskrift(['mand'], { slags: 'foraelder', koen: 'kvinde' })).toBe('Farmor');
  });
  test('enke efter blodforfader', () => {
    expect(stiOverskrift(['mand'], { slags: 'enke' })).toBe('Fars enke');
    expect(stiOverskrift(['mand', 'mand'], { slags: 'enke' })).toBe('Farfars enke');
  });
});
