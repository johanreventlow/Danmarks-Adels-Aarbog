import { describe, it, expect } from 'vitest';
import {
  buildTidslinje,
  formatMedieAlder,
  fetchKandidatDetalje,
  klassificerMedie,
  mapFamilieRows,
  mapHaendelser,
  mapMediaAnvendelse,
  mapMediaBibliotekRows,
  mapPersonMediaRows,
  mapUdrensPreview,
  mediaAnvendelseQuerySpecs,
  mediaBibliotekQuerySpecs,
  mapStories,
  storyPrefillFraPost,
} from '../redaktionRead';
import type { Model } from '../types';

describe('fetchKandidatDetalje', () => {
  it('komponerer de eksisterende lazy person-fetches til en samlet detalje', async () => {
    const evidence = { felter: {}, koen: 'mand' };
    const narrativer = [{ id: 1, sourceId: 3, sourceTitel: 'DAA', udgave: '1939', side: '12', tekst: 'Tekst', privat: false }];
    const familie = { somPartner: [], somBarn: [] };
    const relationer = [{ relationId: 7, art: 'gods' as const, objektType: 'estate', objektId: '9', navn: 'Frisenvold', rolle: 'ejer', periode: '1700' }];
    const loaders = {
      evidence: vi.fn().mockResolvedValue(evidence),
      narrativer: vi.fn().mockResolvedValue(narrativer),
      familie: vi.fn().mockResolvedValue(familie),
      relationer: vi.fn().mockResolvedValue(relationer),
    };

    await expect(fetchKandidatDetalje('42', loaders)).resolves.toEqual({
      evidence, narrativer, familie, relationer,
    });
    expect(loaders.evidence).toHaveBeenCalledWith('42');
    expect(loaders.narrativer).toHaveBeenCalledWith('person', 42);
    expect(loaders.familie).toHaveBeenCalledWith('42');
    expect(loaders.relationer).toHaveBeenCalledWith('42');
  });
});

describe('hændelses-tidslinje', () => {
  it('mapper også skjulte og fletter fact-kobling uden dublet, NULL sidst', () => {
    const hs = mapHaendelser([
      { id: 1, klausul: 'Tidlig', kategori: 'rejse', date_min: '1500-01-01', date_max: '1500-12-31', date_qualifier: null, date_raw: '1500', feed_status: 'skjult', narrative_id: 1, span_start: 0, span_laengde: 6, fact_id: null, relation_id: null, narrative: { side: '2', source: { id: 5, titel: 'DAA', udgave: null } } },
      { id: 2, klausul: 'Født her', kategori: 'familie', date_min: '1600-01-01', date_max: '1600-12-31', date_qualifier: null, date_raw: '1600', feed_status: 'interessant', narrative_id: 1, span_start: 8, span_laengde: 8, fact_id: 7, relation_id: null, narrative: null },
      { id: 3, klausul: 'Udateret', kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null, feed_status: 'kandidat', narrative_id: 1, span_start: null, span_laengde: null, fact_id: null, relation_id: null, narrative: null },
    ] as never);
    expect(hs[0]).toMatchObject({ feedStatus: 'skjult', sourceId: 5, sourceTitel: 'DAA', side: '2' });
    const evidence = { koen: null, felter: { foedt: [{ felt: 'foedt', faktatype: 'fødsel', factId: 7,
      konklusionAssertionId: 70, uenig: false, oplysninger: [{ assertionId: 70, vaerdi: '1600', erKonklusion: true,
        dato: { min: '1600-01-01', max: '1600-12-31', qualifier: null, raw: '1600' }, kilder: [] }] }] } };
    const out = buildTidslinje(hs, evidence);
    expect(out.map((p) => p.id)).toEqual(['h:1', 'f:7', 'h:3']);
    expect(out[1]).toMatchObject({ art: 'rygrad', klausul: 'Født her', factId: 7 });
  });
});

