// Våbengalleriet (spec 2026-11-24-billeder-2018-20-design.md, runde 3): alle gæste-synlige medier af én slags, i id-orden.
import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
let byTable: Record<string, FakeRow[]> = {};
const eqKald: Array<[string, string, unknown]> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    storage: {
      from: vi.fn(() => ({
        createSignedUrls: vi.fn(async (paths: string[]) => ({
          data: paths.map((p) => ({ path: p, signedUrl: `signed:${p}` })), error: null,
        })),
      })),
    },
    auth: { onAuthStateChange: vi.fn() },
    from(table: string) {
      const rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq: (kol: string, v: unknown) => { eqKald.push([table, kol, v]); return builder; },
        in: () => builder,
        order: () => builder,
        range: async (from: number, to: number) => ({ data: rows.slice(from, to + 1), error: null }),
        then(resolve: (value: { data: FakeRow[]; error: null }) => void) {
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
      };
      return builder;
    },
  },
}));

import { fetchMediaAfSlags } from '../media';

beforeEach(() => {
  eqKald.length = 0;
  byTable = {
    media: [
      { id: 190, slags: 'våben', titel: 'Grevskabet Vallø', kunstner: null, datering: '1713', storage_path: 'l/190.jpg' },
      { id: 185, slags: 'våben', titel: 'Våben: von Reventlow', kunstner: null, datering: null, storage_path: 'l/185.jpg' },
    ],
    media_variant: [], fact: [], conclusion: [], assertion: [],
  };
});

describe('fetchMediaAfSlags', () => {
  it('henter kun den ønskede slags og giver dem i id-orden med signeret url', async () => {
    const items = await fetchMediaAfSlags('våben');
    expect(eqKald).toContainEqual(['media', 'slags', 'våben']);
    expect(items.map((m) => m.id)).toEqual(['185', '190']);
    expect(items[0].url).toBe('signed:l/185.jpg');
    expect(items[1].titel).toBe('Grevskabet Vallø');
  });

  it('ingen medier giver en tom liste', async () => {
    byTable.media = [];
    expect(await fetchMediaAfSlags('våben')).toEqual([]);
  });
});
