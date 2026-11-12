import { buildModel, type ParentChild, type Union } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { buildFeedOrder, NAEVNT_VINDUE } from '../order';
import { buildNaevnt } from '../pool';
import { TEMP_DISABLED_KINDS } from '../score';
import type { FeedAux, FeedCard, FeedInputs, Model, NaevntGrundlag } from '../types';

function person(id: string, over: Partial<{
  name: string; born: number | null; died: number | null; years: string;
  title: string; bio: string; privat: boolean;
}> = {}) {
  return {
    id, name: 'Person ' + id, born: null, died: 1700, years: '1650–1700', title: '', bio: '',
    privat: false, ...over,
  };
}

function mkModel(
  persons: ReturnType<typeof person>[],
  { unions = [], parentChild = [], uden = [] }: {
    unions?: Union[]; parentChild?: ParentChild[]; uden?: string[];
  } = {},
): Model {
  const model = buildModel({ persons, unions, parentChild }) as unknown as Model;
  const sourcesBy: Model['sourcesBy'] = {};
  for (const p of persons) {
    if (!uden.includes(p.id)) sourcesBy[p.id] = [{ ref: `Linje I, nr. ${p.id}`, work: 'DAA 1939' }];
  }
  return { ...model, sourcesBy };
}

const EMPTY_AUX: FeedAux = { godsListe: [], vaabenListe: [], officesBy: {} };
const GRUNDLAG: NaevntGrundlag = { personerMedMereEndNavn: new Set() };
const LONG_BIO = 'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, '
  + 'virke og eftermæle, skrevet med tilstrækkeligt mange detaljer og sammenhæng.';

function baseInputs(over: Partial<FeedInputs> = {}): FeedInputs {
  return {
    seed: 1, todayISO: '2026-07-18', meId: null, focusId: null,
    disabledKinds: TEMP_DISABLED_KINDS, naevntGrundlag: GRUNDLAG, ...over,
  };
}

const ids = (cards: FeedCard[]) => cards.map((c) => c.id);

describe('buildNaevnt — hvem får kortet', () => {
  it('person med kun navn og bog-nummer får kortet med kilde og overskrift', () => {
    const cards = buildNaevnt(mkModel([person('1')]), GRUNDLAG, EMPTY_AUX, {}, {});
    expect(cards).toEqual([{
      kind: 'naevnt', id: 'naevnt:1', personId: '1', name: 'Person 1', years: '1650–1700',
      relation: null, kilde: 'Linje I, nr. 1', kicker: 'Nævnt i Aarbogen',
    }]);
  });

  it('udelukker enhver tekst (også kort), titel, privat og manglende bog-nummer', () => {
    const model = mkModel([
      person('kort', { bio: 'Nævnt 1650.' }),
      person('titel', { title: 'Kammerherre' }),
      person('privat', { privat: true }),
      person('utallet'),
      person('ok'),
    ], { uden: ['utallet'] });
    expect(ids(buildNaevnt(model, GRUNDLAG, EMPTY_AUX, {}, {}))).toEqual(['naevnt:ok']);
  });

  it('tomt bog-nummer (hverken linje eller nr.) tæller ikke som kilde', () => {
    const model = mkModel([person('1')]);
    const tom = { ...model, sourcesBy: { '1': [{ ref: '', work: 'DAA' }] } };
    expect(buildNaevnt(tom, GRUNDLAG, EMPTY_AUX, {}, {})).toEqual([]);
  });

  it('udelukker personer med embede/gods, embede i aux, hændelser eller historier', () => {
    const model = mkModel(['gods', 'embede', 'haendelse', 'historie', 'ok'].map((id) => person(id)));
    const aux: FeedAux = { ...EMPTY_AUX, officesBy: { embede: [{ label: 'Amtmand', period: '', _y: 0 }] } };
    const cards = buildNaevnt(
      model, { personerMedMereEndNavn: new Set(['gods']) }, aux,
      { haendelse: [{
        id: 'h', klausul: 'x', kategori: null, dato: { min: null, max: null, qualifier: null },
        dateRaw: null, interessant: false, rygrad: true, kilde: null,
      }] },
      { historie: [{
        id: 's', titel: null, tekst: 'x', dato: { min: null, max: null, qualifier: null },
        dateRaw: null, haendelseId: null, publiceretDato: null, kilde: null,
      }] },
    );
    expect(ids(cards)).toEqual(['naevnt:ok']);
  });

  it('udelukker forældre — også når barnet er levende', () => {
    const model = mkModel([
      // Forældrene døde efter barnets fødsel, ellers fjerner buildModel kanten som umulig.
      person('far', { died: 2000 }), person('mor', { died: 2000 }),
      person('barn', { died: null, born: 1990 }),
    ], {
      unions: [{ id: 'f1', p1: 'far', p2: 'mor', p2_name: null, year: null }],
      parentChild: [{ child: 'barn', parent: 'far', union: 'f1' }, { child: 'barn', parent: 'mor', union: 'f1' }],
    });
    // Gennem feedets GDPR-port: barnet er ikke sikkert dødt, forældrene har børn → ingen kort.
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs());
    expect(cards.filter((c) => c.kind === 'naevnt')).toEqual([]);
  });

  it('»Barn af …« nævner kun sikkert døde forældre', () => {
    const model = mkModel([
      person('far', { name: 'Frederik' }), person('mor', { name: 'Mette', died: null, born: 1990 }),
      person('barn'),
    ], {
      unions: [{ id: 'f1', p1: 'far', p2: 'mor', p2_name: null, year: null }],
      parentChild: [{ child: 'barn', parent: 'far', union: 'f1' }, { child: 'barn', parent: 'mor', union: 'f1' }],
    });
    const naevnt = buildFeedOrder(model, EMPTY_AUX, baseInputs()).filter((c) => c.kind === 'naevnt');
    expect(naevnt).toHaveLength(1);
    expect(naevnt[0]).toMatchObject({ personId: 'barn', relation: 'Barn af Frederik' });
  });
});

