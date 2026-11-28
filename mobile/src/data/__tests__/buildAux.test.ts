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
  expect(ejerloes?.ownerCount).toBe(0); // ejerløs gods er MED (modsat estateList)
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
});

describe('buildAux: sammenlagte godser og hører under (#471)', () => {
  const ejer = (id: number, gods: number) => ({ subjekt_type: 'person', subjekt_id: id, objekt_type: 'estate', objekt_id: gods, rolle: 'ejer', periode_raw: null });
  const gr = (s: number, o: number, rolle: string, periode: string | null = null) => ({ subjekt_type: 'estate', subjekt_id: s, objekt_type: 'estate', objekt_id: o, rolle, periode_raw: periode });
  const input = {
    ...base,
    estates: [
      { id: 5, navn: 'Gods fem', slags: 'gård' }, { id: 405, navn: 'Gods fem (dublet)', slags: null },
      { id: 7, navn: 'Grevskabet', slags: 'grevskab' },
    ] as never,
    relations: [ejer(1, 5), ejer(2, 405), ejer(3, 7)] as never,
  };
  const medRel = { ...input, godsRelationer: [gr(405, 5, 'sammenlagt_i'), gr(5, 7, 'hører_under', '1700-1800')] as never };

  test('sammenlagt række skjules i lister og er alias til den overlevende', () => {
    const aux = buildAux(medRel);
    expect(aux.estateList.map((g) => g.id).sort()).toEqual(['5', '7']);
    expect(aux.godsListe.map((g) => g.id).sort()).toEqual(['5', '7']);
    expect(aux.estateById['405'].id).toBe('5');
    expect(aux.estateById['405'].navn).toBe('Gods fem');
  });
  test('art, hører under og omfattede', () => {
    const aux = buildAux(medRel);
    expect(aux.estateById['5'].art).toBe('Gård');
    expect(aux.estateById['5'].hoererUnder).toEqual([{ id: '7', navn: 'Grevskabet', periode: '1700-1800' }]);
    expect(aux.estateById['7'].art).toBe('Grevskab');
    expect(aux.estateById['7'].omfattede).toEqual([{ id: '5', navn: 'Gods fem' }]);
  });
  test.each([['udeladt', undefined], ['tom', []]])('uden gods-relationer (%s) er alt som før #471', (_n, rel) => {
    const aux = buildAux({ ...input, godsRelationer: rel as never });
    expect(aux.estateList.map((g) => [g.id, g.navn])).toEqual([['5', 'Gods fem'], ['405', 'Gods fem (dublet)'], ['7', 'Grevskabet']]);
    expect(aux.godsListe.map((g) => [g.id, g.navn, g.slags])).toEqual([['5', 'Gods fem', 'gård'], ['405', 'Gods fem (dublet)', ''], ['7', 'Grevskabet', 'grevskab']]);
    expect(Object.keys(aux.estateById).sort()).toEqual(['405', '5', '7']);
    expect(aux.estateById['405'].id).toBe('405');
    expect(aux.estateById['405'].navn).toBe('Gods fem (dublet)');
    expect(aux.estateById['5'].hoererUnder).toEqual([]);
    expect(aux.estateById['7'].omfattede).toEqual([]);
  });
  test('kreds i sammenlagt_i: begge rækker forbliver synlige og er deres eget alias', () => {
    const aux = buildAux({ ...input, godsRelationer: [gr(5, 405, 'sammenlagt_i'), gr(405, 5, 'sammenlagt_i')] as never });
    expect(aux.estateList.map((g) => g.id).sort()).toEqual(['405', '5', '7']);
    expect(aux.godsListe.map((g) => g.id).sort()).toEqual(['405', '5', '7']);
    expect(aux.estateById['5'].id).toBe('5');
    expect(aux.estateById['405'].id).toBe('405');
  });
});

describe('buildAux: rækker markeret »ikke et gods« (#471)', () => {
  const ejer = (id: number, gods: number) => ({ subjekt_type: 'person', subjekt_id: id, objekt_type: 'estate', objekt_id: gods, rolle: 'ejer', periode_raw: '1399' });
  const input = {
    ...base,
    estates: [
      { id: 5, navn: 'Gods fem', slags: 'gård' }, { id: 9, navn: 'Forlening af Preetz Kloster (1399)', slags: 'ikke_gods' },
      { id: 10, navn: 'Skænket, ikke i eje', slags: 'ikke_gods' },
    ] as never,
    relations: [ejer(1, 5), ejer(1, 9)] as never,
  };
  test('skjules i oversigt, godsliste og personens besiddelser, men ejerforholdet bevares', () => {
    const aux = buildAux(input);
    expect(aux.estateList.map((g) => g.id)).toEqual(['5']);
    expect(aux.godsListe.map((g) => g.id)).toEqual(['5']);
    expect(aux.estatesBy['1'].map((e) => e.id)).toEqual(['5']);
    expect(aux.ownersByEstate['9']).toHaveLength(1);
  });
  test('direkte link virker, også uden ejere, og viser artsetiketten »Ikke et gods«', () => {
    const aux = buildAux(input);
    expect(aux.estateById['9'].art).toBe('Ikke et gods');
    expect(aux.estateById['10'].navn).toBe('Skænket, ikke i eje');
    expect(aux.estateById['10'].art).toBe('Ikke et gods');
  });
});