describe('stories i redaktionen (fase 3)', () => {
  it('mapStories medtager alle statusser, NULL-felter og sorterer kilder på link-id', () => {
    const rows = [
      { id: 9, titel: 'Klar', tekst: 'Tekst', date_min: '1671-01-01', date_max: '1671-12-31',
        date_qualifier: 'about', date_raw: 'ca. 1671', status: 'klar', publiceret_dato: null,
        privat: false, haendelse_id: 12, fact_id: null, relation_id: null, historical_event_id: null,
        story_kilde: [
          { id: 7, source_id: 5, side: null, source: { titel: null, udgave: 'DAA 1939' } },
          { id: 3, source_id: 2, side: '112', source: { titel: 'DAA', udgave: null } },
        ] },
      { id: 10, titel: null, tekst: 'Arkiveret', date_min: null, date_max: null,
        date_qualifier: null, date_raw: null, status: 'arkiveret', publiceret_dato: null,
        privat: null, haendelse_id: null, fact_id: null, relation_id: null,
        historical_event_id: null, story_kilde: null },
    ];
    const out = mapStories(rows as never);
    expect(out.map((s) => s.status)).toEqual(['klar', 'arkiveret']);
    expect(out[0]).toMatchObject({ id: 9, haendelseId: 12,
      dato: { min: '1671-01-01', raw: 'ca. 1671' },
      kilder: [{ sourceId: 2, side: '112', sourceTitel: 'DAA' },
        { sourceId: 5, side: null, sourceTitel: 'DAA 1939' }] });
    expect(out[1]).toMatchObject({ titel: null, privat: false, haendelseId: null, kilder: [] });
  });

  it('storyPrefillFraPost kopierer klausul, dato, hændelsesanker og kilde med side', () => {
    expect(storyPrefillFraPost({ art: 'haendelse', id: 'h:12', haendelseId: 12,
      klausul: 'Han drog til Norge.', kategori: 'rejse',
      dato: { min: '1671-01-01', max: '1671-12-31', qualifier: 'about', raw: 'ca. 1671' },
      sourceId: 2, side: '112' })).toEqual({
        tekst: 'Han drog til Norge.', haendelseId: 12,
        dateMin: '1671-01-01', dateMax: '1671-12-31',
        dateQualifier: 'about', dateRaw: 'ca. 1671', kilder: [{ sourceId: 2, side: '112' }],
      });
  });

  it('storyPrefillFraPost uden sourceId giver tom kildeliste', () => {
    expect(storyPrefillFraPost({ art: 'rygrad', id: 'f:3', factId: 3,
      klausul: 'Født 1671', kategori: 'fødsel',
      dato: { min: null, max: null, qualifier: null, raw: '1671' } }).kilder).toEqual([]);
  });
});

// Minimal model-stub: kun byId.{name,years} bruges af mapFamilieRows (navnAf/aarAf).
const model = {
  byId: {
    '2': { name: 'Anna von Brockdorff', years: '1650–1700' },
    '3': { name: 'Conrad', years: '* 1675' },
    '4': { name: 'Detlef', years: '† 1712' },
  },
} as unknown as Model;

