import { groupSameAs, validateGroups, collapseSameAs } from '../collapseSameAs';
import type { Db, AppPerson } from '../types';

const known = (...ids: string[]) => new Set(ids);

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson => ({
  id,
  name: id,
  born: null,
  died: null,
  years: '',
  title: '',
  bio: '',
  privat: false,
  ...o,
});
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

describe('groupSameAs', () => {
  it('par: objekt = kanonisk', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('A', 'B'));
    expect(quarantined).toEqual([]);
    expect([...groups.entries()]).toEqual([['B', expect.arrayContaining(['A', 'B'])]]);
  });
  it('kæde A→B, B→C → C kanonisk', () => {
    const { groups } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'B', canonical: 'C' },
      ],
      known('A', 'B', 'C'),
    );
    expect([...groups.keys()]).toEqual(['C']);
    expect(groups.get('C')!.sort()).toEqual(['A', 'B', 'C']);
  });
  it('tvetydig sink A→B, A→C → karantæne', () => {
    const { groups, quarantined } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'A', canonical: 'C' },
      ],
      known('A', 'B', 'C'),
    );
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink/i);
  });
  it('retnings-cyklus A→B, B→A → karantæne', () => {
    const { groups, quarantined } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'B', canonical: 'A' },
      ],
      known('A', 'B'),
    );
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/sink|cyklus/i);
  });
  it('ufuldstændig komponent (endpoint mangler) → karantæne', () => {
    const { groups, quarantined } = groupSameAs([{ alias: 'A', canonical: 'B' }], known('B'));
    expect(groups.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/ufuldstændig|mangler/i);
  });
  it('duplikerede kanter normaliseres', () => {
    const { groups } = groupSameAs(
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'A', canonical: 'B' },
      ],
      known('A', 'B'),
    );
    expect(groups.get('B')!.sort()).toEqual(['A', 'B']);
  });
});

describe('validateGroups', () => {
  it('Conrad: tomt + ikke-tomt forældre-sæt → accepteret', () => {
    const g = new Map([['V1', ['III58', 'V1']]]);
    const d = db([P('III58'), P('V1'), P('far')], [{ child: 'III58', parent: 'far', union: 'f1' }]);
    const { accepted, quarantined } = validateGroups(g, d);
    expect(quarantined).toEqual([]);
    expect(accepted.has('V1')).toBe(true);
  });
  it('konkurrerende ikke-tomme forældre → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db(
      [P('A'), P('B'), P('p1'), P('p2')],
      [
        { child: 'A', parent: 'p1', union: 'f1' },
        { child: 'B', parent: 'p2', union: 'f2' },
      ],
    );
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/konkurrerende forældre/i);
  });
  it('selv-forælder efter merge → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A'), P('B')], [{ child: 'A', parent: 'B', union: 'f1' }]); // A barn af B; A=B → selv-forælder
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/selv/i);
  });
  it('global cyklus via uberørt node → karantæne', () => {
    // X barn af Y; Y barn af B; A barn af X; A=B (merge) → B er ane til sig selv gennem X,Y
    const g = new Map([['B', ['A', 'B']]]);
    const d = db(
      [P('A'), P('B'), P('X'), P('Y')],
      [
        { child: 'X', parent: 'Y', union: 'f1' },
        { child: 'Y', parent: 'B', union: 'f2' },
        { child: 'A', parent: 'X', union: 'f3' },
      ],
    );
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/cyklus/i);
  });
  it('kendt-forskelligt køn → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A', { koen: 'mand' }), P('B', { koen: 'kvinde' })], []);
    const { quarantined } = validateGroups(g, d);
    expect(quarantined[0].reason).toMatch(/køn/i);
  });
  it('ikke-overlappende levetider → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A', { born: 1600, died: 1650 }), P('B', { born: 1700, died: 1750 })], []);
    const { quarantined } = validateGroups(g, d);
    expect(quarantined[0].reason).toMatch(/levetid|vital/i);
  });
});

describe('collapseSameAs (fuld)', () => {
  const ext = new Map([
    ['III58', { linje: 'III', nr: 58 }],
    ['V1', { linje: 'V', nr: 1 }],
    ['far', { linje: 'III', nr: 40 }],
  ]);
  it('Conrad: fletter datoer + arver forælder + mergedFrom + regen years', () => {
    const rawDb: Db = {
      persons: [
        P('III58', { name: 'Conrad', born: null }),
        P('V1', { name: 'Conrad de Reventlow', born: 1644, died: 1708 }),
        P('far', { name: 'Iwan' }),
      ],
      unions: [],
      parentChild: [{ child: 'III58', parent: 'far', union: 'f1' }],
    };
    const r = collapseSameAs(rawDb, [{ alias: 'III58', canonical: 'V1' }], ext);
    expect(r.canonicalIdById['III58']).toBe('V1');
    const v1 = r.db.persons.find((p) => p.id === 'V1')!;
    expect(v1.born).toBe(1644); // coalesce
    expect(v1.years).toContain('1644'); // regenereret
    expect(r.db.persons.some((p) => p.id === 'III58')).toBe(false); // foldet væk
    expect(r.db.parentChild.find((pc) => pc.child === 'V1')?.parent).toBe('far'); // arvet forælder
    expect(r.mergedFrom['V1']).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ linje: 'III', nr: 58 }),
        expect.objectContaining({ linje: 'V', nr: 1 }),
      ]),
    );
  });
  it('privat = OR', () => {
    const rawDb: Db = {
      persons: [P('A', { privat: false }), P('B', { privat: true })],
      unions: [],
      parentChild: [],
    };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }], new Map());
    expect(r.db.persons.find((p) => p.id === 'B')!.privat).toBe(true);
  });
  it('kant-dedup familie-bevidst: samme (forælder,barn,familie) → én; forskellig familie bevares', () => {
    const rawDb: Db = {
      persons: [P('A'), P('B'), P('c')],
      unions: [],
      parentChild: [
        { child: 'c', parent: 'A', union: 'f1' },
        { child: 'c', parent: 'B', union: 'f1' },
        { child: 'c', parent: 'B', union: 'f2' },
      ],
    };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }], new Map());
    const cEdges = r.db.parentChild.filter((pc) => pc.child === 'c' && pc.parent === 'B');
    expect(cEdges.map((e) => e.union).sort()).toEqual(['f1', 'f2']); // f1 deduplikeret, f2 bevaret
  });
  it('karantæneret gruppe foldes ikke (begge poster forbliver)', () => {
    const rawDb: Db = { persons: [P('A'), P('B'), P('C')], unions: [], parentChild: [] };
    const r = collapseSameAs(
      rawDb,
      [
        { alias: 'A', canonical: 'B' },
        { alias: 'A', canonical: 'C' },
      ],
      new Map(),
    );
    expect(r.db.persons.map((p) => p.id).sort()).toEqual(['A', 'B', 'C']);
    expect(r.quarantined.length).toBe(1);
  });
});
