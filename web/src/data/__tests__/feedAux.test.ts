import { createFeedStream, resumeStream } from '@daa/feed';
import { buildModel } from '@daa/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ArmsItem, EstateItem } from '../public';
import type { Model } from '../types';

let byTable: Record<string, unknown[]> = {};
let inCalls: { table: string; column: string; values: unknown[] }[] = [];
let rpc = vi.fn();
function makeResult<T>(data: T[] | null, error: unknown = null) {
  return {
    range: async () => ({ data, error }),
    then: (resolve: (v: { data: T[] | null; error: unknown }) => void) => resolve({ data, error }),
  };
}
vi.mock('../../supabase', () => ({
  supabase: {
    rpc: (name: string, args: unknown) => rpc(name, args),
    from: (table: string) => {
      const b: Record<string, unknown> = {
        select: () => b,
        eq: () => b,
        in: (column: string, values: unknown[]) => {
          inCalls.push({ table, column, values });
          return b;
        },
        order: () => makeResult(byTable[table] ?? []),
        // getAll kalder .range() direkte på hvad end kæden ender med — matcher den rigtige
        // klient hvor .range() er tilgængelig for enden af enhver kæde, ikke kun efter .order().
        range: async () => ({ data: byTable[table] ?? [], error: null }),
      };
      return b;
    },
  },
}));

const { FEED_BIO_IN_CHUNK, FEED_BIO_PARALLEL, buildFeedBioSubjectIds, buildWebFeedAux, fetchFeedBios, withFeedBios } = await import('../feedAux');

beforeEach(() => { byTable = {}; inCalls = []; rpc = vi.fn(); });

describe('buildWebFeedAux', () => {
  it('mapper estates/arms til FeedAux-felterne', () => {
    const estates: EstateItem[] = [{ id: 'e1', navn: 'Christianssæde', slags: 'Gods', ownerCount: 5 }];
    const arms: ArmsItem[] = [{ id: 'v1', blasonering: 'Delt skjold', note: '', media: [] }];
    const aux = buildWebFeedAux(estates, arms);
    expect(aux.godsListe).toEqual([{ id: 'e1', navn: 'Christianssæde', slags: 'Gods', ownerCount: 5 }]);
    expect(aux.vaabenListe).toEqual([{ id: 'v1', blasonering: 'Delt skjold', note: '' }]);
    expect(aux.officesBy).toEqual({});
  });
  it('tomme/null input → tomme lister, ingen crash', () => {
    const aux = buildWebFeedAux(null, null);
    expect(aux.godsListe).toEqual([]);
    expect(aux.vaabenListe).toEqual([]);
  });
});

