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

  it('hele søskendeflokken under begge forældre; halvsøskende kun ved kendte, forskellige andre forældre', () => {
    const m = model({ persons: [P('A', 'Anna'), P('B', 'Bo'), P('C', 'Cille'), P('D', 'Dan'), P('E', 'Eva'), P('F', 'Far', 'mand'), P('M', 'Mor', 'kvinde'), P('M2', 'Mor2', 'kvinde')],
      unions: [
        { id: 'u1', p1: 'F', p2: 'M', p2_name: null, year: null },
        { id: 'u1b', p1: 'F', p2: 'M', p2_name: null, year: null }, // samme par, anden udgaves familie
        { id: 'u2', p1: 'F', p2: 'M2', p2_name: null, year: null },
      ],
      parentChild: [
        { child: 'A', parent: 'F', union: 'u1' }, { child: 'A', parent: 'M', union: 'u1' },
        { child: 'B', parent: 'F', union: 'u1' }, { child: 'B', parent: 'M', union: 'u1' },
        { child: 'C', parent: 'F', union: 'u2' }, { child: 'C', parent: 'M2', union: 'u2' }, // halvsøster via Far
        { child: 'D', parent: 'M', union: null as unknown as string }, // ukendt familie → ikke »halv«
        { child: 'E', parent: 'F', union: 'u1b' }, { child: 'E', parent: 'M', union: 'u1b' }, // helsøster i en anden familie-række
      ] });
    const r = byggFokusRaekker(m, 'A')!;
    expect(navne(r.soeskende).sort()).toEqual(['Anna', 'Bo', 'Cille', 'Dan', 'Eva']);
    const s = Object.fromEntries(r.soeskende.map((x) => [x.person.name, x]));
    expect(s.Anna.iFokus).toBe(true);
    expect(s.Bo.halv).toBe(false);
    expect(s.Cille.halv).toBe(true);
    expect(s.Dan.halv).toBe(false);
    expect(s.Eva.halv).toBe(false); // samme forældrepar, blot en anden familie-række
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
    expect(r.aegteskaber.map((a) => a.navn)).toEqual(['Anna', 'Margaretha']); // samme ægtefælle i to familier = ét ægteskab
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

  it('en familie med kun én partner er ikke et ægteskab', () => {
    const m = model({ persons: [P('H', 'Hartwich', 'mand'), P('K', 'Karl')],
      unions: [{ id: 'u1', p1: 'H', p2: null, p2_name: null, year: null }],
      parentChild: [{ child: 'K', parent: 'H', union: 'u1' }] });
    const r = byggFokusRaekker(m, 'H')!;
    expect(r.aegteskaber).toEqual([]);
    expect(r.boerneGrupper.map((g) => navne(g.boern))).toEqual([['Karl']]);
    expect(r.boerneNote).toBeNull();
  });

  // Conrad-formen (prod 2026-11-21): 2018-20 nummererer Gabel-børnene V/2-7 og Hahn-børnene V/8-17.
  const nr = (linje: string, n: number) => ({ sourceId: '20', linje, nr: n, nrLabel: null });
  const udgaver = [{ sourceId: '20', label: 'DAA 2018-20', aar: 2018 }];

  it('børn i bogens rækkefølge inden for hvert ægteskab', () => {
    const m = model({ persons: [P('A', 'Conrad', 'mand'), P('E1', 'Gabel'), P('E2', 'Hahn'), P('K1', 'K1'), P('K2', 'K2'), P('K3', 'K3'), P('K4', 'K4')],
      unions: [
        { id: 'u1', p1: 'A', p2: 'E1', p2_name: null, year: null },
        { id: 'u2', p1: 'A', p2: 'E2', p2_name: null, year: null },
      ],
      parentChild: [
        { child: 'K3', parent: 'A', union: 'u1' }, { child: 'K1', parent: 'A', union: 'u1' },
        { child: 'K4', parent: 'A', union: 'u2' }, { child: 'K2', parent: 'A', union: 'u2' },
      ] }, { udgaver, bogNrBy: { A: [nr('V', 1)], K1: [nr('V', 2)], K3: [nr('V', 3)], K2: [nr('V', 4)], K4: [nr('V', 5)] } });
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.boerneGrupper.map((g) => [g.aegteskab?.navn ?? null, navne(g.boern)])).toEqual([
      ['Gabel', ['K1', 'K3']], ['Hahn', ['K2', 'K4']],
    ]);
  });

  it('søskende i bogens rækkefølge, også når fokus er et barn (prod: Charlotte Amalie, 392)', () => {
    const m = model({ persons: [P('A', 'Conrad', 'mand'), P('E1', 'Gabel'), P('E2', 'Hahn'), P('K1', 'K1'), P('K2', 'K2'), P('K3', 'K3'), P('K4', 'K4')],
      unions: [
        { id: 'u1', p1: 'A', p2: 'E1', p2_name: null, year: null },
        { id: 'u2', p1: 'A', p2: 'E2', p2_name: null, year: null },
      ],
      parentChild: [
        { child: 'K3', parent: 'A', union: 'u1' }, { child: 'K1', parent: 'A', union: 'u1' },
        { child: 'K4', parent: 'A', union: 'u2' }, { child: 'K2', parent: 'A', union: 'u2' },
        { child: 'K3', parent: 'E1', union: 'u1' }, { child: 'K1', parent: 'E1', union: 'u1' },
      ] }, { udgaver, bogNrBy: { A: [nr('V', 1)], K1: [nr('V', 2)], K3: [nr('V', 3)], K2: [nr('V', 4)], K4: [nr('V', 5)] } });
    expect(navne(byggFokusRaekker(m, 'K1')!.soeskende)).toEqual(['K1', 'K3', 'K2', 'K4']);
  });

  it('ét ægteskab: én gruppe i bogens rækkefølge', () => {
    const m = model({ persons: [P('A', 'Anna'), P('E', 'Erik'), P('K1', 'K1'), P('K2', 'K2'), P('K3', 'K3')],
      unions: [{ id: 'u1', p1: 'E', p2: 'A', p2_name: null, year: null }],
      parentChild: [{ child: 'K3', parent: 'A', union: 'u1' }, { child: 'K1', parent: 'A', union: 'u1' }, { child: 'K2', parent: 'A', union: 'u1' }] },
    { udgaver, bogNrBy: { K1: [nr('V', 7)], K2: [nr('V', 8)], K3: [nr('V', 9)] } });
    const r = byggFokusRaekker(m, 'A')!;
    expect(r.boerneGrupper.map((g) => navne(g.boern))).toEqual([['K1', 'K2', 'K3']]);
  });
});
