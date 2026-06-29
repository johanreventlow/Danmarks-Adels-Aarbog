import { eraAdvarsel } from '../eraAdvarsel';

test('eraAdvarsel: barn født før forælder → advarsel', () => {
  expect(eraAdvarsel(1600, [{ foedsel: 1650, doed: 1700 }])).toMatch(/før forælder/i);
});
test('eraAdvarsel: barn født efter forælders død+margin → advarsel', () => {
  expect(eraAdvarsel(1705, [{ foedsel: 1650, doed: 1700 }])).toMatch(/efter forælders død/i);
});
test('eraAdvarsel: konsistent → null', () => {
  expect(eraAdvarsel(1675, [{ foedsel: 1650, doed: 1700 }])).toBeNull();
});
test('eraAdvarsel: manglende år → null (ingen falsk advarsel)', () => {
  expect(eraAdvarsel(null, [{ foedsel: 1650, doed: 1700 }])).toBeNull();
  expect(eraAdvarsel(1600, [{ foedsel: null, doed: null }])).toBeNull();
});
