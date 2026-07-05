import { buildModel } from '../buildModel';
import { buildBidirectionalColumns, buildSearch, buildSnapPath, columnLabel, routeToMe, searchPool, treeFocusA, wayToMe } from '../selectors';
import type { Db } from '../types';
import type { SearchItem } from '../selectors';

// NB: initialOf bruger efternavn (sidst token) — testfixture bruger Æbeltoft som efternavn
// for at POOL-grupperne reelt inkluderer 'Æ' sidst i dansk orden (brief antog fornavn-gruppering).
const POOL: SearchItem[] = [
  { id: '1', name: 'Conrad Reventlow', years: '1644–1708', born: 1644 },
  { id: '2', name: 'Anne Reventlow', years: '1680–1740', born: 1680 },
  { id: '3', name: 'Ingrid Æbeltoft', years: '1600–1650', born: 1600 },
];

test('searchPool: query filtrerer på navn (case-insensitiv)', () => {
  const r = searchPool(POOL, { query: 'anne', sort: 'alpha', activeLetter: null });
  expect(r.matches.map((m) => m.id)).toEqual(['2']);
});

test('searchPool: born-sort sorterer på fødeår, alfabet-bar skjult', () => {
  const r = searchPool(POOL, { query: '', sort: 'born', activeLetter: null });
  expect(r.matches.map((m) => m.born)).toEqual([1600, 1644, 1680]);
  expect(r.showLetters).toBe(false);
});

test('searchPool: dansk alfabet — Æ sidst i grupper', () => {
  const r = searchPool(POOL, { query: '', sort: 'alpha', activeLetter: null });
  expect(r.groups[r.groups.length - 1].letter).toBe('Æ');
});

test('buildSearch-wrapper giver samme matches som searchPool på model.persons', () => {
  const model = { persons: [{ id: '9', name: 'Test Person', years: '1700', born: 1700 }] } as never;
  const viaWrapper = buildSearch(model, { query: '', sort: 'alpha', activeLetter: null });
  const viaPool = searchPool([{ id: '9', name: 'Test Person', years: '1700', born: 1700 }],
    { query: '', sort: 'alpha', activeLetter: null });
  expect(viaWrapper.matches).toEqual(viaPool.matches);
});

const mk = (id: string, name: string, born: number | null = null) => ({
  id,
  name,
  born,
  died: null,
  years: born ? `* ${born}` : '',
  title: '',
  bio: '',
});

const db: Db = {
  persons: [
    mk('1', 'Conrad Reventlow', 1644),
    mk('2', 'Anne Ahlefeldt', 1650),
    mk('3', 'Bent Østergaard', 1670),
    mk('4', 'Åse Bang', 1700),
  ],
  unions: [{ id: 'f1', p1: '1', p2: '2', p2_name: null, year: null }],
  parentChild: [
    { child: '3', parent: '1', union: 'f1' },
    { child: '4', parent: '1', union: 'f1' },
  ],
};
const model = buildModel(db);

describe('buildSearch — §9.1 alfabet-hop', () => {
  test('alfabetisk uden query: bygger forekommende bogstaver i dansk orden (Å sidst)', () => {
    const r = buildSearch(model, { query: '', sort: 'alpha', activeLetter: null });
    // efternavne: Reventlow(R), Ahlefeldt(A), Østergaard(Ø), Bang(B)
    expect(r.showLetters).toBe(true);
    expect(r.letters.map((l) => l.label)).toEqual(['Alle', 'A', 'B', 'R', 'Ø']);
  });

  test('grupper har sticky-bogstaver i dansk orden', () => {
    const r = buildSearch(model, { query: '', sort: 'alpha', activeLetter: null });
    expect(r.groups.map((g) => g.letter)).toEqual(['A', 'B', 'R', 'Ø']);
  });

  test('activeLetter filtrerer på efternavns-initial', () => {
    const r = buildSearch(model, { query: '', sort: 'alpha', activeLetter: 'Ø' });
    expect(r.matches.map((m) => m.name)).toEqual(['Bent Østergaard']);
  });

  test('fødeår-sort skjuler alfabet-bar og sorterer efter born', () => {
    const r = buildSearch(model, { query: '', sort: 'born', activeLetter: null });
    expect(r.showLetters).toBe(false);
    expect(r.groups).toEqual([]);
    expect(r.matches.map((m) => m.born)).toEqual([1644, 1650, 1670, 1700]);
  });

  test('query skjuler alfabet-bar og filtrerer på navn', () => {
    const r = buildSearch(model, { query: 'reven', sort: 'alpha', activeLetter: null });
    expect(r.showLetters).toBe(false);
    expect(r.matches.map((m) => m.name)).toEqual(['Conrad Reventlow']);
  });
});

