import { describe, expect, it } from 'vitest';
import { buildModel, type AppPerson } from '@daa/core';
import type { Model } from '../types';
import { levetid, matchNavn, roererPerioden, soeg, soegFiltre, soegSti, stavemaader, STANDARD_FILTRE } from '../soeg';

const P = (id: string, name: string, born: number | null = null, died: number | null = null): AppPerson =>
  ({ id, name, born, died, years: '', title: '', bio: '', privat: false, koen: null });

describe('filtre i adressen', () => {
  it('tur-retur; kun afvigelser skrives', () => {
    expect(soegSti({ q: 'Conrad' })).toBe('/soeg?q=Conrad');
    expect(soegSti(STANDARD_FILTRE)).toBe('/soeg');
    const f = { ...STANDARD_FILTRE, q: 'a b', type: 'personer' as const, linje: 'k:1', fra: 1600, til: 1900, sort: 'foedt' as const, bm: true };
    expect(soegFiltre(soegSti(f).split('?')[1])).toEqual(f);
  });
  it('type=godser (fra før fase 7a) betyder besiddelser', () => {
    expect(soegFiltre('?type=godser').type).toBe('besiddelser');
  });
  it('ugyldige værdier falder tilbage til standarden', () => {
    expect(soegFiltre('?type=x&sort=y&fra=abc&bm=2')).toEqual(STANDARD_FILTRE);
  });
});

describe('matchNavn', () => {
  it('rang efter hvor søgeordet står; fremhævning af den bogstavrette forekomst', () => {
    expect(matchNavn('Conradina Augusta', 'conrad')).toEqual({ rang: 0, maerker: [[0, 6]] });
    expect(matchNavn('Greve Conrad de Reventlow', 'conrad')).toEqual({ rang: 1, maerker: [[6, 12]] });
    expect(matchNavn('Hans Falconrad', 'conrad')).toEqual({ rang: 2, maerker: [[8, 14]] });
  });
  it('flere søgeord hver for sig, også med titel imellem', () => {
    expect(matchNavn('Greve Conrad de Reventlow', 'conrad reventlow')).toEqual({ rang: 3, maerker: [[6, 12], [16, 25]] });
  });
  it('foldet match uden fremhævning', () => {
    expect(matchNavn('Detlef Reventlow', 'detlev')).toEqual({ rang: 4, maerker: [] });
    expect(matchNavn('Detlef Reventlow', 'reventlov')).toEqual({ rang: 4, maerker: [] });
    expect(matchNavn('Detlef Reventlow', 'holck')).toBeNull();
  });
});

describe('levetid', () => {
  it('åbent endepunkt regnes et menneskeliv fra det kendte; uden årstal kan personen ikke placeres', () => {
    expect(levetid({ born: 1640, died: 1708 })).toEqual([1640, 1708]);
    expect(levetid({ born: null, died: 1708 })).toEqual([1608, 1708]);
    expect(levetid({ born: 1640, died: null })).toEqual([1640, 1740]);
    expect(levetid({ born: null, died: null })).toBeNull();
  });
  it('spændet tæller med, når det rører perioden', () => {
    const p = { born: 1640, died: 1708 };
    expect(roererPerioden(p, 1700, 1900)).toBe(true);
    expect(roererPerioden(p, 1708, null)).toBe(true);
    expect(roererPerioden(p, 1709, null)).toBe(false);
    expect(roererPerioden(p, null, 1639)).toBe(false);
    expect(roererPerioden({ born: null, died: null }, 1600, 1700)).toBeNull();
    expect(roererPerioden({ born: null, died: null }, null, null)).toBe(true);
  });
  it('en usikker dato tæller i hele sin bredde (fixturens »† 1406/1410«)', () => {
    const p = { born: null, died: 1406, doedSpaend: [1406, 1410] as [number, number] };
    expect(levetid(p)).toEqual([1306, 1410]);
    expect(roererPerioden(p, 1408, 1409)).toBe(true);
    expect(roererPerioden({ born: null, died: 1406 }, 1408, 1409)).toBe(false); // uden spændet: kun 1406
  });
});

