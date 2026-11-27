import { buildAux } from '../buildAux';

// --- Task 1: flade entitets-lister (2C-1) ---

const base = { sources: [], relations: [], estates: [], orgs: [], media: [], arms: [] };

test('buildAux: kildeListe fra sources (felt-map + sort)', () => {
  const aux = buildAux({ ...base, sources: [
    { id: 2, slags: 'kirkebog', titel: 'Øster', udgave: '1700', ekstern: null },
    { id: 1, slags: 'bog', titel: 'Aarbog', udgave: 'DAA 2018', ekstern: null },
  ] as never });
  expect(aux.kildeListe.map((k) => k.titel)).toEqual(['Aarbog', 'Øster']); // dansk sort, Ø sidst
  expect(aux.kildeListe[0]).toEqual({ id: '1', titel: 'Aarbog', slags: 'bog', udgave: 'DAA 2018' });
});

test('buildAux: vaabenListe fra arms (null-fallback + dansk-sorteret)', () => {
  const aux = buildAux({ ...base, arms: [
    { id: 5, blasonering: null, note: 'x' },
    { id: 6, blasonering: 'Ørn', note: '' },
    { id: 7, blasonering: 'Bjørn', note: '' },
  ] as never });
  expect(aux.vaabenListe[0]).toEqual({ id: '5', blasonering: '', note: 'x' }); // tom streng = mindst
  expect(aux.vaabenListe.map((v) => v.blasonering)).toEqual(['', 'Bjørn', 'Ørn']); // dansk sort: Ø sidst
});

test('buildAux: godsListe komplet (inkl. ejerløse) m. ownerCount', () => {
  const aux = buildAux({ ...base,
    estates: [{ id: 1, navn: 'Brahetrolleborg', slags: null }, { id: 2, navn: 'Ejerløs', slags: null }] as never,
    relations: [{ subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null }] as never,
  });
  const brahe = aux.godsListe.find((g) => g.id === '1');
  const ejerloes = aux.godsListe.find((g) => g.id === '2');
  expect(brahe?.ownerCount).toBe(1);
  expect(ejerloes?.ownerCount).toBe(0); // ejerløs gods er MED
});

test('buildAux: estateList og estateById rummer alle godser, også ejerløse (som web)', () => {
  const aux = buildAux({ ...base,
    estates: [{ id: 1, navn: 'Brahetrolleborg', slags: 'gods' }, { id: 2, navn: 'Ejerløs', slags: null }] as never,
    relations: [{ subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '(1700-†)' }] as never,
  });
  expect(aux.estateList.map((e) => [e.id, e.ownerCount, e.ejerIds])).toEqual([['1', 1, ['9']], ['2', 0, []]]);
  expect(aux.estateById['2']).toEqual({ id: '2', navn: 'Ejerløs', slags: '', stedId: null });
  // Bogens periodetekst bevares til ejerrækken; period er uden parenteser som før.
  expect(aux.ownersByEstate['1']?.[0]).toMatchObject({ period: '1700-†', periodeRaw: '(1700-†)' });
});

test('buildAux: orgListe + medieListe felt-map', () => {
  const aux = buildAux({ ...base,
    orgs: [{ id: 1, navn: 'Hæren', slags: 'myndighed' }] as never,
    media: [{ id: 1, slags: 'foto', titel: 'Portræt', kunstner: 'NN', datering: '1900' }] as never });
  expect(aux.orgListe[0]).toEqual({ id: '1', navn: 'Hæren', slags: 'myndighed' });
  expect(aux.medieListe[0]).toMatchObject({ id: '1', titel: 'Portræt', slags: 'foto', kunstner: 'NN', datering: '1900' });
});

