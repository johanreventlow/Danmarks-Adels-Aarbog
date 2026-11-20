import { describe, expect, it } from 'vitest';
import { buildModel, computeRelationship, slaegtskabTilMig, type AppPerson, type Db, type Konfidens } from '@daa/core';
import type { Model } from '../types';
import { faellesAneTekst, personForslag, slaegtledTekst, slaegtskabsKontekst, vejTrin } from '../slaegtskab';

const P = (id: string, name: string, years = '', koen: AppPerson['koen'] = null): AppPerson =>
  ({ id, name, born: null, died: null, years, title: '', bio: '', privat: false, koen });

// Otto → Otto d.y. → Friedrich → Magdalena; Friedrich→Magdalena er formodet.
const model = buildModel({
  persons: [P('1', 'Otto Reventlow', '1634', 'mand'), P('2', 'Otto Reventlow', 'ca. 1660–1700', 'mand'),
    P('3', 'Friedrich Reventlow', '', 'mand'), P('4', 'Magdalena Sophia Reventlow', '1745', 'kvinde'),
    P('5', 'Detlef Reventlow'), P('6', 'Lensgreve Conrad Reventlow'), P('7', 'Anna Conradina'), P('8', 'Conradine Holck'), P('9', 'Hans Falconer')],
  unions: [],
  parentChild: [{ child: '2', parent: '1', union: 'u1' }, { child: '3', parent: '2', union: 'u2' }, { child: '4', parent: '3', union: 'u3' }],
}) as unknown as Model;
model.indexes.konfByEdge = { '4|3': 'formodet' };

describe('personForslag', () => {
  it('navnet begynder > et ord begynder > indeholder; dansk alfabetisk inden for hver', () => {
    expect(personForslag(model, 'con').map((f) => f.name)).toEqual(['Conradine Holck', 'Anna Conradina', 'Lensgreve Conrad Reventlow', 'Hans Falconer']);
    expect(personForslag(model, 'otto').map((f) => f.id)).toEqual(['1', '2']);
    expect(personForslag(model, '   ')).toEqual([]);
  });
  it('stavemåde-foldet: Detlev finder Detlef', () => {
    expect(personForslag(model, 'detlev').map((f) => f.name)).toEqual(['Detlef Reventlow']);
  });
  it('bærer leveår, så to med samme navn kan skelnes', () => {
    expect(personForslag(model, 'otto').map((f) => f.years)).toEqual(['1634', 'ca. 1660–1700']);
  });
});

describe('vejen trin for trin', () => {
  const rel = computeRelationship(model as never, '1', '4');
  const line = rel.lines[0];
  it('første person, fælles ane og anden person mærkes; det formodede led bærer ordet', () => {
    const t = vejTrin(line);
    expect(t.map((x) => x.id)).toEqual(['1', '2', '3', '4']);
    expect(t[0]).toMatchObject({ foerste: true, faellesAne: true, anden: false, usikkertLed: null });
    expect(t[3]).toMatchObject({ anden: true, usikkertLed: 'formodet' });
    expect(t[1].usikkertLed).toBeNull();
    expect(line.usikker).toBe(true);
  });
  it('slægtled og fælles ane i ord', () => {
    expect(slaegtledTekst(line)).toBe('Tre slægtled');
    expect(faellesAneTekst(line)).toBe('Fælles ane: Otto Reventlow');
    expect(faellesAneTekst({ ...line, aner: ['A & B', 'C & D'] })).toBe('Fælles aner: A & B · C & D');
  });
});

