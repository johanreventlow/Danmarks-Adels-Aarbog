// Dækker kun det renderer-uafhængige repository-lag (rene async-funktioner). `useBookmarks`-
// hook'ens session-gating/optimistiske toggle/rollback/race-guard er identisk i struktur med
// web-portens (fuldt renderHook-testet der, se web/src/data/__tests__/bookmarks.test.ts) og
// verificeres her empirisk i iOS-simulatoren (jf. spec §8 + Task 6) — @testing-library/
// react-native@14's renderHook virker ikke i dette repos jest+RN19-opsætning (afprøvet:
// selv en triviel useState-hook giver `result === undefined`); afhængigheden droppet igen
// frem for at efterlade et ubrugeligt/vildledende test-værktøj.
import { createRemoteBookmarkRepository } from '../bookmarks';

let mockRows: { user_id: string; person_id: string }[] = [];
let mockFailNextWrite = false;

jest.mock('../supabase', () => ({
  supabase: {
    from: (table: string) => {
      if (table !== 'bookmark') throw new Error('uventet tabel: ' + table);
      return {
        select: () => ({
          order: () => Promise.resolve({ data: mockRows.map((r) => ({ person_id: r.person_id })), error: null }),
        }),
        upsert: (row: { person_id: string }) => {
          if (mockFailNextWrite) { mockFailNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
          if (!mockRows.some((r) => r.person_id === row.person_id)) mockRows.unshift({ user_id: 'u1', person_id: row.person_id });
          return Promise.resolve({ error: null });
        },
        delete: () => ({
          eq: (_col: string, id: string) => {
            if (mockFailNextWrite) { mockFailNextWrite = false; return Promise.resolve({ error: { message: 'boom' } }); }
            mockRows = mockRows.filter((r) => r.person_id !== id);
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  },
  supabaseEnabled: true,
}));

beforeEach(() => { mockRows = []; mockFailNextWrite = false; });

describe('createRemoteBookmarkRepository', () => {
  it('list/add/remove sender person_id som streng (ikke Number())', async () => {
    const repo = createRemoteBookmarkRepository();
    await repo.add('99999999999999'); // > 2^53 — ville korrumperes af Number()
    expect(await repo.list()).toEqual(['99999999999999']);
    await repo.remove('99999999999999');
    expect(await repo.list()).toEqual([]);
  });

  it('add er idempotent (dublet-forsøg ændrer ikke listen)', async () => {
    const repo = createRemoteBookmarkRepository();
    await repo.add('42');
    await repo.add('42');
    expect(await repo.list()).toEqual(['42']);
  });

  it('add kaster ved skrivefejl', async () => {
    const repo = createRemoteBookmarkRepository();
    mockFailNextWrite = true;
    await expect(repo.add('1')).rejects.toThrow('boom');
  });

  it('remove kaster ved skrivefejl', async () => {
    const repo = createRemoteBookmarkRepository();
    await repo.add('1');
    mockFailNextWrite = true;
    await expect(repo.remove('1')).rejects.toThrow('boom');
  });

  it('list() på tom base giver tom liste', async () => {
    expect(await createRemoteBookmarkRepository().list()).toEqual([]);
  });
});
