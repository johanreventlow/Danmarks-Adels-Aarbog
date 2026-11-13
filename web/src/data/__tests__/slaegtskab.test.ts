import { describe, expect, it } from 'vitest';
import { buildModel, computeRelationship, type AppPerson } from '@daa/core';
import type { Model } from '../types';
import { faellesAneTekst, personForslag, slaegtledTekst, vejTrin } from '../slaegtskab';

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
