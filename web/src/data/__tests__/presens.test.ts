import { mapPresensGrundlag, mapPresensNavneDele, formatAnkerNavn, formatAndetNavn, erAdelsTitel, feminiserTitel } from '../presens';

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

test('feminiserTitel: mandstitel → kvindelig form (case-insensitivt)', () => {
  expect(feminiserTitel('Lensgreve')).toBe('Lensgrevinde');
  expect(feminiserTitel('greve')).toBe('Grevinde');
  expect(feminiserTitel('BARON')).toBe('Baronesse');
  expect(feminiserTitel('Friherre')).toBe('Friherreinde');
  expect(feminiserTitel('Rigsgreve')).toBe('Rigsgrevinde');
});

test('feminiserTitel: ukendt/ikke-bøjelig titel giver null (fx Komtesse — ingen "gifter sig til"-form)', () => {
  expect(feminiserTitel('Komtesse')).toBeNull();
  expect(feminiserTitel('Premierløjtnant i vesttyske Pionier Bataillons reserve')).toBeNull();
});

test('mapPresensNavneDele: gift-ind kvinde overtager ægtefællens titel+efternavn, egen fødeidentitet i født-klausul — Hedwig-scenariet', () => {
  // Reelt prod-scenarie (bruger-verifikation 2026-07-24): Hedwig Mundhenke (811) er enke efter
  // Lensgreve Henning Lothar Gerd Reventlow (380). Efter datastrukturering (visning_navn='Hedwig',
  // visning_efternavn='Mundhenke', ingen egen titel) skal hun vises "Lensgrevinde Hedwig
  // Reventlow, født Mundhenke" — ALDRIG "Hedwig Mundhenke" (hendes rå, utilgiftede identitet).
  const personer = [
    { id: 811, visning_navn: 'Hedwig', visning_efternavn: 'Mundhenke', koen: 'kvinde' },
    { id: 380, visning_navn: 'Henning Lothar Gerd', visning_efternavn: 'Reventlow', koen: 'mand' },
  ];
  const adelsTitelFakta = [{ subjekt_id: 380, vaerdi_tekst: 'Lensgreve' }];
  const aegtefaelleIdById = new Map([['811', '380'], ['380', '811']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['811']).toEqual({ navn: 'Hedwig', titel: 'Lensgrevinde', efternavn: 'Reventlow', fodt: 'Mundhenke', tilgiftet: true });
  expect(formatAndetNavn(r['811'], 'fallback')).toBe('Lensgrevinde Hedwig Reventlow, født Mundhenke');
});

test('mapPresensNavneDele: gift-ind kvinde der selv var adelig — fødetitel bevares i født-klausul (Beke-scenariet)', () => {
  // Beke (852, afdød, ikke i præsenslisten — men bekræftet af bruger som andet eksempel): født
  // komtesse Ahlefeldt-Laurvig, gift med en lensgreve Reventlow. Hendes EGEN adelstitel viger for
  // ægtefællens rang i hovedvisningen, men bevares i født-klausulen.
  const personer = [
    { id: 852, visning_navn: 'Beke', visning_efternavn: 'Ahlefeldt-Laurvig', koen: 'kvinde' },
    { id: 900, visning_navn: 'En Lensgreve', visning_efternavn: 'Reventlow', koen: 'mand' },
  ];
  const adelsTitelFakta = [
    { subjekt_id: 852, vaerdi_tekst: 'Komtesse' },
    { subjekt_id: 900, vaerdi_tekst: 'Lensgreve' },
  ];
  const aegtefaelleIdById = new Map([['852', '900'], ['900', '852']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['852']).toEqual({ navn: 'Beke', titel: 'Lensgrevinde', efternavn: 'Reventlow', fodt: 'komtesse Ahlefeldt-Laurvig', tilgiftet: true });
  expect(formatAndetNavn(r['852'], 'fallback')).toBe('Lensgrevinde Beke Reventlow, født komtesse Ahlefeldt-Laurvig');
});

test('mapPresensNavneDele: gift-ind kvinde UDEN registreret pigenavn — efternavnet vises stadig i begge formater', () => {
  // Reviewfund (whole-branch-review 2026-07-24): tilgiftet-flaget er UAFHÆNGIGT af fodt — en gift-ind
  // kvinde uden eget registreret efternavn får ingen født-klausul (intet at vise), men skal STADIG
  // have ægtefællens efternavn med i "øvrige rækker"-formatet, ligesom hovedrække-formatet allerede
  // gjorde ubetinget. Før fixet var gaten på `fodt`s tilstedeværelse, så dette tilfælde tabte
  // efternavnet i formatAndetNavn alene — de to formater var uenige om samme person.
  const personer = [
    { id: 811, visning_navn: 'Hedwig', visning_efternavn: null, koen: 'kvinde' },
    { id: 380, visning_navn: 'Henning Lothar Gerd', visning_efternavn: 'Reventlow', koen: 'mand' },
  ];
  const adelsTitelFakta = [{ subjekt_id: 380, vaerdi_tekst: 'Lensgreve' }];
  const aegtefaelleIdById = new Map([['811', '380'], ['380', '811']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['811']).toEqual({ navn: 'Hedwig', titel: 'Lensgrevinde', efternavn: 'Reventlow', tilgiftet: true });
  expect(r['811'].fodt).toBeUndefined();
  expect(formatAnkerNavn(r['811'], 'fallback')).toBe('Hedwig lensgrevinde Reventlow');
  expect(formatAndetNavn(r['811'], 'fallback')).toBe('Lensgrevinde Hedwig Reventlow');
});

test('mapPresensNavneDele: ægtefællen har slet ingen adelstitel-fakta — ingen tilgift-override', () => {
  const personer = [
    { id: 1, visning_navn: 'Anni', visning_efternavn: null, koen: 'kvinde' },
    { id: 2, visning_navn: 'Manden', visning_efternavn: 'Reventlow', koen: 'mand' },
  ];
  const adelsTitelFakta: { subjekt_id: number; vaerdi_tekst: string }[] = []; // manden har ingen adelstitel
  const aegtefaelleIdById = new Map([['1', '2'], ['2', '1']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['1']).toEqual({ navn: 'Anni', titel: '', efternavn: '' });
  expect(r['1'].fodt).toBeUndefined();
});

test('mapPresensNavneDele: ægtefællens adelstitel er ikke kønsbøjelig (allerede en kvindeform, fx datafejl) — ingen tilgift-override', () => {
  // Adskilt fra testen ovenfor: her HAR "manden" en adelstitel-fakta (består erAdelsTitel), men
  // den findes ikke i FEMININ_TITEL (kun mands-formerne er nøgler der) — feminiserTitel afviser
  // den, og overrideet skal derfor udeblive ligesom ved manglende titel-fakta.
  const personer = [
    { id: 1, visning_navn: 'Anni', visning_efternavn: null, koen: 'kvinde' },
    { id: 2, visning_navn: 'Manden', visning_efternavn: 'Reventlow', koen: 'mand' },
  ];
  const adelsTitelFakta = [{ subjekt_id: 2, vaerdi_tekst: 'Grevinde' }]; // datafejl: allerede en kvindeform
  const aegtefaelleIdById = new Map([['1', '2'], ['2', '1']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['1']).toEqual({ navn: 'Anni', titel: '', efternavn: '' });
  expect(r['1'].fodt).toBeUndefined();
});

test('mapPresensNavneDele: ægtefællen har gyldig titel men mangler efternavn — ingen tilgift-override', () => {
  const personer = [
    { id: 1, visning_navn: 'Anni', visning_efternavn: null, koen: 'kvinde' },
    { id: 2, visning_navn: 'Manden', visning_efternavn: null, koen: 'mand' }, // intet efternavn registreret
  ];
  const adelsTitelFakta = [{ subjekt_id: 2, vaerdi_tekst: 'Greve' }];
  const aegtefaelleIdById = new Map([['1', '2'], ['2', '1']]);
  const r = mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
  expect(r['1']).toEqual({ navn: 'Anni', titel: '', efternavn: '' });
  expect(r['1'].fodt).toBeUndefined();
});

test('mapPresensNavneDele: mand uden ægtefælle-opslag rammes ikke af kvinde-mekanismen', () => {
  const personer = [{ id: 380, visning_navn: 'Henning Lothar Gerd', visning_efternavn: 'Reventlow', koen: 'mand' }];
  const adelsTitelFakta = [{ subjekt_id: 380, vaerdi_tekst: 'Lensgreve' }];
  const r = mapPresensNavneDele(personer, adelsTitelFakta, new Map([['811', '380']]));
  expect(r['380']).toEqual({ navn: 'Henning Lothar Gerd', titel: 'Lensgreve', efternavn: 'Reventlow' });
});

test('formatAnkerNavn/formatAndetNavn: født-klausul vedhæftes uændret uanset format', () => {
  const dele = { navn: 'Hedwig', titel: 'Lensgrevinde', efternavn: 'Reventlow', fodt: 'Mundhenke', tilgiftet: true };
  expect(formatAnkerNavn(dele, 'fallback')).toBe('Hedwig lensgrevinde Reventlow, født Mundhenke');
  expect(formatAndetNavn(dele, 'fallback')).toBe('Lensgrevinde Hedwig Reventlow, født Mundhenke');
});
