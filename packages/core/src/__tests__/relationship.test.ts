import { buildModel } from '../buildModel';
import { computeRelationship, multiplicitetForled, relationshipLabel } from '../relationship';
import type { Db } from '../types';

const mk = (id: string, name: string) => ({ id, name, born: null, died: null, years: '', title: '', bio: '' });

// Træ:  G ─┬─ P1 ─┬─ A
//          │      └─ A2
//          └─ P2 ──── B
const db: Db = {
  persons: ['G', 'P1', 'P2', 'A', 'A2', 'B'].map((id) => mk(id, id)),
  unions: [
    { id: 'fG', p1: 'G', p2: null, p2_name: null, year: null },
    { id: 'fP1', p1: 'P1', p2: null, p2_name: null, year: null },
    { id: 'fP2', p1: 'P2', p2: null, p2_name: null, year: null },
  ],
  parentChild: [
    { child: 'P1', parent: 'G', union: 'fG' },
    { child: 'P2', parent: 'G', union: 'fG' },
    { child: 'A', parent: 'P1', union: 'fP1' },
    { child: 'A2', parent: 'P1', union: 'fP1' },
    { child: 'B', parent: 'P2', union: 'fP2' },
  ],
};
const model = buildModel(db);

describe('relationshipLabel — danske etiketter', () => {
  test('samme person / forælder-barn / bedsteforælder', () => {
    expect(relationshipLabel(0, 0)).toBe('Samme person');
    expect(relationshipLabel(0, 1)).toBe('Forælder & barn');
    expect(relationshipLabel(2, 0)).toBe('Bedsteforælder & barnebarn');
  });
  test('søskende / onkel / fætter-grader', () => {
    expect(relationshipLabel(1, 1)).toBe('Søskende');
    expect(relationshipLabel(2, 1)).toBe('Onkel/tante & niece/nevø');
    expect(relationshipLabel(2, 2)).toBe('1. grads fætter/kusine');
    expect(relationshipLabel(3, 3)).toBe('2. grads fætter/kusine');
  });
  test('forskudt fætterskab', () => {
    expect(relationshipLabel(3, 2)).toBe('1. grads fætter/kusine · 1 gang forskudt');
    expect(relationshipLabel(4, 2)).toBe('1. grads fætter/kusine · 2 gange forskudt');
  });
});

describe('computeRelationship — over et konkret træ', () => {
  test('A og B = 1. grads fætter/kusine, fælles ane G', () => {
    const r = computeRelationship(model, 'A', 'B');
    expect(r.found).toBe(true);
    expect(r.label).toBe('1. grads fætter/kusine');
    expect(r.lcaId).toBe('G');
    expect(r.lcaName).toBe('G');
  });
  test('trin-for-trin: A → P1 → G(LCA) → P2 → B', () => {
    const r = computeRelationship(model, 'A', 'B');
    expect(r.steps.map((s) => s.id)).toEqual(['A', 'P1', 'G', 'P2', 'B']);
    expect(r.steps.find((s) => s.isLca)?.id).toBe('G');
  });
  test('søskende A & A2', () => {
    expect(computeRelationship(model, 'A', 'A2').label).toBe('Søskende');
  });
  test('onkel: A & P2', () => {
    expect(computeRelationship(model, 'A', 'P2').label).toBe('Onkel/tante & niece/nevø');
  });
  test('samme person', () => {
    expect(computeRelationship(model, 'A', 'A').label).toBe('Samme person');
  });
  test('ingen påvist forbindelse mellem adskilte grene', () => {
    const r = computeRelationship(model, 'A', 'X_uden_for_traeet');
    expect(r.found).toBe(false);
  });
});