describe('soeg', () => {
  const model = buildModel({
    persons: [P('1', 'Greve Conrad de Reventlow', 1640, 1708), P('2', 'Conrad Georg Reventlow', 1749, 1815),
      P('3', 'Anna Conradina', null, null), P('4', 'Detlef Reventlow', 1700, null)],
    unions: [], parentChild: [],
  }) as unknown as Model;
  model.lineage = { byPerson: { 1: ['L5'], 2: ['L5'], 4: ['L3'] }, list: [], navn: { L5: 'V. linje', L3: 'III. linje' } } as never;
  const godser = [{ id: 'e1', navn: 'Conradsborg', slags: 'gods', ownerCount: 2 }, { id: 'e2', navn: 'Clausholm', slags: 'gods', ownerCount: 4 }];
  const f = (x: Partial<typeof STANDARD_FILTRE>) => ({ ...STANDARD_FILTRE, ...x });

  it('bedste match først; personer og godser; linjens navn følger med', () => {
    const r = soeg(model, godser, f({ q: 'conrad' }));
    expect(r.personer.map((p) => p.id)).toEqual(['2', '3', '1']);
    expect(r.personer.find((p) => p.id === '1')?.linje).toBe('V. linje');
    expect(r.godser.map((g) => g.navn)).toEqual(['Conradsborg']);
  });
  it('linje og levetid filtrerer kun personer; godser udelades så; personer uden årstal tælles', () => {
    expect(soeg(model, godser, f({ q: 'conrad', linje: 'L5' })).personer.map((p) => p.id)).toEqual(['2', '1']);
    const r = soeg(model, godser, f({ q: 'conrad', fra: 1700, til: 1720 }));
    expect(r.personer.map((p) => p.id)).toEqual(['1']);
    expect(r.udenAar).toBe(1);
    expect(r.godser).toEqual([]);
  });
  it('bm=1 i et delt link hos en læser uden bogmærker filtrerer ikke', () => {
    expect(soeg(model, godser, f({ q: 'conrad', bm: true })).personer).toHaveLength(3);
  });
  it('uden søgeord: kun personer, medmindre besiddelser vælges; type=godser fra før 7a forstås', () => {
    expect(soeg(model, godser, f({})).godser).toEqual([]);
    expect(soeg(model, godser, f({ type: 'besiddelser' })).godser.map((g) => g.navn)).toEqual(['Clausholm', 'Conradsborg']);
  });
  it('bogmærker og sortering efter fødeår', () => {
    expect(soeg(model, godser, f({ bm: true }), new Set(['4', '2'])).personer.map((p) => p.id)).toEqual(['2', '4']);
    expect(soeg(model, godser, f({ sort: 'foedt' })).personer.map((p) => p.id)).toEqual(['1', '4', '2', '3']);
  });
});

describe('stavemaader', () => {
  const navne = ['Conrad Reventlow', 'Detlef Reventlow', 'Anna Holck', 'Adelheid de Reventlou', 'Conradt Holck'];
  it('»Revenlow« (ingen træffere) foreslår de nærmeste ord', () => {
    expect(stavemaader(navne, 'Revenlow')).toEqual(['Reventlow', 'Reventlou']); // nærmeste først
  });
  it('»Reventlow« og »Reventlou« peger på hinanden (foldning alene gør dem ikke ens)', () => {
    expect(matchNavn('Adelheid de Reventlou', 'reventlow')).toBeNull();
    expect(stavemaader(navne, 'Reventlow')).toEqual(['Reventlou']);
    expect(stavemaader(navne, 'Reventlou')).toEqual(['Reventlow']);
  });
  it('kun det første ord med naboer skiftes; ord, søgningen allerede rammer, foreslås ikke', () => {
    expect(stavemaader(navne, 'conrad reventlou')).toEqual(['conrad Reventlow']);
    expect(stavemaader(navne, 'Conrad')).toEqual([]); // Conradt indeholder søgeordet og findes allerede
    expect(stavemaader(navne, 'Xyzzy')).toEqual([]);
  });
  it('det søgeord, der intet rammer, skiftes først; korte ord får ingen naboer', () => {
    const flere = [...navne, 'Otto Reventlow', 'Otte Holck', 'Ida Holck'];
    expect(stavemaader(flere, 'Otto Revenlow')).toEqual(['Otto Reventlow', 'Otto Reventlou']);
    expect(stavemaader(flere, 'Otto')).toEqual([]);
    expect(stavemaader(flere, 'Ida')).toEqual([]);
  });
  it('kønsvarianter er andre navne, ikke stavemåder', () => {
    const ns = ['Christian Holck', 'Christina Holck', 'Christine Holck', 'Benedict Holck', 'Benedicte Holck', 'Frederik Holck', 'Fredrik Holck', 'Friderike Holck'];
    expect(stavemaader(ns, 'Christian')).toEqual([]);
    expect(stavemaader(ns, 'Benedicte')).toEqual([]);
    expect(stavemaader(ns, 'Frederik')).toEqual(['Fredrik']);
  });
});
