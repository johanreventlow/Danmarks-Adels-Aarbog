import { describe, it, expect } from 'vitest';
import { buildGenCoords } from '../generations';

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
