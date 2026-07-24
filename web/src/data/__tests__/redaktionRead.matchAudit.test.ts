import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;

let relationRows: FakeRow[] = [];
let rpcRowsByPersonId: Record<number, FakeRow[]> = {};
let rpcError: { message: string } | null = null;
const rpcCalls: Array<{ name: string; args: { p_type: string; p_ids: number[] } }> = [];
const selectCalls: string[] = [];

vi.mock('../../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
    from(table: string) {
      let rows = table === 'relation' ? [...relationRows] : [];
      const builder = {
        select(columns: string) {
          selectCalls.push(columns);
          return builder;
        },
        eq(column: string, value: unknown) {
          rows = rows.filter((row) => row[column] === value);
          return builder;
        },
        range: async (from: number, to: number) => ({ data: rows.slice(from, to + 1), error: null }),
      };
      return builder;
    },
    async rpc(name: string, args: { p_type: string; p_ids: number[] }) {
      rpcCalls.push({ name, args });
      return {
        data: rpcError
          ? null
          : args.p_ids.flatMap((personId) =>
            (rpcRowsByPersonId[personId] ?? []).map((row) => ({ subjekt_id: personId, ...row }))),
        error: rpcError,
      };
    },
  },
}));

const {
  fetchIkkeSammeSomPar,
  fetchMatchAudit,
  fetchSammeSomPar,
  parseMatchRelationPar,
} = await import('../redaktionRead');

beforeEach(() => {
  relationRows = [];
  rpcRowsByPersonId = {};
  rpcError = null;
  rpcCalls.length = 0;
  selectCalls.length = 0;
});

