import { kildeAf } from '../FaktaKort';
import type { Oplysning } from '../../../data/redaktionRead';

const mkOplysning = (kilder: Oplysning['kilder']): Oplysning => ({
  assertionId: 1, vaerdi: 'test', kilder, erKonklusion: true,
});

describe('kildeAf', () => {
  test('ingen kilde-rækker → "(kilde mangler)"', () => {
    expect(kildeAf(mkOplysning([]))).toBe('(kilde mangler)');
  });

  test('source-linket kilde (sourceTitel + side)', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20', side: '361' }]))).toBe('DAA 2018-20, 361');
  });

  // Redaktionelt tilføjede oplysninger har ALDRIG en linket source — kun fritekst i
  // citatTekst. Før rettelsen viste dette "(kilde mangler)" på trods af at redaktøren rent
  // faktisk havde indtastet en kildeangivelse (brugerfund 2026-07-23, spejler web-rettelsen).
  test('ingen source, men citatTekst (fritekst-kilde) → citatTekst vises', () => {
    expect(kildeAf(mkOplysning([{ sourceId: null, citatTekst: 'Dansk Adels Aarbog – DAA 2018-20' }]))).toBe('Dansk Adels Aarbog – DAA 2018-20');
  });

  test('hverken source, side eller citatTekst → "(kilde mangler)"', () => {
    expect(kildeAf(mkOplysning([{ sourceId: null }]))).toBe('(kilde mangler)');
  });

  test('linket source vinder over co-eksisterende citatTekst (bog-indlæste fakta uændret)', () => {
    expect(kildeAf(mkOplysning([{ sourceId: 5, sourceTitel: 'DAA 2018-20', citatTekst: 'skal ikke vises' }]))).toBe('DAA 2018-20');
  });
});
