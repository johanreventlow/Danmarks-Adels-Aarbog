import { describe, expect, it } from 'vitest';
import { buildModel } from '../buildModel';
import { lineageContextKey } from '../lineage';
import { byggStatuslinje, egenAdelstitel, traeTitel } from '../statuslinje';
import type { AppPerson, Koen, Lineage, Model } from '../types';

const k = (lineageId: string) => lineageContextKey({ slaegtId: '1', lineageId });
const k4 = k('4');
const k5 = k('5');
const k7 = k('7');

const p = (id: string, koen: Koen, title = ''): AppPerson => ({
  id, name: id, born: null, died: null, years: '', title, bio: '', privat: false, koen,
});

const persons: AppPerson[] = [
  p('v44', 'mand', 'Greve'), p('iv1', 'mand', 'Greve'), p('datter', 'kvinde', 'Komtesse'),
  p('friherre', 'mand', 'Friherre'), p('utitlet', 'mand'), p('stifter', 'mand', 'Greve'),
  p('ingen', 'mand'),
  // Beke: født komtesse, ingift, gift med lensgreve i V
  p('beke', 'kvinde', 'Komtesse'), p('lensgreveV', 'mand', 'Lensgreve'),
  p('ingiftUdenTitel', 'kvinde'), p('greveIV', 'mand', 'Greve'),
  p('komtesseGiftBorgerlig', 'kvinde', 'Komtesse'), p('borgerlig', 'mand'),
  p('k', 'kvinde'), p('greveV', 'mand', 'Greve'), p('lensgreveV2', 'mand', 'Lensgreve'),
  p('fodtGift', 'kvinde', 'Komtesse'), p('greveAnden', 'mand', 'Greve'),
  p('mandUdenLinje', 'mand', 'Greve'), p('gift2', 'kvinde'),
  p('egen', 'kvinde', 'Grevinde'), p('greveE', 'mand', 'Greve'),
];

const unions = [
  { id: 'f1', p1: 'lensgreveV', p2: 'beke', p2_name: null, year: null },
  { id: 'f2', p1: 'greveIV', p2: 'ingiftUdenTitel', p2_name: null, year: null },
  { id: 'f3', p1: 'borgerlig', p2: 'komtesseGiftBorgerlig', p2_name: null, year: null },
  { id: 'f4', p1: 'greveV', p2: 'k', p2_name: null, year: null },
  { id: 'f5', p1: 'lensgreveV2', p2: 'k', p2_name: null, year: null },
  { id: 'f6', p1: 'greveAnden', p2: 'fodtGift', p2_name: null, year: null },
  { id: 'f7', p1: 'mandUdenLinje', p2: 'gift2', p2_name: null, year: null },
  { id: 'f8', p1: 'greveE', p2: 'egen', p2_name: null, year: null },
];

const lineage: Lineage = {
  byPerson: {
    v44: [k5], iv1: [k4], datter: [k5], friherre: [k7], utitlet: [k5], stifter: [k5],
    lensgreveV: [k5], greveIV: [k4], greveV: [k5], lensgreveV2: [k5], greveAnden: [k7],
    greveE: [k5], fodtGift: [k5], mandUdenLinje: ['legacy-source:1:V'],
  },
  list: [
    { linje: k4, count: 1, headId: '298', navn: 'IV' },
    { linje: k5, count: 3, headId: 'stifter', navn: 'V' },
    { linje: k7, count: 1, headId: '999', navn: 'VII' },
  ],
  navn: {},
};

const m: Model = {
  ...buildModel({ persons, unions, parentChild: [] }),
  lineage,
  adelsnavne: { '4': 'de Reventlou', '5': 'af Reventlow' },
  slaegtsnavn: 'Reventlow',
  skilsmisser: {},
};