describe('treeFocusA — variant A fokus', () => {
  test('søskende = forælderens børn; børn = fokus-personens børn', () => {
    const v = treeFocusA(model, '3');
    expect(v.parent?.id).toBe('1');
    expect(v.siblings.map((s) => s.id).sort()).toEqual(['3', '4']);
  });

  test('rod uden forælder: kun personen selv som "søskende"', () => {
    const v = treeFocusA(model, '1');
    expect(v.parent).toBeNull();
    expect(v.siblings.map((s) => s.id)).toEqual(['1']);
    expect(v.children.map((c) => c.id).sort()).toEqual(['3', '4']);
  });
});

describe('buildSnapPath — variant C lodret linje', () => {
  test('aner-til-fokus + første-barn-hale; depth peger på fokus', () => {
    const r = buildSnapPath(model, '3', '1');
    // 3's forælder er 1 → up=[1,3]; 3 har ingen børn → path=[1,3], depth=1 (fokus=3)
    expect(r.path).toEqual(['1', '3']);
    expect(r.depth).toBe(1);
  });
  test('fra roden: depth 0 + ned ad første barn', () => {
    const r = buildSnapPath(model, '1', '1');
    expect(r.depth).toBe(0);
    expect(r.path[0]).toBe('1');
    expect(r.path[1]).toBe('3'); // første barn
  });
});

describe('buildBidirectionalColumns — variant B (bidirektionel)', () => {
  test('anker med børn, ingen forældre: [Fokus, Børn]', () => {
    const cols = buildBidirectionalColumns(model, '1', [], []);
    expect(cols.map((c) => c.key)).toEqual(['anchor:0', 'descendant:1']);
    expect(cols[1].label).toBe('Børn');
    expect(cols[1].people.map((p) => p.id).sort()).toEqual(['3', '4']);
    expect(cols[1].selectedId).toBeNull();
  });
  test('anker med forælder, ingen børn: [Forældre, Fokus]', () => {
    const cols = buildBidirectionalColumns(model, '3', [], []);
    expect(cols.map((c) => c.key)).toEqual(['ancestor:1', 'anchor:0']);
    expect(cols[0].label).toBe('Forældre');
    expect(cols[0].people.map((p) => p.id)).toEqual(['1']);
  });
  test('efterkommer-drill markerer selected + stopper ved barnløs', () => {
    const cols = buildBidirectionalColumns(model, '1', [], ['3']);
    expect(cols.find((c) => c.key === 'descendant:1')!.selectedId).toBe('3');
    expect(cols.some((c) => c.key === 'descendant:2')).toBe(false); // 3 er barnløs
  });
  test('kolonne-keys er kollisionsfri', () => {
    const cols = buildBidirectionalColumns(model, '1', [], ['3']);
    const keys = cols.map((c) => c.key);
    expect(new Set(keys).size).toBe(keys.length);
  });
});

