import { buildBidirectionalColumns } from '../tree';
import { buildModel } from '../buildModel';
import type { AppPerson, Db } from '../types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson => ({
  id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o,
});
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

// Slægt: GF+GM → F (+ M) → A (fokus) → {C1, C2}; C1 → G1.
//   GF, GM = bedsteforældre (F's forældre); F, M = A's forældre; C1,C2 = A's børn; G1 = C1's barn.
const model = buildModel(
  db(
    [P('GF'), P('GM'), P('F'), P('M'), P('A'), P('C1'), P('C2'), P('G1')],
    [
      { child: 'F', parent: 'GF', union: 'u0' },
      { child: 'F', parent: 'GM', union: 'u0' },
      { child: 'A', parent: 'F', union: 'u1' },
      { child: 'A', parent: 'M', union: 'u1' },
      { child: 'C1', parent: 'A', union: 'u2' },
      { child: 'C2', parent: 'A', union: 'u2' },
      { child: 'G1', parent: 'C1', union: 'u3' },
    ],
  ),
);
const ids = (people: { id: string }[]) => people.map((p) => p.id);
const col = (cols: ReturnType<typeof buildBidirectionalColumns>, key: string) => cols.find((c) => c.key === key);

describe('buildBidirectionalColumns', () => {
  it('ukendt anker → ingen kolonner', () => {
    expect(buildBidirectionalColumns(model, 'findes-ikke', [], [])).toEqual([]);
  });

  it('default (ingen valg): [Forældre, Fokus, Børn] i rækkefølge, korrekte labels', () => {
    const cols = buildBidirectionalColumns(model, 'A', [], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0', 'descendant:1']);
    expect(cols.map((c) => c.label)).toEqual(['Forældre', 'Fokus', 'Børn']);
    expect(ids(col(cols, 'ancestor:1')!.people).sort()).toEqual(['F', 'M']);
    expect(ids(col(cols, 'anchor:0')!.people)).toEqual(['A']);
    expect(ids(col(cols, 'descendant:1')!.people).sort()).toEqual(['C1', 'C2']);
    expect(col(cols, 'ancestor:1')!.selectedId).toBeNull();
    expect(col(cols, 'descendant:1')!.selectedId).toBeNull();
    expect(col(cols, 'anchor:0')!.selectedId).toBe('A');
  });

  it('ane-drill: vælg forælder F → Bedsteforældre-kolonne (F’s forældre) dukker op til venstre', () => {
    const cols = buildBidirectionalColumns(model, 'A', ['F'], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:2', 'ancestor:1', 'anchor:0', 'descendant:1']);
    expect(col(cols, 'ancestor:1')!.selectedId).toBe('F');
    expect(col(cols, 'ancestor:2')!.label).toBe('Bedsteforældre');
    expect(ids(col(cols, 'ancestor:2')!.people).sort()).toEqual(['GF', 'GM']);
  });

  it('efterkommer-drill (regression): vælg barn C1 → Børnebørn-kolonne til højre', () => {
    const cols = buildBidirectionalColumns(model, 'A', [], ['C1']);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0', 'descendant:1', 'descendant:2']);
    expect(col(cols, 'descendant:1')!.selectedId).toBe('C1');
    expect(col(cols, 'descendant:2')!.label).toBe('Børnebørn');
    expect(ids(col(cols, 'descendant:2')!.people)).toEqual(['G1']);
  });

  it('begge retninger samtidig: aner OG efterkommere udfoldet', () => {
    const cols = buildBidirectionalColumns(model, 'A', ['F'], ['C1']);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:2', 'ancestor:1', 'anchor:0', 'descendant:1', 'descendant:2']);
  });

  it('retning uden data udelades (anker uden forældre → ingen ane-kolonne)', () => {
    const cols = buildBidirectionalColumns(model, 'GF', [], []);
    expect(cols.map((c) => c.kind)).not.toContain('ancestor'); // GF har ingen registrerede forældre
    expect(cols[0].kind).toBe('anchor');
  });

  it('blad-person begge veje (G1: har forælder, ingen børn) → kun Forældre + Fokus', () => {
    const cols = buildBidirectionalColumns(model, 'G1', [], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0']);
  });

  it('dyb label-fallback: N× tipoldeforældre/-børn fra dybde 5', () => {
    // Byg en lineær 6-generations kæde p0→p1→…→p5 og drill helt igennem.
    const chain = buildModel(
      db(
        ['p0', 'p1', 'p2', 'p3', 'p4', 'p5'].map((id) => P(id)),
        [
          { child: 'p1', parent: 'p0', union: 'c' },
          { child: 'p2', parent: 'p1', union: 'c' },
          { child: 'p3', parent: 'p2', union: 'c' },
          { child: 'p4', parent: 'p3', union: 'c' },
          { child: 'p5', parent: 'p4', union: 'c' },
        ],
      ),
    );
    const down = buildBidirectionalColumns(chain, 'p0', [], ['p1', 'p2', 'p3', 'p4']);
    expect(col(down, 'descendant:4')!.label).toBe('Tipoldebørn'); // dybde 4 navngives stadig
    expect(col(down, 'descendant:5')!.label).toBe('2× Tipoldebørn');
    const up = buildBidirectionalColumns(chain, 'p5', ['p4', 'p3', 'p2', 'p1'], []);
    expect(col(up, 'ancestor:5')!.label).toBe('2× Tipoldeforældre');
  });

  it('cyklus-guard: self-forælder terminerer uden gentagelse', () => {
    const loop = buildModel(db([P('X')], [{ child: 'X', parent: 'X', union: 'c' }]));
    const cols = buildBidirectionalColumns(loop, 'X', [], []);
    // X er sin egen forælder: visited (seedet med ankeret X) filtrerer X ud → ingen ane-kolonne, terminerer.
    expect(cols.map((c) => c.kind)).not.toContain('ancestor');
    expect(cols.map((c) => c.kind)).not.toContain('descendant');
    expect(cols.map((c) => c.key)).toEqual(['anchor:0']);
  });

  it('kolonne-keys er stabile og kollisionsfri på tværs af retninger', () => {
    const cols = buildBidirectionalColumns(model, 'A', ['F'], ['C1']);
    const keys = cols.map((c) => c.key);
    expect(new Set(keys).size).toBe(keys.length); // ingen dublet-keys (ancestor:1 ≠ descendant:1)
  });
});

describe('fallback-ring', () => {
  // Minimal model: anker P (V, lokal 1, founder) uden beviste forældre; to naboer i III lokal 11.
  // genCoords sendes som EKSPLICIT 5. arg — IKKE på model (jf. post-B3 design-justering: mobils
  // Model bærer bevidst ikke genCoordsByPerson; byggeren skal være platform-agnostisk).
  const fbModel = buildModel(db([P('P'), P('A'), P('B')], []));

  it('bygger en founder-hop fallback-ring når aner-ringen er tom', () => {
    const genCoords = {
      // Founder P = collapset V-1 + III-58 → bærer BEGGE koordinater (coalescer aldrig).
      P: [
        { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
        { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
      ],
      A: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
      B: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
    };
    const cols = buildBidirectionalColumns(fbModel, 'P', [], [], genCoords);
    const fb = cols.find((c) => c.fallback);
    expect(fb).toBeDefined();
    expect(fb!.people.map((p) => p.id).sort()).toEqual(['A', 'B']);
    expect(fb!.genLabel).toContain('slægtled');
  });

  it('uden genCoords: ingen fallback-ring (bagudkompatibel 4-arg-kald)', () => {
    const cols = buildBidirectionalColumns(fbModel, 'P', [], []);
    expect(cols.find((c) => c.fallback)).toBeUndefined();
  });
});
