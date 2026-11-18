import { kildeAf } from '../Redaktion';
import type { Oplysning } from '../data/redaktionRead';

const mkOplysning = (kilder: Oplysning['kilder']): Oplysning => ({
  assertionId: 1, vaerdi: 'test', kilder, erKonklusion: true,
});

describe('kildeAf', () => {
  test('ingen kilde-rækker → "ingen kilde"', () => {
    expect(kildeAf(mkOplysning([]))).toBe('ingen kilde');
  });

  test('source-linket kilde viser den trykte side (sideTrykt) med »s.«', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20', side: '361', sideTrykt: '361' }]))).toBe('DAA 2018-20, s. 361');
  });

  // #388 (19/11): citation.side er PDF-siden; Redaktion viste »Dansk Adels Aarbog – DAA 1939, 544« for trykt s. 55.
  test('rå PDF-side vises aldrig: 1939 PDF-side 544 → »s. 55«', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 3, sourceTitel: 'Dansk Adels Aarbog – DAA 1939', side: '544', sideTrykt: '55' }])))
      .toBe('Dansk Adels Aarbog – DAA 1939, s. 55');
  });

  test('side uden trykt side (kan ikke omregnes) → kun værket, ikke PDF-siden', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 3, sourceTitel: 'Dansk Adels Aarbog – DAA 1939', side: '544' }]))).toBe('Dansk Adels Aarbog – DAA 1939');
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

  test('linket source vinder over co-eksisterende citatTekst (bog-indlæste fakta uændret)', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20', citatTekst: 'skal ikke vises' }]))).toBe('DAA 2018-20');
  });

  test('kun første kilde-række bruges', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'Første' }, { sourceId: 6, sourceTitel: 'Anden' }]))).toBe('Første');
  });
});