describe('mapFamilieRows — år på partnere og børn', () => {
  const families = [{ id: 10, type: 'vielse' }];
  const members = [
    { family_id: 10, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 2, rolle: 'partner', ordinal: null, konfidens: null },
    { family_id: 10, person_id: 3, rolle: 'barn', ordinal: 1, konfidens: 'sikker' },
    { family_id: 10, person_id: 4, rolle: 'barn', ordinal: 2, konfidens: null },
  ];

  it('partner får navn + aar fra model.byId[pid].years', () => {
    const fam = mapFamilieRows('1', families, members, model);
    expect(fam.somPartner).toHaveLength(1);
    expect(fam.somPartner[0].partnere).toEqual([
      { personId: '2', navn: 'Anna von Brockdorff', aar: '1650–1700', konfidens: null, ordinal: null },
    ]);
  });

  it('børn får aar (fødsels/dødsår) fra model, i visningsrækkefølge', () => {
    const fam = mapFamilieRows('1', families, members, model);
    expect(fam.somPartner[0].boern).toEqual([
      { personId: '3', navn: 'Conrad', aar: '* 1675', rolle: 'barn', konfidens: 'sikker', ordinal: 1 },
      { personId: '4', navn: 'Detlef', aar: '† 1712', rolle: 'barn', konfidens: null, ordinal: 2 },
    ]);
  });

  it('aar er tom streng når personen mangler i model (graceful)', () => {
    const fam = mapFamilieRows('1', families,
      [{ family_id: 10, person_id: 1, rolle: 'partner', ordinal: null, konfidens: null },
       { family_id: 10, person_id: 99, rolle: 'barn', ordinal: 1, konfidens: null }],
      model);
    expect(fam.somPartner[0].boern[0]).toMatchObject({ personId: '99', navn: '#99', aar: '' });
  });
});


describe('mapPersonMediaRows (mediehåndtering fase 1)', () => {
  const rich = {
    kunstner: 'Jens Juel', datering: 'ca. 1780', rettigheder_status: 'public_domain',
    mime_type: 'image/jpeg', byte_size: 1234, bredde: 800, hoejde: 1000, original_filnavn: 'portraet.jpg',
  };
  it('mapper alle filside-felter, url og relationId', () => {
    const rows = [{ id: 91, slags: 'foto', titel: 'Portræt', storage_path: 'redaktor/a.jpg',
                    upload_status: 'klar', maa_publiceres: true, created_at: '2026-07-20T08:00:00Z',
                    sha256: 'abc123', ...rich }];
    const signed = new Map([['redaktor/a.jpg', 'https://signed/a.jpg']]);
    const relByMediaId = new Map([['91', '501']]);
    expect(mapPersonMediaRows(rows, signed, relByMediaId)).toEqual([{
      id: '91', relationId: '501', slags: 'foto', titel: 'Portræt', storagePath: 'redaktor/a.jpg',
      kunstner: 'Jens Juel', datering: 'ca. 1780', rettighederStatus: 'public_domain',
      mimeType: 'image/jpeg', byteSize: 1234, bredde: 800, hoejde: 1000, originalFilnavn: 'portraet.jpg',
      uploadStatus: 'klar', maaPubliceres: true, createdAt: '2026-07-20T08:00:00Z',
      primaer: false, sha256: 'abc123', url: 'https://signed/a.jpg', thumbUrl: 'https://signed/a.jpg',
    }]);
  });
  it('manglende felter får fail-closed defaults', () => {
    const rows = [{ id: 92, slags: null, titel: null, kunstner: null, datering: null, storage_path: null,
      upload_status: null, maa_publiceres: null, rettigheder_status: null, mime_type: null,
      byte_size: null, bredde: null, hoejde: null, original_filnavn: null, created_at: null }];
    expect(mapPersonMediaRows(rows)).toEqual([{
      id: '92', relationId: '', slags: '', titel: null, storagePath: null, kunstner: null, datering: null,
      rettighederStatus: 'ukendt', mimeType: null, byteSize: null, bredde: null, hoejde: null,
      originalFilnavn: null, uploadStatus: 'kladde', maaPubliceres: false, createdAt: null,
      primaer: false, sha256: null,
      url: null, thumbUrl: null,
    }]);
  });
  it('thumb-variant bruges, og fjernet bevares til genopret', () => {
    const rows = [{ id: 93, slags: 'foto', titel: 'Fjernet', storage_path: 'large.jpg',
      upload_status: 'fjernet', maa_publiceres: true, ...rich }];
    const signed = new Map([['large.jpg', 'large-url'], ['thumb.jpg', 'thumb-url']]);
    const out = mapPersonMediaRows(rows, signed, new Map(), new Map([['93', 'thumb.jpg']]));
    expect(out[0]).toMatchObject({ id: '93', uploadStatus: 'fjernet', url: 'large-url', thumbUrl: 'thumb-url' });
  });
});

