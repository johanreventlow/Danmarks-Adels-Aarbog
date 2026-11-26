// »Om slægten« (6e, batch 5): hvert afsnit bærer sin udgave, så linjeafsnit fra forskellige udgaver kan skelnes.
import { byggAboutSections, indledningKilde, type RawAboutRow } from '../about';

const src2018 = { slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 2018-20', aar: 2018, udgave: 'DAA 2018-20' };
const src1939 = { slags: 'DAA-udgave', titel: 'Danmarks Adels Aarbog 1939', aar: 1939, udgave: 'DAA 1939' };

const rows: RawAboutRow[] = [
  { id: 1, subjekt_type: 'slaegt', subjekt_id: 1, source_id: 2, tekst: 'Slægten …', source: src2018 },
  { id: 2, subjekt_type: 'lineage', subjekt_id: 50, source_id: 2, tekst: 'Linje V i 2018-20', source: src2018 },
  { id: 3, subjekt_type: 'lineage', subjekt_id: 60, source_id: 1, tekst: 'Linje IV i 1939', source: src1939 },
  { id: 4, subjekt_type: 'lineage', subjekt_id: 60, source_id: 1, tekst: 'Privat kladde', privat: true, source: src1939 },
];

test('slægtens afsnit først, derefter linjerne i kodeorden, hver med sin udgave', () => {
  const s = byggAboutSections(rows, [
    { id: 60, navn: 'Den grevelige Linje af 1673', kode: 'IV' },
    { id: 50, navn: 'Den grevelige Linje af 1673', kode: 'V' },
  ]);
  expect(s.map((x) => [x.lineageId, x.lineageKode, x.kilde, x.tekst])).toEqual([
    [null, null, 'DAA 2018-20', 'Slægten …'],
    ['60', 'IV', 'DAA 1939', 'Linje IV i 1939'],
    ['50', 'V', 'DAA 2018-20', 'Linje V i 2018-20'],
  ]);
  expect(s.map(indledningKilde)).toEqual(['Kilde: DAA 2018-20', 'Kilde: DAA 1939', 'Kilde: DAA 2018-20']);
});

test('kildelinjen falder tilbage til årstallet og ellers til »Kilde ikke registreret«', () => {
  expect(indledningKilde({ kilde: null, aar: 1939 })).toBe('Kilde: Danmarks Adels Aarbog 1939');
  expect(indledningKilde({ kilde: null, aar: null })).toBe('Kilde ikke registreret');
});

test('linje uden navn får sin kode som overskrift', () => {
  const s = byggAboutSections([rows[1]], [{ id: 50, navn: null, kode: 'V' }]);
  expect(s[0].lineageNavn).toBe('Linje V');
});