it('»Barn af …« viser et formodet forældreled med ordet (invariant 7)', () => {
  const model = mkModel([person('far', { name: 'Frederik' }), person('mor', { name: 'Mette' }), person('barn')], {
    unions: [{ id: 'f1', p1: 'far', p2: 'mor', p2_name: null, year: null }],
    parentChild: [
      { child: 'barn', parent: 'far', union: 'f1', konfidens: 'formodet' },
      { child: 'barn', parent: 'mor', union: 'f1', konfidens: 'sikker' },
    ],
  });
  const kort = buildNaevnt(model, GRUNDLAG, EMPTY_AUX, {}, {}).find((c) => c.id === 'naevnt:barn');
  expect(kort).toMatchObject({ relation: 'Barn af Frederik (formodet) og Mette' });
});

describe('buildFeedOrder — naevnt-porten', () => {
  const model = mkModel([person('1'), person('2')]);

  it('uden naevntGrundlag bygges ingen naevnt-kort (fail-closed)', () => {
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ naevntGrundlag: undefined }));
    expect(cards.some((c) => c.kind === 'naevnt')).toBe(false);
  });

  it('disabledKinds kan slå typen fra', () => {
    const disabled = new Set([...TEMP_DISABLED_KINDS, 'naevnt' as const]);
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ disabledKinds: disabled }));
    expect(cards.some((c) => c.kind === 'naevnt')).toBe(false);
  });

  it('samle-tallet trækker placerede naevnt-kort fra', () => {
    const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs());
    const naevnt = cards.filter((c) => c.kind === 'naevnt').length;
    const samle = cards.find((c) => c.kind === 'samle');
    expect(naevnt).toBe(1); // loftet dropper den anden
    expect(samle).toMatchObject({ count: 1 });
  });
});

// Rig fixture: portrætter + mange nævnte (langt flere end portrætter, som i prod).
function rigModel(portraetter: number, naevnte: number): Model {
  return mkModel([
    ...Array.from({ length: portraetter }, (_, i) => person('p' + i, { bio: LONG_BIO })),
    ...Array.from({ length: naevnte }, (_, i) => person('n' + i)),
  ]);
}

describe('buildFeedOrder — højst ét naevnt pr. seks kort', () => {
  it(`intet vindue på ${NAEVNT_VINDUE} kort rummer to naevnt, over mange seeds`, () => {
    const model = rigModel(40, 400);
    for (let seed = 0; seed < 200; seed++) {
      const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed }));
      for (let i = 0; i + NAEVNT_VINDUE <= cards.length; i++) {
        const antal = cards.slice(i, i + NAEVNT_VINDUE).filter((c) => c.kind === 'naevnt').length;
        expect(antal, `seed=${seed}, vindue=${i}`).toBeLessThanOrEqual(1);
      }
    }
  });

  it('R3 holder stadig, og ingen person har både portræt og naevnt', () => {
    const model = rigModel(40, 400);
    for (let seed = 0; seed < 200; seed++) {
      const cards = buildFeedOrder(model, EMPTY_AUX, baseInputs({ seed }));
      let lastPortraitPos = -1;
      cards.forEach((c, i) => { if (c.kind === 'portrait' || c.kind === 'dagensperson') lastPortraitPos = i; });
      for (let i = 0; i + 6 <= cards.length && i <= lastPortraitPos; i++) {
        expect(
          cards.slice(i, i + 6).some((c) => c.kind === 'portrait' || c.kind === 'dagensperson'),
          `seed=${seed}, vindue=${i}`,
        ).toBe(true);
      }
      const portraetPersoner = new Set(cards.filter((c) => c.kind === 'portrait').map((c) => 'personId' in c && c.personId));
      for (const c of cards) {
        if (c.kind === 'naevnt') expect(portraetPersoner.has(c.personId)).toBe(false);
      }
    }
  });

  it('når kun naevnt er tilbage, droppes resten i stedet for at bryde loftet', () => {
    const cards = buildFeedOrder(rigModel(0, 30), EMPTY_AUX, baseInputs());
    expect(cards.filter((c) => c.kind === 'naevnt')).toHaveLength(1);
    expect(cards[cards.length - 1]).toMatchObject({ kind: 'samle', count: 29 });
  });

  it('uden naevntGrundlag (mobilen) er ordningen identisk med en model helt uden nævnte', () => {
    for (let seed = 0; seed < 20; seed++) {
      const uden = buildFeedOrder(rigModel(20, 50), EMPTY_AUX, baseInputs({ seed, naevntGrundlag: undefined }))
        .filter((c) => c.kind !== 'samle');
      const kunPortraetter = buildFeedOrder(rigModel(20, 0), EMPTY_AUX, baseInputs({ seed, naevntGrundlag: undefined }))
        .filter((c) => c.kind !== 'samle');
      expect(ids(uden)).toEqual(ids(kunPortraetter));
    }
  });
});
