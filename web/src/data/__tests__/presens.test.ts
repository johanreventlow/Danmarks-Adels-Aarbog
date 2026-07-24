import { mapPresensGrundlag, mapPresensNavneDele, formatAnkerNavn, formatAndetNavn, erAdelsTitel } from '../presens';

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

test('mapPresensNavneDele: kobler rå person-rækker + adels-titel-fakta til navne-dele pr. id', () => {
  const personer = [
    { id: 476, visning_navn: 'Christian Ditlev Ludvig', visning_efternavn: 'Reventlow' },
    { id: 999, visning_navn: 'Ingeborg Theresia Pfab', visning_efternavn: null },
  ];
  const adelsTitelFakta = [{ subjekt_id: 476, vaerdi_tekst: 'Lensgreve' }];
  const r = mapPresensNavneDele(personer, adelsTitelFakta);
  expect(r['476']).toEqual({ navn: 'Christian Ditlev Ludvig', titel: 'Lensgreve', efternavn: 'Reventlow' });
  expect(r['999']).toEqual({ navn: 'Ingeborg Theresia Pfab', titel: '', efternavn: '' });
});

test('mapPresensNavneDele: person 469s reelle prod-scenarie (fetchAdelsTitelFakta har allerede udelukket hvervet)', () => {
  // Fundet ved bruger-verifikation: "Einar…" har to afklarede titel-fakta i prod, "Greve" og
  // "Premierløjtnant i vesttyske Pionier Bataillons reserve". Den cachede visning_titel-kolonne
  // (IKKE længere brugt her, se kommentar i presens.ts) valgte fejlagtigt den sidste. Kildelaget
  // (fetchAdelsTitelFakta) filtrerer allerede hvervet fra FØR mapPresensNavneDele kaldes — denne
  // test bekræfter kun output for det RIGTIGE, allerede-filtrerede input (ingen "første fund
  // vinder"-tievalg testes her, se testen nedenfor for det).
  const personer = [{ id: 469, visning_navn: 'Einar Karl Ludwig', visning_efternavn: 'Reventlow' }];
  const adelsTitelFakta = [{ subjekt_id: 469, vaerdi_tekst: 'Greve' }];
  const r = mapPresensNavneDele(personer, adelsTitelFakta);
  expect(r['469'].titel).toBe('Greve');
});

test('mapPresensNavneDele: to konkurrerende adelstitler for samme person — første i input-rækkefølgen vinder', () => {
  // Ægte tie-break-test (i modsætning til testen ovenfor): to FORSKELLIGE, begge-gyldige
  // adelstitler for samme person (fx grevelig linje OG friherre-arv). fetchAdelsTitelFakta
  // sikrer input-rækkefølgen er laveste-conclusion-id-først (ORDER BY id på alle tre led) —
  // her simuleres det direkte ved array-rækkefølgen.
  const personer = [{ id: 469, visning_navn: 'Einar Karl Ludwig', visning_efternavn: 'Reventlow' }];
  const adelsTitelFakta = [
    { subjekt_id: 469, vaerdi_tekst: 'Greve' },
    { subjekt_id: 469, vaerdi_tekst: 'Baron' },
  ];
  const r = mapPresensNavneDele(personer, adelsTitelFakta);
  expect(r['469'].titel).toBe('Greve'); // først i rækkefølgen, ikke sidst
});

test('formatAnkerNavn: fornavne + titel (småt) inde i navnet + efternavn — bogens hovedrække-format', () => {
  expect(formatAnkerNavn({ navn: 'Christian Ditlev Ludvig', titel: 'Lensgreve', efternavn: 'Reventlow' }, 'fallback'))
    .toBe('Christian Ditlev Ludvig lensgreve Reventlow');
});

test('formatAnkerNavn: uden titel eller efternavn udelades de blot, ingen dobbelt-mellemrum', () => {
  expect(formatAnkerNavn({ navn: 'Ingeborg Theresia Pfab', titel: '', efternavn: '' }, 'fallback'))
    .toBe('Ingeborg Theresia Pfab');
});

test('formatAnkerNavn: manglende navne-dele falder tilbage til fallback', () => {
  expect(formatAnkerNavn(undefined, 'person 42')).toBe('person 42');
  expect(formatAnkerNavn({ navn: '', titel: '', efternavn: '' }, 'person 42')).toBe('person 42');
});

test('formatAndetNavn: Titel (stort forbogstav) + fornavne, ALDRIG efternavn — bogens øvrige-række-format', () => {
  expect(formatAndetNavn({ navn: 'Johan Martin', titel: 'Greve', efternavn: 'Reventlow' }, 'fallback')).toBe('Greve Johan Martin');
});

test('formatAndetNavn: titelløs person (fx gift-ind ægtefælle) vises uden præfiks', () => {
  expect(formatAndetNavn({ navn: 'Anni Gregersen', titel: '', efternavn: '' }, 'fallback')).toBe('Anni Gregersen');
});

test('formatAndetNavn: normaliserer stort forbogstav uanset lagret store/små bogstaver (ingen DB-håndhævelse)', () => {
  expect(formatAndetNavn({ navn: 'Julie', titel: 'komtesse', efternavn: 'Reventlow' }, 'fallback')).toBe('Komtesse Julie');
  expect(formatAndetNavn({ navn: 'Julie', titel: 'KOMTESSE', efternavn: 'Reventlow' }, 'fallback')).toBe('KOMTESSE Julie');
});

test('formatAndetNavn: manglende navne-dele falder tilbage til fallback', () => {
  expect(formatAndetNavn(undefined, 'person 42')).toBe('person 42');
});

test('erAdelsTitel: bekræftede adelstitler (case-insensitivt) — regression for person 469-fundet', () => {
  expect(erAdelsTitel('Greve')).toBe(true);
  expect(erAdelsTitel('greve')).toBe(true);
  expect(erAdelsTitel('GREVE')).toBe(true);
  expect(erAdelsTitel('Komtesse')).toBe(true);
  expect(erAdelsTitel('Comtesse')).toBe(true); // alternativ stavemåde set i prod
  expect(erAdelsTitel('Lensgrevinde')).toBe(true);
});

test('erAdelsTitel: hverv/militærgrad/embede afvises — den præcise fejl der blev fundet i prod', () => {
  // Person 469 "Einar…" har begge disse som afklarede titel-fakta i prod; kun "Greve" må bruges.
  expect(erAdelsTitel('Premierløjtnant i vesttyske Pionier Bataillons reserve')).toBe(false);
  expect(erAdelsTitel('Geheimekonferensraad Greve')).toBe(false); // sammensat hofembede — ikke ren adelstitel
  expect(erAdelsTitel('Dr.')).toBe(false);
  expect(erAdelsTitel('hofjægermester')).toBe(false);
  expect(erAdelsTitel('til Ziesendorf og Brockhusen')).toBe(false);
});