describe('klassificerMedie (mediehåndtering fase 2)', () => {
  const uploadStatuses = ['klar', 'kladde', 'fejlet', 'fjernet'] as const;
  const rettighederStatuses = ['ukendt', 'licenseret'] as const;

  for (const uploadStatus of uploadStatuses) {
    for (const rettighederStatus of rettighederStatuses) {
      for (const maaPubliceres of [false, true]) {
        for (const antalAfbildet of [0, 1]) {
          for (const antalMentions of [0, 1]) {
            it(`${uploadStatus}/${rettighederStatus}/public=${maaPubliceres}/afbildet=${antalAfbildet}/mentions=${antalMentions}`, () => {
              const expected = [];
              if (uploadStatus === 'klar' && (rettighederStatus === 'ukendt' || !maaPubliceres)) expected.push('rettigheder');
              if (uploadStatus === 'klar' && antalAfbildet === 0 && antalMentions === 0) expected.push('loese');
              if (uploadStatus === 'kladde' || uploadStatus === 'fejlet') expected.push('strandede');
              if (uploadStatus === 'fjernet') expected.push('papirkurv');
              expect(klassificerMedie({ uploadStatus, rettighederStatus, maaPubliceres }, antalAfbildet, antalMentions, false))
                .toEqual(expected);
            });
          }
        }
      }
    }
  }

  it('tillader flere køer samtidig', () => {
    expect(klassificerMedie({ uploadStatus: 'klar', rettighederStatus: 'ukendt', maaPubliceres: false }, 0, 0, false))
      .toEqual(['rettigheder', 'loese']);
  });

  it('tilføjer dubletter kun for klar og bevarer multi-kø', () => {
    expect(klassificerMedie(
      { uploadStatus: 'klar', rettighederStatus: 'ukendt', maaPubliceres: false }, 1, 0, true,
    )).toEqual(['rettigheder', 'dubletter']);
    expect(klassificerMedie(
      { uploadStatus: 'kladde', rettighederStatus: 'ukendt', maaPubliceres: false }, 0, 0, true,
    )).toEqual(['strandede']);
    expect(klassificerMedie(
      { uploadStatus: 'fjernet', rettighederStatus: 'ukendt', maaPubliceres: false }, 0, 0, true,
    )).toEqual(['papirkurv']);
  });
});

describe('formatMedieAlder', () => {
  const nu = new Date('2026-07-20T12:00:00.000Z');

  it.each([
    [null, 'ukendt alder'],
    ['', 'ukendt alder'],
    ['ikke-en-dato', 'ukendt alder'],
    ['2026-07-20T12:01:00.000Z', 'ukendt alder'],
    ['2026-07-20T11:00:01.000Z', 'under 1 time — muligvis i gang'],
    ['2026-07-20T11:00:00.000Z', '1 time'],
    ['2026-07-20T10:00:00.000Z', '2 timer'],
    ['2026-07-19T12:00:00.000Z', '1 dag'],
    ['2026-07-14T12:00:00.000Z', '6 dage'],
    ['2026-07-13T12:00:00.000Z', '1 uge'],
    ['2026-06-22T12:00:00.000Z', '4 uger'],
    ['2026-06-20T12:00:00.000Z', '1 måned'],
    ['2026-05-21T12:00:00.000Z', '2 måneder'],
  ])('formatterer %s deterministisk som %s', (createdAt, forventet) => {
    expect(formatMedieAlder(createdAt, nu)).toBe(forventet);
  });
});

