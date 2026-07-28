import { buildAux } from '../buildAux';
import type { RawExtId, RawLineage, RawSource } from '../types';

// --- Task 1: flade entitets-lister (2C-1) ---

const base = { extIds: [], sources: [], relations: [], estates: [], orgs: [], media: [], lineage: [], arms: [] };

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

describe('buildAux — linje-stamfader = laveste nr (§9.2 kritisk path)', () => {
  const extIds: RawExtId[] = [
    { person_id: 10, source_id: 1, linje: 'I', nr: 5 },
    { person_id: 11, source_id: 1, linje: 'I', nr: 2 }, // laveste i I → stamfader
    { person_id: 12, source_id: 1, linje: 'I', nr: 9 },
    { person_id: 20, source_id: 1, linje: 'V', nr: 3 },
    { person_id: 21, source_id: 1, linje: 'V', nr: 1 }, // laveste i V → stamfader
  ];
  const aux = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [] });

  test('linjeList har én entry pr. linje, sorteret', () => {
    expect(aux.linjeList.map((l) => l.linje)).toEqual(['I', 'V']);
  });

  test('headId peger på personen med laveste nr', () => {
    const I = aux.linjeList.find((l) => l.linje === 'I');
    const V = aux.linjeList.find((l) => l.linje === 'V');
    expect(I?.headId).toBe('11');
    expect(V?.headId).toBe('21');
  });

  test('count tæller medlemmer pr. linje', () => {
    expect(aux.linjeList.find((l) => l.linje === 'I')?.count).toBe(3);
  });

  test('linjeByPerson mapper person → linje(r) (array)', () => {
    expect(aux.linjeByPerson['11']).toEqual(['I']);
    expect(aux.linjeByPerson['21']).toEqual(['V']);
  });
});

describe('buildAux — samme_som-kanonisering (Task 5)', () => {
  // III58 (linje III) + V1 (linje V) folder til V1 → V1 hører til begge linjer, og alle person-
  // id-bærende strukturer peger på V1.
  const canonicalIdById = { III58: 'V1' };
  const extIds: RawExtId[] = [
    { person_id: 'III58', source_id: 1, linje: 'III', nr: 58 },
    { person_id: 'V1', source_id: 1, linje: 'V', nr: 1 },
  ];

  test('linjeByPerson samler flere linjer for collapsed person', () => {
    const aux = buildAux({ ...base, extIds }, canonicalIdById);
    expect(aux.linjeByPerson['V1']?.sort()).toEqual(['III', 'V']);
    expect(aux.linjeByPerson['III58']).toBeUndefined(); // alias-nøgle findes ikke
  });

  test('linjeList.headId kanoniseres (head var alias III58)', () => {
    const aux = buildAux({ ...base, extIds }, canonicalIdById);
    expect(aux.linjeList.find((l) => l.linje === 'III')?.headId).toBe('V1');
  });

  test('ownersByEstate.personId + sourcesBy-nøgle kanoniseres', () => {
    const aux = buildAux(
      {
        ...base,
        extIds,
        estates: [{ id: 1, navn: 'Gods', slags: null }] as never,
        relations: [
          { subjekt_type: 'person', subjekt_id: 'III58', objekt_type: 'estate', objekt_id: 1, rolle: 'ejer', periode_raw: null },
        ] as never,
      },
      canonicalIdById,
    );
    expect(aux.ownersByEstate['1']?.[0].personId).toBe('V1');
    expect(aux.sourcesBy['V1']).toBeDefined();
    expect(aux.sourcesBy['III58']).toBeUndefined();
  });
});

describe('buildAux — linje-navne fra lineage', () => {
  const extIds: RawExtId[] = [
    { person_id: 10, source_id: 1, linje: 'I', nr: 1 },
    { person_id: 20, source_id: 1, linje: 'V', nr: 1 },
    { person_id: 30, source_id: 1, linje: 'III', nr: 1 }, // ingen lineage-række → fallback
  ];
  const lineage: RawLineage[] = [
    { source_id: 1, kode: 'I', navn: 'Den holstenske linje' },
    { source_id: 1, kode: 'V', navn: 'Den grevelige linje af 1673' },
  ];
  const aux = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [], lineage });

  test('linjeNavn mapper kode → navn', () => {
    expect(aux.linjeNavn['I']).toBe('Den holstenske linje');
    expect(aux.linjeNavn['V']).toBe('Den grevelige linje af 1673');
  });

  test('linjeList bærer navn; manglende lineage → navn null (UI falder tilbage til kode)', () => {
    expect(aux.linjeList.find((l) => l.linje === 'I')?.navn).toBe('Den holstenske linje');
    expect(aux.linjeList.find((l) => l.linje === 'III')?.navn).toBeNull();
  });

  test('uden lineage-arg → alle navne null (bagudkompatibel)', () => {
    const a2 = buildAux({ extIds, sources: [], relations: [], estates: [], orgs: [], media: [] });
    expect(a2.linjeNavn).toEqual({});
    expect(a2.linjeList.every((l) => l.navn === null)).toBe(true);
  });
});

describe('buildAux — kilder ("Linje X, nr. N" + trykt værk)', () => {
  const extIds: RawExtId[] = [{ person_id: 7, source_id: 1, linje: 'II', nr: 4 }];
  const sources: RawSource[] = [
    { id: 1, slags: 'bog', titel: 'Danmarks Adels Aarbog', udgave: null, ekstern: null },
  ];
  const aux = buildAux({ extIds, sources, relations: [], estates: [], orgs: [], media: [] });

  test('kilde-reference komponeres', () => {
    expect(aux.sourcesBy['7']).toEqual([{ ref: 'Linje II, nr. 4', work: 'Danmarks Adels Aarbog' }]);
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

test('buildAux: bog-nummeret vinder — citationen fortrænger ikke "Linje X, nr. N"', () => {
  const aux = buildAux({
    ...base,
    sources: [DAA_1939] as never,
    extIds: [{ person_id: 7, source_id: 3, linje: 'II', nr: 4 }] as never,
    citationKilder: [{ person_id: '7', work: 'DAA 1939', side: '12' }],
  });
  expect(aux.sourcesBy['7']).toEqual([{ work: 'DAA 1939', ref: 'Linje II, nr. 4' }]);
});

test('buildAux: uden citationKilder er adfærden uændret (bagudkompat)', () => {
  const aux = buildAux({
    ...base,
    sources: [DAA_1939] as never,
    extIds: [{ person_id: 7, source_id: 3, linje: 'II', nr: 4 }] as never,
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