test('buildAux: medieListe-status, anvendelsestal, køer og kø-tællere', () => {
  const aux = buildAux({
    ...base,
    media: [
      { id: 1, titel: 'Rettighedsløst', upload_status: 'klar', maa_publiceres: false, rettigheder_status: 'ukendt' },
      { id: 2, titel: 'Strandet', upload_status: 'fejlet', maa_publiceres: false, rettigheder_status: 'ukendt' },
      { id: 3, titel: 'Brugt', upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'public_domain' },
      { id: 4, titel: 'Papirkurv', upload_status: 'fjernet', maa_publiceres: true, rettigheder_status: 'public_domain' },
    ] as never,
    relations: [
      { subjekt_type: 'person', subjekt_id: 7, objekt_type: 'media', objekt_id: 3, rolle: 'afbildet', periode_raw: null },
    ] as never,
    mediaRelations: [
      { subjekt_type: 'media', subjekt_id: 3, objekt_type: 'estate', objekt_id: 9, rolle: 'afbildet', periode_raw: null },
    ] as never,
    mediaMentions: [
      { kilde_type: 'narrative', kilde_id: 40, maal_type: 'media', maal_id: 3 },
    ] as never,
  });

  expect(aux.medieListe.find((m) => m.id === '1')).toMatchObject({
    uploadStatus: 'klar', maaPubliceres: false, rettighederStatus: 'ukendt',
    antalAfbildet: 0, antalMentions: 0, koeer: ['rettigheder', 'loese'],
  });
  expect(aux.medieListe.find((m) => m.id === '3')).toMatchObject({
    antalAfbildet: 2, antalMentions: 1, koeer: [],
  });
  expect(aux.medieKoeTaellere).toEqual({ rettigheder: 1, loese: 1, strandede: 1, papirkurv: 1, dubletter: 0 });
});

test('buildAux: dubletkandidater bruger samme 3-feltsnøgle og opdaterer tælleren', () => {
  const aux = buildAux({
    ...base,
    media: [
      { id: 1, titel: 'A', upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'public_domain',
        byte_size: 100, bredde: 10, hoejde: 20 },
      { id: 2, titel: 'B', upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'public_domain',
        byte_size: 100, bredde: 10, hoejde: 20 },
      { id: 3, titel: 'Kladde', upload_status: 'kladde', maa_publiceres: false, rettigheder_status: 'ukendt',
        byte_size: 100, bredde: 10, hoejde: 20 },
    ] as never,
  });

  expect(aux.medieListe.filter((m) => m.koeer.includes('dubletter')).map((m) => m.id)).toEqual(['1', '2']);
  expect(aux.medieKoeTaellere.dubletter).toBe(2);
});

test('buildAux: mediaBy kobles via relation person→media (afbildet), ikke m.person_id', () => {
  const media = [
    { id: 1, slags: 'foto', titel: 'Portræt af 10' },
    { id: 2, slags: 'segl', titel: 'Løst objekt uden afbildet-person' },
  ] as never;
  const relations = [
    { subjekt_type: 'person', subjekt_id: 10, objekt_type: 'media', objekt_id: 1, rolle: 'afbildet', periode_raw: null },
    // ikke-afbildet relation til media → skal IKKE tælle som portræt/materiale
    { subjekt_type: 'person', subjekt_id: 10, objekt_type: 'media', objekt_id: 2, rolle: 'skabt_af', periode_raw: null },
  ] as never;
  const aux = buildAux({ ...base, media, relations });
  expect(aux.mediaBy['10']?.map((m) => m.id)).toEqual([1]); // kun afbildet, i relations-rækkefølge
  expect(aux.mediaBy['2']).toBeUndefined(); // media-id er ikke en person-nøgle (den gamle bug)
});

test('buildAux: mediaBy kanoniserer person-id (samme_som-collapse)', () => {
  const media = [{ id: 1, slags: 'maleri', titel: 'P' }] as never;
  const relations = [
    { subjekt_type: 'person', subjekt_id: 58, objekt_type: 'media', objekt_id: 1, rolle: 'afbildet', periode_raw: null },
  ] as never;
  const aux = buildAux({ ...base, media, relations }, { '58': '1' }); // 58 foldet til kanonisk 1
  expect(aux.mediaBy['1']?.map((m) => m.id)).toEqual([1]);
  expect(aux.mediaBy['58']).toBeUndefined();
});

describe('buildAux — samme_som-kanonisering (Task 5)', () => {
  test('ownersByEstate.personId kanoniseres', () => {
    const aux = buildAux(
      {
        ...base,
        estates: [{ id: 1, navn: 'Gods', slags: null }] as never,
        relations: [
          { subjekt_type: 'person', subjekt_id: 'III58', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null },
        ] as never,
      },
      { III58: 'V1' },
    );
    expect(aux.ownersByEstate['1']?.[0].personId).toBe('V1');
  });
});

// --- Kilde-faldback for personer uden bog-nummer (ægtefæller) ---

const DAA_1939 = { id: 3, slags: 'DAA-udgave', titel: 'DAA 1939', udgave: 'DAA 1939', ekstern: null };