describe('mapMediaBibliotekRows', () => {
  const media = [
    { id: 91, slags: 'foto', titel: 'Portræt', kunstner: 'Jens Juel', datering: '1780',
      storage_path: 'large-91.jpg', upload_status: 'klar', maa_publiceres: false,
      rettigheder_status: 'ukendt', mime_type: 'image/jpeg', byte_size: 100, bredde: 80,
      hoejde: 100, original_filnavn: 'portraet.jpg', created_at: '2026-07-20T08:00:00Z' },
    { id: 92, slags: 'scanning', titel: 'Løs scanning', kunstner: null, datering: null,
      storage_path: null, upload_status: 'klar', maa_publiceres: true,
      rettigheder_status: 'public_domain', mime_type: null, byte_size: null, bredde: null,
      hoejde: null, original_filnavn: null, created_at: null },
  ];

  it('joiner begge relationsretninger og tæller unikke mål samt mentions', () => {
    const out = mapMediaBibliotekRows(
      media,
      [
        { subjekt_id: 501, objekt_id: 91 },
        { subjekt_id: 501, objekt_id: 91 },
      ],
      [{ subjekt_id: 91, objekt_type: 'estate', objekt_id: 601 }],
      [{ maal_id: 91 }, { maal_id: 92 }, { maal_id: 91 }],
      new Map([['large-91.jpg', 'large-url'], ['thumb-91.jpg', 'thumb-url']]),
      new Map([['91', 'thumb-91.jpg']]),
    );
    expect(out[0]).toMatchObject({
      id: '91', antalAfbildet: 2, antalMentions: 2, koeer: ['rettigheder'],
      createdAt: '2026-07-20T08:00:00Z', url: 'large-url', thumbUrl: 'thumb-url',
    });
    expect(out[0]).not.toHaveProperty('relationId');
    expect(out[1]).toMatchObject({ id: '92', antalAfbildet: 0, antalMentions: 1, koeer: [], createdAt: null });
  });

  it('giver media uden relationer eller mentions 0/0 og klassificerer dem som løse', () => {
    const out = mapMediaBibliotekRows([media[1]], [], [], []);
    expect(out[0]).toMatchObject({ antalAfbildet: 0, antalMentions: 0, koeer: ['loese'] });
  });

  it('finder kun andre klare medier med samme komplette 3-feltsnøgle som mulige dubletter', () => {
    const basis = { slags: 'foto', titel: null, kunstner: null, datering: null, storage_path: null,
      maa_publiceres: true, rettigheder_status: 'public_domain', mime_type: 'image/jpeg',
      original_filnavn: null, created_at: null };
    const rows = [
      { ...basis, id: 1, upload_status: 'klar', byte_size: 100, bredde: 10, hoejde: 20 },
      { ...basis, id: 2, upload_status: 'klar', byte_size: 100, bredde: 10, hoejde: 20, mime_type: 'image/png' },
      { ...basis, id: 3, upload_status: 'klar', byte_size: 100, bredde: 10, hoejde: 20 },
      { ...basis, id: 4, upload_status: 'klar', byte_size: 200, bredde: 10, hoejde: 20 },
      { ...basis, id: 5, upload_status: 'klar', byte_size: 200, bredde: 10, hoejde: 20 },
      { ...basis, id: 6, upload_status: 'klar', byte_size: null, bredde: 10, hoejde: 20 },
      { ...basis, id: 12, upload_status: 'klar', byte_size: null, bredde: 10, hoejde: 20 },
      { ...basis, id: 13, upload_status: 'klar', byte_size: 500, bredde: null, hoejde: 20 },
      { ...basis, id: 14, upload_status: 'klar', byte_size: 500, bredde: null, hoejde: 20 },
      { ...basis, id: 15, upload_status: 'klar', byte_size: 600, bredde: 10, hoejde: null },
      { ...basis, id: 16, upload_status: 'klar', byte_size: 600, bredde: 10, hoejde: null },
      { ...basis, id: 7, upload_status: 'kladde', byte_size: 300, bredde: 30, hoejde: 40 },
      { ...basis, id: 8, upload_status: 'klar', byte_size: 300, bredde: 30, hoejde: 40 },
      { ...basis, id: 9, upload_status: 'fjernet', byte_size: 400, bredde: 40, hoejde: 50 },
      { ...basis, id: 10, upload_status: 'klar', byte_size: 400, bredde: 40, hoejde: 50 },
    ];
    const out = mapMediaBibliotekRows(rows, [], [], []);
    const dubletIds = out.filter((m) => m.koeer.includes('dubletter')).map((m) => m.id);
    expect(dubletIds).toEqual(['1', '2', '3', '4', '5']);
    expect(out.find((m) => m.id === '7')?.koeer).toContain('strandede');
  });

  it('kræver et andet media-id, ikke blot to rækker med samme id', () => {
    const row = { slags: 'foto', titel: null, kunstner: null, datering: null, storage_path: null,
      maa_publiceres: true, rettigheder_status: 'public_domain', mime_type: 'image/jpeg',
      original_filnavn: null, created_at: null, id: 11, upload_status: 'klar',
      byte_size: 500, bredde: 50, hoejde: 60 };
    expect(mapMediaBibliotekRows([row, row], [], [], []).every((m) => !m.koeer.includes('dubletter'))).toBe(true);
  });

  it('bevarer max bigint media- og målid gennem de faktiske rå bibliotek-shapes', () => {
    const max = '9223372036854775807';
    const row = { slags: 'foto', titel: null, kunstner: null, datering: null, storage_path: null,
      maa_publiceres: true, rettigheder_status: 'public_domain', mime_type: 'image/jpeg',
      original_filnavn: null, created_at: null, id: max, upload_status: 'klar',
      byte_size: 500, bredde: 50, hoejde: 60 };
    expect(mapMediaBibliotekRows(
      [row], [{ subjekt_id: max, objekt_id: max }], [], [{ maal_id: max }],
    )[0]).toMatchObject({ id: max, antalAfbildet: 1, antalMentions: 1 });
  });
});