// Bilineal regression: slægtskab der KUN går via den anden forælder (mor-linjen).
// Den gamle én-forælder-kæde (parentId = primær forælder) missede dette tavst.
//
// Far-side:  Ff ── M1 ── C1
// Mor-side:  Mf ─┬─ Mor_C1 ── C1   (C1's mor)
//                └─ Mor_C2 ── C2   (C2's mor)   ⇒ C1 & C2 er 1. grads fætter/kusine via Mf
//
// Hvert barn har TO forælder-knuder; den primære (p1/far) deler ingen ane — kun mødrene gør.
describe('bilineal — slægtskab via mor-linjen', () => {
  const mk2 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '' });
  const db2: Db = {
    persons: ['Ff', 'Mf', 'M1', 'Mor_C1', 'Mor_C2', 'Far_C2', 'C1', 'C2'].map(mk2),
    unions: [
      { id: 'u_mf', p1: 'Mf', p2: null, p2_name: null, year: null },
      { id: 'u_c1', p1: 'M1', p2: 'Mor_C1', p2_name: null, year: null },
      { id: 'u_c2', p1: 'Far_C2', p2: 'Mor_C2', p2_name: null, year: null },
    ],
    parentChild: [
      { child: 'Mor_C1', parent: 'Mf', union: 'u_mf' },
      { child: 'Mor_C2', parent: 'Mf', union: 'u_mf' },
      // C1 har far M1 (p1, primær) + mor Mor_C1 (p2). Kun moren forbinder til Mf.
      { child: 'C1', parent: 'M1', union: 'u_c1' },
      { child: 'C1', parent: 'Mor_C1', union: 'u_c1' },
      // C2 har far Far_C2 (p1, primær) + mor Mor_C2 (p2).
      { child: 'C2', parent: 'Far_C2', union: 'u_c2' },
      { child: 'C2', parent: 'Mor_C2', union: 'u_c2' },
    ],
  };
  const m2 = buildModel(db2);

  test('C1 & C2 = 1. grads fætter/kusine via fælles morfar Mf', () => {
    const r = computeRelationship(m2, 'C1', 'C2');
    expect(r.found).toBe(true);
    expect(r.label).toBe('1. grads fætter/kusine');
    expect(r.lcaId).toBe('Mf');
  });
  test('stien går gennem mødrene: C1 → Mor_C1 → Mf → Mor_C2 → C2', () => {
    const r = computeRelationship(m2, 'C1', 'C2');
    expect(r.steps.map((s) => s.id)).toEqual(['C1', 'Mor_C1', 'Mf', 'Mor_C2', 'C2']);
  });
  test('C1 & sin egen mor = forælder & barn (via p2-forælder)', () => {
    expect(computeRelationship(m2, 'C1', 'Mor_C1').label).toBe('Forælder & barn');
  });
});

// Pedigree collapse / fætter-ægteskab: to personer forbundet ad FLERE linjer.
// MRCA skal vælge den NÆRMESTE fælles ane (mindste samlede afstand), ikke en fjernere.
//
//        Old ──┬── P ─────── S        (S = barn af P)
//              └── Q ──┬──── D         (D = barnebarn: Q→R→D)
//                      R ────┘
// S og D deler den nære ane P/Q-forælder? Nej — konstruér klart:
//   G ─┬─ S            (S barn af G)
//      └─ R ── D       (D barn af R, R barn af G)  ⇒ S & D via G: onkel/niece
//   men D har OGSÅ S som forælder gennem en anden union ⇒ nærmere ane vinder.
describe('MRCA vælger nærmeste fælles ane', () => {
  const mk3 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '' });
  const db3: Db = {
    persons: ['G', 'S', 'R', 'D'].map(mk3),
    unions: [
      { id: 'g', p1: 'G', p2: null, p2_name: null, year: null },
      { id: 'sd', p1: 'S', p2: null, p2_name: null, year: null },
      { id: 'rd', p1: 'R', p2: null, p2_name: null, year: null },
    ],
    parentChild: [
      { child: 'S', parent: 'G', union: 'g' },
      { child: 'R', parent: 'G', union: 'g' },
      // D er barn af BÅDE S (nær) og R (som selv er barn af G).
      { child: 'D', parent: 'S', union: 'sd' },
      { child: 'D', parent: 'R', union: 'rd' },
    ],
  };
  const m3 = buildModel(db3);

  test('S & D: nærmeste ane er S selv (forælder & barn), ikke G', () => {
    const r = computeRelationship(m3, 'S', 'D');
    expect(r.label).toBe('Forælder & barn');
    expect(r.lcaId).toBe('S');
  });
});

