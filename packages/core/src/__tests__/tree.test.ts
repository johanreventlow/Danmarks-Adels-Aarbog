import { describe, it, expect } from 'vitest';
import { buildBidirectionalColumns, columnGen, columnLabel, unknownParentRing, unknownChildSection, type GenCoords, type ParentsUnknownMap, type Traverse } from '../tree';
import { GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE } from '../generations';
import { buildModel } from '../buildModel';
import type { AppPerson, Db, Koen, Model, ModelPerson } from '../types';

// Traversering er app-specifik og injiceres (webs childIdx-form bruges her som test-traverse —
// mobilens childrenByUnion-form dækkes af mobile/src/data/__tests__/selectors.test.ts).
const childrenOf: Traverse = (m, id) =>
  [...(m.indexes.childIdx[id] ?? new Set<string>())]
    .map((cid) => m.byId[cid])
    .filter(Boolean) as ModelPerson[];
const parentsOf: Traverse = (m, id) =>
  (m.indexes.parentsByChild[id] ?? [])
    .map((pid) => m.byId[pid])
    .filter(Boolean) as ModelPerson[];

// Binder traverse-injektionen én gang, så scenarierne kalder med samme form som før
// parameteriseringen af buildBidirectionalColumns.
const buildCols = (
  m: Model,
  anchorId: string,
  up: string[],
  down: string[],
  genCoords?: GenCoords,
  parentsUnknown?: ParentsUnknownMap,
) => buildBidirectionalColumns(m, anchorId, up, down, childrenOf, parentsOf, genCoords, parentsUnknown);

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
    expect(buildCols(model, 'findes-ikke', [], [])).toEqual([]);
  });

  it('default (ingen valg): [Forældre, Fokus, Børn] i rækkefølge, korrekte labels', () => {
    const cols = buildCols(model, 'A', [], []);
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
    const cols = buildCols(model, 'A', ['F'], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:2', 'ancestor:1', 'anchor:0', 'descendant:1']);
    expect(col(cols, 'ancestor:1')!.selectedId).toBe('F');
    expect(col(cols, 'ancestor:2')!.label).toBe('Bedsteforældre');
    expect(ids(col(cols, 'ancestor:2')!.people).sort()).toEqual(['GF', 'GM']);
  });

  it('efterkommer-drill (regression): vælg barn C1 → Børnebørn-kolonne til højre', () => {
    const cols = buildCols(model, 'A', [], ['C1']);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0', 'descendant:1', 'descendant:2']);
    expect(col(cols, 'descendant:1')!.selectedId).toBe('C1');
    expect(col(cols, 'descendant:2')!.label).toBe('Børnebørn');
    expect(ids(col(cols, 'descendant:2')!.people)).toEqual(['G1']);
  });

  it('begge retninger samtidig: aner OG efterkommere udfoldet', () => {
    const cols = buildCols(model, 'A', ['F'], ['C1']);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:2', 'ancestor:1', 'anchor:0', 'descendant:1', 'descendant:2']);
  });

  it('retning uden data udelades (anker uden forældre → ingen ane-kolonne)', () => {
    const cols = buildCols(model, 'GF', [], []);
    expect(cols.map((c) => c.kind)).not.toContain('ancestor'); // GF har ingen registrerede forældre
    expect(cols[0].kind).toBe('anchor');
  });

  it('blad-person begge veje (G1: har forælder, ingen børn) → kun Forældre + Fokus', () => {
    const cols = buildCols(model, 'G1', [], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0']);
  });

  it('ingen ugated fallback: tom bevist ane-ring er en ærlig dødende (INGEN gæt-kolonne selv med genCoords)', () => {
    // 'GF' har ingen beviste forældre men bærer en koordinat + der findes personer i forrige slægtled.
    // Uden en markering (Phase C) må der ALDRIG dukke en kandidat-kolonne op — det var v1/v2-fejlen.
    const genCoords = {
      GF: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
      GM: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
    };
    const cols = buildCols(model, 'GF', [], [], genCoords);
    expect(cols.map((c) => c.kind)).not.toContain('ancestor');
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
    const down = buildCols(chain, 'p0', [], ['p1', 'p2', 'p3', 'p4']);
    expect(col(down, 'descendant:4')!.label).toBe('Tipoldebørn'); // dybde 4 navngives stadig
    expect(col(down, 'descendant:5')!.label).toBe('2× Tipoldebørn');
    const up = buildCols(chain, 'p5', ['p4', 'p3', 'p2', 'p1'], []);
    expect(col(up, 'ancestor:5')!.label).toBe('2× Tipoldeforældre');
  });

  it('cyklus-guard: self-forælder terminerer uden gentagelse', () => {
    const loop = buildModel(db([P('X')], [{ child: 'X', parent: 'X', union: 'c' }]));
    const cols = buildCols(loop, 'X', [], []);
    // X er sin egen forælder: visited (seedet med ankeret X) filtrerer X ud → ingen ane-kolonne, terminerer.
    expect(cols.map((c) => c.kind)).not.toContain('ancestor');
    expect(cols.map((c) => c.kind)).not.toContain('descendant');
    expect(cols.map((c) => c.key)).toEqual(['anchor:0']);
  });

  it('kolonne-keys er stabile og kollisionsfri på tværs af retninger', () => {
    const cols = buildCols(model, 'A', ['F'], ['C1']);
    const keys = cols.map((c) => c.key);
    expect(new Set(keys).size).toBe(keys.length); // ingen dublet-keys (ancestor:1 ≠ descendant:1)
  });
});

