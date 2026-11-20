import { buildModel } from '../buildModel';
import { collapseSameAs } from '../collapseSameAs';
import { computeRelationship } from '../relationship';
import type { AppPerson, Db, Konfidens } from '../types';

const person = (id: string, extra: Partial<AppPerson> = {}): AppPerson => ({
  id, name: `Anna ${id}`, born: null, died: null, years: '', title: '', bio: '', privat: false, ...extra,
});

describe('review37 M1 — række-id er ikke bevis for halvslægtskab', () => {
  test.each([
    ['ulinkede mødre med samme navn og overlappende spænd', false, false],
    ['samme persons to rækker bliver aldrig halvbrødre', true, false],
    ['manglende datoer beviser ikke forskellige mødre', false, true],
  ])('%s', (_label, sammeBarn, udenDatoer) => {
    const db: Db = {
      persons: [
        person('f1', { name: 'Bent B', koen: 'mand' }), person('f2', { name: 'Bent B', koen: 'mand' }),
        person('m1', { name: 'Anna A', born: udenDatoer ? null : 1820, foedtSpaend: udenDatoer ? null : [1818, 1822] }),
        person('m2', { name: 'Anna A', born: udenDatoer ? null : 1821, foedtSpaend: udenDatoer ? null : [1820, 1824] }),
        person('a', { name: 'Dan D', born: 1850, koen: 'mand' }),
        person('b', { name: sammeBarn ? 'Dan D' : 'Emil E', born: 1850, koen: 'mand' }),
      ],
      unions: [
        { id: 'u1', p1: 'f1', p2: 'm1', p2_name: null, year: null },
        { id: 'u2', p1: 'f2', p2: 'm2', p2_name: null, year: null },
      ],
      parentChild: [
        { child: 'a', parent: 'f1', union: 'u1' }, { child: 'a', parent: 'm1', union: 'u1' },
        { child: 'b', parent: 'f2', union: 'u2' }, { child: 'b', parent: 'm2', union: 'u2' },
      ],
    };
    const collapsed = collapseSameAs(db, [{ alias: 'f2', canonical: 'f1' }], new Map());
    expect(collapsed.quarantined).toEqual([]);
    const r = computeRelationship(buildModel(collapsed.db), 'a', 'b');
    expect(r.label).toBe('Brødre');
    expect(r.lines.every((l) => !l.half)).toBe(true);
  });
});

function siblings(motherA: string, motherB: string, koenA: AppPerson['koen'] = null, koenB: AppPerson['koen'] = null) {
  return buildModel({
    persons: [
      person('f', { name: 'Bent B', born: 1800, died: 1880, koen: 'mand' }),
      person('m1', { name: motherA, born: 1805, died: 1870, foedtSpaend: [1803, 1807], koen: 'kvinde' }),
      person('m2', { name: motherB, born: 1806, died: 1875, foedtSpaend: [1804, 1808], koen: 'kvinde' }),
      person('a', { name: 'Dan D', born: 1830, koen: koenA }),
      person('b', { name: 'Emil E', born: 1840, koen: koenB }),
    ],
    unions: [
      { id: 'u1', p1: 'f', p2: 'm1', p2_name: null, year: 1825 },
      { id: 'u2', p1: 'f', p2: 'm2', p2_name: null, year: 1835 },
    ],
    parentChild: [
      { child: 'a', parent: 'f', union: 'u1' }, { child: 'a', parent: 'm1', union: 'u1' },
      { child: 'b', parent: 'f', union: 'u2' }, { child: 'b', parent: 'm2', union: 'u2' },
    ],
  });
}

describe('review37 M1 — forskellige hustruer og plausible navnealiaser', () => {
  test.each<[AppPerson['koen'], AppPerson['koen'], string]>([
    ['mand', 'mand', 'Halvbrødre'], ['kvinde', 'kvinde', 'Halvsøstre'],
    ['mand', 'kvinde', 'Halvbror & halvsøster'], [null, null, 'Halvsøskende'],
  ])('forskellige hustruer med overlappende levetider (%s/%s) → %s', (ka, kb, label) => {
    const r = computeRelationship(siblings('Anna A', 'Clara C', ka, kb), 'a', 'b');
    expect(r.label).toBe(label);
    expect(r.lines[0].half).toBe(true);
    expect(computeRelationship(siblings('Anna A', 'Clara A', ka, kb), 'a', 'b').label).toBe(label);
  });

  test.each([
    ['Anna A', 'Anna A'], ['Anna A', 'Anna Clara A'], ['Anna Clara A', 'Anna A'],
    ['  ÁNNA,   A. ', 'Anna A'], ['Anna Clara A', 'A Anna Clara'],
    ['', 'Anna A'],
  ])('ulinkede moderrækker med navne »%s« / »%s« og overlappende spænd er ikke bevist forskellige', (a, b) => {
    expect(computeRelationship(siblings(a, b), 'a', 'b').lines[0].half).toBe(false);
  });

  test('fælles kanonisk id udelukker halv trods forskellige navne', () => {
    const m = siblings('Anna A', 'Clara C');
    m.canonicalIdById = { m1: 'm1', m2: 'm1' };
    expect(computeRelationship(m, 'a', 'b').lines[0].half).toBe(false);
  });
});

