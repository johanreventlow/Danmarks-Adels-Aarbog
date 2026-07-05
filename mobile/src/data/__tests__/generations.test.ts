import { buildGenCoords, adjacentGen, previousAncestorGen, type GenCoord } from '../generations';

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
});

describe('adjacentGen dir=-1 (aner)', () => {
  const coords: GenCoord[] = [
    { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
    { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
  ];
  it('går et lokalt slægtled tilbage i samme linje', () => {
    expect(adjacentGen(coords, '1', '10', 12, -1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 11 });
  });
  it('hopper til moderlinjen ved founder (lokal 1)', () => {
    expect(adjacentGen(coords, '1', '50', 1, -1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 11 });
  });
  it('stopper fail-closed når ingen entydig moderlinje findes', () => {
    const only = [coords[0]]; // kun V, lokal 1, ingen gen>1-koordinat
    expect(adjacentGen(only, '1', '50', 1, -1)).toBeNull();
  });
  it('stopper fail-closed når flere moderlinje-kandidater findes', () => {
    const multi: GenCoord[] = [
      { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
      { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
      { sourceId: '1', linje: 'IIIb', lineageId: '10', parentLineageId: null, lokal: 8, gennem: 8, kuld: null },
    ];
    expect(adjacentGen(multi, '1', '50', 1, -1)).toBeNull();
  });
});

describe('adjacentGen dir=+1 (efterkommer)', () => {
  const coords: GenCoord[] = [
    { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
    { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: null, kuld: null },
  ];
  it('samme linje et slægtled frem, ingen hop', () => {
    expect(adjacentGen(coords, '1', '10', 12, 1)).toEqual({ sourceId: '1', lineageId: '10', linje: 'III', lokal: 13 });
  });
  it('en founder (lokal 1) går frem i egen linje, IKKE tilbage til moderlinjen', () => {
    expect(adjacentGen(coords, '1', '50', 1, 1)).toEqual({ sourceId: '1', lineageId: '50', linje: 'V', lokal: 2 });
  });
});

describe('previousAncestorGen (midlertidig wrapper, fjernes i Task 4)', () => {
  const coords: GenCoord[] = [
    { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
    { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
  ];
  it('går et lokalt slægtled tilbage i samme linje', () => {
    expect(previousAncestorGen(coords, 'III', 12)).toEqual({ linje: 'III', lokal: 11 });
  });
  it('hopper til moderlinjen ved founder (lokal 1)', () => {
    expect(previousAncestorGen(coords, 'V', 1)).toEqual({ linje: 'III', lokal: 11 });
  });
});
