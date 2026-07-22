// @vitest-environment jsdom
import { render, screen } from '@testing-library/react';
import { PresensGrenSektion } from '../PresensView';
import type { PresensGren } from '@daa/core';

const gren: PresensGren = {
  anker: { personId: 'A', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' },
  ankerBlok: { id: 'A', levende: true, forbindelsesled: false, partnere: [{ id: 'P', levende: true }], boern: [
    { id: 'B', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false },
  ], usikker: false },
  grupper: [
    { overskrift: 'Søstre', niveau: 1, art: 'soeskende', usikker: false, roedder: [
      { id: 'S', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: true },
    ] },
  ],
};
const navnAf = (id: string) => ({ A: 'Anker Person', P: 'Partner Person', B: 'Barn Person', S: 'Søster Person' }[id] ?? id);
const aarAf = () => '';

test('gren-sektion viser overskrift, ankerblok, gruppe og usikkerheds-markering', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('II linje, 1. gren')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
  expect(screen.getByText('Søstre')).toBeTruthy();
  expect(screen.getByText('Søster Person')).toBeTruthy();
  expect(screen.getByTitle(/usikkert slægtskab/i)).toBeTruthy(); // konfidens-markering (invariant 7)
});