// Anepar = én linje: helsøskende deler BÅDE far og mor, men skal vises som ÉN "Søskende",
// ikke to identiske linjer. Halvsøskende deler kun den ene forælder (begge andre kendt).
describe('anepar-collapse + halv-relationer', () => {
  const mk4 = (id: string, koen?: 'mand' | 'kvinde') =>
    ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', koen: koen ?? null });
  // Far + Mor → S1, S2 (helsøskende).  Far + Mor2 → H (halvsøskende til S1/S2).
  const db4: Db = {
    persons: [mk4('Far', 'mand'), mk4('Mor', 'kvinde'), mk4('Mor2', 'kvinde'), mk4('S1', 'mand'), mk4('S2', 'kvinde'), mk4('H', 'mand')],
    unions: [
      { id: 'u1', p1: 'Far', p2: 'Mor', p2_name: null, year: null },
      { id: 'u2', p1: 'Far', p2: 'Mor2', p2_name: null, year: null },
    ],
    parentChild: [
      { child: 'S1', parent: 'Far', union: 'u1' },
      { child: 'S1', parent: 'Mor', union: 'u1' },
      { child: 'S2', parent: 'Far', union: 'u1' },
      { child: 'S2', parent: 'Mor', union: 'u1' },
      { child: 'H', parent: 'Far', union: 'u2' },
      { child: 'H', parent: 'Mor2', union: 'u2' },
    ],
  };
  const m4 = buildModel(db4);

  test('helsøskende S1 & S2 = ÉN linje (anepar Far & Mor), ikke to', () => {
    const r = computeRelationship(m4, 'S1', 'S2');
    expect(r.lines).toHaveLength(1);
    expect(r.lines[0].coupleNames).toBe('Far & Mor');
    expect(r.lines[0].half).toBe(false);
  });
  test('helsøskende: kønsbestemt "Bror & søster"', () => {
    expect(computeRelationship(m4, 'S1', 'S2').label).toBe('Bror & søster');
  });
  test('halvsøskende S1 & H (kun fælles far) = "Halvbrødre"', () => {
    const r = computeRelationship(m4, 'S1', 'H');
    expect(r.lines).toHaveLength(1);
    expect(r.lines[0].half).toBe(true);
    expect(r.label).toBe('Halvbrødre');
  });
});

