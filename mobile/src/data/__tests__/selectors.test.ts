import { buildModel } from '../buildModel';
import { buildColumns, buildSearch, buildSnapPath, treeFocusA } from '../selectors';
import type { Db } from '../types';

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

describe('buildColumns — variant B drill-down', () => {
  test('rod-kolonne + børne-kolonne', () => {
    const cols = buildColumns(model, ['1']);
    expect(cols.map((c) => c.level)).toEqual([0, 1]);
    expect(cols[0].people.map((p) => p.id)).toEqual(['1']);
    expect(cols[1].people.map((p) => p.id).sort()).toEqual(['3', '4']);
    expect(cols[1].selected).toBeNull();
  });
  test('valgt sti markerer selected pr. niveau', () => {
    const cols = buildColumns(model, ['1', '3']);
    expect(cols[0].selected).toBe('1');
    expect(cols[1].selected).toBe('3');
    // 3 har ingen børn → ingen tredje kolonne
    expect(cols.length).toBe(2);
  });
});