describe('slægtled-labels fra faktisk koordinat (genCoords, valgfri)', () => {
  const coord = (over: Partial<{ sourceId: string; linje: string; lineageId: string | null; lokal: number }> = {}) => ({
    sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null, ...over,
  });

  it('uden genCoords → rene kinship-labels (ingen slægtled-tal)', () => {
    const cols = buildCols(model, 'A', [], []);
    expect(cols.map((c) => c.label)).toEqual(['Forældre', 'Fokus', 'Børn']);
  });

  it('bevist ancestor-kolonne + anker får kombineret label fra genCoords', () => {
    const genCoords = { A: [coord()], F: [coord({ lokal: 10 })], M: [coord({ lokal: 10 })] };
    const cols = buildCols(model, 'A', [], [], genCoords);
    expect(col(cols, 'ancestor:1')!.label).toBe('Forældre · 10. slægtled · III-linjen');
    expect(col(cols, 'anchor:0')!.label).toBe('11. slægtled · III-linjen');
    expect(col(cols, 'descendant:1')!.label).toBe('Børn'); // C1/C2 uden koordinat → kinship-only
  });

  it('bevist descendant-kolonne får kombineret label fra genCoords', () => {
    const genCoords = { A: [coord()], C1: [coord({ lokal: 12 })], C2: [coord({ lokal: 12 })] };
    const cols = buildCols(model, 'A', [], [], genCoords);
    expect(col(cols, 'descendant:1')!.label).toBe('Børn · 12. slægtled · III-linjen');
  });

  it('(review 20 H1) founder-anker læser FAKTISK koordinat — ikke aritmetik: en ane i III/lokal 4 '
    + 'under en V/lokal-1-founder får "4. slægtled · III-linjen", ALDRIG "0. slægtled"', () => {
    const founderModel = buildModel(db([P('P'), P('X')], [{ child: 'P', parent: 'X', union: 'u' }]));
    const genCoords = {
      P: [{ sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: null, lokal: 1, gennem: 12, kuld: null }],
      X: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 4, gennem: 4, kuld: null }],
    };
    const cols = buildCols(founderModel, 'P', [], [], genCoords);
    expect(col(cols, 'ancestor:1')!.label).toContain('4. slægtled');
    expect(col(cols, 'ancestor:1')!.label).toContain('III');
    expect(col(cols, 'ancestor:1')!.label).not.toContain('0. slægtled');
    expect(col(cols, 'anchor:0')!.label).toBe('1. slægtled · V-linjen');
  });

  it('founder-anker med FLERE linje-koordinater (tvetydig) → "Fokus" (ingen arbitrær linje)', () => {
    const founderModel = buildModel(db([P('P')], []));
    const genCoords = {
      P: [
        { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
        { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
      ],
    };
    const cols = buildCols(founderModel, 'P', [], [], genCoords);
    expect(col(cols, 'anchor:0')!.label).toBe('Fokus');
  });
});