describe('mapMediaAnvendelse', () => {
  it('mapper begge relationsretninger og opløser mention via narrativets subjekt', () => {
    const out = mapMediaAnvendelse({
      personRelationer: [{ id: 501, subjekt_id: 42, kvalifikator: { primaer: true } }],
      objektRelationer: [{ id: 502, objekt_type: 'estate', objekt_id: 7 }],
      mentions: [{ kilde_type: 'narrative', kilde_id: 301 }],
      narrativer: [{ id: 301, subjekt_type: 'person', subjekt_id: 42 }],
      navneBySubjekt: new Map([['person:42', 'Conrad Reventlow'], ['estate:7', 'Brahetrolleborg']]),
    });
    expect(out).toEqual({
      afbildet: [
        { type: 'person', id: '42', navn: 'Conrad Reventlow', relationId: '501', primaer: true },
        { type: 'estate', id: '7', navn: 'Brahetrolleborg', relationId: '502', primaer: false },
      ],
      mentions: [{ kildeType: 'narrative', kildeId: '301', subjektNavn: 'Conrad Reventlow' }],
    });
  });

  it('falder lukket tilbage ved ukendt mention-kilde eller subjekt', () => {
    const out = mapMediaAnvendelse({
      personRelationer: [], objektRelationer: [],
      mentions: [{ kilde_type: 'note', kilde_id: 99 }, { kilde_type: 'narrative', kilde_id: 302 }],
      narrativer: [{ id: 302, subjekt_type: 'lineage', subjekt_id: 8 }],
      navneBySubjekt: new Map(),
    });
    expect(out.mentions).toEqual([
      { kildeType: 'note', kildeId: '99', subjektNavn: '(ukendt subjekt)' },
      { kildeType: 'narrative', kildeId: '302', subjektNavn: 'lineage #8' },
    ]);
  });

  it('bevarer max bigint for relation, mål, mention og narrativ-subjekt', () => {
    const max = '9223372036854775807';
    expect(mapMediaAnvendelse({
      personRelationer: [{ id: max, subjekt_id: max }],
      objektRelationer: [{ id: max, objekt_type: 'estate', objekt_id: max }],
      mentions: [{ kilde_type: 'narrative', kilde_id: max }],
      narrativer: [{ id: max, subjekt_type: 'person', subjekt_id: max }],
      navneBySubjekt: new Map([[`person:${max}`, 'Stor person'], [`estate:${max}`, 'Stort gods']]),
    })).toEqual({
      afbildet: [
        { type: 'person', id: max, navn: 'Stor person', relationId: max, primaer: false },
        { type: 'estate', id: max, navn: 'Stort gods', relationId: max, primaer: false },
      ],
      mentions: [{ kildeType: 'narrative', kildeId: max, subjektNavn: 'Stor person' }],
    });
  });
});

