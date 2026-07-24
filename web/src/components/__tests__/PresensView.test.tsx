// @vitest-environment jsdom
import { render, screen } from '@testing-library/react';
import { PresensGrenSektion, PresensLinjeSektion } from '../PresensView';
import type { PresensGren } from '@daa/core';
import type { PresensLinjeGruppe } from '@daa/core';
import type { PresensLinjeInfo } from '../../data/presensLinjer';

const gren: PresensGren = {
  anker: { personId: 'A', linje: 'II', gren: 1, raaVaerdi: 'II linje, 1. gren' },
  ankerBlok: { id: 'A', levende: true, forbindelsesled: false, partnere: [{ id: 'P', levende: true }], boern: [
    { id: 'B', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: false },
  ], usikker: false, krydsReference: false },
  grupper: [
    { overskrift: 'Søstre', niveau: 1, art: 'soeskende', usikker: false, roedder: [
      { id: 'S', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: true, krydsReference: false },
      { id: 'S2', levende: true, forbindelsesled: false, partnere: [], boern: [], usikker: false, krydsReference: true },
    ] },
  ],
};
const navnAf = (id: string) => ({ A: 'Anker Person', P: 'Partner Person', B: 'Barn Person', S: 'Søster Person', S2: 'Krydset Person' }[id] ?? id);
const aarAf = () => '';

test('gren-sektion viser overskrift, ankerblok, gruppe og usikkerheds-markering', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('1. gren')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
  expect(screen.getByText('Søstre')).toBeTruthy();
  expect(screen.getByText('Søster Person')).toBeTruthy();
  expect(screen.getByTitle(/usikkert slægtskab/i)).toBeTruthy(); // konfidens-markering (invariant 7)
});

test('krydsReference-node viser en henvisningsnote i stedet for at gentage undertræet', () => {
  render(<PresensGrenSektion gren={gren} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  // Noten sidder i sit eget indlejrede span (samme mønster som ⚠-markøren, review 26/task 8),
  // så getByText matcher den separat fra personnavnets egen direkte tekstknude.
  expect(screen.getByText('(vist andetsteds i denne gren)')).toBeTruthy();
  expect(screen.getByText('Krydset Person')).toBeTruthy();
});

test('linje-sektion viser linjenummer, titel, navn og dens grene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'II', grene: [gren] };
  const info: PresensLinjeInfo = { titel: 'Den grevelige linje af 1673', slaegtsnavn: 'Reventlow', vaaben: null };
  render(<PresensLinjeSektion gruppe={gruppe} info={info} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('II')).toBeTruthy();
  expect(screen.getByText('Den grevelige linje af 1673')).toBeTruthy();
  expect(screen.getByText('Reventlow')).toBeTruthy();
  expect(screen.getByText('1. gren')).toBeTruthy(); // fra den indlejrede gren-sektion
});

test('linje-sektion uden info (data endnu ikke tilknyttet) viser stadig grenene', () => {
  const gruppe: PresensLinjeGruppe = { linje: 'IV', grene: [gren] };
  render(<PresensLinjeSektion gruppe={gruppe} info={undefined} navnAf={navnAf} aarAf={aarAf} onPick={() => {}} />);
  expect(screen.getByText('IV')).toBeTruthy();
  expect(screen.getByText('Anker Person')).toBeTruthy();
});