// To adskilte grene; ved fjern=true er G2 én generation længere væk.
function twoLines(fjern = false): Db {
  const pairs = [
    ['A', 'Pa'], ['A', 'Qa'], ['B', 'Pb'], ['B', 'Qb'],
    ['Pa', 'G1'], ['Pb', 'G1'],
    ...(fjern ? [['Qa', 'Ra'], ['Qb', 'Rb'], ['Ra', 'G2'], ['Rb', 'G2']] : [['Qa', 'G2'], ['Qb', 'G2']]),
  ];
  return {
    persons: [...new Set(pairs.flat())].map((id) => person(id)), unions: [],
    parentChild: pairs.map(([child, parent]) => ({ child, parent, union: `u${child}`, konfidens: 'sikker' })),
  };
}

describe('review37 M2 — uangivet/sikker bekræfter, usikre led gør ikke', () => {
  test.each<Konfidens | undefined>([null, undefined, 'sikker'])('uangivet/sikker (%s) tæller som en sikker uafhængig linje', (k) => {
    const db = twoLines();
    db.parentChild.forEach((pc) => { pc.konfidens = k; });
    const line = computeRelationship(buildModel(db), 'A', 'B').lines[0];
    expect(line.uafhaengige).toBe(2);
    expect(line.usikker).toBe(false);
  });

  test.each<Konfidens>(['sandsynlig', 'formodet', 'omstridt'])('en %s kant tæller ikke som en sikker uafhængig linje', (k) => {
    const db = twoLines();
    db.parentChild[0].konfidens = k;
    const line = computeRelationship(buildModel(db), 'A', 'B').lines[0];
    expect(line.multiplicitet).toBe(2);
    expect(line.uafhaengige).toBe(1);
    db.parentChild[1].konfidens = k;
    expect(computeRelationship(buildModel(db), 'A', 'B').lines[0].uafhaengige).toBe(0);
  });

  test.each<Konfidens>(['sandsynlig', 'formodet', 'omstridt'])('fælles %s led gør begge linjer ikke-uafhængigt sikre', (k) => {
    const pairs = [['A', 'N'], ['N', 'P1'], ['N', 'P2'], ['P1', 'G1'], ['P2', 'G2'],
      ['B', 'Q1'], ['B', 'Q2'], ['Q1', 'R1'], ['Q2', 'R2'], ['R1', 'G1'], ['R2', 'G2']];
    const db: Db = {
      persons: [...new Set(pairs.flat())].map((id) => person(id)), unions: [],
      parentChild: pairs.map(([child, parent]) => ({ child, parent, union: `u${child}`, konfidens: child === 'A' ? k : 'sikker' })),
    };
    const line = computeRelationship(buildModel(db), 'A', 'B').lines[0];
    expect(line.multiplicitet).toBe(2);
    expect(line.usikker).toBe(true);
    expect(line.uafhaengige).toBe(0);
  });

  test.each<Konfidens | undefined>([null, undefined, 'sikker', 'sandsynlig', 'formodet', 'omstridt'])('en anden linje med %s bekræfter kun ved uangivet/sikker', (k) => {
    const db = twoLines(true);
    db.parentChild[0].konfidens = 'omstridt';
    db.parentChild[1].konfidens = k;
    const r = computeRelationship(buildModel(db), 'A', 'B');
    expect(r.lines[0].usikker).toBe(true);
    expect(r.alternativSolidLinje).toBe(k == null || k === 'sikker');
  });
});

describe('review37 M3 — kun kronologisk umulige hele spænd droppes', () => {
  const edge = { child: 'c', parent: 'p', union: 'u' };
  test.each<[string, Partial<AppPerson>, Partial<AppPerson>]>([
    ['barnets seneste fødselsår kan passe', { born: 1820 }, { born: 1810, foedtSpaend: [1810, 1830] }],
    ['forælderens tidligste fødselsår kan passe', { born: 1820, foedtSpaend: [1800, 1820] }, { born: 1810 }],
    ['dødsspændets sidste år tillader posthum fødsel', { died: 1840, doedSpaend: [1840, 1850] }, { born: 1851 }],
  ])('%s', (_label, parent, child) => {
    const m = buildModel({ persons: [person('p', parent), person('c', child)], unions: [], parentChild: [edge] });
    expect(m.indexes.parentsByChild.c).toEqual(['p']);
  });

  test.each<[string, Partial<AppPerson>, Partial<AppPerson>]>([
    ['barnets hele fødselsspænd ligger før forælderens', { foedtSpaend: [1820, 1830] }, { foedtSpaend: [1800, 1810] }],
    ['barnets hele fødselsspænd ligger efter dødsspænd plus margin', { doedSpaend: [1840, 1850] }, { foedtSpaend: [1852, 1860] }],
  ])('%s (også uden rå årstal)', (_label, parent, child) => {
    const m = buildModel({ persons: [person('p', parent), person('c', child)], unions: [], parentChild: [edge] });
    expect(m.byId.c.parentId).toBeNull();
    expect(m.indexes.parentsByChild.c ?? []).toEqual([]);
    expect(m.indexes.childIdx.p?.has('c') ?? false).toBe(false);
    expect(m.indexes.childrenByUnion.p?.u ?? []).toEqual([]);
  });
});
