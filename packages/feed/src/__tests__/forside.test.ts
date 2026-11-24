import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import {
  blevVoksen, doedForLaengeSiden, harIndhold, harRigtigtNavn, kunForsideVaerdige, type ForsideKontekst,
} from '../forside';
import { buildFeedOrder } from '../order';
import { bookmarkPersonId } from '../types';
import type { FeedCard, FeedInputs, HaendelseItem, LivsdatoBy, Model } from '../types';

type P = Model['persons'][number];

// died defaulter til sikkert-død som i order.test.ts.
function person(id: string, over: Partial<P> = {}): P {
  return {
    id, name: 'Person ' + id, born: null, died: 1700, years: '', title: '', bio: '', privat: false,
    parentId: null, spouse: '', ...over,
  } as P;
}

function mkModel(persons: P[]): Model {
  return buildModel({ persons, unions: [], parentChild: [] }) as unknown as Model;
}

function haendelse(id: string, over: Partial<HaendelseItem> = {}): HaendelseItem {
  return {
    id, klausul: 'En klausul.', kategori: null, dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    interessant: false, rygrad: false, kilde: null, ...over,
  };
}

const K: ForsideKontekst = { dagsAar: 2026, haendelserBy: {}, officesBy: {} };

describe('harRigtigtNavn', () => {
  it.each(['(Søn) Reventlow', '( datter ) Reventlow', 'N. N. von Lützow', 'N.N. Lunov eller Anne Juel af Aabjærg'])(
    '%s er ikke et rigtigt navn', (navn) => expect(harRigtigtNavn(navn)).toBe(false),
  );
  it.each(['(Anna?) von Ahlefeldt', 'Christian Ditlev Reventlow', 'Nanna Reventlow'])(
    '%s er et rigtigt navn', (navn) => expect(harRigtigtNavn(navn)).toBe(true),
  );
});

describe('blevVoksen', () => {
  it('død før 15 år er ikke voksen', () => {
    expect(blevVoksen(person('1', { born: 1700, died: 1700 }))).toBe(false);
    expect(blevVoksen(person('1', { born: 1700, died: 1714 }))).toBe(false);
  });
  it('15 år eller ukendt alder tæller som voksen', () => {
    expect(blevVoksen(person('1', { born: 1700, died: 1715 }))).toBe(true);
    expect(blevVoksen(person('1', { born: null, died: 1700 }))).toBe(true);
  });
  it.each(['† ung', 'lille', '+ ung', '† ung.'])('dødsteksten »%s« er ikke voksen', (doedTekst) => {
    expect(blevVoksen(person('1', { born: null, doedTekst }))).toBe(false);
  });
  it('en almindelig dødstekst er voksen', () => {
    expect(blevVoksen(person('1', { born: null, doedTekst: '† 1750' }))).toBe(true);
  });
});

describe('doedForLaengeSiden (dagsAar 2026)', () => {
  it('dødsår mindst 25 år tilbage', () => {
    expect(doedForLaengeSiden(person('1', { died: 2001 }), 2026)).toBe(true);
    expect(doedForLaengeSiden(person('1', { died: 2002 }), 2026)).toBe(false);
  });
  it('et dødsspænd tæller med sit øvre år', () => {
    expect(doedForLaengeSiden(person('1', { died: 1990, doedSpaend: [1990, 2005] }), 2026)).toBe(false);
  });
  it('uden dødsår: født for mindst 145 år siden', () => {
    expect(doedForLaengeSiden(person('1', { died: null, born: 1881 }), 2026)).toBe(true);
    expect(doedForLaengeSiden(person('1', { died: null, born: 1882 }), 2026)).toBe(false);
    expect(doedForLaengeSiden(person('1', { died: null, born: null }), 2026)).toBe(false);
  });
});

describe('harIndhold', () => {
  it('biografi fra 200 tegn', () => {
    expect(harIndhold(person('1', { bio: 'x'.repeat(199) }), K)).toBe(false);
    expect(harIndhold(person('1', { bio: 'x'.repeat(200) }), K)).toBe(true);
  });
  it('titel', () => expect(harIndhold(person('1', { title: 'Kammerherre' }), K)).toBe(true));
  it('kun hændelser uden rygrad tæller', () => {
    expect(harIndhold(person('1'), { ...K, haendelserBy: { '1': [haendelse('h1', { rygrad: true })] } })).toBe(false);
    expect(harIndhold(person('1'), { ...K, haendelserBy: { '1': [haendelse('h1')] } })).toBe(true);
  });
  it('embede', () => {
    expect(harIndhold(person('1'), { ...K, officesBy: { '1': [{ label: 'Amtmand', period: '1750', _y: 1750 }] } }))
      .toBe(true);
  });
  it('billede', () => expect(harIndhold(person('1'), { ...K, personerMedBillede: new Set(['1']) })).toBe(true));
  it('intet', () => expect(harIndhold(person('1'), K)).toBe(false));
});