describe('fetchFeedBios', () => {
  it('afgrænser model+alias-id server-side gennem v2-RPCen i bidder', async () => {
    // Alle id'er i ét kald ramte gæsternes 3 s-loft i prod (1.725 id'er, 57014) — derfor bidder.
    rpc.mockImplementation(async (name: string) => (
      name === 'narrative_record_contract_version' ? { data: 2, error: null } : { data: [], error: null }));
    const modelIds = Array.from({ length: 401 }, (_, i) => String(i + 1));
    await fetchFeedBios({ alias1: '1', irrelevantAlias: '9999' }, modelIds);
    const bioCalls = rpc.mock.calls.filter(([name]) => name === 'public_person_bio_source_versions_v2');
    const sendt = bioCalls.flatMap(([, args]) => (args as { p_person_ids: number[] }).p_person_ids);
    expect(bioCalls.length).toBe(Math.ceil(401 / FEED_BIO_IN_CHUNK));
    for (const [, args] of bioCalls) {
      expect((args as { p_person_ids: number[] }).p_person_ids.length).toBeLessThanOrEqual(FEED_BIO_IN_CHUNK);
    }
    expect(sendt).toHaveLength(401);
    expect(new Set(sendt).size).toBe(401);
    expect(sendt).toContain(1);
    expect(sendt).not.toContain(9999);
  });
  it('har højst FEED_BIO_PARALLEL bio-kald i gang ad gangen', async () => {
    // 9 samtidige kald à 200 id'er strakte hvert kald over 3 s-loftet i prod (2026-11-21).
    let aktive = 0; let maks = 0;
    rpc.mockImplementation(async (name: string) => {
      if (name === 'narrative_record_contract_version') return { data: 2, error: null };
      aktive += 1; maks = Math.max(maks, aktive);
      await new Promise((r) => setTimeout(r, 5));
      aktive -= 1;
      return { data: [], error: null };
    });
    const modelIds = Array.from({ length: FEED_BIO_IN_CHUNK * 7 + 3 }, (_, i) => String(i + 1));
    await fetchFeedBios({}, modelIds);
    const bioCalls = rpc.mock.calls.filter(([name]) => name === 'public_person_bio_source_versions_v2');
    expect(bioCalls.length).toBe(8);
    expect(maks).toBeLessThanOrEqual(FEED_BIO_PARALLEL);
    expect(maks).toBeGreaterThan(1);
  });
  it('bidstørrelsen holder hvert kald langt under gæsteloftet', () => {
    // Prod 2026-11-21: ~10 ms pr. id; 50 id'er à 3 parallelt gav maks 1,4 s (loft 3 s).
    expect(FEED_BIO_IN_CHUNK).toBeLessThanOrEqual(50);
    expect(FEED_BIO_PARALLEL).toBeLessThanOrEqual(3);
  });
  it('vælger én v2-default på tværs af aliaser i forskellige bidder', async () => {
    const modelIds = Array.from({ length: FEED_BIO_IN_CHUNK + 1 }, (_, i) => String(i + 1));
    const sidst = Number(modelIds.at(-1));
    rpc.mockImplementation(async (name: string, args: { p_person_ids?: number[] }) => {
      if (name === 'narrative_record_contract_version') return { data: 2, error: null };
      const ids = args.p_person_ids ?? [];
      return { data: [
        ...(ids.includes(1) ? [{ person_id: 1, source_id: 30, source_year: 2020, record_order: null, source_record_ref: null, source_label: 'DAA', record_label: 'Overgangsdata', narrative_text: 'Ny legacy', citation_label: '', provenance_kind: 'legacy_narrative' }] : []),
        ...(ids.includes(sidst) ? [{ person_id: sidst, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'bound', source_label: 'DAA', record_label: 'Post 1', narrative_text: 'Bundet alias-post', citation_label: '', provenance_kind: 'source_record' }] : []),
      ], error: null };
    });
    const bios = await fetchFeedBios({ '1': 'canon', [String(sidst)]: 'canon' }, modelIds);
    const bioCalls = rpc.mock.calls.filter(([name]) => name === 'public_person_bio_source_versions_v2');
    expect(bioCalls.length).toBeGreaterThan(1);
    expect(bios.canon).toBe('Bundet alias-post');
  });
  it('en fejl i én bid er en eksplicit hente-fejl for hele hentningen', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    let n = 0;
    rpc.mockImplementation(async (name: string) => {
      if (name === 'narrative_record_contract_version') return { data: 2, error: null };
      n += 1;
      return n === 2 ? { data: null, error: { code: '57014' } } : { data: [], error: null };
    });
    const modelIds = Array.from({ length: FEED_BIO_IN_CHUNK * 2 + 1 }, (_, i) => String(i + 1));
    await expect(fetchFeedBios({}, modelIds)).rejects.toThrow('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    spy.mockRestore();
  });

  it('bygger stabilt subject-id-sæt med relevante aliases', () => {
    expect(buildFeedBioSubjectIds({ a: '1', b: '9' }, ['2', '1'])).toEqual(['1', '2', 'a']);
  });

  it('vælger den første eligible bundne v2-bio uden tekstsammenføjning', async () => {
    rpc.mockResolvedValueOnce({ data: 2, error: null }).mockResolvedValueOnce({ data: [
      { person_id: 1, source_id: 10, source_year: 1939, record_order: 1, source_record_ref: 'gammel', source_label: 'DAA 1939', record_label: 'Post 1', narrative_text: 'Gammel biografi.', citation_label: '', provenance_kind: 'source_record' },
      { person_id: 1, source_id: 20, source_year: 2012, record_order: 2, source_record_ref: 'ny-anden', source_label: 'DAA 2012', record_label: 'Post 2', narrative_text: 'Ny anden biografi.', citation_label: '', provenance_kind: 'source_record' },
      { person_id: 1, source_id: 20, source_year: 2012, record_order: 1, source_record_ref: 'ny-foerste', source_label: 'DAA 2012', record_label: 'Post 1', narrative_text: 'Ny biografi.', citation_label: '', provenance_kind: 'source_record' },
    ], error: null });
    const bios = await fetchFeedBios({}, ['1']);
    expect(bios['1']).toBe('Ny biografi.');
  });
  it('kanoniserer person-id', async () => {
    rpc.mockResolvedValueOnce({ data: 2, error: null }).mockResolvedValueOnce({ data: [
      { person_id: 1, source_id: 10, source_year: 1939, record_order: 1, source_record_ref: 'r1', source_label: 'DAA 1939', record_label: 'Post 1', narrative_text: 'En historie.', citation_label: '', provenance_kind: 'source_record' },
    ], error: null });
    const bios = await fetchFeedBios({ '1': 'canon1' }, ['1']);
    expect(bios.canon1).toBe('En historie.');
    expect(bios['1']).toBeUndefined();
  });
  it('vælger én v2-default på tværs af same_som-aliaser før kanonisering', async () => {
    rpc.mockResolvedValueOnce({ data: 2, error: null }).mockResolvedValueOnce({ data: [
      { person_id: 1, source_id: 30, source_year: 2020, record_order: null, source_record_ref: null, source_label: 'DAA', record_label: 'Overgangsdata', narrative_text: 'Ny legacy', citation_label: '', provenance_kind: 'legacy_narrative' },
      { person_id: 2, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'bound', source_label: 'DAA', record_label: 'Post 1', narrative_text: 'Bundet alias-post', citation_label: '', provenance_kind: 'source_record' },
    ], error: null });
    await expect(fetchFeedBios({ '1': 'canon', '2': 'canon' }, ['1', '2'])).resolves.toEqual({ canon: 'Bundet alias-post' });
  });
  it('serverens tomme gatede v2-svar giver ingen bio', async () => {
    rpc.mockResolvedValueOnce({ data: 2, error: null }).mockResolvedValueOnce({ data: [], error: null });
    const bios = await fetchFeedBios({}, ['1']);
    expect(bios.a).toBeUndefined();
  });
  it('lader en v2 RPC-fejl være en eksplicit hente-fejl', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    rpc
      .mockResolvedValueOnce({ data: 2, error: null })
      .mockResolvedValueOnce({ data: null, error: { message: 'RPC utilgængelig' } });
    await expect(fetchFeedBios({}, ['1'])).rejects.toThrow('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
    spy.mockRestore();
  });
  it('bevarer den tolerante v1-fallback når den gamle RPC afviser', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    rpc
      .mockResolvedValueOnce({ data: 1, error: null })
      .mockRejectedValueOnce(new Error('v1 RPC utilgængelig'));
    await expect(fetchFeedBios({}, ['1'])).resolves.toEqual({});
    spy.mockRestore();
  });
});

