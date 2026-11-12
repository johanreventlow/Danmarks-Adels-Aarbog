// @vitest-environment jsdom
// B11 (spec 2026-10-29 §4.4) + 6e-1 (spec 2026-11-12 §5.2-5.3): fakta-sektionen i persondetaljen med tre
// kildevisninger og noter om den anden udgave.
import { render, screen } from '@testing-library/react';
import type { Udgave, UdgaveFaktaLinje, UdgaveFaktaVisning } from '@daa/core';
import { describe, expect, it } from 'vitest';
import { PersonFakta } from '../PersonFakta';

const D39: Udgave = { sourceId: '3', label: 'DAA 1939', aar: 1939 };

const linje = (o: Partial<UdgaveFaktaLinje>): UdgaveFaktaLinje => ({
  noegle: o.faktatype ?? 'x', faktatype: 'navn', vaerdi: '', kilder: [], omstridt: false, andre: [], noter: [], ...o,
});

const visning: UdgaveFaktaVisning = {
  linjer: [
    linje({ noegle: '1', faktatype: 'navn', vaerdi: 'Anna',
      kilder: [{ kind: 'bundet', label: 'DAA 2018-20, s. 45 · I-32', recordRef: 'r1' }] }),
    linje({ noegle: '2', faktatype: 'fødsel', vaerdi: '1701',
      kilder: [{ kind: 'import', label: 'DAA 1939, s. 123', recordRef: null }] }),
    linje({ noegle: '3', faktatype: 'begravelse', vaerdi: '—',
      kilder: [{ kind: 'ingen', label: 'Kilde ikke registreret', recordRef: null }] }),
    linje({ noegle: '4', faktatype: 'død', vaerdi: '', omstridt: true,
      andre: [
        { assertionId: '41', value: '1760', source: { kind: 'import', label: 'DAA 2018-20', recordRef: null } },
        { assertionId: '42', value: '1761', source: { kind: 'import', label: 'DAA 1939, s. 9', recordRef: null } },
      ] }),
  ],
  kunI: [],
};
const tom: UdgaveFaktaVisning = { linjer: [], kunI: [] };

describe('PersonFakta', () => {
  it('viser overskrift, værdier og de tre kildevisninger', () => {
    render(<PersonFakta visning={visning} error={false} />);
    expect(screen.getByText('Fakta')).toBeTruthy();
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.getByText('bundet til bogens post')).toBeTruthy();
    expect(screen.getByText('DAA 2018-20, s. 45 · I-32')).toBeTruthy();
    expect(screen.getAllByText('fra den oprindelige import').length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText('DAA 1939, s. 123')).toBeTruthy();
    expect(screen.getByText('Kilde ikke registreret')).toBeTruthy();
  });

  it('viser alle kilder for en sammenlagt linje', () => {
    render(<PersonFakta visning={{ linjer: [linje({ faktatype: 'titel', vaerdi: 'Greve', kilder: [
      { kind: 'bundet', label: 'DAA 2018-20, s. 137 · III-58', recordRef: 'a' },
      { kind: 'bundet', label: 'DAA 2018-20, s. 201-202 · V-1', recordRef: 'b' },
    ] })], kunI: [] }} error={false} />);
    expect(screen.getByText('DAA 2018-20, s. 137 · III-58')).toBeTruthy();
    expect(screen.getByText('DAA 2018-20, s. 201-202 · V-1')).toBeTruthy();
  });

  it('omstridt viser mærket og Andre udsagn med hver sin kilde', () => {
    render(<PersonFakta visning={visning} error={false} />);
    expect(screen.getByText('omstridt')).toBeTruthy();
    expect(screen.getByText('Andre udsagn')).toBeTruthy();
    expect(screen.getByText('1761')).toBeTruthy();
    expect(screen.getByText('DAA 1939, s. 9')).toBeTruthy();
  });

  it('viser ✓ også i DAA 1939 under en enig linje', () => {
    render(<PersonFakta visning={{ linjer: [linje({ faktatype: 'fødsel', vaerdi: '21. april 1644',
      noter: [{ art: 'enig', udgave: D39 }] })], kunI: [] }} error={false} />);
    const note = screen.getByText('✓ også i DAA 1939');
    expect(screen.getByText('21. april 1644').compareDocumentPosition(note) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('viser DAA 1939 skriver: a; b', () => {
    render(<PersonFakta visning={{ linjer: [linje({ faktatype: 'død', vaerdi: '1708',
      noter: [{ art: 'skriver', udgave: D39, vaerdier: ['a', 'b'] }] })], kunI: [] }} error={false} />);
    expect(screen.getByText('DAA 1939 skriver: a; b')).toBeTruthy();
  });

  it('viser Kun i DAA 1939 sidst', () => {
    const { container } = render(<PersonFakta visning={{
      linjer: [linje({ faktatype: 'navn', vaerdi: 'Conrad' })],
      kunI: [{ udgave: D39, faktatype: 'begravelse', vaerdier: ['Herlufsholm', 'Sorø'] }],
    }} error={false} />);
    const overskrift = screen.getByText('Kun i DAA 1939');
    expect(screen.getByText('Begravet: Herlufsholm; Sorø')).toBeTruthy();
    expect(screen.getByText('Conrad').compareDocumentPosition(overskrift) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(container.textContent?.endsWith('Begravet: Herlufsholm; Sorø')).toBe(true);
  });

  it('kun kunI uden egne linjer viser stadig sektionen', () => {
    render(<PersonFakta visning={{ linjer: [], kunI: [{ udgave: D39, faktatype: 'død', vaerdier: ['1708'] }] }} error={false} />);
    expect(screen.getByText('Fakta')).toBeTruthy();
    expect(screen.getByText('Død: 1708')).toBeTruthy();
  });

  it('fejl viser »Fakta kunne ikke hentes«', () => {
    render(<PersonFakta visning={null} error={true} />);
    expect(screen.getByText('Fakta kunne ikke hentes')).toBeTruthy();
  });

  it('tom visning uden fejl renderer intet', () => {
    expect(render(<PersonFakta visning={tom} error={false} />).container.textContent).toBe('');
    expect(render(<PersonFakta visning={null} error={false} />).container.textContent).toBe('');
  });
});
