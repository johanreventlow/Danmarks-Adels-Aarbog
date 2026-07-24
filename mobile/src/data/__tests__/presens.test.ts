import {
  erAdelsTitel,
  feminiserTitel,
  formatAndetNavn,
  formatAnkerNavn,
  mapPresensGrundlag,
  mapPresensNavneDele,
} from '../presens';

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

test('mapPresensNavneDele: kobler personrækker og adelstitler pr. id', () => {
  const r = mapPresensNavneDele(
    [
      { id: 476, visning_navn: 'Christian Ditlev Ludvig', visning_efternavn: 'Reventlow' },
      { id: 999, visning_navn: 'Ingeborg Theresia Pfab', visning_efternavn: null },
    ],
    [{ subjekt_id: 476, vaerdi_tekst: 'Lensgreve' }],
  );

  expect(r['476']).toEqual({
    navn: 'Christian Ditlev Ludvig',
    titel: 'Lensgreve',
    efternavn: 'Reventlow',
  });
  expect(r['999']).toEqual({ navn: 'Ingeborg Theresia Pfab', titel: '', efternavn: '' });
});

test('mapPresensNavneDele: første gyldige adelstitel vinder deterministisk', () => {
  const r = mapPresensNavneDele(
    [{ id: 469, visning_navn: 'Einar Karl Ludwig', visning_efternavn: 'Reventlow' }],
    [
      { subjekt_id: 469, vaerdi_tekst: 'Greve' },
      { subjekt_id: 469, vaerdi_tekst: 'Baron' },
    ],
  );

  expect(r['469'].titel).toBe('Greve');
});

test('formatAnkerNavn: fulde fornavne + titel med småt + efternavn', () => {
  expect(formatAnkerNavn(
    { navn: 'Christian Ditlev Ludvig', titel: 'Lensgreve', efternavn: 'Reventlow' },
    'fallback',
  )).toBe('Christian Ditlev Ludvig lensgreve Reventlow');
});

test('formatAndetNavn: titel med stort forbogstav + fornavne uden efternavn', () => {
  expect(formatAndetNavn(
    { navn: 'Julie', titel: 'komtesse', efternavn: 'Reventlow' },
    'fallback',
  )).toBe('Komtesse Julie');
});

test('navneformater falder tilbage ved manglende navne-dele', () => {
  expect(formatAnkerNavn(undefined, 'person 42')).toBe('person 42');
  expect(formatAndetNavn(undefined, 'person 42')).toBe('person 42');
});

test('erAdelsTitel accepterer adelstitler og afviser hverv', () => {
  expect(erAdelsTitel('GREVE')).toBe(true);
  expect(erAdelsTitel('Comtesse')).toBe(true);
  expect(erAdelsTitel('Premierløjtnant i vesttyske Pionier Bataillons reserve')).toBe(false);
  expect(erAdelsTitel('Geheimekonferensraad Greve')).toBe(false);
});

test('feminiserTitel bøjer mandlige adelstitler og afviser andre værdier', () => {
  expect(feminiserTitel('Lensgreve')).toBe('Lensgrevinde');
  expect(feminiserTitel('BARON')).toBe('Baronesse');
  expect(feminiserTitel('Friherre')).toBe('Friherreinde');
  expect(feminiserTitel('Komtesse')).toBeNull();
});

test('mapPresensNavneDele: gift-ind kvinde overtager ægtefællens rang og efternavn', () => {
  const r = mapPresensNavneDele(
    [
      { id: 811, visning_navn: 'Hedwig', visning_efternavn: 'Mundhenke', koen: 'kvinde' },
      { id: 380, visning_navn: 'Henning Lothar Gerd', visning_efternavn: 'Reventlow', koen: 'mand' },
    ],
    [{ subjekt_id: 380, vaerdi_tekst: 'Lensgreve' }],
    new Map([['811', '380'], ['380', '811']]),
  );

  expect(r['811']).toEqual({
    navn: 'Hedwig',
    titel: 'Lensgrevinde',
    efternavn: 'Reventlow',
    fodt: 'Mundhenke',
    tilgiftet: true,
  });
  expect(formatAndetNavn(r['811'], 'fallback'))
    .toBe('Lensgrevinde Hedwig Reventlow, født Mundhenke');
});

test('mapPresensNavneDele: egen fødetitel bevares i født-klausulen', () => {
  const r = mapPresensNavneDele(
    [
      { id: 852, visning_navn: 'Beke', visning_efternavn: 'Ahlefeldt-Laurvig', koen: 'kvinde' },
      { id: 900, visning_navn: 'En Lensgreve', visning_efternavn: 'Reventlow', koen: 'mand' },
    ],
    [
      { subjekt_id: 852, vaerdi_tekst: 'Komtesse' },
      { subjekt_id: 900, vaerdi_tekst: 'Lensgreve' },
    ],
    new Map([['852', '900'], ['900', '852']]),
  );

  expect(formatAndetNavn(r['852'], 'fallback'))
    .toBe('Lensgrevinde Beke Reventlow, født komtesse Ahlefeldt-Laurvig');
});

test('tilgiftet og født holdes adskilt: gift-ind kvinde uden pigenavn beholder efternavnet', () => {
  const r = mapPresensNavneDele(
    [
      { id: 811, visning_navn: 'Hedwig', visning_efternavn: null, koen: 'kvinde' },
      { id: 380, visning_navn: 'Henning Lothar Gerd', visning_efternavn: 'Reventlow', koen: 'mand' },
    ],
    [{ subjekt_id: 380, vaerdi_tekst: 'Lensgreve' }],
    new Map([['811', '380'], ['380', '811']]),
  );

  expect(r['811']).toEqual({
    navn: 'Hedwig',
    titel: 'Lensgrevinde',
    efternavn: 'Reventlow',
    tilgiftet: true,
  });
  expect(r['811'].fodt).toBeUndefined();
  expect(formatAnkerNavn(r['811'], 'fallback')).toBe('Hedwig lensgrevinde Reventlow');
  expect(formatAndetNavn(r['811'], 'fallback')).toBe('Lensgrevinde Hedwig Reventlow');
});

test('gift-ind override kræver både bøjelig titel og ægtefællens efternavn', () => {
  const personer = [
    { id: 1, visning_navn: 'Anni', visning_efternavn: null, koen: 'kvinde' },
    { id: 2, visning_navn: 'Manden', visning_efternavn: null, koen: 'mand' },
  ];
  const r = mapPresensNavneDele(
    personer,
    [{ subjekt_id: 2, vaerdi_tekst: 'Greve' }],
    new Map([['1', '2']]),
  );

  expect(r['1']).toEqual({ navn: 'Anni', titel: '', efternavn: '' });
});
