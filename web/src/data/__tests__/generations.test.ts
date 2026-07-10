import { describe, it, expect } from 'vitest';
import { buildGenCoords, buildParentsUnknown, GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE } from '../generations';

const lineage = [
  { id: '10', source_id: '1', kode: 'III', navn: 'Midterste', parent_lineage_id: null },
  { id: '50', source_id: '1', kode: 'V', navn: 'Yngre', parent_lineage_id: '10' },
];

describe('buildGenCoords', () => {
  it('samler flere linje-koordinater på én kanonisk founder', () => {
    const ext = [
      { person_id: '900', source_id: '1', linje: 'V', nr: 1, slaegtled_lokal: 1, slaegtled_gennem: 12, kuld: null },
      { person_id: '901', source_id: '1', linje: 'III', nr: 58, slaegtled_lokal: 12, slaegtled_gennem: 12, kuld: null },
    ];
    const coords = buildGenCoords(ext, lineage, { '900': '900', '901': '900' });
    expect(coords['900']).toHaveLength(2);
    expect(coords['900'].map((c) => c.linje).sort()).toEqual(['III', 'V']);
  });

  it('NULL linje karantænes (ingen koordinat)', () => {
    const ext = [{ person_id: '5', source_id: '1', linje: null, nr: null, slaegtled_lokal: null, slaegtled_gennem: null, kuld: null }];
    expect(buildGenCoords(ext, lineage, { '5': '5' })['5']).toBeUndefined();
  });

  it('bærer lokal/gennem/kuld + linje-navn videre pr. koordinat', () => {
    const ext = [{ person_id: '7', source_id: '1', linje: 'III', nr: 3, slaegtled_lokal: 3, slaegtled_gennem: 3, kuld: 'II' }];
    const coords = buildGenCoords(ext, lineage, { '7': '7' });
    expect(coords['7'][0]).toMatchObject({ linje: 'III', lineageId: '10', lokal: 3, gennem: 3, kuld: 'II' });
  });
});

describe('buildParentsUnknown (marker-gated resolver)', () => {
  const idmap = { '10': '10', '11': '11', '99': '10' }; // 99 er alias for kanonisk 10

  it('markering med afklaret konklusion → grad + proveniens pr. kanonisk person', () => {
    const out = buildParentsUnknown(
      [{ id: 500, subjekt_id: 10 }],
      [{ target_id: 500, valgt_assertion_id: 800 }],
      [{ id: 800, vaerdi_tekst: GRADE_FORAELDER_UKENDT }],
      [{ assertion_id: 800, citat_tekst: 'DAA 1939 s.97' }],
      idmap,
    );
    expect(out['10']).toEqual({ grade: GRADE_FORAELDER_UKENDT, kilde: 'DAA 1939 s.97' });
  });

  it('fact UDEN afklaret konklusion → ikke en aktiv markering (ekskluderet)', () => {
    const out = buildParentsUnknown(
      [{ id: 500, subjekt_id: 10 }],
      [], // ingen afklaret konklusion
      [{ id: 800, vaerdi_tekst: GRADE_FORAELDER_UKENDT }],
      [{ assertion_id: 800, citat_tekst: 'x' }],
      idmap,
    );
    expect(out['10']).toBeUndefined();
  });

  it('kanoniserer subjekt_id (alias 99 → kanonisk 10)', () => {
    const out = buildParentsUnknown(
      [{ id: 501, subjekt_id: 99 }],
      [{ target_id: 501, valgt_assertion_id: 801 }],
      [{ id: 801, vaerdi_tekst: GRADE_INGEN_FORBINDELSE }],
      [{ assertion_id: 801, citat_tekst: null }],
      idmap,
    );
    expect(out['10']).toEqual({ grade: GRADE_INGEN_FORBINDELSE, kilde: null });
    expect(out['99']).toBeUndefined();
  });

  it('to markeringer på samme person → første afklarede vinder (deterministisk)', () => {
    const out = buildParentsUnknown(
      [{ id: 502, subjekt_id: 11 }, { id: 503, subjekt_id: 11 }],
      [{ target_id: 502, valgt_assertion_id: 802 }, { target_id: 503, valgt_assertion_id: 803 }],
      [{ id: 802, vaerdi_tekst: GRADE_FORAELDER_UKENDT }, { id: 803, vaerdi_tekst: GRADE_INGEN_FORBINDELSE }],
      [],
      idmap,
    );
    expect(out['11'].grade).toBe(GRADE_FORAELDER_UKENDT);
  });
});
