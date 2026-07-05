import { buildAnchorPeers, buildBidirectionalColumns, columnLabel } from '../tree';
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
    expect(fb!.kuldGroups?.['I']?.map((p) => p.id)).toEqual(['A']);
    expect(fb!.kuldGroups?.['II']?.map((p) => p.id)).toEqual(['B']);
  });

  it('uden genCoords: ingen fallback-ring (bagudkompatibel 4-arg-kald)', () => {
    const cols = buildBidirectionalColumns(fbModel, 'P', [], []);
    expect(cols.find((c) => c.fallback)).toBeUndefined();
  });

  it('scoper ringen til samme kilde (udgave) — samme (linje,lokal) men anden sourceId medtages IKKE (F2, dual-review 2026-07-05)', () => {
    const fbModel2 = buildModel(db([P('P'), P('A'), P('B'), P('D')], []));
    const genCoords = {
      P: [
        { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
        { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
      ],
      A: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
      B: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
      // Samme (linje, lokal) som A/B, men en ANDEN udgave (sourceId '2') — en anden trykt DAA-
      // udgaves "linje III, slægtled 11" må ikke smelte sammen med P's egen udgaves ring.
      D: [{ sourceId: '2', linje: 'III', lineageId: '99', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
    };
    const cols = buildBidirectionalColumns(fbModel2, 'P', [], [], genCoords);
    const fb = cols.find((c) => c.fallback);
    expect(fb).toBeDefined();
    expect(fb!.people.map((p) => p.id).sort()).toEqual(['A', 'B']);
  });
});

describe('buildBidirectionalColumns · v2 activeCoord (bidirektionel fallback + peers + labels)', () => {
  const coord = (over: Partial<{ sourceId: string; linje: string; lineageId: string | null; lokal: number; kuld: string | null }> = {}) => ({
    sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null, ...over,
  });
  const active = { sourceId: '1', lineageId: '10', lokal: 11 };

  it('(d) activeCoord=null → v1-adfærd uændret: ingen peers, ingen efterkommer-fallback, gamle labels', () => {
    const genCoords = { A: [coord()], F: [coord({ lokal: 10 })], M: [coord({ lokal: 10 })] };
    const cols = buildBidirectionalColumns(model, 'A', [], [], genCoords, null);
    expect(cols.map((c) => c.label)).toEqual(['Forældre', 'Fokus', 'Børn']);
    expect(col(cols, 'anchor:0')!.people.map((p) => p.id)).toEqual(['A']);
    expect(col(cols, 'anchor:0')!.overflowPeers).toBe(0);
    expect(cols.find((c) => c.fallback)).toBeUndefined();
  });

  it('(b) anker-kolonne har focusId + naboer når activeCoord er givet', () => {
    const genCoords = {
      A: [coord()], F: [coord({ lokal: 10 })], M: [coord({ lokal: 10 })],
      C1: [coord({ lokal: 11 })], // deler A's slægtled → nabo
    };
    const cols = buildBidirectionalColumns(model, 'A', [], [], genCoords, active);
    const anchor = col(cols, 'anchor:0')!;
    expect(anchor.focusId).toBe('A');
    expect(anchor.people.map((p) => p.id)).toEqual(['A', 'C1']);
    expect(anchor.overflowPeers).toBe(0);
  });

  it('(c) bevist ancestor-kolonne får kombineret label "Forældre · N. slægtled" fra activeCoord', () => {
    const genCoords = { A: [coord()], F: [coord({ lokal: 10 })], M: [coord({ lokal: 10 })] };
    const cols = buildBidirectionalColumns(model, 'A', [], [], genCoords, active);
    expect(col(cols, 'ancestor:1')!.label).toBe('Forældre · 10. slægtled');
    expect(col(cols, 'anchor:0')!.label).toBe('11. slægtled · III-linjen');
  });

  it('(c) bevist descendant-kolonne får kombineret label "Børn · N. slægtled"', () => {
    const genCoords = { A: [coord()], C1: [coord({ lokal: 12 })], C2: [coord({ lokal: 12 })] };
    const cols = buildBidirectionalColumns(model, 'A', [], [], genCoords, active);
    expect(col(cols, 'descendant:1')!.label).toBe('Børn · 12. slægtled');
  });

  it('(a) efterkommer-fallback-ring bygges når childrenOf er tom + activeCoord givet (ny person i G+1)', () => {
    // Egen minimal model: 'leaf' har ingen registrerede børn; 'X' er en fremmed person på G+1.
    const leafModel = buildModel(db([P('leaf'), P('X')], []));
    const genCoords = {
      leaf: [coord({ lokal: 20 })],
      X: [coord({ lokal: 21, kuld: 'I' })],
    };
    const activeAtLeaf = { sourceId: '1', lineageId: '10', lokal: 20 };
    const cols = buildBidirectionalColumns(leafModel, 'leaf', [], [], genCoords, activeAtLeaf);
    const fb = cols.find((c) => c.fallback && c.kind === 'descendant');
    expect(fb).toBeDefined();
    expect(fb!.people.map((p) => p.id)).toEqual(['X']);
    expect(fb!.genLabel).toContain('21. slægtled');
    expect(fb!.label).toBe('muligt · 21. slægtled · III-linjen');
  });

  it('(a) ærlig dødende: ingen efterkommer-fallback-ring når ingen match findes på lokal+1', () => {
    const leafModel = buildModel(db([P('leaf')], []));
    const genCoords = { leaf: [coord({ lokal: 20 })] }; // ingen andre personer på lokal 21
    const activeAtLeaf = { sourceId: '1', lineageId: '10', lokal: 20 };
    const cols = buildBidirectionalColumns(leafModel, 'leaf', [], [], genCoords, activeAtLeaf);
    expect(cols.find((c) => c.fallback)).toBeUndefined();
  });

  it('v1-regression: source/lineage-scoped ane-fallback + founder-hop uændret (dir=-1 via buildBidirectionalColumns)', () => {
    const fbModel = buildModel(db([P('P'), P('A'), P('B')], []));
    const genCoords = {
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
    expect(fb!.kind).toBe('ancestor');
    expect(fb!.people.map((p) => p.id).sort()).toEqual(['A', 'B']);
    expect(fb!.kuldGroups?.['I']?.map((p) => p.id)).toEqual(['A']);
    expect(fb!.kuldGroups?.['II']?.map((p) => p.id)).toEqual(['B']);
  });
});

describe('columnLabel', () => {
  it('anker m. slægtled → "N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'anchor', depth: 0, slaegtled: 11, linje: 'III' })).toBe('11. slægtled · III-linjen');
  });

  it('anker uden slægtled → "Fokus"', () => {
    expect(columnLabel({ kind: 'anchor', depth: 0, slaegtled: null, linje: null })).toBe('Fokus');
  });

  it('fallback → "muligt · N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 2, slaegtled: 9, linje: 'V', fallback: true }))
      .toBe('muligt · 9. slægtled · V-linjen');
  });

  it('bevist ancestor depth≤4 m. slægtled → "kinship · N. slægtled"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 1, slaegtled: 12, linje: 'III' })).toBe('Forældre · 12. slægtled');
    expect(columnLabel({ kind: 'ancestor', depth: 4, slaegtled: 5, linje: 'III' }))
      .toBe('Tipoldeforældre · 5. slægtled');
  });

  it('bevist ancestor depth≤4 uden slægtled → kun kinship', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 1, slaegtled: null, linje: null })).toBe('Forældre');
  });

  it('bevist descendant depth≤4 m. slægtled → "kinship · N. slægtled"', () => {
    expect(columnLabel({ kind: 'descendant', depth: 1, slaegtled: 13, linje: 'III' })).toBe('Børn · 13. slægtled');
  });

  it('bevist descendant depth≤4 uden slægtled → kun kinship', () => {
    expect(columnLabel({ kind: 'descendant', depth: 2, slaegtled: null, linje: null })).toBe('Børnebørn');
  });

  it('bevist ancestor depth≥5 m. slægtled → "N. slægtled" (ikke kinship-navn)', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 5, slaegtled: 3, linje: 'III' })).toBe('3. slægtled');
  });

  it('bevist ancestor depth≥5 uden slægtled → v1-fallback "N× Tipoldeforældre"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 5, slaegtled: null, linje: null })).toBe('2× Tipoldeforældre');
    expect(columnLabel({ kind: 'ancestor', depth: 7, slaegtled: null, linje: null })).toBe('4× Tipoldeforældre');
  });

  it('bevist descendant depth≥5 m. slægtled → "N. slægtled" (ikke kinship-navn)', () => {
    expect(columnLabel({ kind: 'descendant', depth: 6, slaegtled: 20, linje: 'III' })).toBe('20. slægtled');
  });

  it('bevist descendant depth≥5 uden slægtled → v1-fallback "N× Tipoldebørn"', () => {
    expect(columnLabel({ kind: 'descendant', depth: 5, slaegtled: null, linje: null })).toBe('2× Tipoldebørn');
  });
});

