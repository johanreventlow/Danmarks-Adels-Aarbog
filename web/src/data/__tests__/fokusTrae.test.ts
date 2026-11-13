import { describe, expect, it } from 'vitest';
import { buildModel, type AppPerson, type Db } from '@daa/core';
import type { Model } from '../types';
import { byggFokusRaekker, BOERN_UDEN_AEGTESKAB } from '../fokusTrae';

const P = (id: string, name: string, koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name, born: null, died: null, years: '', title: '', bio: '', privat: false, koen });
const model = (db: Db, ekstra: Partial<Model> = {}): Model => ({ ...(buildModel(db) as unknown as Model), ...ekstra });
const navne = (xs: { person: { name: string } }[]) => xs.map((x) => x.person.name);

describe('byggFokusRaekker', () => {
  it('forældre med rolle efter køn; ingen manglende, når begge er der', () => {
    const m = model({ persons: [P('A', 'Anna'), P('F', 'Far', 'mand'), P('M', 'Mor', 'kvinde')], unions: [],
      parentChild: [{ child: 'A', parent: 'F', union: 'u1' }, { child: 'A', parent: 'M', union: 'u1' }] });
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.foraeldre.map((f) => [f.person.name, f.rolle])).toEqual([['Far', 'Far'], ['Mor', 'Mor']]);
    expect(r.manglendeForaelder).toBeNull();
  });

  it('»Mor ikke angivet i bogen« kun ved én forælder af kendt køn', () => {
    const med = (koen: AppPerson['koen']) => byggFokusRaekker(model({ persons: [P('A', 'Anna'), P('F', 'F', koen)], unions: [],
      parentChild: [{ child: 'A', parent: 'F', union: 'u1' }] }), 'A')!.manglendeForaelder;
    expect(med('mand')).toBe('Mor ikke angivet i bogen');
    expect(med('kvinde')).toBe('Far ikke angivet i bogen');
    expect(med(null)).toBe('Den anden forælder er ikke angivet i bogen');
  });

  it('ingen forældre: forskel på manglende kant og bogens »ukendt«', () => {
    const db: Db = { persons: [P('A', 'Anna')], unions: [], parentChild: [] };
    expect(byggFokusRaekker(model(db), 'A')!.manglendeForaelder).toBe('Forældre ikke angivet i bogen');
    expect(byggFokusRaekker(model(db, { parentsUnknownByPerson: { A: {} as never } }), 'A')!.manglendeForaelder)
      .toBe('Forældrene kendes ikke ifølge bogen');
  });

  it('hele søskendeflokken under begge forældre; halvsøskende kun ved to kendte, forskellige fødselsfamilier', () => {
    const m = model({ persons: [P('A', 'Anna'), P('B', 'Bo'), P('C', 'Cille'), P('D', 'Dan'), P('F', 'Far', 'mand'), P('M', 'Mor', 'kvinde'), P('M2', 'Mor2', 'kvinde')], unions: [],
      parentChild: [
        { child: 'A', parent: 'F', union: 'u1' }, { child: 'A', parent: 'M', union: 'u1' },
        { child: 'B', parent: 'F', union: 'u1' }, { child: 'B', parent: 'M', union: 'u1' },
        { child: 'C', parent: 'F', union: 'u2' }, { child: 'C', parent: 'M2', union: 'u2' }, // halvsøster via Far
        { child: 'D', parent: 'M', union: null as unknown as string }, // ukendt familie → ikke »halv«
      ] });
    const r = byggFokusRaekker(m, 'A')!;
    expect(navne(r.soeskende).sort()).toEqual(['Anna', 'Bo', 'Cille', 'Dan']);
    const s = Object.fromEntries(r.soeskende.map((x) => [x.person.name, x]));
    expect(s.Anna.iFokus).toBe(true);
    expect(s.Bo.halv).toBe(false);
    expect(s.Cille.halv).toBe(true);
    expect(s.Dan.halv).toBe(false);
  });

  it('usikre led bærer ordet', () => {
    const m = model({ persons: [P('A', 'Anna'), P('F', 'Far', 'mand'), P('B', 'Barn')], unions: [],
      parentChild: [{ child: 'A', parent: 'F', union: 'u1' }, { child: 'B', parent: 'A', union: 'u2' }] });
    m.indexes.konfByEdge = { 'A|F': 'formodet', 'B|A': 'omstridt' };
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.foraeldre[0].konf).toBe('formodet');
    expect(r.boerneGrupper[0].boern[0].konf).toBe('omstridt');
    expect(r.harUsikre).toBe(true);
  });

  it('flere ægteskaber: børn pr. ægteskab, når data angiver det; resten samlet med note', () => {
    const m = model({ persons: [P('A', 'Iwan', 'mand'), P('E1', 'Anna'), P('E2', 'Margaretha'), P('K1', 'Joachim'), P('K2', 'Otto'), P('K3', 'Elsabe')],
      unions: [
        { id: 'u1', p1: 'A', p2: 'E1', p2_name: null, year: null },
        { id: 'u2', p1: 'A', p2: 'E2', p2_name: null, year: null },
        { id: 'u3', p1: 'A', p2: 'E2', p2_name: null, year: null }, // samme ægtefælle registreret to gange
      ],
      parentChild: [
        { child: 'K1', parent: 'A', union: 'u1' }, { child: 'K2', parent: 'A', union: 'u3' },
        { child: 'K3', parent: 'A', union: null as unknown as string },
      ] });
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.aegteskaber.map((a) => [a.navn, a.gange])).toEqual([['Anna', 1], ['Margaretha', 2]]);
    expect(r.boerneGrupper.map((g) => [g.aegteskab?.navn ?? null, navne(g.boern)])).toEqual([
      ['Anna', ['Joachim']], ['Margaretha', ['Otto']], [null, ['Elsabe']],
    ]);
    expect(r.boerneNote).toBe(BOERN_UDEN_AEGTESKAB);
    expect(r.antalBoern).toBe(3);
  });

  it('ét ægteskab: børnene samlet uden note', () => {
    const m = model({ persons: [P('A', 'Anna'), P('E', 'Erik'), P('K', 'Karl')],
      unions: [{ id: 'u1', p1: 'E', p2: 'A', p2_name: null, year: null }],
      parentChild: [{ child: 'K', parent: 'A', union: 'u1' }] });
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.aegteskaber.map((a) => a.navn)).toEqual(['Erik']);
    expect(r.boerneGrupper).toHaveLength(1);
    expect(r.boerneGrupper[0].aegteskab).toBeNull();
    expect(r.boerneNote).toBeNull();
  });
});
