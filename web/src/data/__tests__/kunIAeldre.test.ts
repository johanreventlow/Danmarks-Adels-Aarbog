import { buildModel, type BogNr } from '@daa/core';
import { describe, expect, it } from 'vitest';
import type { Model } from '../types';
import { kunIAeldreTekst } from '../kunIAeldre';

const N = (sourceId: string): BogNr => ({ sourceId, linje: 'V', nr: 1, nrLabel: null });
const model: Model = {
  ...buildModel({ persons: [], unions: [], parentChild: [] }),
  indexes: { ...buildModel({ persons: [], unions: [], parentChild: [] }).indexes, parentsByChild: { B: ['F'] } },
  bogNrBy: { F: [N('20')], B: [N('10')] },
  udgaver: [
    { sourceId: '20', aar: 2018, label: 'DAA 2018-20' },
    { sourceId: '10', aar: 1939, label: 'DAA 1939' },
  ],
};

describe('kunIAeldreTekst', () => {
  it('giver den præcise mærke-, forklarings- og sidetekst', () => {
    expect(kunIAeldreTekst(model, 'B')).toEqual({
      maerke: 'Kun i DAA 1939', forklaring: 'Står i DAA 1939, men ikke i DAA 2018-20.',
      linje: 'Nævnes kun i DAA 1939 og er ikke med i DAA 2018-20.',
    });
  });

  it('flere udgaver forbindes med og, nyeste først', () => {
    expect(kunIAeldreTekst({
      ...model, bogNrBy: { F: [N('20')], B: [N('10'), N('15')] },
      udgaver: [...model.udgaver!, { sourceId: '15', aar: 1982, label: 'DAA 1982' }],
    }, 'B')).toEqual({
      maerke: 'Kun i DAA 1982 og DAA 1939',
      forklaring: 'Står i DAA 1982 og DAA 1939, men ikke i DAA 2018-20.',
      linje: 'Nævnes kun i DAA 1982 og DAA 1939 og er ikke med i DAA 2018-20.',
    });
  });

  it('person i begge udgaver giver null', () => {
    expect(kunIAeldreTekst({ ...model, bogNrBy: { F: [N('20')], B: [N('10'), N('20')] } }, 'B')).toBeNull();
  });

  it('ukendt kilde udelades fra barnets liste', () => {
    expect(kunIAeldreTekst({ ...model, bogNrBy: { F: [N('20')], B: [N('ukendt'), N('10')] } }, 'B')?.maerke)
      .toBe('Kun i DAA 1939');
  });

  it('kun ukendte kilder eller manglende udgaver giver null', () => {
    expect(kunIAeldreTekst({ ...model, bogNrBy: { F: [N('20')], B: [N('ukendt')] } }, 'B')).toBeNull();
    expect(kunIAeldreTekst({ ...model, udgaver: undefined }, 'B')).toBeNull();
  });

  it('person uden forældre giver null', () => {
    expect(kunIAeldreTekst(model, 'F')).toBeNull();
  });
});
