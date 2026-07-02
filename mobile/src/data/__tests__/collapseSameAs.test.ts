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
  // §6.5-hul (review-fund): kun fødselsår kendt (intet dødsår) → levetids-tjekket springes over,
  // men fødsler >80 år fra hinanden kan ikke være samme person.
  it('fødsler årtier fra hinanden uden dødsår → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d = db([P('A', { born: 1644 }), P('B', { born: 1750 })], []);
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/fødsler|vital/i);
  });
  // §6.1-hul (review-fund): to partnere i en union der kanoniserer til samme id → selv-ægtefælle.
  it('selv-ægtefælle efter merge → karantæne', () => {
    const g = new Map([['B', ['A', 'B']]]);
    const d: Db = {
      persons: [P('A'), P('B')],
      unions: [{ id: 'u1', p1: 'A', p2: 'B', p2_name: null, year: null }], // A gift med B; A=B → selv-ægtefælle
      parentChild: [],
    };
    const { accepted, quarantined } = validateGroups(g, d);
    expect(accepted.size).toBe(0);
    expect(quarantined[0].reason).toMatch(/ægtefælle/i);
  });
  // D1 (Codex-fund): en interagerende gruppe (P→Q) der selv rejektes (køn) må ikke maskere
  // konkurrerende forældre for en anden gruppe (A→B): A har forælder P, B har forælder Q. Hvis
  // P/Q optimistisk kanoniseres sammen ser A/B's forældre ens ud og A→B slipper igennem — men når
  // P→Q rejektes er P≠Q, så A→B har to forskellige forældre-familier og SKAL karantæneres.
  it('rejekteret forældre-gruppe maskerer ikke konkurrerende forældre (fixed-point)', () => {
    const g = new Map([
      ['B', ['A', 'B']],
      ['Q', ['P', 'Q']],
    ]);
    const d = db(
      [P('A'), P('B'), P('P', { koen: 'mand' }), P('Q', { koen: 'kvinde' })],
      [
        { child: 'A', parent: 'P', union: 'f1' },
        { child: 'B', parent: 'Q', union: 'f2' },
      ],
    );
    const { accepted, quarantined } = validateGroups(g, d);
    // Q rejektes (køn), OG B rejektes (konkurrerende forældre efter P/Q af-mergedes).
    expect(accepted.has('B')).toBe(false);
    expect(quarantined.some((q) => /konkurrerende forældre/i.test(q.reason))).toBe(true);
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
  // D2 (Codex-fund): når to parentChild-rækker kanoniserer til samme (forælder,barn,familie) med
  // forskellig konfidens, skal den STÆRKESTE overleve dedup — ikke first-wins (buildModel ser kun
  // den overlevende række og kan ikke genskabe den stærkere).
  it('kant-dedup beholder stærkeste konfidens ved kollision', () => {
    const rawDb: Db = {
      persons: [P('A'), P('B'), P('c')],
      unions: [],
      parentChild: [
        { child: 'c', parent: 'A', union: 'f1', konfidens: 'formodet' },
        { child: 'c', parent: 'B', union: 'f1', konfidens: 'sikker' },
      ],
    };
    const r = collapseSameAs(rawDb, [{ alias: 'A', canonical: 'B' }], new Map());
    const edges = r.db.parentChild.filter((pc) => pc.child === 'c' && pc.parent === 'B');
    expect(edges).toHaveLength(1);
    expect(edges[0].konfidens).toBe('sikker');
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
  // Regression (review-fund): cyklus-attribution må kun ramme grupper der faktisk ER i cyklussen.
  // Her skaber N's merge cyklussen P↔N; M er en accepteret gruppe på DFS-stakken FØR cyklussen,
  // men uden for den. Fejl-attribution over-karantænerer M (uskyldig gruppe foldes ikke). Fikset
  // søger kun cyklus-udsnittet, så KUN N karantæneres og M foldes korrekt. Projektionen forbliver
  // acyklisk under begge (restart-loopet fanger N), men M skal folde.
  it('cyklus-attribution over-karantænerer ikke en uskyldig gruppe uden for cyklussen', () => {
    const rawDb: Db = {
      persons: [P('a1'), P('M'), P('a2'), P('N'), P('P')],
      unions: [],
      parentChild: [
        { child: 'M', parent: 'P', union: 'f1' }, // M barn af P (M accepteret, uden for cyklus)
        { child: 'P', parent: 'N', union: 'f2' }, // P barn af N
        { child: 'a2', parent: 'P', union: 'f3' }, // a2 barn af P → N barn af P (lukker cyklus N↔P)
      ],
    };
    const r = collapseSameAs(
      rawDb,
      [
        { alias: 'a1', canonical: 'M' },
        { alias: 'a2', canonical: 'N' },
      ],
      new Map(),
    );
    // N's cyklus-skabende merge karantæneres.
    expect(r.quarantined.some((q) => /cyklus/i.test(q.reason))).toBe(true);
    expect(r.canonicalIdById['a2']).toBeUndefined(); // N ikke foldet
    // M er uskyldig og skal folde (a1 → M).
    expect(r.canonicalIdById['a1']).toBe('M');
    // Den projicerede forældre-graf forbliver acyklisk.
    const parents = new Map<string, string[]>();
    for (const pc of r.db.parentChild) (parents.get(pc.child) ?? parents.set(pc.child, []).get(pc.child)!).push(pc.parent);
    const seen = new Map<string, number>();
    const hasCycle = (n: string): boolean => {
      if (seen.get(n) === 1) return true;
      if (seen.get(n) === 2) return false;
      seen.set(n, 1);
      for (const p of parents.get(n) ?? []) if (hasCycle(p)) return true;
      seen.set(n, 2);
      return false;
    };
    expect([...parents.keys()].some((n) => hasCycle(n))).toBe(false);
  });
});