// Dobbelt-fætterskab (to brødre gift med to søstre) — den klassiske adels-konfiguration:
// A & B er beslægtet ad TO uafhængige anepar-linjer samtidig (far-siden + mor-siden).
// Begge linjer skal med, hver som ÉT anepar (ikke fire enkelt-aner).
describe('multi-linje — dobbelt fætterskab', () => {
  const mk5 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', koen: null });
  // Far-par Ffa+Ffk → fa, fb (brødre).  Mor-par Mfa+Mfk → ma, mb (søstre).
  // fa+ma → A ; fb+mb → B   ⇒ A,B = dobbelt 1. grads fætre.
  const db5: Db = {
    persons: ['Ffa', 'Ffk', 'Mfa', 'Mfk', 'fa', 'fb', 'ma', 'mb', 'A', 'B'].map(mk5),
    unions: [
      { id: 'upf', p1: 'Ffa', p2: 'Ffk', p2_name: null, year: null },
      { id: 'upm', p1: 'Mfa', p2: 'Mfk', p2_name: null, year: null },
      { id: 'ua', p1: 'fa', p2: 'ma', p2_name: null, year: null },
      { id: 'ub', p1: 'fb', p2: 'mb', p2_name: null, year: null },
    ],
    parentChild: [
      { child: 'fa', parent: 'Ffa', union: 'upf' },
      { child: 'fa', parent: 'Ffk', union: 'upf' },
      { child: 'fb', parent: 'Ffa', union: 'upf' },
      { child: 'fb', parent: 'Ffk', union: 'upf' },
      { child: 'ma', parent: 'Mfa', union: 'upm' },
      { child: 'ma', parent: 'Mfk', union: 'upm' },
      { child: 'mb', parent: 'Mfa', union: 'upm' },
      { child: 'mb', parent: 'Mfk', union: 'upm' },
      { child: 'A', parent: 'fa', union: 'ua' },
      { child: 'A', parent: 'ma', union: 'ua' },
      { child: 'B', parent: 'fb', union: 'ub' },
      { child: 'B', parent: 'mb', union: 'ub' },
    ],
  };
  const m5 = buildModel(db5);

  test('samme afstand ad to anepar → slås sammen til ÉN "Dobbelt"-linje', () => {
    const r = computeRelationship(m5, 'A', 'B');
    expect(r.lines).toHaveLength(1);
    expect(r.lines[0].multiplicitet).toBe(2);
    expect(r.label).toBe('Dobbelt 1. grads fætter/kusine');
  });
  test('begge anepar listes på den sammenslåede linje', () => {
    const r = computeRelationship(m5, 'A', 'B');
    expect(r.lines[0].aner).toHaveLength(2);
    // Far-parret (Ffa & Ffk) og mor-parret (Mfa & Mfk), uanset rækkefølge.
    expect(r.lines[0].aner.join(' | ')).toMatch(/Ffa & Ffk/);
    expect(r.lines[0].aner.join(' | ')).toMatch(/Mfa & Mfk/);
    expect(r.lines[0].half).toBe(false);
  });
  test('korroboration: to kant-disjunkte stier → uafhaengige === 2', () => {
    // Far-side (A→fa→…→fb→B) og mor-side (A→ma→…→mb→B) deler ingen kant.
    expect(computeRelationship(m5, 'A', 'B').lines[0].uafhaengige).toBe(2);
  });
});

describe('korroboration — enkelt linje er ikke bekræftet', () => {
  // Genbrug det simple træ fra toppen: A & B er fætre via ÉN fælles ane G (én sti).
  test('enkelt forbindelse → uafhaengige === 1', () => {
    expect(computeRelationship(model, 'A', 'B').lines[0].uafhaengige).toBe(1);
  });
});

describe('multiplicitetForled', () => {
  test('1 → tomt, 2 → Dobbelt, 3 → Tredobbelt, 6 → Seksdobbelt', () => {
    expect(multiplicitetForled(1)).toBe('');
    expect(multiplicitetForled(2)).toBe('Dobbelt');
    expect(multiplicitetForled(3)).toBe('Tredobbelt');
    expect(multiplicitetForled(6)).toBe('Seksdobbelt');
  });
  test('>6 falder tilbage til "N-dobbelt"', () => {
    expect(multiplicitetForled(7)).toBe('7-dobbelt');
  });
});

