import { createFeedStream, resumeStream } from '@daa/feed';
import { buildModel } from '@daa/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ArmsItem, EstateItem } from '../public';
import type { Model } from '../types';

let byTable: Record<string, unknown[]> = {};
function makeResult<T>(data: T[] | null, error: unknown = null) {
  return {
    range: async () => ({ data, error }),
    then: (resolve: (v: { data: T[] | null; error: unknown }) => void) => resolve({ data, error }),
  };
}
vi.mock('../../supabase', () => ({
  supabase: {
    from: (table: string) => {
      const b: Record<string, unknown> = {
        select: () => b,
        eq: () => b,
        order: () => makeResult(byTable[table] ?? []),
        // getAll kalder .range() direkte på hvad end kæden ender med — matcher den rigtige
        // klient hvor .range() er tilgængelig for enden af enhver kæde, ikke kun efter .order().
        range: async () => ({ data: byTable[table] ?? [], error: null }),
      };
      return b;
    },
  },
}));

const { buildWebFeedAux, fetchFeedBios, withFeedBios } = await import('../feedAux');

beforeEach(() => { byTable = {}; });

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
  it('vælger foretrukken bio pr. person på tværs af flere udgaver (nyeste år vinder)', async () => {
    byTable = {
      narrative: [
        { id: 1, subjekt_id: 'a', tekst: 'Gammel biografi.', source_id: 10, privat: false },
        { id: 2, subjekt_id: 'a', tekst: 'Ny biografi.', source_id: 20, privat: false },
      ],
      source: [
        { id: 10, slags: 'DAA-udgave', udgave: 'DAA 1939', aar: 1939 },
        { id: 20, slags: 'DAA-udgave', udgave: 'DAA 2012', aar: 2012 },
      ],
    };
    const bios = await fetchFeedBios({});
    expect(bios.a).toBe('Ny biografi.');
  });
  it('kanoniserer person-id', async () => {
    byTable = {
      narrative: [{ id: 1, subjekt_id: 'alias1', tekst: 'En historie.', source_id: 10, privat: false }],
      source: [{ id: 10, slags: 'DAA-udgave', udgave: 'DAA 1939', aar: 1939 }],
    };
    const bios = await fetchFeedBios({ alias1: 'canon1' });
    expect(bios.canon1).toBe('En historie.');
    expect(bios.alias1).toBeUndefined();
  });
  it('private narrativer springes over', async () => {
    byTable = {
      narrative: [{ id: 1, subjekt_id: 'a', tekst: 'Hemmelig.', source_id: 10, privat: true }],
      source: [{ id: 10, slags: 'DAA-udgave', udgave: 'DAA 1939', aar: 1939 }],
    };
    const bios = await fetchFeedBios({});
    expect(bios.a).toBeUndefined();
  });
  it('fejl → tomt objekt, aldrig kast', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    byTable = {};
    vi.doMock('../../supabase', () => ({ supabase: { from: () => { throw new Error('boom'); } } }));
    const { fetchFeedBios: freshFetch } = await import('../feedAux');
    const bios = await freshFetch({});
    expect(bios).toEqual({});
    spy.mockRestore();
    vi.doUnmock('../../supabase');
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
