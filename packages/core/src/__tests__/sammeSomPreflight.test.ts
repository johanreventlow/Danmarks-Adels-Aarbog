import { foldePrognose, previewSammeSom, prognoseGrundlag } from '../sammeSomPreflight';
import { buildModel } from '../buildModel';
import { resolveSameAs } from '../collapseSameAs';
import type { Db, AppPerson } from '../types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson =>
  ({ id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o });

describe('previewSammeSom (rådgivende)', () => {
  it('rent link folder → folder=true, ingen grund', () => {
    const db: Db = { persons: [P('a'), P('b')], unions: [], parentChild: [] };
    expect(previewSammeSom(db, [], { alias: 'a', canonical: 'b' })).toEqual({ folder: true, grund: null });
  });
  it('køn-konflikt → folder=false med grund', () => {
    const db: Db = { persons: [P('a', { koen: 'mand' }), P('b', { koen: 'kvinde' })], unions: [], parentChild: [] };
    const r = previewSammeSom(db, [], { alias: 'a', canonical: 'b' });
    expect(r.folder).toBe(false);
    expect(r.grund).toMatch(/køn/i);
  });
  it('konkurrerende forældre → folder=false', () => {
    const db: Db = {
      persons: [P('a'), P('b'), P('p1'), P('p2')],
      unions: [],
      parentChild: [
        { child: 'a', parent: 'p1', union: 'f1' },
        { child: 'b', parent: 'p2', union: 'f2' },
      ],
    };
    const r = previewSammeSom(db, [], { alias: 'a', canonical: 'b' });
    expect(r.folder).toBe(false);
    expect(r.grund).toMatch(/forældre/i);
  });
});

// Redaktionens bekræftelsesdialog kaldte previewSammeSom uden de eksisterende samme_som-kanter. Når
// forældrene allerede er koblet på tværs af udgaverne (1939 ↔ 2018-20), lignede de to forældresæt så
// "konkurrerende forældre" — en falsk advarsel (decisions 2026-11-12; 6 af 6 par foldede med kanterne).
describe('forældre koblet på tværs af udgaverne', () => {
  const db: Db = {
    persons: [P('a39'), P('b18'), P('far39'), P('mor39'), P('far18'), P('mor18')],
    unions: [],
    parentChild: [
      { child: 'a39', parent: 'far39', union: 'f39' },
      { child: 'a39', parent: 'mor39', union: 'f39' },
      { child: 'b18', parent: 'far18', union: 'f18' },
      { child: 'b18', parent: 'mor18', union: 'f18' },
    ],
  };
  const kanter = [{ alias: 'far39', canonical: 'far18' }, { alias: 'mor39', canonical: 'mor18' }];

  it('uden kanterne ser forældrene konkurrerende ud (fejlens mekanisme)', () => {
    expect(previewSammeSom(db, [], { alias: 'a39', canonical: 'b18' }).folder).toBe(false);
  });
  it('med kanterne folder parret', () => {
    expect(previewSammeSom(db, kanter, { alias: 'a39', canonical: 'b18' })).toEqual({ folder: true, grund: null });
  });
});

describe('foldePrognose (dialogens prognose)', () => {
  const db: Db = { persons: [P('a'), P('b')], unions: [], parentChild: [] };
  it('afventer, mens kanterne ikke er hentet — aldrig en advarsel uden kanter', () => {
    expect(foldePrognose(db, null, { alias: 'a', canonical: 'b' })).toEqual({ status: 'afventer' });
  });
  it('ukendt, hvis kanterne ikke kunne hentes', () => {
    expect(foldePrognose(db, 'fejl', { alias: 'a', canonical: 'b' })).toEqual({ status: 'ukendt' });
  });
  it('klar med previewSammeSoms svar, når kanterne er hentet', () => {
    expect(foldePrognose(db, [], { alias: 'a', canonical: 'b' })).toEqual({ status: 'klar', folder: true, grund: null });
  });
});

// Review 37 M11: redaktionerne byggede prognosens grundlag af den færdige model — uden ægteskaber og uden de
// forældrekanter, buildModel frasorterer som umulige. Den rigtige sammenlægning ser begge dele.
describe('prognoseGrundlag: samme grundlag som den rigtige sammenlægning (M11)', () => {
  const raa: Db = {
    persons: [
      P('a', { born: 1800 }), P('b', { born: 1801 }),
      P('c', { born: 1700 }), P('d', { born: 1700 }),
      P('p', { born: 1850 }), P('q', { born: 1660 }),
    ],
    unions: [{ id: 'fab', p1: 'a', p2: 'b', p2_name: 'b', year: null }],
    parentChild: [
      // c's forælder p er født efter c: buildModel dropper kanten, sammenlægningen ser den.
      { child: 'c', parent: 'p', union: 'fp' },
      { child: 'd', parent: 'q', union: 'fq' },
    ],
  };
  const model = buildModel(raa);
  // Sådan byggede Redaktion.tsx og mobilens person-side grundlaget før.
  const beskaaret: Db = {
    persons: model.persons, unions: [],
    parentChild: Object.entries(model.indexes.parentsByChild).flatMap(([child, ps]) => ps.map((parent) => ({ child, parent, union: '' }))),
  };
  const facit = (h: { alias: string; canonical: string }) =>
    !resolveSameAs(raa, [h]).quarantined.some((q) => q.members.includes(h.alias));

  it.each([
    ['gift par (selv-ægtefælle)', { alias: 'a', canonical: 'b' }],
    ['frasorteret forældrekant (konkurrerende forældre)', { alias: 'c', canonical: 'd' }],
  ])('%s: det beskårne grundlag tog fejl, prognoseGrundlag svarer som sammenlægningen', (_navn, h) => {
    expect(facit(h)).toBe(false);
    expect(previewSammeSom(beskaaret, [], h).folder).toBe(true); // fejlen, review 37 M11
    expect(previewSammeSom(prognoseGrundlag({ ...model, grundlagDb: raa }), [], h).folder).toBe(facit(h));
  });

  it('uden grundlagDb: ægteskaberne tages fra modellen, så det gifte par fanges stadig', () => {
    expect(previewSammeSom(prognoseGrundlag(model), [], { alias: 'a', canonical: 'b' }).folder).toBe(false);
  });
});