describe('merge-læsequeries caster bigint før JSON-dekodning', () => {
  it('biblioteksqueries caster media- og relationsmål; filtre er separate specs', () => {
    expect(mediaBibliotekQuerySpecs()).toEqual({
      media: { table: 'media', select: expect.stringContaining('id::text') },
      personRelationer: { table: 'relation', select: 'subjekt_id::text,objekt_id::text' },
      objektRelationer: { table: 'relation', select: 'subjekt_id::text,objekt_type,objekt_id::text' },
      mentions: { table: 'text_mention', select: 'maal_id::text' },
    });
  });

  it('anvendelsesqueries caster relation-, mål-, mention- og narrativ-id', () => {
    expect(mediaAnvendelseQuerySpecs()).toEqual({
      personRelationer: { table: 'relation', select: 'id::text,subjekt_id::text,kvalifikator' },
      objektRelationer: { table: 'relation', select: 'id::text,objekt_type,objekt_id::text' },
      mentions: { table: 'text_mention', select: 'kilde_type,kilde_id::text' },
      narrativer: { table: 'narrative', select: 'id::text,subjekt_type,subjekt_id::text' },
    });
  });
});

describe('mapUdrensPreview (mediehåndtering fase 4)', () => {
  it('mapper den aktuelle preview-RPC-kontrakt til camelCase', () => {
    expect(mapUdrensPreview({
      upload_status: 'fjernet', kan_udrenses: false,
      blokeringer: ['1 tilknytning skal fjernes først'],
      antal_tilknytninger: 1, antal_mentions: 2, antal_fakta: 3, antal_stories: 4,
      antal_narrativer: 5, antal_noter: 6, antal_forslag: 7,
      tilknytninger: [{ relation_id: 11, retning: 'ud', modpart_type: 'person', modpart_id: 42 }],
      mentions: [{ kilde_type: 'narrative', kilde_id: 21 }],
      fakta: [31], stories: [41], narrativer: [51], noter: [61], forslag: [71],
      stier: [{ bucket: 'media', sti: 'redaktor/a.jpg', kilde: 'media' }],
    })).toEqual({
      uploadStatus: 'fjernet', kanUdrenses: false,
      blokeringer: ['1 tilknytning skal fjernes først'],
      antalTilknytninger: 1, antalMentions: 2, antalFakta: 3, antalStories: 4,
      antalNarrativer: 5, antalNoter: 6, antalForslag: 7,
      tilknytninger: [{ relationId: '11', retning: 'ud', modpartType: 'person', modpartId: '42' }],
      mentions: [{ kildeType: 'narrative', kildeId: '21' }],
      fakta: ['31'], stories: ['41'], narrativer: ['51'], noter: ['61'], forslag: ['71'],
      stier: [{ bucket: 'media', sti: 'redaktor/a.jpg', kilde: 'media' }],
    });
  });

  it('giver fail-closed scalarer og tomme lister ved tomt input', () => {
    expect(mapUdrensPreview(null)).toEqual({
      uploadStatus: '', kanUdrenses: false, blokeringer: [],
      antalTilknytninger: 0, antalMentions: 0, antalFakta: 0, antalStories: 0,
      antalNarrativer: 0, antalNoter: 0, antalForslag: 0,
      tilknytninger: [], mentions: [], fakta: [], stories: [], narrativer: [], noter: [], forslag: [], stier: [],
    });
  });
});
