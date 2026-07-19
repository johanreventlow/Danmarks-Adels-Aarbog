import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { score } from '../score';
import { buildStorieBy, buildStorieKort } from '../story';
import type { StoryRow } from '../story';
import type { HaendelserBy, Model, StorieBy, StoryItem } from '../types';

function row(id: number, over: Partial<StoryRow> = {}): StoryRow {
  return {
    id, subjekt_id: 'p1', haendelse_id: null, titel: null,
    tekst: `Historie ${id}`, date_min: null, date_max: null,
    date_qualifier: null, date_raw: null, status: 'publiceret',
    publiceret_dato: '2026-07-01', privat: false, ...over,
  };
}

describe('buildStorieBy', () => {
  it('joiner kilder/sources, kanoniserer og bevarer hændelses-ankeret', () => {
    const out = buildStorieBy(
      [row(1, { subjekt_id: 'alias', haendelse_id: 55, titel: 'Slaget' })],
      [{ id: 100, story_id: 1, source_id: 20, side: '112' }],
      [{ id: 20, udgave: '1939' }],
      { alias: 'kanonisk' },
    );
    expect(out.kanonisk).toEqual([expect.objectContaining({
      id: '1', titel: 'Slaget', haendelseId: '55',
      publiceretDato: '2026-07-01', kilde: 'DAA 1939, s. 112',
    })]);
  });

  it('joiner flere kilder deterministisk i kilde-rækkernes id-orden med " · "', () => {
    const out = buildStorieBy(
      [row(1)],
      [
        { id: 102, story_id: 1, source_id: 21, side: null },
        { id: 101, story_id: 1, source_id: 20, side: '7' },
      ],
      [{ id: 20, udgave: '1939' }, { id: 21, udgave: '2018-20' }],
    );
    expect(out.p1[0].kilde).toBe('DAA 1939, s. 7 · DAA 2018-20');
  });

  it('ingen kilder ⇒ kilde null; source uden udgave udelades', () => {
    const out = buildStorieBy(
      [row(1), row(2)],
      [{ id: 100, story_id: 2, source_id: 20, side: '5' }],
      [{ id: 20, udgave: null }],
    );
    expect(out.p1.find((s) => s.id === '1')?.kilde).toBeNull();
    expect(out.p1.find((s) => s.id === '2')?.kilde).toBeNull();
  });

  it('filtrerer defensivt ikke-publiceret og privat', () => {
    const out = buildStorieBy([
      row(1, { status: 'kladde' }), row(2, { privat: true }), row(3),
    ], [], []);
    expect(out.p1.map((s) => s.id)).toEqual(['3']);
  });

  it('sorterer stabilt på numerisk id og håndterer tomme input', () => {
    const out = buildStorieBy([row(10), row(2)], [], []);
    expect(out.p1.map((s) => s.id)).toEqual(['2', '10']);
    expect(buildStorieBy([], [], [])).toEqual({});
  });
});

function mkModel(ids: string[]): Model {
  return buildModel({
    persons: ids.map((id) => ({ id, name: 'Person ' + id, born: null, died: null,
      years: '', title: '', bio: '', privat: false })),
    unions: [], parentChild: [],
  }) as unknown as Model;
}

function storie(id: string, over: Partial<StoryItem> = {}): StoryItem {
  return {
    id, titel: null, tekst: 'En kort redaktionel minihistorie om personens liv og virke.',
    dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    haendelseId: null, publiceretDato: null, kilde: null, ...over,
  };
}

describe('buildStorieKort', () => {
  const model = mkModel(['p1', 'p2']);

  it('prioriterer dateRaw, ellers år af min, ellers null', () => {
    const by: StorieBy = { p1: [
      storie('1', { dateRaw: 'ca. 1580', dato: { min: '1580-01-01', max: null, qualifier: null } }),
      storie('2', { dato: { min: '1671-05-02', max: '1671-05-02', qualifier: 'exact' } }),
      storie('3'),
    ] };
    const { cards } = buildStorieKort(model, by, {}, '2026-07-19');
    expect(cards.map((card) => card.kind === 'historie' ? card.aarLabel : null))
      .toEqual(['ca. 1580', '1671', null]);
  });

  it('arver kategori fra ankeret og registrerer alle forankrede id-er', () => {
    const hs: HaendelserBy = { p1: [{
      id: 'h9', klausul: 'x', kategori: 'krig',
      dato: { min: null, max: null, qualifier: null }, dateRaw: null,
      interessant: false, rygrad: false, kilde: null,
    }] };
    const by: StorieBy = { p1: [
      storie('1', { haendelseId: 'h9' }), storie('2', { haendelseId: 'h404' }), storie('3'),
    ] };
    const { cards, usedHaendelseIds } = buildStorieKort(model, by, hs, '2026-07-19');
    expect(cards.map((card) => card.kind === 'historie' ? card.kategori : null))
      .toEqual(['krig', null, null]);
    expect([...usedHaendelseIds].sort()).toEqual(['h404', 'h9']);
  });

  it('markerer dag 30 som nyPubliceret, men ikke dag 31', () => {
    const by: StorieBy = { p1: [
      storie('1', { publiceretDato: '2026-06-19' }),
      storie('2', { publiceretDato: '2026-06-18' }),
      storie('3'),
    ] };
    const { cards } = buildStorieKort(model, by, {}, '2026-07-19');
    expect(cards.map((card) => card.kind === 'historie' ? Boolean(card.nyPubliceret) : null))
      .toEqual([true, false, false]);
  });

  it('udelader ukendt person, sorterer stabilt og håndterer tomme input', () => {
    const by: StorieBy = { spoegelse: [storie('1')], p2: [storie('3'), storie('2')] };
    expect(buildStorieKort(model, by, {}, '2026-07-19').cards.map((card) => card.id))
      .toEqual(['story:2', 'story:3']);
    expect(buildStorieKort(model, {}, {}, '2026-07-19').cards).toEqual([]);
  });
});

describe('score — historie', () => {
  const kort = { kind: 'historie' as const, id: 'story:1', personId: 'p1', titel: null,
    tekst: 't', aarLabel: null, kategori: null, kilde: null, kicker: 'Historie' };
  const ctx = { bookmarkedIds: new Set<string>(), seenWeights: {} };

  it('ligger over portrait ved basis-score', () => {
    const portraet = { kind: 'portrait' as const, id: 'portrait:p1', personId: 'p1', name: 'N',
      years: '', initials: 'N', title: null, bio: 'b', kicker: 'Portræt' };
    expect(score(kort, ctx)).toBeGreaterThan(score(portraet, ctx));
  });

  it('fordobler nyPubliceret', () => {
    expect(score({ ...kort, nyPubliceret: true }, ctx)).toBeCloseTo(score(kort, ctx) * 2);
  });
});