describe('byggStatuslinje', () => {
  it('hof-del + egen titel + linjens adelsnavn', () => {
    expect(byggStatuslinje(m, 'v44', ['Kammerherre'])).toBe('Kammerherre, greve af Reventlow');
    expect(byggStatuslinje(m, 'iv1', [])).toBe('Greve de Reventlou');
    expect(byggStatuslinje(m, 'datter', null)).toBe('Komtesse af Reventlow');
  });
  it('linje uden regel: titlen alene; uden titel: hoftitlen alene; intet: null', () => {
    expect(byggStatuslinje(m, 'friherre', null)).toBe('Friherre');
    expect(byggStatuslinje(m, 'utitlet', ['Kammerherre'])).toBe('Kammerherre');
    expect(byggStatuslinje(m, 'ingen', [])).toBeNull();
  });
  it('linjens stifter: ingen partikel', () => {
    expect(byggStatuslinje(m, 'stifter', null)).toBe('Greve');
  });
  it('gift-del: komtesse gift lensgreve; ingift uden titel; ingen hof for kvinder', () => {
    expect(byggStatuslinje(m, 'beke', ['dekanesse'])).toBe('Komtesse, gift lensgrevinde af Reventlow');
    expect(byggStatuslinje(m, 'datter', ['Kammerherre'])).toBe('Komtesse af Reventlow');
    expect(byggStatuslinje(m, 'ingiftUdenTitel', null)).toBe('Gift grevinde de Reventlou');
    expect(byggStatuslinje(m, 'komtesseGiftBorgerlig', null)).toBe('Komtesse');
  });
  it('mand uden regel men med linje: slægtsnavnet uden partikel; fødselsadelsnavn bevares', () => {
    expect(byggStatuslinje(m, 'fodtGift', null)).toBe('Komtesse af Reventlow, gift grevinde Reventlow');
  });
  it('mand uden ikke-teknisk linje og uden regel: ingen gift-del', () => {
    expect(byggStatuslinje(m, 'gift2', null)).toBeNull();
  });
  it('skilt og ukendt skilsmisse giver ingen gift-del (fail-closed)', () => {
    const mSkilt: Model = { ...m, skilsmisser: { '1': { dateMin: null, dateMax: null } } };
    expect(byggStatuslinje(mSkilt, 'beke', null)).toBe('Komtesse');
    expect(byggStatuslinje({ ...m, skilsmisser: null }, 'beke', null)).toBe('Komtesse');
    expect(byggStatuslinje({ ...m, skilsmisser: undefined }, 'beke', null)).toBe('Komtesse');
  });
  it('flere ægteskaber: højeste rang vinder', () => {
    expect(byggStatuslinje(m, 'k', null)).toBe('Gift lensgrevinde af Reventlow');
  });
  it('en skilt lensgreve tæller ikke; den gældende greve gør', () => {
    const mSkilt: Model = { ...m, skilsmisser: { '5': { dateMin: null, dateMax: null } } };
    expect(byggStatuslinje(mSkilt, 'k', null)).toBe('Gift grevinde af Reventlow');
  });
  it('en mand får ingen gift-del, og hof-delen kræver mand og hentede detaljer', () => {
    expect(byggStatuslinje(m, 'lensgreveV', ['Kammerherre'])).toBe('Kammerherre, lensgreve af Reventlow');
    expect(byggStatuslinje(m, 'v44', null)).toBe('Greve af Reventlow');
  });
});

describe('egenAdelstitel og traeTitel', () => {
  it('titlen følger navnet: fødselstitlen, ikke ægteskabstitlen', () => {
    expect(egenAdelstitel(m, 'beke')).toBe('Komtesse');
    expect(traeTitel(m, 'beke')).toBe('Komtesse');
    expect(traeTitel(m, 'v44')).toBe('Greve');
  });
  it('ingen adelstitel (hof- eller tom titel) → null', () => {
    const m2 = { ...m, byId: { ...m.byId, utitlet: { ...m.byId.utitlet, title: 'Kammerherre' } } };
    expect(egenAdelstitel(m2, 'utitlet')).toBeNull();
    expect(traeTitel(m, 'ingen')).toBeNull();
  });
  it('kvindes titel lig mandens feminiserede titel er en ægteskabstitel → null', () => {
    expect(egenAdelstitel(m, 'egen')).toBeNull();
    expect(byggStatuslinje(m, 'egen', null)).toBe('Gift grevinde af Reventlow');
  });
  it('bogens stavning bevares', () => {
    const m2 = { ...m, byId: { ...m.byId, datter: { ...m.byId.datter, title: 'Comtesse' } } };
    expect(traeTitel(m2, 'datter')).toBe('Comtesse');
    expect(byggStatuslinje(m2, 'datter', null)).toBe('Comtesse af Reventlow');
  });
});