describe('kunForsideVaerdige', () => {
  it('udtynder persons og byId, men lader indexes være', () => {
    const model = mkModel([
      person('1', { name: 'Christian Reventlow', born: 1700, died: 1760, title: 'Greve' }),
      person('2', { name: '(Søn) Reventlow', born: 1700, died: 1760, title: 'Greve' }),
      person('3', { name: 'Anna Reventlow', born: 1700, died: 1701, title: 'Komtesse' }),
    ]);
    const ud = kunForsideVaerdige(model, K);
    expect(ud.persons.map((p) => p.id)).toEqual(['1']);
    expect(Object.keys(ud.byId)).toEqual(['1']);
    expect(ud.indexes).toBe(model.indexes);
  });
});

describe('buildFeedOrder med forsideKrav', () => {
  const LANG = 'x'.repeat(220);
  const AUX = { godsListe: [], vaabenListe: [], officesBy: {} };
  const base = (over: Partial<FeedInputs> = {}): FeedInputs => ({
    seed: 1, todayISO: '2026-11-24', meId: null, focusId: null, disabledKinds: new Set(), ...over,
  });
  const personKort = (cards: FeedCard[], id: string) => cards.filter((c) => bookmarkPersonId(c) === id);

  it('forsideKrav udelader ikke-forsideværdige', () => {
    const model = mkModel([
      person('1', { name: '(Søn) Reventlow', bio: LANG }),
      person('2', { name: 'Christian Reventlow', bio: LANG }),
      person('3', { name: 'Anna Reventlow', born: 1700, died: 1701, bio: LANG }),
    ]);
    const ids = new Set(buildFeedOrder(model, AUX, base({ forsideKrav: true }))
      .map(bookmarkPersonId).filter((id): id is string => id != null));
    expect([...ids]).toEqual(['2']);
  });

  const enPerson = () => mkModel([person('1', { name: 'Christian Reventlow', bio: LANG, title: 'Greve' })]);
  const livsdatoBy: LivsdatoBy = {
    '1': {
      foedt: { min: '1750-11-03', max: '1750-11-03', qualifier: null },
      doed: { min: '1800-11-20', max: '1800-11-20', qualifier: null },
    },
  };

  it('forsideKrav giver højst ét kort pr. person', () => {
    expect(personKort(buildFeedOrder(enPerson(), AUX, base({ livsdatoBy })), '1').length).toBeGreaterThan(1);
    for (let seed = 1; seed <= 50; seed++) {
      expect(personKort(buildFeedOrder(enPerson(), AUX, base({ seed, livsdatoBy, forsideKrav: true })), '1'))
        .toHaveLength(1);
    }
  });

  it('fastgjort kort vinder over personens øvrige kort', () => {
    const cards = buildFeedOrder(enPerson(), AUX, base({
      livsdatoBy, forsideKrav: true, disabledKinds: new Set(['citat', 'dagensperson']),
      pins: [{ kortNoegle: 'portrait:1', handling: 'pin' }],
    }));
    expect(personKort(cards, '1').map((c) => c.id)).toEqual(['portrait:1']);
  });

  it('kort uden person berøres ikke', () => {
    const aux = { ...AUX, godsListe: ['a', 'b', 'c'].map((id) => ({ id, navn: 'Gods ' + id, slags: 'gods', ownerCount: 1 })) };
    const cards = buildFeedOrder(enPerson(), aux, base({ forsideKrav: true }));
    expect(cards.filter((c) => c.kind === 'gods')).toHaveLength(3);
  });

  it('uden forsideKrav er output uændret', () => {
    const model = mkModel([
      person('1', { name: 'Christian Reventlow', bio: LANG, title: 'Greve' }),
      person('2', { name: 'Anna Reventlow', born: 1700, died: 1701, bio: LANG }),
    ]);
    for (let seed = 1; seed <= 20; seed++) {
      const uden = buildFeedOrder(model, AUX, base({ seed, livsdatoBy }));
      expect(buildFeedOrder(model, AUX, base({ seed, livsdatoBy, forsideKrav: false }))).toEqual(uden);
      expect(personKort(uden, '2').length).toBeGreaterThan(0);
    }
  });
});
