import { buildAux } from '../buildAux';
import { buildModel } from '@daa/core';
import { buildFeed, firstQuotableSentence, type FeedCard } from '../buildFeed';
import { interleave, stableHash } from '../feedHash';
import type { AppPerson, Aux, Db, Model } from '../types';

// --- Fixtures ---------------------------------------------------------------
const LONG_BIO =
  'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke her.';

function person(id: string, over: Partial<AppPerson> = {}): AppPerson {
  return {
    id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(persons: AppPerson[], unions: Db['unions'] = []): Model {
  const db: Db = { persons, unions, parentChild: [] };
  return buildModel(db);
}

const EMPTY_AUX: Aux = buildAux({
  extIds: [], sources: [], relations: [], estates: [], orgs: [], media: [],
});

const OPTS = { meId: null, focusId: null, today: 2026 };
const kinds = (cards: FeedCard[], k: FeedCard['kind']) => cards.filter((c) => c.kind === k);

// --- feedHash ---------------------------------------------------------------
describe('stableHash', () => {
  it('er deterministisk og usigneret', () => {
    expect(stableHash('p1')).toBe(stableHash('p1'));
    expect(stableHash('p1')).toBeGreaterThanOrEqual(0);
    expect(stableHash('p1')).not.toBe(stableHash('p2'));
  });
});

describe('interleave', () => {
  it('fletter grupper round-robin og springer tomme over', () => {
    expect(interleave([['a1', 'a2', 'a3'], ['b1'], [], ['c1', 'c2']]))
      .toEqual(['a1', 'b1', 'c1', 'a2', 'c2', 'a3']);
  });
  it('tom input → tom liste', () => {
    expect(interleave([])).toEqual([]);
    expect(interleave([[], []])).toEqual([]);
  });
});

// --- firstQuotableSentence --------------------------------------------------
describe('firstQuotableSentence', () => {
  it('vælger første sætning i 40–180 tegn', () => {
    const bio = 'Kort. Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke. Mere.';
    expect(firstQuotableSentence(bio)).toBe(
      'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke.',
    );
  });
  it('returnerer null når intet passer', () => {
    expect(firstQuotableSentence('Kort. For lidt.')).toBeNull();
    expect(firstQuotableSentence('')).toBeNull();
  });
});

// --- portrait/citat partition (§3.3a) --------------------------------------
describe('buildFeed — portrait/citat', () => {
  it('samme person bliver ALDRIG både portrait og citat', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const cards = buildFeed(mkModel(persons), EMPTY_AUX, OPTS);
    const portraitIds = new Set(kinds(cards, 'portrait').map((c) => (c as { personId: string }).personId));
    for (const c of kinds(cards, 'citat')) {
      expect(portraitIds.has((c as { personId: string }).personId)).toBe(false);
    }
  });
  it('person uden bio giver intet person-kort', () => {
    const cards = buildFeed(mkModel([person('x', { bio: '   ' })]), EMPTY_AUX, OPTS);
    expect(kinds(cards, 'portrait')).toHaveLength(0);
    expect(kinds(cards, 'citat')).toHaveLength(0);
  });
});

// --- jubilæum ---------------------------------------------------------------
describe('buildFeed — jubilæum', () => {
  it('100 år → kort; 99 → intet', () => {
    const persons = [person('j1', { born: 1926 }), person('j2', { born: 1927 })];
    const jub = kinds(buildFeed(mkModel(persons), EMPTY_AUX, { meId: null, focusId: null, today: 2026 }), 'jubilaeum');
    const ids = jub.map((c) => (c as { personId: string }).personId);
    expect(ids).toContain('j1');
    expect(ids).not.toContain('j2');
  });
});

// --- slaegt-guard -----------------------------------------------------------
describe('buildFeed — slaegt', () => {
  it('intet kort uden både meId og focusId', () => {
    const persons = [person('a'), person('b')];
    const m = mkModel(persons);
    expect(buildFeed(m, EMPTY_AUX, { meId: null, focusId: 'b', today: 2026 }).some((c) => c.kind === 'slaegt')).toBe(false);
    expect(buildFeed(m, EMPTY_AUX, { meId: 'a', focusId: 'a', today: 2026 }).some((c) => c.kind === 'slaegt')).toBe(false);
  });
  it('urelaterede personer (found:false) → intet kort, ingen crash', () => {
    const m = mkModel([person('a'), person('b')]);
    expect(() => buildFeed(m, EMPTY_AUX, { meId: 'a', focusId: 'b', today: 2026 })).not.toThrow();
    expect(buildFeed(m, EMPTY_AUX, { meId: 'a', focusId: 'b', today: 2026 }).some((c) => c.kind === 'slaegt')).toBe(false);
  });
});

// --- determinisme + caps + tom ---------------------------------------------
describe('buildFeed — assembly', () => {
  it('deterministisk: samme input → identisk output', () => {
    const persons = Array.from({ length: 30 }, (_, i) => person('p' + i, { born: 1900 + i, bio: LONG_BIO }));
    const m = mkModel(persons);
    expect(buildFeed(m, EMPTY_AUX, OPTS)).toEqual(buildFeed(m, EMPTY_AUX, OPTS));
  });
  it('tom model → tom liste', () => {
    expect(buildFeed(mkModel([]), EMPTY_AUX, OPTS)).toEqual([]);
  });
  it('portrait-cap = 12', () => {
    const persons = Array.from({ length: 80 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    expect(kinds(buildFeed(mkModel(persons), EMPTY_AUX, OPTS), 'portrait').length).toBeLessThanOrEqual(12);
  });

  it('samle-kort tæller ikke-viste personer og står sidst', () => {
    const persons = Array.from({ length: 80 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const cards = buildFeed(mkModel(persons), EMPTY_AUX, OPTS);
    const samle = cards.filter((c) => c.kind === 'samle') as Array<Extract<FeedCard, { kind: 'samle' }>>;
    expect(samle).toHaveLength(1);
    expect(cards[cards.length - 1].kind).toBe('samle');
    const shown = kinds(cards, 'portrait').length + kinds(cards, 'citat').length;
    expect(samle[0].count).toBe(80 - shown);
  });

  it('intet samle-kort når alle personer vises', () => {
    const cards = buildFeed(mkModel([person('p0', { bio: LONG_BIO })]), EMPTY_AUX, OPTS);
    expect(cards.some((c) => c.kind === 'samle')).toBe(false);
  });
});