// Konfidens på stien: svageste led flager usikkerhed (invariant #7) uden at lade
// uangivne led larme. Konfidens sidder på barnets link (parentChild.konfidens).
describe('konfidens på stien — svageste led', () => {
  const mk6 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', koen: null });
  //  G ─┬─ P1 ── A
  //     └─ P2 ── B     (A,B fætre via G)
  const tree = (bLink: 'sikker' | 'sandsynlig' | 'formodet' | 'omstridt' | undefined, extra: Partial<Db> = {}): Db => ({
    persons: ['G', 'P1', 'P2', 'A', 'B'].map(mk6),
    unions: [
      { id: 'fG', p1: 'G', p2: null, p2_name: null, year: null },
      { id: 'fP1', p1: 'P1', p2: null, p2_name: null, year: null },
      { id: 'fP2', p1: 'P2', p2: null, p2_name: null, year: null },
    ],
    parentChild: [
      { child: 'P1', parent: 'G', union: 'fG' },
      { child: 'P2', parent: 'G', union: 'fG' },
      { child: 'A', parent: 'P1', union: 'fP1' },
      { child: 'B', parent: 'P2', union: 'fP2', konfidens: bLink },
    ],
    ...extra,
  });

  test('ren sti (ingen konfidens) → usikker=false, weakest=null', () => {
    const r = computeRelationship(buildModel(tree(undefined)), 'A', 'B');
    expect(r.lines[0].usikker).toBe(false);
    expect(r.lines[0].weakestKonfidens).toBeNull();
  });
  test('formodet led → usikker=true, weakest=formodet, og kanten sidder på B-trinnet', () => {
    const r = computeRelationship(buildModel(tree('formodet')), 'A', 'B');
    expect(r.lines[0].usikker).toBe(true);
    expect(r.lines[0].weakestKonfidens).toBe('formodet');
    expect(r.steps.find((s) => s.id === 'B')?.edgeKonfidens).toBe('formodet');
  });
  test('sikker led flager IKKE usikkerhed', () => {
    const r = computeRelationship(buildModel(tree('sikker')), 'A', 'B');
    expect(r.lines[0].weakestKonfidens).toBe('sikker');
    expect(r.lines[0].usikker).toBe(false);
  });
  test('omstridt er svagere end formodet (svageste vinder)', () => {
    // Tilføj et formodet led højere oppe (A→P1) sammen med et omstridt (B→P2).
    const db = tree('omstridt');
    db.parentChild = db.parentChild.map((pc) =>
      pc.child === 'A' && pc.parent === 'P1' ? { ...pc, konfidens: 'formodet' as const } : pc,
    );
    const r = computeRelationship(buildModel(db), 'A', 'B');
    expect(r.lines[0].weakestKonfidens).toBe('omstridt');
  });
  test('samme kant med flere påstande → STÆRKESTE bevares', () => {
    const db = tree('formodet');
    db.parentChild.push({ child: 'B', parent: 'P2', union: 'fP2', konfidens: 'sikker' });
    const r = computeRelationship(buildModel(db), 'A', 'B');
    expect(r.lines[0].weakestKonfidens).toBe('sikker');
    expect(r.lines[0].usikker).toBe(false);
  });
});

// Kønsbestemte moderne etiketter (relationshipLabel med koen-opts).
describe('kønsbestemte etiketter', () => {
  test('fætter/kusine efter køn', () => {
    expect(relationshipLabel(2, 2, { koenA: 'mand', koenB: 'mand' })).toBe('1. grads fætre');
    expect(relationshipLabel(2, 2, { koenA: 'kvinde', koenB: 'kvinde' })).toBe('1. grads kusiner');
    expect(relationshipLabel(2, 2, { koenA: 'mand', koenB: 'kvinde' })).toBe('1. grads fætter & kusine');
  });
  test('onkel & niece efter køn (ældre = mindst afstand)', () => {
    expect(relationshipLabel(1, 2, { koenA: 'mand', koenB: 'kvinde' })).toBe('Onkel & niece');
    expect(relationshipLabel(2, 1, { koenA: 'kvinde', koenB: 'mand' })).toBe('Onkel & niece');
  });
  test('forælder & barn efter køn (anen = afstand 0)', () => {
    expect(relationshipLabel(0, 1, { koenA: 'kvinde', koenB: 'mand' })).toBe('Mor & søn');
    expect(relationshipLabel(1, 0, { koenA: 'mand', koenB: 'kvinde' })).toBe('Mor & søn');
  });
  test('ukendt køn falder tilbage til neutrale strenge', () => {
    expect(relationshipLabel(2, 2)).toBe('1. grads fætter/kusine');
    expect(relationshipLabel(1, 2)).toBe('Onkel/tante & niece/nevø');
  });
});