describe('slaegtskabsKontekst — linjen over navnet set fra »Det er mig«', () => {
  // Træ (som core's relationship.test.ts):  G ─┬─ P1 ─┬─ A
  //                                            │      └─ A2 (mand)
  //                                            └─ P2 ──── B (mand)
  // S (ingen forældre) er gift med B, med A2 og med en ukendt uden id; A er gift med B (fætter-kusine-ægteskab).
  // X har hverken forældre eller ægtefæller.
  const byg = (konf: { 'B|P2'?: Konfidens; 'A2|P1'?: Konfidens } = {}) =>
    buildModel({
      persons: [P('G', 'G'), P('P1', 'P1'), P('P2', 'P2'), P('A', 'A'), P('A2', 'A2', '', 'mand'), P('B', 'B', '', 'mand'), P('S', 'S'), P('X', 'X')],
      unions: [
        { id: 'fG', p1: 'G', p2: null, p2_name: null, year: null },
        { id: 'fP1', p1: 'P1', p2: null, p2_name: null, year: null },
        { id: 'fP2', p1: 'P2', p2: null, p2_name: null, year: null },
        { id: 'uSB', p1: 'S', p2: 'B', p2_name: null, year: null },
        { id: 'uSA2', p1: 'S', p2: 'A2', p2_name: null, year: null },
        { id: 'uAB', p1: 'A', p2: 'B', p2_name: null, year: null },
        { id: 'uS0', p1: 'S', p2: null, p2_name: 'Ukendt', year: null },
      ],
      parentChild: [
        { child: 'P1', parent: 'G', union: 'fG' },
        { child: 'P2', parent: 'G', union: 'fG' },
        { child: 'A', parent: 'P1', union: 'fP1' },
        { child: 'A2', parent: 'P1', union: 'fP1', konfidens: konf['A2|P1'] ?? null },
        { child: 'B', parent: 'P2', union: 'fP2', konfidens: konf['B|P2'] ?? null },
      ],
    } as Db) as unknown as Model;
  const m = byg();

  it('skjult uden »Det er mig«, og når mig ikke findes i modellen', () => {
    expect(slaegtskabsKontekst(m, null, 'B')).toEqual({ art: 'skjult' });
    expect(slaegtskabsKontekst(m, 'findes-ikke', 'B')).toEqual({ art: 'skjult' });
  });

  it('»dig« på min egen side', () => {
    expect(slaegtskabsKontekst(m, 'A', 'A')).toEqual({ art: 'dig' });
  });

  it('min ægtefælle vinder over blodslægtskab (fætter-kusine-ægteskab)', () => {
    expect(slaegtskabsKontekst(m, 'A', 'B')).toEqual({ art: 'min-aegtefaelle' });
  });

  it('blodslægtning: ordet fra den nærmeste linje, sikker', () => {
    expect(slaegtskabsKontekst(m, 'A2', 'B')).toEqual({ art: 'blod', ord: 'din 1. grads fætter', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false });
  });

  it.each(['sandsynlig', 'formodet'] as const)('%s led → sandsynligvis; omstridt led → omstridt', (k) => {
    expect(slaegtskabsKontekst(byg({ 'B|P2': k }), 'A2', 'B')).toMatchObject({ art: 'blod', sikkerhed: 'sandsynligvis', bekraeftetAndenVej: false });
    expect(slaegtskabsKontekst(byg({ 'B|P2': 'omstridt' }), 'A2', 'B')).toMatchObject({ art: 'blod', sikkerhed: 'omstridt' });
  });

  it('usikker nærmeste linje bekræftet af en anden, sikker linje', () => {
    // Som core's alternativSolidLinje-fixtur: A & B er 1. grads fætre via G (Pb→B omstridt) og 2. grads via K.
    const mk7 = (id: string) => P(id, id);
    const single = (id: string) => ({ id, p1: id, p2: null, p2_name: null, year: null });
    const byg7 = (konf: Konfidens) =>
      buildModel({
        persons: ['A', 'B', 'Pa', 'Pb', 'Qa', 'Qb', 'Ra', 'Rb', 'G', 'K'].map(mk7),
        unions: [
          { id: 'uA', p1: 'Pa', p2: 'Qa', p2_name: null, year: null },
          { id: 'uB', p1: 'Pb', p2: 'Qb', p2_name: null, year: null },
          ...['Ra', 'Rb', 'G', 'K'].map(single),
        ],
        parentChild: [
          { child: 'A', parent: 'Pa', union: 'uA' },
          { child: 'A', parent: 'Qa', union: 'uA', konfidens: 'sikker' },
          { child: 'B', parent: 'Pb', union: 'uB', konfidens: konf },
          { child: 'B', parent: 'Qb', union: 'uB', konfidens: 'sikker' },
          { child: 'Pa', parent: 'G', union: 'uPa' },
          { child: 'Pb', parent: 'G', union: 'uPb' },
          { child: 'Qa', parent: 'Ra', union: 'uQa', konfidens: 'sikker' },
          { child: 'Qb', parent: 'Rb', union: 'uQb', konfidens: 'sikker' },
          { child: 'Ra', parent: 'K', union: 'uRa', konfidens: 'sikker' },
          { child: 'Rb', parent: 'K', union: 'uRb', konfidens: 'sikker' },
        ],
      } as Db) as unknown as Model;
    expect(slaegtskabsKontekst(byg7('omstridt'), 'A', 'B')).toEqual({ art: 'blod', ord: 'din 1. grads fætter/kusine', sikkerhed: 'omstridt', veje: 2, bekraeftetAndenVej: true });
    expect(slaegtskabsKontekst(byg7(null), 'A', 'B')).toMatchObject({ art: 'blod', sikkerhed: 'sikker', veje: 2, bekraeftetAndenVej: false });
  });

  it('ordet følger den nærmeste linjes egen retning, aldrig »dobbelt«', () => {
    // G1 → A, P; P → B; G2 → B, Q; Q → A. B er både nevø og onkel til A; core slår linjerne sammen.
    const mand = (id: string) => P(id, id, '', 'mand');
    const mr = buildModel({
      persons: ['G1', 'G2', 'P', 'Q', 'A', 'B'].map(mand),
      unions: [
        { id: 'uA', p1: 'G1', p2: 'Q', p2_name: null, year: null },
        { id: 'uB', p1: 'P', p2: 'G2', p2_name: null, year: null },
      ],
      parentChild: [
        { child: 'A', parent: 'G1', union: 'uA' },
        { child: 'A', parent: 'Q', union: 'uA' },
        { child: 'B', parent: 'P', union: 'uB' },
        { child: 'B', parent: 'G2', union: 'uB' },
        { child: 'P', parent: 'G1', union: 'uG1' },
        { child: 'Q', parent: 'G2', union: 'uG2' },
      ],
    } as Db) as unknown as Model;
    const l0 = computeRelationship(mr, 'A', 'B').lines[0];
    const k = slaegtskabsKontekst(mr, 'A', 'B');
    expect(k.art).toBe('blod');
    if (k.art !== 'blod') return;
    expect(k.ord).toBe(slaegtskabTilMig(l0.d1, l0.d2, { koen: 'mand', half: l0.half }));
    expect(k.ord).not.toMatch(/dobbelt/i);
    // Fixturen rammer faktisk sammenlægningen: én linje med to aner, og ordet er nevø (G1-vejen), ikke »onkel & nevø«.
    expect(l0.multiplicitet).toBe(2);
    expect(k.ord).toBe('din nevø');
  });

  it('indgiftet: nærmeste slægtning blandt ægtefællerne, ordet med ægtefællens køn', () => {
    expect(slaegtskabsKontekst(m, 'A', 'S')).toEqual({ art: 'gift', ord: 'din bror', aegtefaelleId: 'A2', aegtefaelleNavn: 'A2', sikkerhed: 'sikker', veje: 1, bekraeftetAndenVej: false });
  });

  it('ægtefælle uden id og ægtefællepost med fokus selv springes over', () => {
    const ms = byg();
    ms.indexes.spousesBy.S = [{ id: null, name: 'Ukendt' }, { id: 'S', name: 'S' }, ...ms.indexes.spousesBy.S.filter((s) => s.id)];
    expect(slaegtskabsKontekst(ms, 'A', 'S')).toMatchObject({ art: 'gift', aegtefaelleId: 'A2' });
    ms.indexes.spousesBy.S = [{ id: null, name: 'Ukendt' }, { id: 'S', name: 'S' }];
    expect(slaegtskabsKontekst(ms, 'A', 'S')).toEqual({ art: 'ingen' });
  });

  it('indgiftet med usikkert led → sandsynligvis', () => {
    expect(slaegtskabsKontekst(byg({ 'A2|P1': 'formodet' }), 'A', 'S')).toMatchObject({ art: 'gift', aegtefaelleId: 'A2', sikkerhed: 'sandsynligvis' });
  });

  it('ingen fælles ane', () => {
    expect(slaegtskabsKontekst(m, 'A', 'X')).toEqual({ art: 'ingen' });
  });
});
