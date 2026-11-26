// Personskærmens »Besiddelser« (mobil-paritet): udgave-reglen fra @daa/core, samme gods samlet med alle perioder.
import type { UdgaveFaktaInput } from '@daa/core';
import { godserTilVisning } from '../personGodser';
import type { EstateRef } from '../types';

const udgaver = [{ sourceId: '1', label: 'DAA 1939', aar: 1939 }, { sourceId: '2', label: 'DAA 2018-20', aar: 2018 }];
// Personen er foldet af to rækker: 80 fra 2018-20 og 81 fra 1939 (eksterne nøgler).
const input: UdgaveFaktaInput = { rows: [], udgaver, udgaveForPersonRaekke: { '80': '2', '81': '1' }, fritekstKilde: {} };
const e = (id: string, navn: string, period: string, personId: string): EstateRef => ({ id, navn, period, personId });
const estates: EstateRef[] = [
  e('1', 'Christianssæde', '1700-10', '80'),
  e('1', 'Christianssæde', '1720-30', '80'),
  e('2', 'Pederstrup', '', '80'),
  e('3', 'Brahetrolleborg', '1730', '81'),
  e('1', 'Christianssæde', '1700-10', '81'),
];

describe('godserTilVisning', () => {
  test('valgt udgave: kun dens godser; samme gods én gang med alle perioder', () => {
    expect(godserTilVisning(estates, input, udgaver, '2')).toEqual([
      { id: '1', navn: 'Christianssæde', perioder: '1700-10, 1720-30' },
      { id: '2', navn: 'Pederstrup', perioder: '' },
    ]);
    expect(godserTilVisning(estates, input, udgaver, '1').map((g) => g.navn)).toEqual(['Brahetrolleborg', 'Christianssæde']);
  });

  test('uden valgt udgave: alle godser, perioder samlet uden dubletter', () => {
    expect(godserTilVisning(estates, input, udgaver, null)).toEqual([
      { id: '1', navn: 'Christianssæde', perioder: '1700-10, 1720-30' },
      { id: '2', navn: 'Pederstrup', perioder: '' },
      { id: '3', navn: 'Brahetrolleborg', perioder: '1730' },
    ]);
  });
});