describe('columnLabel', () => {
  it('anker m. slægtled → "N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'anchor', depth: 0, slaegtled: 11, linje: 'III' })).toBe('11. slægtled · III-linjen');
  });

  it('anker uden slægtled → "Fokus"', () => {
    expect(columnLabel({ kind: 'anchor', depth: 0, slaegtled: null, linje: null })).toBe('Fokus');
  });

  it('bevist ancestor depth≤4 m. slægtled + linje → "kinship · N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 1, slaegtled: 12, linje: 'III' }))
      .toBe('Forældre · 12. slægtled · III-linjen');
    expect(columnLabel({ kind: 'ancestor', depth: 4, slaegtled: 5, linje: 'III' }))
      .toBe('Tipoldeforældre · 5. slægtled · III-linjen');
  });

  it('bevist ancestor depth≤4 m. slægtled UDEN linje → "kinship · N. slægtled"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 1, slaegtled: 12, linje: null })).toBe('Forældre · 12. slægtled');
  });

  it('bevist ancestor depth≤4 uden slægtled → kun kinship', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 1, slaegtled: null, linje: null })).toBe('Forældre');
  });

  it('bevist descendant depth≤4 m. slægtled + linje → "kinship · N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'descendant', depth: 1, slaegtled: 13, linje: 'III' }))
      .toBe('Børn · 13. slægtled · III-linjen');
  });

  it('bevist descendant depth≤4 uden slægtled → kun kinship', () => {
    expect(columnLabel({ kind: 'descendant', depth: 2, slaegtled: null, linje: null })).toBe('Børnebørn');
  });

  it('bevist ancestor depth≥5 m. slægtled + linje → "N. slægtled · linje-linjen" (ikke kinship-navn)', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 5, slaegtled: 3, linje: 'III' })).toBe('3. slægtled · III-linjen');
  });

  it('bevist ancestor depth≥5 m. slægtled UDEN linje → "N. slægtled"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 5, slaegtled: 3, linje: null })).toBe('3. slægtled');
  });

  it('bevist ancestor depth≥5 uden slægtled → "N× Tipoldeforældre"', () => {
    expect(columnLabel({ kind: 'ancestor', depth: 5, slaegtled: null, linje: null })).toBe('2× Tipoldeforældre');
    expect(columnLabel({ kind: 'ancestor', depth: 7, slaegtled: null, linje: null })).toBe('4× Tipoldeforældre');
  });

  it('bevist descendant depth≥5 m. slægtled + linje → "N. slægtled · linje-linjen"', () => {
    expect(columnLabel({ kind: 'descendant', depth: 6, slaegtled: 20, linje: 'III' })).toBe('20. slægtled · III-linjen');
  });

  it('bevist descendant depth≥5 uden slægtled → "N× Tipoldebørn"', () => {
    expect(columnLabel({ kind: 'descendant', depth: 5, slaegtled: null, linje: null })).toBe('2× Tipoldebørn');
  });
});

describe('columnGen', () => {
  const coord = (over: Partial<{ sourceId: string; linje: string; lineageId: string | null; lokal: number | null }> = {}) => ({
    sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null, ...over,
  });

  it('alle personer enige om samme (lokal, linje) → returnerer den ene koordinat', () => {
    const genCoords = { F: [coord({ lokal: 10 })], M: [coord({ lokal: 10 })] };
    expect(columnGen(genCoords, [{ id: 'F' } as never, { id: 'M' } as never])).toEqual({ lokal: 10, linje: 'III' });
  });

  it('ingen genCoords → null', () => {
    expect(columnGen(undefined, [{ id: 'F' } as never])).toBeNull();
  });

  it('personer uden koordinat ignoreres (ikke tvetydighed)', () => {
    const genCoords = { F: [coord({ lokal: 10 })] }; // M mangler helt
    expect(columnGen(genCoords, [{ id: 'F' } as never, { id: 'M' } as never])).toEqual({ lokal: 10, linje: 'III' });
  });

  it('blandede/uenige koordinater uden tiebreak → null (kinship-only, ingen gætning)', () => {
    const genCoords = { F: [coord({ lokal: 10 })], M: [coord({ lokal: 9, linje: 'V' })] };
    expect(columnGen(genCoords, [{ id: 'F' } as never, { id: 'M' } as never])).toBeNull();
  });

  it('tvetydig ring + selectedId hvis koordinat matcher → bruges som tiebreak', () => {
    const genCoords = { F: [coord({ lokal: 10 })], M: [coord({ lokal: 9, linje: 'V' })] };
    expect(columnGen(genCoords, [{ id: 'F' } as never, { id: 'M' } as never], 'M')).toEqual({ lokal: 9, linje: 'V' });
  });

  it('tom people-liste → null', () => {
    expect(columnGen({ F: [coord()] }, [])).toBeNull();
  });
});

