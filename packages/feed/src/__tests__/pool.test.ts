import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import {
  buildEmbeder,
  buildArkivKort,
  buildForbundet,
  buildGods,
  buildJubilaeer,
  buildPortraitAndCitat,
  buildSlaegt,
  buildVaaben,
  firstQuotableSentence,
} from '../pool';
import { stableHash } from '../prng';
import type { FeedAux, FeedCard, HaendelseItem, HaendelserBy, Model } from '../types';

const LONG_BIO =
  'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, '
  + 'virke og eftermæle, skrevet med tilstrækkeligt mange detaljer og sammenhæng.';

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

function haendelse(id: string, over: Partial<HaendelseItem> = {}): HaendelseItem {
  return {
    id, klausul: 'En tilstrækkelig lang klausul om personens historiske liv og virke.',
    kategori: null, dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    interessant: false, rygrad: false, kilde: null, ...over,
  };
}

function citatSlotId(): string {
  for (let i = 0; i < 100; i++) {
    const id = 'citatperson' + i;
    if (stableHash(id) % 4 === 0) return id;
  }
  throw new Error('test-fixture fandt ingen citat-slot');
}

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
  it('bio under MIN_BIO_LAENGDE (et enkelt kort fragment) giver intet person-kort', () => {
    const { portraits, citater } = buildPortraitAndCitat(
      mkModel([person('x', { bio: 'Nævnt i skiftet 1650.' })]),
    );
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

  it('vælger en brugbar klausul deterministisk og registrerer præcis dens hændelses-id', () => {
    const id = citatSlotId();
    const m = mkModel([person(id, { bio: LONG_BIO })]);
    const hs: HaendelserBy = { [id]: [
      haendelse('h1', { klausul: 'Denne første historiske klausul er lang nok til at fungere som et citat.' }),
      haendelse('h2', { klausul: 'Denne anden historiske klausul er også lang nok til at fungere som citat.', kilde: 'DAA 1939, s. 12' }),
      haendelse('rygrad', { rygrad: true, klausul: 'Denne rygradsklausul er lang nok, men må aldrig blive valgt som citat.' }),
    ] };
    const a = buildPortraitAndCitat(m, null, hs);
    const b = buildPortraitAndCitat(m, null, hs);
    expect(a.citater).toEqual(b.citater);
    expect(a.usedCitatHaendelseIds).toEqual(b.usedCitatHaendelseIds);
    expect(a.citater).toHaveLength(1);
    const valgt = a.citater[0] as Extract<FeedCard, { kind: 'citat' }>;
    const valgtId = valgt.quote === hs[id][0].klausul ? 'h1' : 'h2';
    expect(a.usedCitatHaendelseIds).toEqual(new Set([valgtId]));
    expect(valgt.quote).not.toBe(hs[id][2].klausul);
  });

  it('falder tilbage til bio og markerer ingen hændelse når klausulen ikke består længdegaten', () => {
    const id = citatSlotId();
    const out = buildPortraitAndCitat(
      mkModel([person(id, { bio: LONG_BIO })]), null,
      { [id]: [haendelse('kort', { klausul: 'For kort.' })] },
    );
    expect((out.citater[0] as Extract<FeedCard, { kind: 'citat' }>).quote).toBe(LONG_BIO);
    expect(out.usedCitatHaendelseIds.size).toBe(0);
  });

  it('lader citat-slot falde ud når hverken klausul eller bio kan citeres', () => {
    const id = citatSlotId();
    const out = buildPortraitAndCitat(
      mkModel([person(id, { bio: 'Kort.' })]), null,
      { [id]: [haendelse('kort', { klausul: 'For kort.' })] },
    );
    expect(out.portraits).toEqual([]);
    expect(out.citater).toEqual([]);
    expect(out.usedCitatHaendelseIds.size).toBe(0);
  });

  it('uden hændelsesargument er output identisk med eksplicit tomt hændelses-map', () => {
    const m = mkModel(Array.from({ length: 12 }, (_, i) => person('r' + i, { bio: LONG_BIO })));
    expect(buildPortraitAndCitat(m)).toEqual(buildPortraitAndCitat(m, null, {}));
  });

  it('filtrerer en citat-kandidat hvis story allerede bruger hændelsen', () => {
    const persons = Array.from({ length: 8 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const model = mkModel(persons);
    const citatPerson = persons.find((candidate) => stableHash(candidate.id) % 4 === 0)!;
    const hs: HaendelserBy = { [citatPerson.id]: [haendelse('h1')] };
    const uden = buildPortraitAndCitat(model, null, hs);
    const med = buildPortraitAndCitat(model, null, hs, new Set(['h1']));
    expect(uden.usedCitatHaendelseIds.has('h1')).toBe(true);
    expect(med.usedCitatHaendelseIds.has('h1')).toBe(false);
    expect(med.citater.find((card) => card.id === 'citat:' + citatPerson.id)).toBeDefined();
  });

  it('uden fjerde argument er output identisk med eksplicit tomt story-sæt', () => {
    const persons = Array.from({ length: 12 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const model = mkModel(persons);
    const hs: HaendelserBy = Object.fromEntries(persons.map((p, i) => [p.id, [haendelse('h' + i)]]));
    expect(buildPortraitAndCitat(model, null, hs))
      .toEqual(buildPortraitAndCitat(model, null, hs, new Set()));
  });
});

describe('buildArkivKort', () => {
  it('filtrerer rygrad/brugte citater og prioriterer dateRaw → år → null', () => {
    const m = mkModel([person('p1', { name: 'Navn P1' })]);
    const hs: HaendelserBy = { p1: [
      haendelse('h3', { dateRaw: 'ca. 1580', dato: { min: '1580-01-01', max: '1580-12-31', qualifier: 'about' } }),
      haendelse('h1', { dato: { min: '1602-04-03', max: '1602-04-03', qualifier: 'exact' }, interessant: true }),
      haendelse('h2'),
      haendelse('rygrad', { rygrad: true }),
      haendelse('brugt'),
    ] };
    const cards = buildArkivKort(m, hs, new Set(['brugt'])) as Array<Extract<FeedCard, { kind: 'arkiv' }>>;
    expect(cards.map((c) => c.id)).toEqual(['arkiv:h1', 'arkiv:h2', 'arkiv:h3']);
    expect(cards.map((c) => c.aarLabel)).toEqual(['1602', null, 'ca. 1580']);
    expect(cards[0]).toMatchObject({ personId: 'p1', name: 'Navn P1', interessant: true });
  });

  it('udelader ukendte person-id’er og håndterer tomt map', () => {
    const m = mkModel([person('kendt')]);
    expect(buildArkivKort(m, { ukendt: [haendelse('h1')] }, new Set())).toEqual([]);
    expect(buildArkivKort(m, {}, new Set())).toEqual([]);
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
  it('ukvalificeret punktinterval fra 1939-konverteren giver paaDagen', () => {
    const persons = [person('j1', { born: 1926 })];
    const livsdatoBy = { j1: { foedt: { min: '1926-07-18', max: '1926-07-18', qualifier: null } } };
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026, livsdatoBy, '2026-07-18'), 'jubilaeum') as Array<{ paaDagen?: boolean }>;
    expect(jub[0].paaDagen).toBe(true);
  });
  it('exact-mærket helårsinterval giver ikke et falsk 1. januar-jubilæum', () => {
    const persons = [person('j1', { born: 1926 })];
    const livsdatoBy = { j1: { foedt: { min: '1926-01-01', max: '1926-12-31', qualifier: 'exact' } } };
    const jub = kinds(buildJubilaeer(mkModel(persons), 2026, livsdatoBy, '2026-01-01'), 'jubilaeum') as Array<{ paaDagen?: boolean }>;
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
