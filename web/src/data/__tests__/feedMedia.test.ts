import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;

const mocks = vi.hoisted(() => ({
  signPaths: vi.fn(),
  fetchMediaFakta: vi.fn(),
}));

let byTable: Record<string, FakeRow[]> = {};
let failQueries = false;
const fromCalls: string[] = [];
const eqCalls: Array<{ table: string; column: string; value: unknown }> = [];
const inCalls: Array<{ table: string; column: string; values: unknown[] }> = [];

vi.mock('../../supabase', () => ({
  supabase: {
    from(table: string) {
      if (failQueries) throw new Error('netværksfejl');
      fromCalls.push(table);
      const rows = byTable[table] ?? [];
      const builder = {
        select: () => builder,
        eq(column: string, value: unknown) {
          eqCalls.push({ table, column, value });
          return builder;
        },
        in(column: string, values: unknown[]) {
          inCalls.push({ table, column, values });
          return builder;
        },
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

vi.mock('../media', () => ({ signPaths: mocks.signPaths, fetchMediaFakta: mocks.fetchMediaFakta }));

const { fetchFeedMediaCandidates, resolveFeedMediaForCards } = await import('../feedMedia');

const canonicalIdById = { '10': '10', '11': '10', '12': '10' };
const relations = [
  { subjekt_id: 11, objekt_id: 101, kvalifikator: null },
  { subjekt_id: 12, objekt_id: 101, kvalifikator: { primaer: true } },
  { subjekt_id: 10, objekt_id: 102, kvalifikator: null },
];
const media = [
  { id: 101, slags: 'maleri', titel: 'A', kunstner: 'K1', datering: '1800', storage_path: 'large/101.jpg' },
  { id: 102, slags: 'brev', titel: 'B', kunstner: null, datering: null, storage_path: 'large/102.jpg' },
];
const variants = [
  { media_id: 101, storage_path: 'medium/101.jpg' },
];

beforeEach(() => {
  byTable = {
    relation: [...relations],
    media: [...media],
    media_variant: [...variants],
  };
  failQueries = false;
  fromCalls.length = 0;
  eqCalls.length = 0;
  inCalls.length = 0;
  mocks.signPaths.mockReset();
  mocks.signPaths.mockResolvedValue(new Map());
  mocks.fetchMediaFakta.mockReset();
  mocks.fetchMediaFakta.mockResolvedValue(new Map());
});

describe('fetchFeedMediaCandidates', () => {
  it('henter relationer, medier og medium-varianter i tre batches og foldet kanoniserer dem', async () => {
    const result = await fetchFeedMediaCandidates(['10'], canonicalIdById);

    expect(fromCalls).toEqual(['relation', 'media', 'media_variant']);
    expect(eqCalls).toEqual(expect.arrayContaining([
      { table: 'relation', column: 'subjekt_type', value: 'person' },
      { table: 'relation', column: 'objekt_type', value: 'media' },
      { table: 'relation', column: 'rolle', value: 'afbildet' },
      { table: 'media_variant', column: 'tier', value: 'medium' },
    ]));
    expect(inCalls).toEqual(expect.arrayContaining([
      { table: 'relation', column: 'subjekt_id', values: [10, 11, 12, 10] },
      { table: 'media', column: 'id', values: [101, 102] },
      { table: 'media_variant', column: 'media_id', values: [101, 102] },
    ]));
    expect(result).toEqual({
      '10': [
        expect.objectContaining({ id: '101', mediumPath: 'medium/101.jpg', largePath: 'large/101.jpg', primaer: true }),
        expect.objectContaining({ id: '102', mediumPath: null, largePath: 'large/102.jpg' }),
      ],
    });
  });

  it('udelader medier uden storage_path og giver stadig alle anmodede kanoniske personer en nøgle', async () => {
    byTable.relation.push({ subjekt_id: 10, objekt_id: 103, kvalifikator: null });
    byTable.media.push({ id: 103, slags: 'foto', titel: null, kunstner: null, datering: null, storage_path: null });

    const result = await fetchFeedMediaCandidates(['10', '99'], canonicalIdById);

    expect(result['10'].map((item) => item.id)).toEqual(['101', '102']);
    expect(result['99']).toEqual([]);
  });

  it('beriger kandidaterne med altTekst fra fetchMediaFakta (medie-metadata Task 6)', async () => {
    mocks.fetchMediaFakta.mockResolvedValue(new Map([
      ['101', { alt_tekst: { factId: '9', vaerdi: 'En dame i sort kjole', dateMin: null, dateMax: null, dateQualifier: null, dateRaw: null } }],
    ]));

    const result = await fetchFeedMediaCandidates(['10'], canonicalIdById);

    expect(mocks.fetchMediaFakta).toHaveBeenCalledWith([101, 102]);
    expect(result['10']).toEqual([
      expect.objectContaining({ id: '101', altTekst: 'En dame i sort kjole' }),
      expect.objectContaining({ id: '102', altTekst: null }),
    ]);
  });

  it('advarer og giver tomme nøgler ved fetch-fejl', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    failQueries = true;

    await expect(fetchFeedMediaCandidates(['10', '99'], canonicalIdById)).resolves.toEqual({ '10': [], '99': [] });
    expect(warn).toHaveBeenCalledWith(expect.stringMatching(/^\[feedMedia\]/), expect.any(Error));
    warn.mockRestore();
  });
});

describe('resolveFeedMediaForCards', () => {
  const candidates = {
    '10': [
      { id: '101', slags: 'maleri', titel: 'A', kunstner: 'K1', datering: '1800', largePath: 'large/101.jpg', mediumPath: 'medium/101.jpg', primaer: true, altTekst: 'En dame i sort kjole' },
      { id: '102', slags: 'brev', titel: 'B', kunstner: '', datering: '', largePath: 'large/102.jpg', mediumPath: null },
    ],
  };

  it('vælger før én samlet signering og lader medium falde tilbage til large', async () => {
    mocks.signPaths.mockResolvedValue(new Map([
      ['medium/101.jpg', 'signed-medium-101'],
      ['large/101.jpg', 'signed-large-101'],
      ['large/102.jpg', 'signed-large-102'],
    ]));

    const result = await resolveFeedMediaForCards([
      { cardId: 'arkiv:10', kind: 'arkiv', personId: '10' },
    ], candidates);

    expect(mocks.signPaths).toHaveBeenCalledTimes(1);
    expect(new Set(mocks.signPaths.mock.calls[0][0])).toEqual(new Set([
      'medium/101.jpg', 'large/101.jpg', 'large/102.jpg',
    ]));
    expect(result['arkiv:10']).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: '101', mediumUrl: 'signed-medium-101', largeUrl: 'signed-large-101', primaer: true, altTekst: 'En dame i sort kjole' }),
      expect.objectContaining({ id: '102', mediumUrl: 'signed-large-102', largeUrl: 'signed-large-102', altTekst: null }),
    ]));
  });

  it('udelader kun elementet uden signeret large-url', async () => {
    mocks.signPaths.mockResolvedValue(new Map([
      ['medium/101.jpg', 'signed-medium-101'],
      ['large/101.jpg', 'signed-large-101'],
    ]));

    const result = await resolveFeedMediaForCards([
      { cardId: 'arkiv:10', kind: 'arkiv', personId: '10' },
    ], candidates);

    expect(result['arkiv:10']).toEqual([
      expect.objectContaining({ id: '101', largeUrl: 'signed-large-101' }),
    ]);
  });

  it('tom anmodning udfører hverken database- eller signeringskald', async () => {
    await expect(resolveFeedMediaForCards([], candidates)).resolves.toEqual({});
    expect(fromCalls).toEqual([]);
    expect(mocks.signPaths).not.toHaveBeenCalled();
  });
});
