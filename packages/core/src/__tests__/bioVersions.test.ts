import { buildBioSourceVersions, buildBioVersions } from '../bioVersions';
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
