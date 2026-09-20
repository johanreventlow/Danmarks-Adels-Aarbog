import {
  buildBioSourceVersions,
  buildBioVersions,
  mapPublicBioSourceVersionsV2,
  selectDefaultPublicBioSourceVersionV2,
} from '../bioVersions';
import type { NarrativeCand } from '../pickPreferredBio';

const C = (o: Partial<NarrativeCand> & Pick<NarrativeCand, 'narrativeId'>): NarrativeCand => ({
  tekst: null, sourceId: null, slags: 'DAA-udgave', aar: null, udgave: null,
  ...o,
});

describe('buildBioVersions', () => {
  it('sorterer nyeste udgave først', () => {
    const versions = buildBioVersions([
      C({ narrativeId: 1, tekst: 'gammel bio', sourceId: 10, aar: 1939, udgave: '1939' }),
      C({ narrativeId: 2, tekst: 'ny bio', sourceId: 20, aar: 2020, udgave: '2018-20' }),
    ]);
    expect(versions.map((v) => v.aar)).toEqual([2020, 1939]);
    expect(versions[0].tekst).toBe('ny bio');
  });

  it('version[0] matcher altid pickPreferredBio-valget (samme determinisme)', () => {
    const cands = [
      C({ narrativeId: 1, tekst: 'A', sourceId: 1, aar: 1900 }),
      C({ narrativeId: 2, tekst: 'B', sourceId: 2, aar: 1950 }),
      C({ narrativeId: 3, tekst: 'C', sourceId: 3, aar: 1950 }), // tie på aar → højeste sourceId vinder
    ];
    const versions = buildBioVersions(cands);
    expect(versions[0].sourceId).toBe(3);
  });

  it('filtrerer tomme tekster og ikke-DAA-udgave-slags fra (samme gate som pickPreferredBio)', () => {
    const versions = buildBioVersions([
      C({ narrativeId: 1, tekst: '', sourceId: 1, aar: 2000 }),
      C({ narrativeId: 2, tekst: 'tng-stub', sourceId: 2, aar: 1999, slags: 'TNG-dump' }),
      C({ narrativeId: 3, tekst: 'gyldig', sourceId: 3, aar: 1950 }),
    ]);
    expect(versions).toHaveLength(1);
    expect(versions[0].tekst).toBe('gyldig');
  });

  it('sammenføjer flere medlemmers narrativ i SAMME udgave (foldet person), dedup eksakte', () => {
    const versions = buildBioVersions([
      C({ narrativeId: 1, tekst: 'kanonisk fuld bio', sourceId: 5, aar: 1939 }),
      C({ narrativeId: 2, tekst: 'alias-stub', sourceId: 5, aar: 1939 }),
      C({ narrativeId: 3, tekst: 'kanonisk fuld bio', sourceId: 5, aar: 1939 }), // eksakt dublet
    ]);
    expect(versions).toHaveLength(1);
    expect(versions[0].tekst).toBe('kanonisk fuld bio\n\nalias-stub');
  });

  it('tom input → tom liste', () => {
    expect(buildBioVersions([])).toEqual([]);
  });
});

describe('buildBioSourceVersions', () => {
  it('bevarer to publicerede records fra samme bog uden at sammenføje dem', () => {
    const versions = buildBioSourceVersions([
      { record_ref: 'ref-b', source_label: 'DAA 1939', record_label: 'Linje I, nr. 2', narrative_text: 'Anden tekst', citation_label: 's. 2', provenance_kind: 'source_record' },
      { record_ref: 'ref-a', source_label: 'DAA 1939', record_label: 'Linje I, nr. 1', narrative_text: 'Første tekst', citation_label: 's. 1', provenance_kind: 'source_record' },
      { record_ref: null, source_label: 'DAA 1939', record_label: 'Overgangsdata', narrative_text: 'Legacy tekst', citation_label: '', provenance_kind: 'legacy_narrative' },
    ]);
    expect(versions).toHaveLength(3);
    expect(versions.map((v) => v.recordRef)).toEqual(['ref-a', 'ref-b', null]);
    expect(versions[2]).toMatchObject({ provenanceKind: 'legacy_narrative', narrativeText: 'Legacy tekst' });
  });
});

describe('mapPublicBioSourceVersionsV2', () => {
  const rows = [
    { person_id: 1, source_id: 9, source_year: null, record_order: null, source_record_ref: 'null-year', source_label: 'Uden år', record_label: 'Post Z', narrative_text: 'Senest i input', citation_label: 's. 9', provenance_kind: 'source_record' },
    { person_id: 1, source_id: 3, source_year: 2020, record_order: null, source_record_ref: null, source_label: 'Misvisende label', record_label: 'Overgangsdata', narrative_text: 'Legacy for source 3', citation_label: '', provenance_kind: 'legacy_narrative' },
    { person_id: 1, source_id: 3, source_year: 2020, record_order: 12, source_record_ref: 's3-side-12', source_label: 'DAA 2020', record_label: 'Å', narrative_text: 'Side tolv', citation_label: 's. 12', provenance_kind: 'source_record' },
    { person_id: 1, source_id: 3, source_year: 2020, record_order: 2, source_record_ref: 's3-side-2', source_label: 'DAA 2020', record_label: 'Ø', narrative_text: 'Side to', citation_label: 's. 2', provenance_kind: 'source_record' },
    { person_id: 1, source_id: 2, source_year: 2020, record_order: 1, source_record_ref: 's2-side-1', source_label: 'Ældre label', record_label: 'A', narrative_text: 'Kilde to', citation_label: 's. 1', provenance_kind: 'source_record' },
  ] as const;

  it('sorterer på struktureret kronologi, opaque source-id, binding, side, dansk label og stabil ref', () => {
    const versions = mapPublicBioSourceVersionsV2(rows);
    expect(versions.map((v) => v.sourceRecordRef)).toEqual([
      's2-side-1', 's3-side-2', 's3-side-12', null, 'null-year',
    ]);
    expect(versions.map((v) => v.narrativeText)).toEqual([
      'Kilde to', 'Side to', 'Side tolv', 'Legacy for source 3', 'Senest i input',
    ]);
  });

  it('vælger første eligible bundne record og falder kun tilbage til legacy uden bundne records', () => {
    const versions = mapPublicBioSourceVersionsV2(rows);
    expect(selectDefaultPublicBioSourceVersionV2(versions)?.sourceRecordRef).toBe('s2-side-1');

    const legacyOnly = mapPublicBioSourceVersionsV2([rows[1]]);
    expect(selectDefaultPublicBioSourceVersionV2(legacyOnly)?.narrativeText).toBe('Legacy for source 3');

    const blankBoundThenLegacy = mapPublicBioSourceVersionsV2([
      { ...rows[2], narrative_text: '   ' },
      rows[1],
    ]);
    expect(selectDefaultPublicBioSourceVersionV2(blankBoundThenLegacy)?.narrativeText).toBe('Legacy for source 3');
  });

  it('afviser en forkert typet v2-kolonne i stedet for at gætte eller falde tilbage', () => {
    expect(() => mapPublicBioSourceVersionsV2([{ ...rows[0], source_id: '9' }])).toThrow(/source_id/);
    expect(() => mapPublicBioSourceVersionsV2([{ ...rows[0], record_order: 1.5 }])).toThrow(/record_order/);
  });
});
