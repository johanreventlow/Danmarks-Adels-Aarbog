import { kildeAf } from '../Redaktion';
import type { Oplysning } from '../data/redaktionRead';

const mkOplysning = (kilder: Oplysning['kilder']): Oplysning => ({
  assertionId: 1, vaerdi: 'test', kilder, erKonklusion: true,
});

describe('kildeAf', () => {
  test('ingen kilde-rækker → "ingen kilde"', () => {
    expect(kildeAf(mkOplysning([]))).toBe('ingen kilde');
  });

  test('source-linket kilde (sourceTitel + side)', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20', side: '361' }]))).toBe('DAA 2018-20, 361');
  });

  test('kun sourceTitel, ingen side', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20' }]))).toBe('DAA 2018-20');
  });

  // Redaktionelt tilføjede oplysninger (opretFakta/tilfoejOplysning) har ALDRIG en linket
  // source — kun fritekst i citatTekst. Før rettelsen viste dette "ingen kilde" på trods af
  // at redaktøren rent faktisk havde indtastet en kildeangivelse (brugerfund 2026-07-23).
  test('ingen source, men citatTekst (fritekst-kilde) → citatTekst vises', () => {
    expect(kildeAf(mkOplysning([{ sourceId: null, citatTekst: 'Dansk Adels Aarbog – DAA 2018-20' }]))).toBe('Dansk Adels Aarbog – DAA 2018-20');
  });

  test('hverken source, side eller citatTekst → "ingen kilde"', () => {
    expect(kildeAf(mkOplysning([{ sourceId: null }]))).toBe('ingen kilde');
  });

  test('kun første kilde-række bruges', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'Første' }, { sourceId: 6, sourceTitel: 'Anden' }]))).toBe('Første');
  });
});
