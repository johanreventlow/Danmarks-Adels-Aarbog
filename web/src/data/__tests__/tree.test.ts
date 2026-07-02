import { buildTreeColumns } from '../tree';
import { buildModel } from '../buildModel';
import type { AppPerson, Db } from '../types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson => ({
  id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o,
});
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

// Familie: R → {C1, C2}; C1 → {G1, G2}. C2 og grandchildren er blade.
const model = buildModel(
  db(
    [P('R'), P('C1'), P('C2'), P('G1'), P('G2')],
    [
      { child: 'C1', parent: 'R', union: 'u1' },
      { child: 'C2', parent: 'R', union: 'u1' },
      { child: 'G1', parent: 'C1', union: 'u2' },
      { child: 'G2', parent: 'C1', union: 'u2' },
    ],
  ),
);

describe('buildTreeColumns', () => {
  it('tom path → ingen kolonner', () => {
    expect(buildTreeColumns(model, [])).toEqual([]);
  });

  it('ukendt rod → ingen kolonner', () => {
    expect(buildTreeColumns(model, ['findes-ikke'])).toEqual([]);
  });

  it('blad-person (ingen børn) → én kolonne med kun personen', () => {
    const cols = buildTreeColumns(model, ['G1']);
    expect(cols.length).toBe(1);
    expect(cols[0].level).toBe(0);
    expect(cols[0].label).toBe('Generation 1');
    expect(cols[0].people.map((p) => p.id)).toEqual(['G1']);
    expect(cols[0].selectedId).toBe('G1');
  });

  it('rod med børn, ingen valgt barn → kol 0 = [rod], kol 1 = alle børn uden valg', () => {
    const cols = buildTreeColumns(model, ['R']);
    expect(cols.length).toBe(2);
    expect(cols[0].people.map((p) => p.id)).toEqual(['R']);
    expect(cols[0].selectedId).toBe('R');
    expect(cols[1].level).toBe(1);
    expect(cols[1].label).toBe('Generation 2');
    expect(cols[1].people.map((p) => p.id).sort()).toEqual(['C1', 'C2']);
    expect(cols[1].selectedId).toBeNull();
  });

  it('drill R→C1 → tre kolonner, C1 valgt i kol 1, C1s børn i kol 2', () => {
    const cols = buildTreeColumns(model, ['R', 'C1']);
    expect(cols.length).toBe(3);
    expect(cols[1].selectedId).toBe('C1');
    expect(cols[2].level).toBe(2);
    expect(cols[2].label).toBe('Generation 3');
    expect(cols[2].people.map((p) => p.id).sort()).toEqual(['G1', 'G2']);
    expect(cols[2].selectedId).toBeNull();
  });

  it('drill til blad R→C2 → stopper (C2 har ingen børn): to kolonner', () => {
    const cols = buildTreeColumns(model, ['R', 'C2']);
    expect(cols.length).toBe(2);
    expect(cols[1].selectedId).toBe('C2');
  });

  it('drill i fuld dybde R→C1→G1 → C1 valgt i kol 1, G1 valgt i kol 2, ingen kol 3 (G1 er blad)', () => {
    const cols = buildTreeColumns(model, ['R', 'C1', 'G1']);
    expect(cols.length).toBe(3);
    expect(cols[1].selectedId).toBe('C1');
    expect(cols[2].selectedId).toBe('G1');
  });
});
