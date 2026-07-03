// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { TreeView } from '../../Folgesvend';
import { buildModel } from '../../data/buildModel';
import type { AppPerson, Db } from '../../data/types';

const P = (id: string, name: string): AppPerson => ({
  id, name, born: null, died: null, years: '', title: '', bio: '', privat: false,
});
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

// Farfar+Farmor → Far (+ Mor) → Anna (fokus) → {Bo, Cille}; Bo → Ida → Emil.
const model = buildModel(
  db(
    [
      P('A', 'Anna'), P('F', 'Far'), P('M', 'Mor'), P('GF', 'Farfar'), P('GM', 'Farmor'),
      P('C1', 'Bo'), P('C2', 'Cille'), P('G1', 'Ida'), P('GG', 'Emil'),
    ],
    [
      { child: 'F', parent: 'GF', union: 'u0' },
      { child: 'F', parent: 'GM', union: 'u0' },
      { child: 'A', parent: 'F', union: 'u1' },
      { child: 'A', parent: 'M', union: 'u1' },
      { child: 'C1', parent: 'A', union: 'u2' },
      { child: 'C2', parent: 'A', union: 'u2' },
      { child: 'G1', parent: 'C1', union: 'u3' },
      { child: 'GG', parent: 'G1', union: 'u4' },
    ],
  ),
);
const props = { model, onPick: () => {}, onFocus: () => {}, hasBookmark: () => false, onToggleBookmark: () => {} };

describe('TreeView', () => {
  it('viser Fokus-variant som standard (ingen kolonne-labels)', () => {
    render(<TreeView {...props} focusId="A" />);
    expect(screen.getByText('Denne generation')).toBeTruthy(); // variant A-markør
    expect(screen.queryByText('Forældre')).toBeNull();
  });

  it('Kolonner default: Forældre + Fokus + Børn synlige (begge retninger)', () => {
    render(<TreeView {...props} focusId="A" />);
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText('Forældre')).toBeTruthy();
    expect(screen.getByText('Børn')).toBeTruthy();
    expect(screen.getByText('Far')).toBeTruthy();
    expect(screen.getByText('Mor')).toBeTruthy();
    expect(screen.getByText('Bo')).toBeTruthy();
    expect(screen.getByText('Cille')).toBeTruthy();
    expect(screen.queryByText('Bedsteforældre')).toBeNull(); // intet ane-valg endnu
    expect(screen.queryByText('Børnebørn')).toBeNull();
    // chevrons peger i drill-retningen
    expect(screen.getAllByText('‹').length).toBeGreaterThan(0); // Far har forældre
    expect(screen.getAllByText('›').length).toBeGreaterThan(0); // Bo har barn
  });

  it('ane-drill: vælg Far → Bedsteforældre-kolonne + onFocus (ikke onPick)', () => {
    let picked: string | null = null, focused: string | null = null;
    render(<TreeView model={model} focusId="A" onPick={(id) => (picked = id)} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Far'));
    expect(focused).toBe('F');
    expect(picked).toBeNull();
    expect(screen.getByText('Bedsteforældre')).toBeTruthy();
    expect(screen.getByText('Farfar')).toBeTruthy();
    expect(screen.getByText('Farmor')).toBeTruthy();
  });

  it('efterkommer-drill: vælg Bo → Børnebørn-kolonne', () => {
    render(<TreeView {...props} focusId="A" />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Bo'));
    expect(screen.getByText('Børnebørn')).toBeTruthy();
    expect(screen.getByText('Ida')).toBeTruthy();
  });

  it('reset (BLOCKER-fix): ekstern nav til en node der er i down men IKKE frontier → nulstiller', () => {
    const { rerender } = render(<TreeView {...props} focusId="A" />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Bo'));  // down=[Bo]
    fireEvent.click(screen.getByText('Ida')); // down=[Bo, Ida] → Oldebørn (Emil) vises
    expect(screen.getByText('Oldebørn')).toBeTruthy();
    expect(screen.getByText('Emil')).toBeTruthy();

    // Ekstern nav til Bo: Bo ER i down, men er IKKE frontier (Ida er) → skal NULSTILLE til Bo.
    // (Et fuldt medlemskabs-tjek ville forkert bevare visningen.)
    rerender(<TreeView model={model} focusId="C1" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} />);
    expect(screen.queryByText('Oldebørn')).toBeNull(); // drill foldet
    expect(screen.getByText('Forældre')).toBeTruthy(); // Bo's forældre (Anna)
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.getByText('Ida')).toBeTruthy();       // Bo's barn i frisk Børn-kolonne
  });
});
