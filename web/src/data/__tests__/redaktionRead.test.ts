import { describe, it, expect } from 'vitest';
import { buildTidslinje, mapFamilieRows, mapHaendelser, mapPersonMediaRows } from '../redaktionRead';
import type { Model } from '../types';

describe('hændelses-tidslinje', () => {
  it('mapper også skjulte og fletter fact-kobling uden dublet, NULL sidst', () => {
    const hs = mapHaendelser([
      { id: 1, klausul: 'Tidlig', kategori: 'rejse', date_min: '1500-01-01', date_max: '1500-12-31', date_qualifier: null, date_raw: '1500', feed_status: 'skjult', narrative_id: 1, span_start: 0, span_laengde: 6, fact_id: null, relation_id: null, narrative: { side: '2', source: { titel: 'DAA', udgave: null } } },
      { id: 2, klausul: 'Født her', kategori: 'familie', date_min: '1600-01-01', date_max: '1600-12-31', date_qualifier: null, date_raw: '1600', feed_status: 'interessant', narrative_id: 1, span_start: 8, span_laengde: 8, fact_id: 7, relation_id: null, narrative: null },
      { id: 3, klausul: 'Udateret', kategori: null, date_min: null, date_max: null, date_qualifier: null, date_raw: null, feed_status: 'kandidat', narrative_id: 1, span_start: null, span_laengde: null, fact_id: null, relation_id: null, narrative: null },
    ] as never);
    expect(hs[0]).toMatchObject({ feedStatus: 'skjult', sourceTitel: 'DAA', side: '2' });
    const evidence = { koen: null, felter: { foedt: [{ felt: 'foedt', faktatype: 'fødsel', factId: 7,
      konklusionAssertionId: 70, uenig: false, oplysninger: [{ assertionId: 70, vaerdi: '1600', erKonklusion: true,
        dato: { min: '1600-01-01', max: '1600-12-31', qualifier: null, raw: '1600' }, kilder: [] }] }] } };
    const out = buildTidslinje(hs, evidence);
    expect(out.map((p) => p.id)).toEqual(['h:1', 'f:7', 'h:3']);
    expect(out[1]).toMatchObject({ art: 'rygrad', klausul: 'Født her', factId: 7 });
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

describe('mapPersonMediaRows (mediehåndtering Slice 0g+0h)', () => {
  it('mapper media-rækker til PersonMedia, url fra den signerede Map, relationId fra rel-Map', () => {
    const rows = [{ id: 91, slags: 'foto', titel: 'Portræt', storage_path: 'redaktor/a.jpg',
                    upload_status: 'klar', maa_publiceres: true }];
    const signed = new Map([['redaktor/a.jpg', 'https://signed/a.jpg']]);
    const relByMediaId = new Map([['91', '501']]);
    expect(mapPersonMediaRows(rows, signed, relByMediaId)).toEqual([{
      id: '91', relationId: '501', slags: 'foto', titel: 'Portræt', storagePath: 'redaktor/a.jpg',
      uploadStatus: 'klar', maaPubliceres: true, url: 'https://signed/a.jpg', thumbUrl: 'https://signed/a.jpg',
    }]);
  });
  it('manglende status/slags/maa_publiceres → fail-closed fallback (kladde, false); ingen signering/relation → null/tom', () => {
    const rows = [{ id: 92, slags: null, titel: null, storage_path: null,
                    upload_status: null, maa_publiceres: null }];
    expect(mapPersonMediaRows(rows)).toEqual([{
      id: '92', relationId: '', slags: '', titel: null, storagePath: null,
      uploadStatus: 'kladde', maaPubliceres: false, url: null, thumbUrl: null,
    }]);
  });
  it('thumbPathByMediaId med matchende signeret sti → thumbUrl bruger thumb, ikke url', () => {
    const rows = [{ id: 94, slags: 'foto', titel: 'Med thumb', storage_path: 'redaktor/d-large.jpg',
                    upload_status: 'klar', maa_publiceres: true }];
    const signed = new Map([
      ['redaktor/d-large.jpg', 'https://signed/d-large.jpg'],
      ['redaktor/d-thumb.jpg', 'https://signed/d-thumb.jpg'],
    ]);
    const thumbPathByMediaId = new Map([['94', 'redaktor/d-thumb.jpg']]);
    expect(mapPersonMediaRows(rows, signed, new Map(), thumbPathByMediaId)).toEqual([{
      id: '94', relationId: '', slags: 'foto', titel: 'Med thumb', storagePath: 'redaktor/d-large.jpg',
      uploadStatus: 'klar', maaPubliceres: true, url: 'https://signed/d-large.jpg', thumbUrl: 'https://signed/d-thumb.jpg',
    }]);
  });
  it('upload_status=fjernet filtreres væk (Slice 0h "slet billede")', () => {
    const rows = [{ id: 93, slags: 'foto', titel: 'Fjernet', storage_path: 'redaktor/c.jpg',
                    upload_status: 'fjernet', maa_publiceres: true }];
    expect(mapPersonMediaRows(rows)).toEqual([]);
  });
});
