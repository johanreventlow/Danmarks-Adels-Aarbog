import { mapPresensGrundlag } from '../presens';

test('mapPresensGrundlag: joiner fact→konklusion→assertion og parser værdier', () => {
  const r = mapPresensGrundlag(
    [{ id: 1, levende: true }, { id: 2, levende: false }, { id: 3, levende: null }],
    [{ id: 10, subjekt_id: 1 }, { id: 11, subjekt_id: 2 }],
    [{ target_id: 10, valgt_assertion_id: 100 }, { target_id: 11, valgt_assertion_id: 101 }],
    [{ id: 100, vaerdi_tekst: 'II linje, 1. gren' }, { id: 101, vaerdi_tekst: 'ukendt format' }],
  );
  expect(r.levendeById).toEqual({ '1': true, '2': false, '3': false });
  // fact 11's værdi kan ikke parses → droppes fail-closed (ingen gættede ankre)
  expect(r.ankre).toEqual([{ personId: '1', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' }]);
});

test('mapPresensGrundlag: fact uden afklaret konklusion droppes', () => {
  const r = mapPresensGrundlag([{ id: 1, levende: true }], [{ id: 10, subjekt_id: 1 }], [], []);
  expect(r.ankre).toEqual([]);
});
