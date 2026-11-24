import { buildModel } from '@daa/core';
import { describe, expect, it } from 'vitest';
import {
  blevVoksen, doedForLaengeSiden, harIndhold, harRigtigtNavn, kunForsideVaerdige, type ForsideKontekst,
} from '../forside';
import type { HaendelseItem, Model } from '../types';

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