describe('fallback-ring — spejler web/src/data/tree.ts (Task C2, post-B3 design-justering)', () => {
  // Minimal model: anker P (V, lokal 1, founder) uden beviste forældre; to naboer i III lokal 11.
  // genCoords sendes som EKSPLICIT 5. arg — IKKE på model (mobils Model bærer bevidst ikke
  // genCoordsByPerson; byggeren skal være platform-agnostisk, jf. web/src/data/tree.ts).
  const fbDb: Db = { persons: [mk('P', 'P'), mk('A', 'A'), mk('B', 'B')], unions: [], parentChild: [] };
  const fbModel = buildModel(fbDb);

  test('bygger en founder-hop fallback-ring når aner-ringen er tom', () => {
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

  test('uden genCoords: ingen fallback-ring (bagudkompatibel 4-arg-kald)', () => {
    const cols = buildBidirectionalColumns(fbModel, 'P', [], []);
    expect(cols.find((c) => c.fallback)).toBeUndefined();
  });

  test('scoper ringen til samme kilde (udgave) — samme (linje,lokal) men anden sourceId medtages IKKE (F2, dual-review 2026-07-05)', () => {
    const fbDb2: Db = { persons: [mk('P', 'P'), mk('A', 'A'), mk('B', 'B'), mk('D', 'D')], unions: [], parentChild: [] };
    const fbModel2 = buildModel(fbDb2);
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

// Wayfinder-fixture: 1 ┬ 2 ┬ 4
//                     │   └ 7
//                     └ 3 ── 5      (6 = isoleret, egen rod)
const wayDb: Db = {
  persons: [
    mk('1', 'Rod Reventlow', 1644),
    mk('2', 'Andet led A', 1670),
    mk('3', 'Andet led B', 1672),
    mk('4', 'Tredje led A', 1700),
    mk('7', 'Tredje led B', 1702),
    mk('5', 'Tredje led C', 1704),
    mk('6', 'Fremmed slægt', 1680),
  ],
  unions: [{ id: 'u1', p1: '1', p2: null, p2_name: null, year: null }],
  parentChild: [
    { child: '2', parent: '1', union: 'u1' },
    { child: '3', parent: '1', union: 'u1' },
    { child: '4', parent: '2', union: 'u1' },
    { child: '7', parent: '2', union: 'u1' },
    { child: '5', parent: '3', union: 'u1' },
  ],
};
const wayModel = buildModel(wayDb);
// snapPath for fokus=4: anekæde [1,2,4] + tom hale → depth 2
const path124 = buildSnapPath(wayModel, '4', '1'); // { path:['1','2','4'], depth:2 }
// snapPath for fokus=1: [1] + førstefødt-hale [2,4] → depth 0
const path1 = buildSnapPath(wayModel, '1', '1');    // { path:['1','2','4'], depth:0 }

describe('wayToMe — vej til mig i Spor', () => {
  test('fokus == mig → arrived', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '4')).toEqual({ step: 'arrived', remaining: 0 });
  });

  test('mig er ane til fokus → up, antal generationer', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '1')).toEqual({ step: 'up', remaining: 2 });
  });

  test('mig er fætter (forgrening m. søskendeskift) → up først, 3 spring', () => {
    // fokus=4 (depth2), mig=5: op til depth1, skift 2→3 (right), ned til 5
    expect(wayToMe(wayModel, path124.path, path124.depth, '5')).toEqual({ step: 'up', remaining: 3 });
  });

  test('mig er førstefødt-efterkommer på linjen → down', () => {
    // fokus=1 (depth0), mig=4: ned, ned
    expect(wayToMe(wayModel, path1.path, path1.depth, '4')).toEqual({ step: 'down', remaining: 2 });
  });

  test('mig er efterkommer men ikke på førstefødt-hale → down først, søskende-trin tælles', () => {
    // fokus=1 (depth0), mig=7: ned (→2), ned (→førstefødt 4), right (4→7)
    expect(wayToMe(wayModel, path1.path, path1.depth, '7')).toEqual({ step: 'down', remaining: 3 });
  });

  test('mig uden fælles ane → null', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, '6')).toBeNull();
  });

  test('mig findes ikke i model → null', () => {
    expect(wayToMe(wayModel, path124.path, path124.depth, 'ukendt')).toBeNull();
  });

  test('mig kræver søskendeskift mod tidligere-født → left', () => {
    // fokus=3 (depth1, snapPath [1,3,5]), mig=2: søskendeskift 3→2 (tidligere-født) = left
    const path3 = buildSnapPath(wayModel, '3', '1');
    expect(wayToMe(wayModel, path3.path, path3.depth, '2')).toEqual({ step: 'left', remaining: 1 });
  });

  test('mig under ikke-førstefødt gren, dybere end synlig hale → down, 3', () => {
    // fokus=1 (depth0, hale [1,2,4]), mig=5 under søskende 3: ned, søskendeskift, ned
    expect(wayToMe(wayModel, path1.path, path1.depth, '5')).toEqual({ step: 'down', remaining: 3 });
  });
});

describe('routeToMe — hele rute-planen til mig (rute-tegning)', () => {
  test('fokus == mig → tom plan', () => {
    expect(routeToMe(wayModel, path124.path, path124.depth, '4')).toEqual([]);
  });

  test('mig er ane → op, op', () => {
    expect(routeToMe(wayModel, path124.path, path124.depth, '1')).toEqual(['up', 'up']);
  });

  test('mig er fætter (forgrening) → op, højre, ned', () => {
    expect(routeToMe(wayModel, path124.path, path124.depth, '5')).toEqual(['up', 'right', 'down']);
  });

  test('mig er førstefødt-efterkommer → ned, ned', () => {
    expect(routeToMe(wayModel, path1.path, path1.depth, '4')).toEqual(['down', 'down']);
  });

  test('mig under ikke-førstefødt gren → ned, ned, højre', () => {
    expect(routeToMe(wayModel, path1.path, path1.depth, '7')).toEqual(['down', 'down', 'right']);
  });

  test('søskendeskift mod tidligere-født → left', () => {
    const path3 = buildSnapPath(wayModel, '3', '1');
    expect(routeToMe(wayModel, path3.path, path3.depth, '2')).toEqual(['left']);
  });

  test('mig uden fælles ane → null', () => {
    expect(routeToMe(wayModel, path124.path, path124.depth, '6')).toBeNull();
  });

  test('mig ligger på snapPath under fokus (scrollet op) → ren lodret, ingen falske søskendeskift', () => {
    // snapPath = mig's egen linje [1,3,5]; fokus=1 (depth0); mig=5 ligger på stien i dybde 2.
    // (3 er IKKE 1's førstefødte — gammel logik lagde fejlagtigt et søskendeskift ind.)
    expect(routeToMe(wayModel, ['1', '3', '5'], 0, '5')).toEqual(['down', 'down']);
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