// Dybe direkte linjer (olde/tipolde/efterkommer) + køn på anen — sjældnere afstande
// der ikke rammes af det lille test-træ, men som etiket-tabellen skal levere korrekt.
describe('relationshipLabel — dybe & kønnede direkte linjer', () => {
  test('olde/tipolde/efterkommer (neutral)', () => {
    expect(relationshipLabel(0, 3)).toBe('Oldeforælder & oldebarn');
    expect(relationshipLabel(4, 0)).toBe('Tipoldeforælder & tipoldebarn');
    expect(relationshipLabel(0, 5)).toBe('Tip-tipoldeforælder & efterkommer');
  });
  test('køn på anen (anen = afstand 0)', () => {
    expect(relationshipLabel(0, 1, { koenA: 'mand' })).toBe('Far & barn');
    expect(relationshipLabel(2, 0, { koenB: 'kvinde' })).toBe('Bedstemor & barnebarn');
    expect(relationshipLabel(0, 3, { koenA: 'kvinde' })).toBe('Oldemor & oldebarn');
    expect(relationshipLabel(0, 4, { koenA: 'mand' })).toBe('Tipoldefar & tipoldebarn');
  });
  test('søn/datter efter efterkommerens køn (anen = afstand 0-siden)', () => {
    expect(relationshipLabel(0, 1, { koenA: 'kvinde', koenB: 'mand' })).toBe('Mor & søn');
    expect(relationshipLabel(1, 0, { koenA: 'kvinde', koenB: 'kvinde' })).toBe('Mor & datter');
    expect(relationshipLabel(1, 0, { koenA: 'kvinde' })).toBe('Forælder & datter'); // anens køn ukendt
  });
});

// Grandonkel-planet (rem===2) + halv-suffiks på onkel- og fætter-etiketter.
describe('relationshipLabel — grandonkel & halv-suffiks', () => {
  test('grandonkel/-tante & grandnevø/-niece', () => {
    expect(relationshipLabel(1, 3)).toBe('Grandonkel/-tante & grandniece/-nevø');
    expect(relationshipLabel(1, 3, { koenA: 'mand', koenB: 'kvinde' })).toBe('Grandonkel & grandniece');
    expect(relationshipLabel(3, 1, { koenA: 'kvinde', koenB: 'mand' })).toBe('Grandonkel & grandniece');
  });
  test('halv-suffiks på onkel og fætter', () => {
    expect(relationshipLabel(1, 2, { half: true })).toBe('Onkel/tante & niece/nevø (halv)');
    expect(relationshipLabel(2, 2, { half: true })).toBe('1. grads fætter/kusine (halv)');
    expect(relationshipLabel(1, 3, { half: true })).toBe('Grandonkel/-tante & grandniece/-nevø (halv)');
  });
});

