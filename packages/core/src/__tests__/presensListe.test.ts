import { buildModel } from '../buildModel';
import { pruneUndertrae } from '../presensListe';
import type { Db, Koen } from '../types';

// Fixture-hjælpere (deles med klatrings- og facit-testene i denne fil).
export const mk = (id: string, koen: Koen = 'mand', born: number | null = null, died: number | null = null) =>
  ({ id, name: 'P' + id, born, died, years: '', title: '', bio: '', privat: false, koen });
export const union = (id: string, p1: string, p2: string | null = null) => ({ id, p1, p2, p2_name: null, year: null });
export const pc = (child: string, parent: string, unionId: string, konfidens?: 'sikker' | 'sandsynlig' | 'formodet' | 'omstridt') =>
  ({ child, parent, union: unionId, ...(konfidens ? { konfidens } : {}) });

describe('pruneUndertrae — bogens s.15-beskæring', () => {
  // A(død) ─ B(død) ─ C(levende);  A ─ D(død, ingen levende under sig)
  const db: Db = {
    persons: [mk('A'), mk('B'), mk('C'), mk('D')],
    unions: [union('fA', 'A'), union('fB', 'B')],
    parentChild: [pc('B', 'A', 'fA'), pc('D', 'A', 'fA'), pc('C', 'B', 'fB')],
  };
  const model = buildModel(db);

  test('afdød med levende barnebarn består som forbindelsesled; gren uden levende beskæres', () => {
    const node = pruneUndertrae(model, { C: true }, 'A');
    expect(node).not.toBeNull();
    expect(node!.forbindelsesled).toBe(true);
    expect(node!.boern.map((b) => b.id)).toEqual(['B']); // D beskåret
    expect(node!.boern[0].boern[0]).toMatchObject({ id: 'C', levende: true, forbindelsesled: false });
  });

  test('afdød uden levende under sig → null', () => {
    expect(pruneUndertrae(model, {}, 'D')).toBeNull();
  });

  test('afdød med efterlevende ægtefælle består (enke-mønstret inline i undertræer)', () => {
    const db2: Db = {
      persons: [mk('X', 'mand'), mk('E', 'kvinde')],
      unions: [{ id: 'fX', p1: 'X', p2: 'E', p2_name: null, year: null }],
      parentChild: [],
    };
    const m2 = buildModel(db2);
    const node = pruneUndertrae(m2, { E: true }, 'X');
    expect(node).not.toBeNull();
    expect(node!.partnere).toEqual([{ id: 'E', levende: true }]);
  });

  test('svag konfidens på kanten markerer barnet usikkert', () => {
    const db3: Db = {
      persons: [mk('A'), mk('B')],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA', 'formodet')],
    };
    const m3 = buildModel(db3);
    const node = pruneUndertrae(m3, { A: true, B: true }, 'A');
    expect(node!.boern[0].usikker).toBe(true);
    expect(node!.usikker).toBe(false); // roden selv har ingen kant op
  });

  test('børn sorteres deterministisk på fødselsår', () => {
    const db4: Db = {
      persons: [mk('A'), mk('B', 'mand', 1980), mk('C', 'kvinde', 1977)],
      unions: [union('fA', 'A')],
      parentChild: [pc('B', 'A', 'fA'), pc('C', 'A', 'fA')],
    };
    const m4 = buildModel(db4);
    const node = pruneUndertrae(m4, { A: true, B: true, C: true }, 'A');
    expect(node!.boern.map((b) => b.id)).toEqual(['C', 'B']);
  });
});
