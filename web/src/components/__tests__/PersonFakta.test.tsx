// @vitest-environment jsdom
// B11 (spec 2026-10-29 §4.4): fakta-sektionen i persondetaljen med tre kildevisninger.
import { render, screen } from '@testing-library/react';
import type { PersonFactView } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { PersonFakta } from '../PersonFakta';

const fakta: PersonFactView[] = [
  { factId: '1', faktatype: 'navn', omstridt: false, others: [],
    chosen: { assertionId: '1', value: 'Anna', source: { kind: 'bundet', label: 'DAA 2018-20, s. 45 · I-32', recordRef: 'r1' } } },
  { factId: '2', faktatype: 'fødsel', omstridt: false, others: [],
    chosen: { assertionId: '2', value: '1701', source: { kind: 'import', label: 'DAA 1939, s. 123', recordRef: null } } },
  { factId: '3', faktatype: 'begravelse', omstridt: false, others: [],
    chosen: { assertionId: '3', value: '—', source: { kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null } } },
  { factId: '4', faktatype: 'død', omstridt: true, chosen: null,
    others: [
      { assertionId: '41', value: '1760', source: { kind: 'import', label: 'DAA 2018-20', recordRef: null } },
      { assertionId: '42', value: '1761', source: { kind: 'import', label: 'DAA 1939, s. 9', recordRef: null } },
    ] },
];

describe('PersonFakta', () => {
  it('viser overskrift, værdier og de tre kildevisninger', () => {
    render(<PersonFakta facts={fakta} error={false} />);
    expect(screen.getByText('Fakta')).toBeTruthy();
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.getByText('bundet til bogens post')).toBeTruthy();
    expect(screen.getByText('DAA 2018-20, s. 45 · I-32')).toBeTruthy();
    expect(screen.getAllByText('fra den oprindelige import').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('DAA 1939, s. 123')).toBeTruthy();
    expect(screen.getByText('Kilde ikke registreret')).toBeTruthy();
  });

  it('omstridt viser mærket og Andre udsagn med hver sin kilde', () => {
    render(<PersonFakta facts={fakta} error={false} />);
    expect(screen.getByText('omstridt')).toBeTruthy();
    expect(screen.getByText('Andre udsagn')).toBeTruthy();
    expect(screen.getByText('1761')).toBeTruthy();
    expect(screen.getByText('DAA 1939, s. 9')).toBeTruthy();
  });

  it('fejl viser »Fakta kunne ikke hentes«', () => {
    render(<PersonFakta facts={[]} error={true} />);
    expect(screen.getByText('Fakta kunne ikke hentes')).toBeTruthy();
  });

  it('tom liste uden fejl renderer intet', () => {
    const { container } = render(<PersonFakta facts={[]} error={false} />);
    expect(container.textContent).toBe('');
  });
});