describe('match-relationer', () => {
  it('parser relationens id additivt sammen med personparret', () => {
    expect(parseMatchRelationPar([{ id: 91, subjekt_id: 3, objekt_id: 8 }])).toEqual([
      { relationId: '91', aId: '3', bId: '8' },
    ]);
  });

  it('fetcher relationId for både samme_som og ikke_samme_som', async () => {
    relationRows = [
      { id: 91, subjekt_id: 3, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
      { id: 92, subjekt_id: 4, objekt_id: 9, rolle: 'ikke_samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];

    await expect(fetchSammeSomPar()).resolves.toEqual([{ relationId: '91', aId: '3', bId: '8' }]);
    await expect(fetchIkkeSammeSomPar()).resolves.toEqual([{ relationId: '92', aId: '4', bId: '9' }]);
    expect(selectCalls).toEqual(['id,subjekt_id,objekt_id', 'id,subjekt_id,objekt_id']);
  });
});

describe('fetchMatchAudit', () => {
  it('henter seneste relevante red_samme_som-række for hvert bekræftet link', async () => {
    const sammeSom = [
      { relationId: '91', aId: '3', bId: '8' },
      { relationId: '93', aId: '5', bId: '9' },
    ];
    rpcRowsByPersonId = {
      8: [
        { actor_navn: 'Nyere redaktør', actor_rolle: 'redaktion', created_at: '2026-07-20T12:00:00Z', operation: 'red_edit_person' },
        { actor_navn: 'Johan', actor_rolle: 'redaktion', created_at: '2026-07-19T10:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 3 som samme som 8' },
        { actor_navn: 'Ældre', actor_rolle: 'redaktion', created_at: '2026-07-18T10:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 2 som samme som 8' },
      ],
      9: [
        { actor_navn: null, actor_rolle: null, created_at: '2026-07-17T09:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 5 som samme som 9' },
      ],
    };

    await expect(fetchMatchAudit(sammeSom, [])).resolves.toEqual([
      {
        relationId: '91', aId: '3', bId: '8',
        beslutning: 'samme_som',
        actorNavn: 'Johan', actorRolle: 'redaktion',
        createdAt: '2026-07-19T10:00:00Z', operation: 'red_samme_som',
      },
      {
        relationId: '93', aId: '5', bId: '9',
        beslutning: 'samme_som',
        actorNavn: null, actorRolle: null,
        createdAt: '2026-07-17T09:00:00Z', operation: 'red_samme_som',
      },
    ]);
    expect(rpcCalls).toEqual([
      { name: 'hist_for_subjekter', args: { p_type: 'person', p_ids: [8, 9] } },
    ]);
    expect(selectCalls).toEqual([]);
  });

  it('bevarer linket med tom audit, når historikken mangler en oprettelsesrække', async () => {
    const sammeSom = [{ relationId: '91', aId: '3', bId: '8' }];
    rpcRowsByPersonId = {
      8: [{ operation: 'red_edit_person' }],
    };

    await expect(fetchMatchAudit(sammeSom, [])).resolves.toEqual([{
      relationId: '91', aId: '3', bId: '8',
      beslutning: 'samme_som',
      actorNavn: null, actorRolle: null, createdAt: null, operation: null,
    }]);
  });

  it('bevarer alle links med tom audit, når det batchede historikopslag fejler', async () => {
    const sammeSom = [
      { relationId: '91', aId: '3', bId: '8' },
      { relationId: '93', aId: '5', bId: '9' },
    ];
    rpcError = { message: 'Midlertidig fejl' };

    await expect(fetchMatchAudit(sammeSom, [])).resolves.toEqual([
      {
        relationId: '91', aId: '3', bId: '8',
        beslutning: 'samme_som',
        actorNavn: null, actorRolle: null, createdAt: null, operation: null,
      },
      {
        relationId: '93', aId: '5', bId: '9',
        beslutning: 'samme_som',
        actorNavn: null, actorRolle: null, createdAt: null, operation: null,
      },
    ]);
  });

  it('matcher hver alias audit, når flere links deler samme kanoniske person', async () => {
    const sammeSom = [
      { relationId: '91', aId: '3', bId: '8' },
      { relationId: '92', aId: '5', bId: '8' },
    ];
    rpcRowsByPersonId = {
      8: [
        {
          actor_navn: 'Nyeste redaktør', actor_rolle: 'redaktion', created_at: '2026-07-20T14:00:00Z',
          operation: 'red_samme_som', summary: 'Markerede person 5 som samme som 8',
        },
        {
          actor_navn: 'Første redaktør', actor_rolle: 'administrator', created_at: '2026-07-19T10:00:00Z',
          operation: 'red_samme_som', summary: 'Markerede person 3 som samme som 8',
        },
      ],
    };

    await expect(fetchMatchAudit(sammeSom, [])).resolves.toEqual([
      {
        relationId: '91', aId: '3', bId: '8',
        beslutning: 'samme_som',
        actorNavn: 'Første redaktør', actorRolle: 'administrator',
        createdAt: '2026-07-19T10:00:00Z', operation: 'red_samme_som',
      },
      {
        relationId: '92', aId: '5', bId: '8',
        beslutning: 'samme_som',
        actorNavn: 'Nyeste redaktør', actorRolle: 'redaktion',
        createdAt: '2026-07-20T14:00:00Z', operation: 'red_samme_som',
      },
    ]);
  });

  it('henter audit for ikke_samme_som via det normaliserede lave person-id', async () => {
    const ikkeSammeSom = [{ relationId: '92', aId: '4', bId: '9' }];
    rpcRowsByPersonId = {
      4: [
        {
          actor_navn: 'Johan', actor_rolle: 'redaktion', created_at: '2026-07-20T15:00:00Z',
          operation: 'red_ikke_samme_som', summary: 'Markerede person 4 og 9 som forskellige',
        },
      ],
    };

    await expect(fetchMatchAudit([], ikkeSammeSom)).resolves.toEqual([{
      relationId: '92', aId: '4', bId: '9', beslutning: 'ikke_samme_som',
      actorNavn: 'Johan', actorRolle: 'redaktion',
      createdAt: '2026-07-20T15:00:00Z', operation: 'red_ikke_samme_som',
    }]);
    expect(rpcCalls).toEqual([
      { name: 'hist_for_subjekter', args: { p_type: 'person', p_ids: [4] } },
    ]);
  });

  it('henter tre beslutningers historik i ét kald med unikke person-id’er', async () => {
    const sammeSom = [
      { relationId: '91', aId: '3', bId: '8' },
      { relationId: '93', aId: '5', bId: '9' },
    ];
    const ikkeSammeSom = [{ relationId: '92', aId: '4', bId: '10' }];

    await fetchMatchAudit(sammeSom, ikkeSammeSom);

    expect(rpcCalls).toEqual([
      { name: 'hist_for_subjekter', args: { p_type: 'person', p_ids: [8, 9, 4] } },
    ]);
  });

  it('springer historikopslaget over, når der ikke er nogen beslutninger', async () => {
    await expect(fetchMatchAudit([], [])).resolves.toEqual([]);
    expect(rpcCalls).toEqual([]);
  });
});
