import { beforeEach, describe, expect, it, vi } from 'vitest';

type FakeRow = Record<string, unknown>;
type RpcResult = { data: FakeRow[] | null; error: { message: string } | null };

let relationRows: FakeRow[] = [];
let rpcByPersonId: Record<number, RpcResult> = {};
const rpcCalls: Array<{ name: string; args: { p_type: string; p_id: number } }> = [];
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
    async rpc(name: string, args: { p_type: string; p_id: number }) {
      rpcCalls.push({ name, args });
      return rpcByPersonId[args.p_id] ?? { data: [], error: null };
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
  rpcByPersonId = {};
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
    relationRows = [
      { id: 91, subjekt_id: 3, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
      { id: 93, subjekt_id: 5, objekt_id: 9, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];
    rpcByPersonId = {
      8: { data: [
        { actor_navn: 'Nyere redaktør', actor_rolle: 'redaktion', created_at: '2026-07-20T12:00:00Z', operation: 'red_edit_person' },
        { actor_navn: 'Johan', actor_rolle: 'redaktion', created_at: '2026-07-19T10:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 3 som samme som 8' },
        { actor_navn: 'Ældre', actor_rolle: 'redaktion', created_at: '2026-07-18T10:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 2 som samme som 8' },
      ], error: null },
      9: { data: [
        { actor_navn: null, actor_rolle: null, created_at: '2026-07-17T09:00:00Z', operation: 'red_samme_som', summary: 'Markerede person 5 som samme som 9' },
      ], error: null },
    };

    await expect(fetchMatchAudit()).resolves.toEqual([
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
      { name: 'hist_for_subjekt', args: { p_type: 'person', p_id: 8 } },
      { name: 'hist_for_subjekt', args: { p_type: 'person', p_id: 9 } },
    ]);
  });

  it('bevarer linket med tom audit, når historikken mangler en oprettelsesrække', async () => {
    relationRows = [
      { id: 91, subjekt_id: 3, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];
    rpcByPersonId = {
      8: { data: [{ operation: 'red_edit_person' }], error: null },
    };

    await expect(fetchMatchAudit()).resolves.toEqual([{
      relationId: '91', aId: '3', bId: '8',
      beslutning: 'samme_som',
      actorNavn: null, actorRolle: null, createdAt: null, operation: null,
    }]);
  });

  it('bevarer øvrige links, når ét links historikopslag fejler', async () => {
    relationRows = [
      { id: 91, subjekt_id: 3, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
      { id: 93, subjekt_id: 5, objekt_id: 9, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];
    rpcByPersonId = {
      8: { data: null, error: { message: 'Midlertidig fejl' } },
      9: { data: [{
        actor_navn: 'Karen', actor_rolle: 'redaktion', created_at: '2026-07-20T13:00:00Z',
        operation: 'red_samme_som', summary: 'Markerede person 5 som samme som 9',
      }], error: null },
    };

    await expect(fetchMatchAudit()).resolves.toEqual([
      {
        relationId: '91', aId: '3', bId: '8',
        beslutning: 'samme_som',
        actorNavn: null, actorRolle: null, createdAt: null, operation: null,
      },
      {
        relationId: '93', aId: '5', bId: '9',
        beslutning: 'samme_som',
        actorNavn: 'Karen', actorRolle: 'redaktion',
        createdAt: '2026-07-20T13:00:00Z', operation: 'red_samme_som',
      },
    ]);
  });

  it('matcher hver alias audit, når flere links deler samme kanoniske person', async () => {
    relationRows = [
      { id: 91, subjekt_id: 3, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
      { id: 92, subjekt_id: 5, objekt_id: 8, rolle: 'samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];
    rpcByPersonId = {
      8: { data: [
        {
          actor_navn: 'Nyeste redaktør', actor_rolle: 'redaktion', created_at: '2026-07-20T14:00:00Z',
          operation: 'red_samme_som', summary: 'Markerede person 5 som samme som 8',
        },
        {
          actor_navn: 'Første redaktør', actor_rolle: 'administrator', created_at: '2026-07-19T10:00:00Z',
          operation: 'red_samme_som', summary: 'Markerede person 3 som samme som 8',
        },
      ], error: null },
    };

    await expect(fetchMatchAudit()).resolves.toEqual([
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
    relationRows = [
      { id: 92, subjekt_id: 4, objekt_id: 9, rolle: 'ikke_samme_som', subjekt_type: 'person', objekt_type: 'person' },
    ];
    rpcByPersonId = {
      4: { data: [
        {
          actor_navn: 'Johan', actor_rolle: 'redaktion', created_at: '2026-07-20T15:00:00Z',
          operation: 'red_ikke_samme_som', summary: 'Markerede person 4 og 9 som forskellige',
        },
      ], error: null },
    };

    await expect(fetchMatchAudit()).resolves.toEqual([{
      relationId: '92', aId: '4', bId: '9', beslutning: 'ikke_samme_som',
      actorNavn: 'Johan', actorRolle: 'redaktion',
      createdAt: '2026-07-20T15:00:00Z', operation: 'red_ikke_samme_som',
    }]);
    expect(rpcCalls).toEqual([
      { name: 'hist_for_subjekt', args: { p_type: 'person', p_id: 4 } },
    ]);
  });
});