describe('unknownParentRing + marker-gatet kandidat-kolonne (Phase C)', () => {
  // Founder P (III/12 + V/1, collapset); N1/N2 i III/11 (kuld-adskilt). P har ingen beviste forældre.
  const pMk = (id: string) => P(id);
  const fbModel = buildModel(db([pMk('P'), pMk('N1'), pMk('N2'), pMk('U')], []));
  const genCoords = {
    P: [
      { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
      { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
    ],
    N1: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
    N2: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
    U: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 5, gennem: 5, kuld: null }], // andet slægtled
  };

  it('markeret person UDEN bevist forælder → kandidat-kolonne med forrige slægtled (founder → moderlinjen III/11)', () => {
    const pu = { P: { grade: GRADE_FORAELDER_UKENDT, kilde: 'DAA 1939 s.97' } };
    const cols = buildCols(fbModel, 'P', [], [], genCoords, pu);
    const cand = cols.find((c) => c.candidate);
    expect(cand).toBeDefined();
    expect(cand!.kind).toBe('ancestor');
    expect(cand!.people.map((p) => p.id).sort()).toEqual(['N1', 'N2']); // U (lokal 5) medtages IKKE
    expect(cand!.label).toBe('11. slægtled · III-linjen');
    expect(cand!.candidateNote).toBe('Mulige forældre — kilden navngiver dem ikke');
    expect(cand!.kilde).toBe('DAA 1939 s.97');
    expect(cand!.kuldGroups?.['I']?.map((p) => p.id)).toEqual(['N1']);
    expect(cand!.kuldGroups?.['II']?.map((p) => p.id)).toEqual(['N2']);
  });

  it('grad "ingen forbindelse angivet" → neutral ordlyd (ikke "mulige forældre")', () => {
    const pu = { P: { grade: GRADE_INGEN_FORBINDELSE, kilde: null } };
    const cols = buildCols(fbModel, 'P', [], [], genCoords, pu);
    const cand = cols.find((c) => c.candidate);
    expect(cand!.candidateNote).toBe('Kilden angiver ingen forbindelse — andre i forrige slægtled');
    expect(cand!.kilde).toBeNull();
  });

  it('UMARKERET person (ingen parentsUnknown-entry) → INGEN kandidat-kolonne selv med genCoords', () => {
    const cols = buildCols(fbModel, 'P', [], [], genCoords, {});
    expect(cols.find((c) => c.candidate)).toBeUndefined();
  });

  it('parentsUnknown ikke sendt (5-arg-kald) → INGEN kandidat-kolonne (bagudkompatibel)', () => {
    const cols = buildCols(fbModel, 'P', [], [], genCoords);
    expect(cols.find((c) => c.candidate)).toBeUndefined();
  });

  it('markeret person MED bevist forælder → bevist ane-ring, ingen kandidat (dødende nås aldrig)', () => {
    const m = buildModel(db([P('kid'), P('far'), P('bed')], [
      { child: 'kid', parent: 'far', union: 'u' },
    ]));
    const gc = {
      kid: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 3, gennem: 3, kuld: null }],
      bed: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
    };
    const cols = buildCols(m, 'kid', [], [], gc, { kid: { grade: GRADE_FORAELDER_UKENDT, kilde: null } });
    expect(cols.find((c) => c.candidate)).toBeUndefined();
    expect(cols.find((c) => c.key === 'ancestor:1')!.people.map((p) => p.id)).toEqual(['far']);
  });

  it('unknownParentRing: markeret men uden forrige-slægtled-medlemmer → null (intet at bladre til)', () => {
    const m = buildModel(db([P('solo')], []));
    const gc = { solo: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 3, gennem: 3, kuld: null }] };
    expect(unknownParentRing(m, gc, 'solo', { grade: GRADE_FORAELDER_UKENDT, kilde: null }, 1)).toBeNull();
  });

  it('unknownParentRing: founder ved lokal 1 (intet lokal 0) → null', () => {
    const m = buildModel(db([P('f'), P('x')], []));
    const gc = {
      f: [{ sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
      x: [{ sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
    };
    expect(unknownParentRing(m, gc, 'f', { grade: GRADE_FORAELDER_UKENDT, kilde: null }, 1)).toBeNull();
  });
});

describe('unknownChildSection + nedad-projektion (efterkommer-retning)', () => {
  const build = (gKoen: Koen = 'mand') => buildModel(db(
    [P('G', { koen: gKoen }), P('A'), P('B'), P('W'), P('W2')],
    [{ child: 'A', parent: 'G', union: 'u' }, { child: 'B', parent: 'G', union: 'u' }],
  ));
  const gc = {
    G: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
    W: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
    W2: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
  };

  it('mandlig anker: børne-kolonnen augmenteres med markeret-uforbunden i næste slægtled (proveniens pr. person)', () => {
    const cols = buildCols(build(), 'G', [], [], gc, { W: { grade: GRADE_INGEN_FORBINDELSE, kilde: 'DAA 1939 s.6' } });
    const kids = cols.find((c) => c.key === 'descendant:1')!;
    expect(kids.people.map((p) => p.id).sort()).toEqual(['A', 'B']);
    expect(kids.unconnectedChildren).toHaveLength(1);
    const g = kids.unconnectedChildren![0];
    expect(g.grade).toBe(GRADE_INGEN_FORBINDELSE);
    expect(g.note).toBe('Kilden forbinder dem ikke opad — står i næste slægtled i linjen');
    expect(g.people.map((x) => x.person.id)).toEqual(['W']);
    expect(g.people[0].kilde).toBe('DAA 1939 s.6');
  });

  it('køns-gate: KVINDELIG anker → ingen nedad-sektion (patrilineært)', () => {
    const cols = buildCols(build('kvinde'), 'G', [], [], gc, { W: { grade: GRADE_INGEN_FORBINDELSE, kilde: null } });
    expect(cols.find((c) => c.key === 'descendant:1')!.unconnectedChildren).toBeUndefined();
  });

  it('bevist-forælder-eksklusion: en markeret person MED bevist forælder (sikkert barn) vises ikke som kandidat', () => {
    const cols = buildCols(build(), 'G', [], [], gc, { A: { grade: GRADE_FORAELDER_UKENDT, kilde: null } });
    expect(cols.find((c) => c.key === 'descendant:1')!.unconnectedChildren).toBeUndefined();
  });

  it('umarkeret person i næste slægtled → ingen sektion (marker-gate)', () => {
    const cols = buildCols(build(), 'G', [], [], gc, {});
    expect(cols.find((c) => c.key === 'descendant:1')!.unconnectedChildren).toBeUndefined();
  });

  it('grad-split: to grader → to grupper, "forælder ukendt" (muligt barn) FØRST, korrekt ordlyd', () => {
    const cols = buildCols(build(), 'G', [], [], gc, {
      W: { grade: GRADE_INGEN_FORBINDELSE, kilde: null },
      W2: { grade: GRADE_FORAELDER_UKENDT, kilde: 'DAA s.7' },
    });
    const groups = cols.find((c) => c.key === 'descendant:1')!.unconnectedChildren!;
    expect(groups.map((g) => g.grade)).toEqual([GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE]);
    expect(groups[0].note).toBe('Muligt barn i linjen — forælderen er ikke navngivet');
    expect(groups[0].people.map((x) => x.person.id)).toEqual(['W2']);
  });

  it('barnløs mandlig anker + markeret-uforbunden i næste slægtled → ren sektion-kolonne', () => {
    const leaf = buildModel(db([P('L', { koen: 'mand' }), P('W')], []));
    const gcLeaf = {
      L: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 3, gennem: 3, kuld: null }],
      W: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 4, gennem: 4, kuld: null }],
    };
    const cols = buildCols(leaf, 'L', [], [], gcLeaf, { W: { grade: GRADE_FORAELDER_UKENDT, kilde: null } });
    const sec = cols.find((c) => c.key === 'descendant:1:unconn')!;
    expect(sec).toBeDefined();
    expect(sec.unconnectedChildren![0].people.map((x) => x.person.id)).toEqual(['W']);
  });

  it('unknownChildSection direkte: uden parentsUnknown → tom; anden linje matcher ikke', () => {
    const m = build();
    expect(unknownChildSection(m, gc, 'G', undefined)).toEqual([]);
    const gc2 = { ...gc, W: [{ sourceId: '1', linje: 'V', lineageId: '99', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }] };
    expect(unknownChildSection(m, gc2, 'G', { W: { grade: GRADE_FORAELDER_UKENDT, kilde: null } })).toEqual([]);
  });
});
