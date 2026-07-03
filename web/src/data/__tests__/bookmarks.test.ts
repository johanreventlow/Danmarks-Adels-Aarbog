// @vitest-environment jsdom
import { renderHook, act } from '@testing-library/react';
import { createLocalBookmarkStore, useBookmarks, buildBookmarkList, BOOKMARKS_KEY } from '../bookmarks';
import type { Model, ModelPerson } from '../types';

function person(id: string, name: string, born: number | null = null): ModelPerson {
  return { id, name, born, died: null, years: born ? `* ${born}` : '', title: '', bio: '', privat: false, parentId: null, spouse: '' };
}

function makeModel(persons: ModelPerson[], lineageByPerson: Record<string, string[]> = {}, lineageNavn: Record<string, string> = {}): Model {
  const byId = Object.fromEntries(persons.map((p) => [p.id, p]));
  return {
    persons,
    byId,
    indexes: { spousesBy: {}, childIdx: {}, parentsByChild: {}, childrenByUnion: {}, unionById: {}, konfByEdge: {} },
    lineage: { byPerson: lineageByPerson, list: [], navn: lineageNavn },
  };
}

describe('createLocalBookmarkStore', () => {
  beforeEach(() => { window.localStorage.clear(); });

  it('toggle tilføjer og fjerner (involutiv)', () => {
    const store = createLocalBookmarkStore();
    expect(store.has('42')).toBe(false);
    store.toggle('42');
    expect(store.has('42')).toBe(true);
    store.toggle('42');
    expect(store.has('42')).toBe(false);
  });

  it('list() returnerer seneste-tilføjet-først', () => {
    const store = createLocalBookmarkStore();
    store.toggle('1');
    store.toggle('2');
    store.toggle('3');
    expect(store.list()).toEqual(['3', '2', '1']);
  });

  it('persisterer på tværs af nye store-instanser', () => {
    createLocalBookmarkStore().toggle('7');
    const store2 = createLocalBookmarkStore();
    expect(store2.has('7')).toBe(true);
  });

  it('korrupt localStorage-værdi giver tom liste (ingen throw)', () => {
    window.localStorage.setItem(BOOKMARKS_KEY, '{not json');
    const store = createLocalBookmarkStore();
    expect(store.list()).toEqual([]);
    expect(() => store.toggle('1')).not.toThrow();
  });

  it('manglende værdi giver tom liste', () => {
    const store = createLocalBookmarkStore();
    expect(store.list()).toEqual([]);
  });
});

describe('useBookmarks — kanonisk dedup + re-normalisering', () => {
  beforeEach(() => { window.localStorage.clear(); });

  it('toggle(alias) → has(canonical) er true', () => {
    const canon = (id: string) => (id === 'alias1' ? 'canon1' : id);
    const { result } = renderHook(() => useBookmarks(canon));
    act(() => result.current.toggle('alias1'));
    expect(result.current.has('canon1')).toBe(true);
  });

  it('re-normaliserer gemt liste når canon ændrer identitet, dedup nyeste-vinder', () => {
    // Simulér en pre-collapse tilstand: alias og kanonisk begge gemt separat.
    window.localStorage.setItem(BOOKMARKS_KEY, JSON.stringify(['alias1', 'canon1']));
    const identity = (id: string) => id;
    const { result, rerender } = renderHook(({ canon }) => useBookmarks(canon), { initialProps: { canon: identity } });
    expect(result.current.ids.size).toBe(2);

    const collapsed = (id: string) => (id === 'alias1' ? 'canon1' : id);
    rerender({ canon: collapsed });
    expect([...result.current.ids]).toEqual(['canon1']);
    expect(JSON.parse(window.localStorage.getItem(BOOKMARKS_KEY)!)).toEqual(['canon1']);
  });
});

describe('buildBookmarkList', () => {
  const reventlow = person('1', 'Anders Reventlow', 1700);
  const ahlefeldt = person('2', 'Bertha Ahlefeldt', 1650);
  const noLineage = person('3', 'Carl Ukendt', 1720);

  const model = makeModel([reventlow, ahlefeldt, noLineage], {
    '1': ['I'],
    '2': ['II', 'I'], // multi-lineage — første kode 'II' afgør gruppe
  }, { I: 'Den holstenske linje', II: 'Den anden linje' });

  it("sort='navn' → én flad gruppe, sorteret A-Å (compareDanish)", () => {
    const groups = buildBookmarkList(['1', '2', '3'], model, 'navn');
    expect(groups).toHaveLength(1);
    expect(groups[0].linje).toBeNull();
    expect(groups[0].people.map((p) => p.id)).toEqual(['1', '2', '3']); // "Anders.." < "Bertha.." < "Carl.." (compareDanish på fulde navn)
  });

  it("sort='linje' → grupperer på FØRSTE linje-kode, multi-lineage-person i én deterministisk gruppe", () => {
    const groups = buildBookmarkList(['1', '2', '3'], model, 'linje');
    const byLinje = Object.fromEntries(groups.map((g) => [g.linje, g.people.map((p) => p.id)]));
    expect(byLinje['I']).toEqual(['1']);
    expect(byLinje['II']).toEqual(['2']);
    expect(byLinje['Uden linje']).toEqual(['3']);
  });

  it('person uden linje-kode havner i "Uden linje"-gruppe sidst', () => {
    const groups = buildBookmarkList(['3', '1'], model, 'linje');
    expect(groups[groups.length - 1].linje).toBe('Uden linje');
  });

  it('ukendt/forældet id filtreres bort', () => {
    const groups = buildBookmarkList(['1', '999'], model, 'navn');
    expect(groups[0].people.map((p) => p.id)).toEqual(['1']);
  });

  it('Æ/Ø/Å sortering via compareDanish', () => {
    const aase = person('4', 'Åse Reventlow');
    const oster = person('5', 'Østerbo Reventlow');
    const m2 = makeModel([aase, oster]);
    const groups = buildBookmarkList(['4', '5'], m2, 'navn');
    expect(groups[0].people.map((p) => p.id)).toEqual(['5', '4']); // Ø før Å
  });
});
