import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import {
  buildDagensPersonCard,
  buildLivsdatoBy,
  buildPaaDenneDag,
  pickDagensPerson,
} from '../temporal';
import type { FuzzyDato, LivsdatoBy, Model } from '../types';

function person(id: string, over: Partial<{
  name: string; born: number | null; died: number | null; years: string;
  title: string; bio: string; privat: boolean;
}> = {}) {
  return {
    id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(persons: ReturnType<typeof person>[]): Model {
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}

const exact = (min: string): FuzzyDato => ({ min, max: min, qualifier: 'exact' });
const about = (min: string): FuzzyDato => ({ min, max: min, qualifier: 'about' });

describe('buildLivsdatoBy', () => {
  it('joiner fact→conclusion→assertion og kanoniserer id', () => {
    const facts = [
      { id: 1, subjekt_id: 'alias1', faktatype: 'fødsel' },
      { id: 2, subjekt_id: 'alias1', faktatype: 'død' },
      { id: 3, subjekt_id: 'p2', faktatype: 'erhverv' }, // ikke fødsel/død → ignoreres
    ];
    const conclusions = [
      { target_id: 1, valgt_assertion_id: 10 },
      { target_id: 2, valgt_assertion_id: 11 },
      { target_id: 3, valgt_assertion_id: 12 },
    ];
    const assertions = [
      { id: 10, date_min: '1700-07-18', date_max: '1700-07-18', date_qualifier: 'exact' },
      { id: 11, date_min: '1750-01-01', date_max: '1750-12-31', date_qualifier: 'about' },
      { id: 12, date_min: '1720-01-01', date_max: null, date_qualifier: 'exact' },
    ];
    const out = buildLivsdatoBy(facts, conclusions, assertions, { alias1: 'canon1' });
    expect(out.canon1?.foedt).toEqual({ min: '1700-07-18', max: '1700-07-18', qualifier: 'exact' });
    expect(out.canon1?.doed).toEqual({ min: '1750-01-01', max: '1750-12-31', qualifier: 'about' });
    expect(out.p2).toBeUndefined();
  });

  it('manglende konklusion/assertion springes tolerant over', () => {
    const facts = [{ id: 1, subjekt_id: 'a', faktatype: 'fødsel' }];
    expect(buildLivsdatoBy(facts, [], [], {})).toEqual({});
    const facts2 = [{ id: 1, subjekt_id: 'a', faktatype: 'fødsel' }];
    const conclusions2 = [{ target_id: 1, valgt_assertion_id: null }];
    expect(buildLivsdatoBy(facts2, conclusions2, [], {})).toEqual({});
  });

  it('tomme input → tomt objekt', () => {
    expect(buildLivsdatoBy([], [], [], {})).toEqual({});
  });
});

describe('buildPaaDenneDag', () => {
  it('dag-match: qualifier exact + MM-DD == todayISO', () => {
    const m = mkModel([person('a', { name: 'A', years: '1700–1780' })]);
    const livsdatoBy: LivsdatoBy = { a: { foedt: exact('1700-07-18') } };
    const cards = buildPaaDenneDag(m, livsdatoBy, '2026-07-18');
    expect(cards).toHaveLength(1);
    expect(cards[0]).toMatchObject({ kind: 'paadennedag', personId: 'a', hvad: 'født', aarstal: 1700, praecision: 'dag', kicker: 'På denne dag' });
  });

  it('måneds-fallback når ingen dag-match findes', () => {
    const m = mkModel([person('a'), person('b')]);
    const livsdatoBy: LivsdatoBy = { a: { foedt: exact('1700-07-05') } };
    const cards = buildPaaDenneDag(m, livsdatoBy, '2026-07-18');
    expect(cards).toHaveLength(1);
    expect(cards[0]).toMatchObject({ praecision: 'maaned', kicker: 'I denne måned' });
  });

  it('qualifier ≠ exact giver aldrig kort (hverken dag eller måned)', () => {
    const m = mkModel([person('a')]);
    const livsdatoBy: LivsdatoBy = { a: { foedt: about('1700-07-18') } };
    expect(buildPaaDenneDag(m, livsdatoBy, '2026-07-18')).toHaveLength(0);
  });

  it('tom livsdatoBy → ingen kort, ingen crash', () => {
    const m = mkModel([person('a')]);
    expect(buildPaaDenneDag(m, {}, '2026-07-18')).toHaveLength(0);
  });
});

describe('pickDagensPerson', () => {
  it('deterministisk pr. dato', () => {
    const m = mkModel(Array.from({ length: 10 }, (_, i) => person('p' + i, { bio: 'x' })));
    expect(pickDagensPerson(m, '2026-07-18')).toBe(pickDagensPerson(m, '2026-07-18'));
  });
  it('skifter mellem forskellige datoer (statistisk — mindst én forskel over flere datoer)', () => {
    const m = mkModel(Array.from({ length: 10 }, (_, i) => person('p' + i, { bio: 'x' })));
    const picks = new Set(
      ['2026-01-01', '2026-02-14', '2026-03-30', '2026-07-18', '2026-12-25'].map((d) => pickDagensPerson(m, d)),
    );
    expect(picks.size).toBeGreaterThan(1);
  });
  it('tom bio-population → null', () => {
    const m = mkModel([person('a', { bio: '' })]);
    expect(pickDagensPerson(m, '2026-07-18')).toBeNull();
  });
});

describe('buildDagensPersonCard', () => {
  it('bygger kortet for en gyldig person', () => {
    const m = mkModel([person('a', { name: 'A', bio: 'En historie.', years: '1700–1780' })]);
    const card = buildDagensPersonCard(m, 'a');
    expect(card).toMatchObject({ kind: 'dagensperson', personId: 'a', name: 'A', kicker: 'Dagens person' });
  });
  it('ukendt personId → null', () => {
    const m = mkModel([person('a')]);
    expect(buildDagensPersonCard(m, 'nope')).toBeNull();
  });
});