function person(id: string, bio = '') {
  return { id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio, privat: false };
}
function mkModel(persons: ReturnType<typeof person>[]): Model {
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}
const EMPTY_AUX = { godsListe: [], vaabenListe: [], officesBy: {} };

describe('withFeedBios', () => {
  it('stempler bio ind uden at røre den originale model', () => {
    const model = mkModel([person('a'), person('b')]);
    const enriched = withFeedBios(model, { a: 'A har en historie.' });
    expect(enriched.byId.a.bio).toBe('A har en historie.');
    expect(enriched.byId.b.bio).toBe('');
    expect(model.byId.a.bio).toBe(''); // original urørt
  });
  it('person uden post i bioBy beholder eksisterende bio', () => {
    const model = mkModel([person('a', 'Allerede sat.')]);
    const enriched = withFeedBios(model, {});
    expect(enriched.byId.a.bio).toBe('Allerede sat.');
  });

  it('strøm-genbyg ved bio-ankomst: resumeStream udelader allerede viste id\'er (§7.3-flowet)', () => {
    const model = mkModel(Array.from({ length: 30 }, (_, i) => person('p' + i)));
    const inputs = { seed: 1, todayISO: '2026-07-18', meId: null, focusId: null };

    // Før bios: kun gods/våben/tidslige kort muligt (ingen bio-personer).
    const before = createFeedStream(model, EMPTY_AUX, inputs);
    const shown = before.next(5);
    const shownIds = new Set(shown.map((c) => c.id));

    // Bios ankommer → enrichet model, SAMME seed, resumeStream springer det allerede viste over.
    const bioBy = Object.fromEntries(
      Array.from({ length: 30 }, (_, i) => ['p' + i, 'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke her.']),
    );
    const enrichedModel = withFeedBios(model, bioBy);
    const after = resumeStream(createFeedStream(enrichedModel, EMPTY_AUX, inputs), shownIds);
    const rest = after.next(10);

    for (const card of rest) expect(shownIds.has(card.id)).toBe(false);
  });
});
