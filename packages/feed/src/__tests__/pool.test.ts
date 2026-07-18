import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import {
  buildEmbeder,
  buildForbundet,
  buildGods,
  buildJubilaeer,
  buildPortraitAndCitat,
  buildSlaegt,
  buildVaaben,
  firstQuotableSentence,
} from '../pool';
import type { FeedAux, FeedCard, Model } from '../types';

const LONG_BIO =
  'Dette er en tilstrækkelig lang og velformet sætning om personens liv og virke her.';

function person(id: string, over: Partial<{
  name: string; born: number | null; died: number | null; years: string;
  title: string; bio: string; privat: boolean;
}> = {}) {
  return {
    id, name: 'Person ' + id, born: null, died: null, years: '', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(persons: ReturnType<typeof person>[], unions: { p1: string; p2: string | null; p2_name: string | null; id: string; year: number | null }[] = []): Model {
  return buildModel({ persons, unions, parentChild: [] }) as unknown as Model;
}

const EMPTY_AUX: FeedAux = { godsListe: [], vaabenListe: [], officesBy: {} };

const kinds = (cards: FeedCard[], k: FeedCard['kind']) => cards.filter((c) => c.kind === k);

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

describe('buildPortraitAndCitat', () => {
  it('samme person bliver ALDRIG både portrait og citat', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const { portraits, citater } = buildPortraitAndCitat(mkModel(persons));
    const portraitIds = new Set(portraits.map((c) => (c as { personId: string }).personId));
    for (const c of citater) {
      expect(portraitIds.has((c as { personId: string }).personId)).toBe(false);
    }
  });
  it('person uden bio giver intet person-kort', () => {
    const { portraits, citater } = buildPortraitAndCitat(mkModel([person('x', { bio: '   ' })]));
    expect(portraits).toHaveLength(0);
    expect(citater).toHaveLength(0);
  });
  it('ingen caps: alle bio-personer bliver kandidater (>12 portrætter muligt)', () => {
    const persons = Array.from({ length: 80 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const { portraits, citater } = buildPortraitAndCitat(mkModel(persons));
    expect(portraits.length + citater.length).toBeGreaterThan(12);
  });
  it('excludeId udelader personen fra begge partitioner', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const { portraits, citater } = buildPortraitAndCitat(mkModel(persons), 'p0');
    const allIds = [...portraits, ...citater].map((c) => (c as { personId: string }).personId);
    expect(allIds).not.toContain('p0');
  });
});

describe('buildJubilaeer', () => {
  it('100 år → kort; 99 → intet', () => {
    const persons = [person('j1', { born: 1926 }), person('j2', { born: 1927 })];
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026), 'jubilaeum');
    const ids = jub.map((c) => (c as { personId: string }).personId);
    expect(ids).toContain('j1');
    expect(ids).not.toContain('j2');
  });
  it('uden livsdatoBy/todayISO: uændret adfærd, aldrig paaDagen', () => {
    const persons = [person('j1', { born: 1926 })];
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026), 'jubilaeum') as Array<{ paaDagen?: boolean; sub: string }>;
    expect(jub[0].paaDagen).toBeUndefined();
    expect(jub[0].sub).toBe('100 år siden Person j1 blev født');
  });
  it('eksakt dato der matcher dagens MM-DD → paaDagen + opgraderet sub', () => {
    const persons = [person('j1', { born: 1926 })];
    const livsdatoBy = { j1: { foedt: { min: '1926-07-18', max: '1926-07-18', qualifier: 'exact' } } };
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026, livsdatoBy, '2026-07-18'), 'jubilaeum') as Array<{ paaDagen?: boolean; sub: string }>;
    expect(jub[0].paaDagen).toBe(true);
    expect(jub[0].sub).toContain('på dagen');
  });
  it('eksakt dato der IKKE matcher dagens MM-DD → ingen paaDagen', () => {
    const persons = [person('j1', { born: 1926 })];
    const livsdatoBy = { j1: { foedt: { min: '1926-01-01', max: '1926-01-01', qualifier: 'exact' } } };
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026, livsdatoBy, '2026-07-18'), 'jubilaeum') as Array<{ paaDagen?: boolean }>;
    expect(jub[0].paaDagen).toBeUndefined();
  });
});

describe('buildSlaegt', () => {
  it('intet kort uden både meId og focusId', () => {
    const m = mkModel([person('a'), person('b')]);
    expect(buildSlaegt(m, null, 'b')).toHaveLength(0);
    expect(buildSlaegt(m, 'a', 'a')).toHaveLength(0);
  });
  it('urelaterede personer (found:false) → intet kort, ingen crash', () => {
    const m = mkModel([person('a'), person('b')]);
    expect(() => buildSlaegt(m, 'a', 'b')).not.toThrow();
    expect(buildSlaegt(m, 'a', 'b')).toHaveLength(0);
  });
});

describe('buildForbundet', () => {
  it('kun unions med begge personer i byId', () => {
    const m = mkModel(
      [person('a'), person('b')],
      [{ id: 'f1', p1: 'a', p2: 'b', p2_name: null, year: 1750 }],
    );
    const cards = buildForbundet(m);
    expect(cards).toHaveLength(1);
    expect((cards[0] as { marBottom: string }).marBottom).toBe('gift 1750');
  });
});

describe('buildGods/buildVaaben/buildEmbeder — tom aux', () => {
  it('tomme FeedAux-felter giver ingen kort, ingen crash', () => {
    const m = mkModel([person('a')]);
    expect(buildGods(EMPTY_AUX)).toHaveLength(0);
    expect(buildVaaben(EMPTY_AUX)).toHaveLength(0);
    expect(buildEmbeder(m, EMPTY_AUX)).toHaveLength(0);
  });
});

describe('tom model', () => {
  it('giver tomme lister overalt', () => {
    const m = mkModel([]);
    const { portraits, citater } = buildPortraitAndCitat(m);
    expect(portraits).toHaveLength(0);
    expect(citater).toHaveLength(0);
    expect(buildJubilaeer(m, 2026)).toHaveLength(0);
    expect(buildForbundet(m)).toHaveLength(0);
    expect(buildSlaegt(m, null, null)).toHaveLength(0);
  });
});
