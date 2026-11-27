// Batch 6 (mobil-paritet): familieblokken bor nu i core. Web's egen test (web/src/data/__tests__/fokusTrae.test.ts)
// dækker reglerne gennem re-eksporten; her prøves den delte sti selv, med børn fra to udgaver.
import { describe, expect, it } from 'vitest';
import { buildModel, type AppPerson, type BogNr, type Db } from '../index';
import type { Model } from '../types';
import { BOERN_UDEN_AEGTESKAB, byggFokusRaekker } from '../fokusTrae';
import { childrenOf, parentsOf } from '../modelTraversering';
import { konfTekst } from '../konfTekst';
import { vielsesDatoerPrFamilie } from '../vielse';

const P = (id: string, name: string, born: number | null = null): AppPerson =>
  ({ id, name, born, died: null, years: '', title: '', bio: '', privat: false, koen: null });
const nr = (sourceId: string, n: number): BogNr => ({ sourceId, linje: 'V', nr: n, nrLabel: null });

// Far med to ægteskaber; C findes kun i 1939 (nr. 2 dér), de øvrige i 2018-20.
const db: Db = {
  persons: [P('F', 'Far'), P('M1', 'Mor1'), P('M2', 'Mor2'), P('A', 'Anna', 1700), P('B', 'Bo', 1690), P('C', 'Carl', 1695), P('D', 'Dan', 1710)],
  unions: [
    { id: 'f1', p1: 'F', p2: 'M1', p2_name: null, year: null },
    { id: 'f2', p1: 'F', p2: 'M2', p2_name: null, year: null },
  ],
  parentChild: [
    { child: 'B', parent: 'F', union: 'f1' }, { child: 'C', parent: 'F', union: 'f1' }, { child: 'A', parent: 'F', union: 'f1' },
    { child: 'D', parent: 'F', union: 'f2' },
  ],
};
const model: Model = {
  ...buildModel(db),
  bogNrBy: {
    F: [nr('20', 1), nr('10', 1)],
    B: [nr('20', 2), nr('10', 1)], C: [nr('10', 2)], A: [nr('20', 3), nr('10', 3)], D: [nr('20', 4)],
  },
  udgaver: [{ sourceId: '20', aar: 2018, label: 'DAA 2018-20' }, { sourceId: '10', aar: 1939, label: 'DAA 1939' }],
};

describe('byggFokusRaekker (core)', () => {
  it('børn pr. ægteskab i bogens rækkefølge; et 1939-barn flettes ind på sin plads', () => {
    const r = byggFokusRaekker(model, 'F')!;
    expect(r.aegteskaber.map((a) => a.navn)).toEqual(['Mor1', 'Mor2']);
    expect(r.boerneGrupper.map((g) => [g.aegteskab?.navn ?? null, g.boern.map((b) => b.person.id)]))
      .toEqual([['Mor1', ['B', 'C', 'A']], ['Mor2', ['D']]]);
    expect(r.boerneNote).toBeNull();
    expect(r.antalBoern).toBe(4);
  });

  it('børn uden kendt ægteskab får den udtrykkelige sætning', () => {
    const m: Model = { ...buildModel({ ...db, parentChild: [...db.parentChild, { child: 'X', parent: 'F', union: '__none' }], persons: [...db.persons, P('X', 'Xenia')] }), bogNrBy: model.bogNrBy, udgaver: model.udgaver };
    const r = byggFokusRaekker(m, 'F')!;
    const sidste = r.boerneGrupper[r.boerneGrupper.length - 1];
    expect(sidste.aegteskab).toBeNull();
    expect(sidste.boern.map((b) => b.person.id)).toEqual(['X']);
    expect(r.boerneNote).toBe(BOERN_UDEN_AEGTESKAB);
  });

  it('traverseringen og konfidensordet er de flyttede', () => {
    expect(childrenOf(model, 'F').map((p) => p.id).sort()).toEqual(['A', 'B', 'C', 'D']);
    expect(parentsOf(model, 'D').map((p) => p.id)).toEqual(['F']);
    expect([konfTekst('omstridt'), konfTekst('formodet'), konfTekst('sandsynlig'), konfTekst(undefined)]).toEqual(['omstridt', 'formodet', '', '']);
  });
});

describe('vielsesDatoerPrFamilie', () => {
  it('mest præcise dato vinder pr. familie; tomme og ukendte kæder udelades', () => {
    const ud = vielsesDatoerPrFamilie(
      [{ id: 1, subjekt_id: 100 }, { id: 2, subjekt_id: 100 }, { id: 3, subjekt_id: 200 }, { id: 4, subjekt_id: 300 }],
      [{ target_id: 1, valgt_assertion_id: 11 }, { target_id: 2, valgt_assertion_id: 12 }, { target_id: 3, valgt_assertion_id: null }, { target_id: 4, valgt_assertion_id: 99 }],
      [
        { id: 11, date_min: '1670-01-01', date_max: '1670-12-31' },
        { id: 12, date_min: '1670-11-18', date_max: '1670-11-18' },
      ],
    );
    expect(ud).toEqual({ '100': '⚭ 18. nov. 1670' });
  });
});

describe('byggFokusRaekker: skilt', () => {
  const skilt = { ...model, skilsmisser: { '1': { dateMin: null, dateMax: null } } };
  it('skilt-flag pr. ægteskab; false uden skilsmisse og ved ukendt (null)', () => {
    expect(byggFokusRaekker(skilt, 'F')!.aegteskaber.map((a) => a.skilt)).toEqual([true, false]);
    expect(byggFokusRaekker({ ...model, skilsmisser: {} }, 'F')!.aegteskaber.map((a) => a.skilt)).toEqual([false, false]);
    expect(byggFokusRaekker({ ...model, skilsmisser: null }, 'F')!.aegteskaber.map((a) => a.skilt)).toEqual([false, false]);
  });
});