describe('buildAnchorPeers', () => {
  const coord = (over: Partial<{ sourceId: string; linje: string; lineageId: string | null; lokal: number }> = {}) => ({
    sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null, ...over,
  });
  const active = { sourceId: '1', lineageId: '10', lokal: 11 };

  it('naboer inkluderet + fokus altid først', () => {
    const m = buildModel(db([P('anker', { name: 'Zebra' }), P('nabo', { name: 'Bertha' })], []));
    const genCoords = { anker: [coord()], nabo: [coord()] };
    const r = buildAnchorPeers(m, genCoords, 'anker', active);
    expect(r.people.map((p) => p.id)).toEqual(['anker', 'nabo']);
    expect(r.overflow).toBe(0);
  });

  it('kun personer med matchende (sourceId,lineageId,lokal) tælles som naboer — resten udelades', () => {
    const m = buildModel(db(
      [P('anker'), P('nabo'), P('anden-linje'), P('ingen-koord')],
      [],
    ));
    const genCoords = {
      anker: [coord()],
      nabo: [coord()],
      'anden-linje': [coord({ lokal: 12 })], // samme kilde/linje, andet slægtled → udelades
    };
    const r = buildAnchorPeers(m, genCoords, 'anker', active);
    expect(r.people.map((p) => p.id).sort()).toEqual(['anker', 'nabo']);
  });

  it('naboer sorteres alfabetisk (dansk collation), fokus forbliver først uanset navn', () => {
    const m = buildModel(db(
      [P('anker', { name: 'Å-anker' }), P('c', { name: 'Conrad' }), P('a', { name: 'Anne' }), P('b', { name: 'Bertha' })],
      [],
    ));
    const genCoords = { anker: [coord()], c: [coord()], a: [coord()], b: [coord()] };
    const r = buildAnchorPeers(m, genCoords, 'anker', active);
    expect(r.people.map((p) => p.id)).toEqual(['anker', 'a', 'b', 'c']);
  });

  it('cap+overflow: 10 naboer, cap 3 → people-længde 4 (fokus+3), overflow 7', () => {
    const peers = Array.from({ length: 10 }, (_, i) => P(`p${i}`, { name: `Navn${i}` }));
    const m = buildModel(db([P('anker'), ...peers], []));
    const genCoords: Record<string, ReturnType<typeof coord>[]> = { anker: [coord()] };
    for (const p of peers) genCoords[p.id] = [coord()];
    const r = buildAnchorPeers(m, genCoords, 'anker', active, 3);
    expect(r.people.length).toBe(4);
    expect(r.people[0].id).toBe('anker');
    expect(r.overflow).toBe(7);
  });

  it('activeCoord == null → kun fokus, ingen naboer (v1-adfærd)', () => {
    const m = buildModel(db([P('anker'), P('nabo')], []));
    const genCoords = { anker: [coord()], nabo: [coord()] };
    const r = buildAnchorPeers(m, genCoords, 'anker', null);
    expect(r.people.map((p) => p.id)).toEqual(['anker']);
    expect(r.overflow).toBe(0);
  });

  it('ukendt anker → tom people, overflow 0', () => {
    const m = buildModel(db([P('nabo')], []));
    const r = buildAnchorPeers(m, { nabo: [coord()] }, 'findes-ikke', active);
    expect(r.people).toEqual([]);
    expect(r.overflow).toBe(0);
  });
});
