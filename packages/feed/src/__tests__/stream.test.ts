import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { createFeedStream, resumeStream } from '../stream';
import type { FeedAux, FeedInputs, Model } from '../types';

function person(id: string, over: Partial<{ bio: string }> = {}) {
  return { id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...over };
}

function mkModel(n: number): Model {
  const persons = Array.from({ length: n }, (_, i) => person('p' + i, { bio: 'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke her.' }));
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}

const EMPTY_AUX: FeedAux = { godsListe: [], vaabenListe: [], officesBy: {} };

function baseInputs(over: Partial<FeedInputs> = {}): FeedInputs {
  return { seed: 1, todayISO: '2026-07-18', meId: null, focusId: null, ...over };
}

describe('createFeedStream', () => {
  it('next(a)+next(b) ≡ next(a+b)', () => {
    const model = mkModel(30);
    const streamA = createFeedStream(model, EMPTY_AUX, baseInputs());
    const combined = [...streamA.next(4), ...streamA.next(7)];

    const streamB = createFeedStream(model, EMPTY_AUX, baseInputs());
    const single = streamB.next(11);

    expect(combined).toEqual(single);
  });

  it('udtømmes korrekt: [] + done() efter slut', () => {
    const model = mkModel(3);
    const stream = createFeedStream(model, EMPTY_AUX, baseInputs());
    const total = stream.total();
    expect(stream.done()).toBe(false);
    const all = stream.next(total);
    expect(all).toHaveLength(total);
    expect(stream.done()).toBe(true);
    expect(stream.next(5)).toEqual([]);
  });

  it('total() matcher den fulde ordnings længde', () => {
    const model = mkModel(20);
    const stream = createFeedStream(model, EMPTY_AUX, baseInputs());
    const all = stream.next(10_000);
    expect(stream.total()).toBe(all.length);
  });

  it('tom model → total 0, done straks, next giver []', () => {
    const stream = createFeedStream(mkModel(0), EMPTY_AUX, baseInputs());
    expect(stream.total()).toBe(0);
    expect(stream.done()).toBe(true);
    expect(stream.next(5)).toEqual([]);
  });
});

describe('resumeStream', () => {
  it('leverer aldrig et id fra shownIds', () => {
    const model = mkModel(30);
    const full = createFeedStream(model, EMPTY_AUX, baseInputs());
    const firstBatch = full.next(5);
    const shown = new Set(firstBatch.map((c) => c.id));

    // Ny strøm med SAMME seed (simulerer web's bio-genbyg, spec §7.3) — resume springer
    // de allerede viste id'er over og fortsætter med resten i uændret rækkefølge.
    const rebuilt = createFeedStream(model, EMPTY_AUX, baseInputs());
    const resumed = resumeStream(rebuilt, shown);
    const rest = resumed.next(10);

    for (const card of rest) expect(shown.has(card.id)).toBe(false);
  });

  it('bevarer indbyrdes rækkefølge af resten', () => {
    const model = mkModel(30);
    const reference = createFeedStream(model, EMPTY_AUX, baseInputs()).next(30);
    const shown = new Set(reference.slice(0, 5).map((c) => c.id));
    const expectedRest = reference.filter((c) => !shown.has(c.id));

    const rebuilt = createFeedStream(model, EMPTY_AUX, baseInputs());
    const resumed = resumeStream(rebuilt, shown);
    const actualRest = resumed.next(30);

    expect(actualRest.map((c) => c.id)).toEqual(expectedRest.map((c) => c.id));
  });

  it('done()/total() delegerer til den underliggende strøm', () => {
    const model = mkModel(3);
    const rebuilt = createFeedStream(model, EMPTY_AUX, baseInputs());
    const resumed = resumeStream(rebuilt, new Set());
    expect(resumed.total()).toBe(rebuilt.total());
    resumed.next(1000);
    expect(resumed.done()).toBe(true);
  });
});
