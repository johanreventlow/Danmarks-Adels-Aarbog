// @vitest-environment jsdom
import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { buildBookmarkList, useBookmarks } from '../bookmarks';
import type { Model, ModelPerson } from '../types';

// In-memory fake af supabase.from('bookmark')-kæden. Delt mutabel tilstand pr. test.
let rows: { user_id: string; person_id: string }[] = [];
let failNextWrite = false;

vi.mock('../../supabase', () => ({
  supabase: {
    from: (table: string) => {
      if (table !== 'bookmark') throw new Error('uventet tabel: ' + table);
      return {
        select: () => ({
          order: () => Promise.resolve({ data: rows.map((r) => ({ person_id: r.person_id })), error: null }),
        }),
        upsert: (row: { person_id: string }) => {
          if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
          if (!rows.some((r) => r.person_id === row.person_id)) rows.unshift({ user_id: 'u1', person_id: row.person_id });
          return Promise.resolve({ error: null });
        },
        delete: () => ({
          eq: (_col: string, id: string) => {
            if (failNextWrite) { failNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
            rows = rows.filter((r) => r.person_id !== id);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  },
}));

function person(id: string, name: string, born: number | null = null): ModelPerson {
  return { id, name, born, died: null, years: born ? `* ${born}` : '', title: '', bio: '', privat: false, parentId: null, spouse: '' };
}

function makeModel(persons: ModelPerson[], lineageByPerson: Record<string, string[]> = {}, lineageNavn: Record<string, string> = {}): Model {
  const byId = Object.fromEntries(persons.map((p) => [p.id, p]));
  return {
    persons, byId,
    indexes: { spousesBy: {}, childIdx: {}, parentsByChild: {}, childrenByUnion: {}, unionById: {}, konfByEdge: {} },
    lineage: { byPerson: lineageByPerson, list: [], navn: lineageNavn },
  };
}

beforeEach(() => { rows = []; failNextWrite = false; });

describe('useBookmarks — udlogget', () => {
  it('tom liste, canSave=false, toggle er no-op', () => {
    const { result } = renderHook(() => useBookmarks(null, (id) => id));
    expect(result.current.ids.size).toBe(0);
    expect(result.current.canSave).toBe(false);
    act(() => result.current.toggle('1'));
    expect(result.current.ids.size).toBe(0);
  });
});

describe('useBookmarks — logget ind', () => {
  const userId = 'u1';

  it('henter list() ved mount', async () => {
    rows = [{ user_id: 'u1', person_id: '42' }];
    const { result } = renderHook(() => useBookmarks(userId, (id) => id));
    await waitFor(() => expect(result.current.ids.has('42')).toBe(true));
    expect(result.current.canSave).toBe(true);
  });

  it('toggle gemmer optimistisk + persisterer (person_id som streng)', async () => {
    const { result } = renderHook(() => useBookmarks(userId, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    act(() => result.current.toggle('99999999999999'));
    expect(result.current.ids.has('99999999999999')).toBe(true);
    await waitFor(() => expect(rows.some((r) => r.person_id === '99999999999999')).toBe(true));
  });

  it('rollback ved skrivefejl', async () => {
    const { result } = renderHook(() => useBookmarks(userId, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    failNextWrite = true;
    act(() => result.current.toggle('1'));
    expect(result.current.ids.has('1')).toBe(true); // optimistisk
    await waitFor(() => expect(result.current.ids.has('1')).toBe(false)); // rullet tilbage
  });

  it('kanoniciserer via canon', async () => {
    rows = [{ user_id: 'u1', person_id: 'alias1' }];
    const canon = (id: string) => (id === 'alias1' ? 'canon1' : id);
    const { result } = renderHook(() => useBookmarks(userId, canon));
    await waitFor(() => expect(result.current.ids.has('canon1')).toBe(true));
  });

  it('review 22 M1: gentaget tryk på samme id mens skrivning er in-flight ignoreres', async () => {
    const { result } = renderHook(() => useBookmarks(userId, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    act(() => { result.current.toggle('7'); result.current.toggle('7'); });
    expect(result.current.ids.has('7')).toBe(true);
    await waitFor(() => expect(rows.filter((r) => r.person_id === '7')).toHaveLength(1));
  });

  it('review 22 N1: samme userId (primitiv) på tværs af re-renders udløser ikke ny fetch', async () => {
    const { result, rerender } = renderHook(() => useBookmarks(userId, (id) => id));
    await waitFor(() => expect(result.current.canSave).toBe(true));
    const idsBefore = result.current.ids;
    rerender();
    rerender();
    // Samme userId + samme canon-reference → effekten refirer ikke → samme ids-reference.
    expect(result.current.ids).toBe(idsBefore);
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