// alternativSolidLinje: NÆRMESTE linje hviler på et svagt led, men en FJERNERE linje
// bekræfter slægtskabet solidt — flaget løfter usikkerheden uden at skjule den.
//   Nær (usikker): A & B er 1. grads fætre via G, men B→Pb-leddet er omstridt.
//   Fjern (solid): A & B er 2. grads fætre via K, alle led uangivne (ingen svaghed).
// NB: et barns to forældre SKAL dele union (buildModel tager kun forældre fra første
// union), så A og B har hver ÉT forælder-par-union (uA/uB).
describe('alternativSolidLinje — fjernere solid linje bekræfter', () => {
  const mk7 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', koen: null });
  const single = (id: string) => ({ id, p1: id, p2: null, p2_name: null, year: null });
  const db7: Db = {
    persons: ['A', 'B', 'Pa', 'Pb', 'Qa', 'Qb', 'Ra', 'Rb', 'G', 'K'].map(mk7),
    unions: [
      { id: 'uA', p1: 'Pa', p2: 'Qa', p2_name: null, year: null },
      { id: 'uB', p1: 'Pb', p2: 'Qb', p2_name: null, year: null },
      ...['Ra', 'Rb', 'G', 'K'].map(single),
    ],
    parentChild: [
      { child: 'A', parent: 'Pa', union: 'uA' },
      { child: 'A', parent: 'Qa', union: 'uA' },
      { child: 'B', parent: 'Pb', union: 'uB', konfidens: 'omstridt' },
      { child: 'B', parent: 'Qb', union: 'uB' },
      { child: 'Pa', parent: 'G', union: 'uPa' },
      { child: 'Pb', parent: 'G', union: 'uPb' },
      { child: 'Qa', parent: 'Ra', union: 'uQa' },
      { child: 'Qb', parent: 'Rb', union: 'uQb' },
      { child: 'Ra', parent: 'K', union: 'uRa' },
      { child: 'Rb', parent: 'K', union: 'uRb' },
    ],
  };
  const m7 = buildModel(db7);

  test('nærmeste linje usikker, fjernere solid → alternativSolidLinje=true', () => {
    const r = computeRelationship(m7, 'A', 'B');
    expect(r.lines[0].label).toBe('1. grads fætter/kusine');
    expect(r.lines[0].usikker).toBe(true);
    expect(r.alternativSolidLinje).toBe(true);
    expect(r.lines.some((l) => !l.usikker && l.label === '2. grads fætter/kusine')).toBe(true);
  });
});

// Korroboration med DELT mellem-knude: to lige-fjerne linjer der deler en mellem-PERSON
// er ikke uafhængig bekræftelse (Mengers definition). multiplicitet=2, men uafhaengige=1.
//   A's eneste forælder N nedstammer fra to IKKE-gifte aner G1, G2 (via N's forælder-par
//   P1 & P2). B nedstammer fra både G1 og G2 ad hver sin gren. Begge linjer går gennem N.
describe('korroboration — delt mellem-knude tæller ikke som uafhængig', () => {
  const mk8 = (id: string) => ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', koen: null });
  const single = (id: string) => ({ id, p1: id, p2: null, p2_name: null, year: null });
  const db8: Db = {
    persons: ['A', 'B', 'N', 'P1', 'P2', 'Q1', 'Q2', 'G1', 'G2'].map(mk8),
    unions: [
      { id: 'uN', p1: 'P1', p2: 'P2', p2_name: null, year: null }, // N's forælder-par
      { id: 'uB', p1: 'Q1', p2: 'Q2', p2_name: null, year: null }, // B's forælder-par
      ...['G1', 'G2'].map(single), // G1 & G2 er IKKE ægtefæller → to distinkte linjer
    ],
    parentChild: [
      { child: 'A', parent: 'N', union: 'uA' },
      { child: 'N', parent: 'P1', union: 'uN' },
      { child: 'N', parent: 'P2', union: 'uN' },
      { child: 'P1', parent: 'G1', union: 'uP1' },
      { child: 'P2', parent: 'G2', union: 'uP2' },
      { child: 'B', parent: 'Q1', union: 'uB' },
      { child: 'B', parent: 'Q2', union: 'uB' },
      { child: 'Q1', parent: 'G1', union: 'uQ1' },
      { child: 'Q2', parent: 'G2', union: 'uQ2' },
    ],
  };
  const m8 = buildModel(db8);

  test('to linjer i samme afstand → multiplicitet=2, men delt N ⇒ uafhaengige=1', () => {
    const r = computeRelationship(m8, 'A', 'B');
    expect(r.lines[0].multiplicitet).toBe(2);
    expect(r.lines[0].uafhaengige).toBe(1);
    // Begge stier deler mellem-knuden N.
    expect(r.lines[0].steps.map((s) => s.id)).toContain('N');
  });
});