test('buildAux: ægtefælle uden person_external_id får kilde fra citationerne', () => {
  const aux = buildAux({
    ...base,
    sources: [DAA_1939] as never,
    citationKilder: [{ person_id: '1690', work: 'DAA 1939', side: '578' }],
  });
  expect(aux.sourcesBy['1690']).toEqual([{ work: 'DAA 1939', ref: 's. 578' }]);
});

// Bogens opslag kommer færdigbygget fra udgaveLag (buildSources); linjerne testes i udgaveLag.test.ts.
const BOG_7 = { '7': [{ work: 'DAA 1939', ref: 'Linje II, nr. 4' }] };

test('buildAux: bog-nummeret vinder — citationen fortrænger ikke "Linje X, nr. N"', () => {
  const aux = buildAux({
    ...base,
    sources: [DAA_1939] as never,
    bogKilder: BOG_7,
    citationKilder: [{ person_id: '7', work: 'DAA 1939', side: '12' }],
  });
  expect(aux.sourcesBy['7']).toEqual([{ work: 'DAA 1939', ref: 'Linje II, nr. 4' }]);
});

test('buildAux: uden citationKilder er adfærden uændret (bagudkompat)', () => {
  const aux = buildAux({
    ...base,
    sources: [DAA_1939] as never,
    bogKilder: BOG_7,
  });
  expect(aux.sourcesBy['7']).toEqual([{ work: 'DAA 1939', ref: 'Linje II, nr. 4' }]);
});

test('buildAux: citation-nøglen kanoniseres som resten af aux', () => {
  const aux = buildAux(
    { ...base, sources: [DAA_1939] as never, citationKilder: [{ person_id: '1690', work: 'DAA 1939', side: '578' }] },
    { '1690': '841' },
  );
  expect(aux.sourcesBy['841']).toEqual([{ work: 'DAA 1939', ref: 's. 578' }]);
  expect(aux.sourcesBy['1690']).toBeUndefined();
});

test('buildAux: ownerCount tæller personer, ikke perioder (ejer med to perioder = 1)', () => {
  const aux = buildAux({ ...base,
    estates: [{ id: 1, navn: 'Gods', slags: null }] as never,
    relations: [
      { subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '1600-1620' },
      { subjekt_type: 'person', subjekt_id: 9, objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: '1640-1660' },
    ] as never,
  });
  expect(aux.godsListe.find((g) => g.id === '1')?.ownerCount).toBe(1);
  expect(aux.estateList.find((g) => g.id === '1')?.ownerCount).toBe(1);
  expect(aux.estateList.find((g) => g.id === '1')?.ejerIds).toEqual(['9']);
});

test('buildAux: mediaByObjekt samler billeder pr. gods/våben fra media→objekt-relationerne, ét medie én gang', () => {
  const aux = buildAux({ ...base,
    media: [{ id: 1, titel: 'Gård' }, { id: 2, titel: 'Våben' }] as never,
    mediaRelations: [
      { subjekt_type: 'media', subjekt_id: 1, objekt_type: 'estate', objekt_id: 9, rolle: 'afbildet', periode_raw: null },
      { subjekt_type: 'media', subjekt_id: 1, objekt_type: 'estate', objekt_id: 9, rolle: 'afbildet', periode_raw: null },
      { subjekt_type: 'media', subjekt_id: 2, objekt_type: 'coat_of_arms', objekt_id: 3, rolle: 'afbildet', periode_raw: null },
      { subjekt_type: 'media', subjekt_id: 404, objekt_type: 'estate', objekt_id: 9, rolle: 'afbildet', periode_raw: null }, // skjult/slettet
    ] as never,
  });
  expect(aux.mediaByObjekt['estate:9']?.map((m) => m.id)).toEqual([1]);
  expect(aux.mediaByObjekt['coat_of_arms:3']?.map((m) => m.id)).toEqual([2]);
});

test('buildAux: vaaben i id-orden (våbensidens hovedvåben er det første), vaabenListe stadig dansk-sorteret', () => {
  const aux = buildAux({ ...base, arms: [
    { id: 7, blasonering: 'Bjørn', note: '' }, { id: 5, blasonering: 'Ørn', note: 'hoved' },
  ] as never });
  expect(aux.vaaben.map((v) => v.id)).toEqual(['5', '7']);
  expect(aux.vaabenListe.map((v) => v.id)).toEqual(['7', '5']);
});
