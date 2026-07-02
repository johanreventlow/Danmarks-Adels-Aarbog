// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { TreeView } from '../../Folgesvend';
import { buildModel } from '../../data/buildModel';
import type { AppPerson, Db } from '../../data/types';

const P = (id: string, o: Partial<AppPerson> = {}): AppPerson => ({
  id, name: id, born: null, died: null, years: '', title: '', bio: '', privat: false, ...o,
});
const db = (persons: AppPerson[], parentChild: Db['parentChild']): Db => ({ persons, unions: [], parentChild });

// R → {C1, C2}; C1 → {G1, G2}.
const model = buildModel(
  db(
    [P('R'), P('C1'), P('C2'), P('G1'), P('G2')],
    [
      { child: 'C1', parent: 'R', union: 'u1' },
      { child: 'C2', parent: 'R', union: 'u1' },
      { child: 'G1', parent: 'C1', union: 'u2' },
      { child: 'G2', parent: 'C1', union: 'u2' },
    ],
  ),
);

describe('TreeView', () => {
  it('viser Fokus-variant som standard (ingen kolonne-generationer)', () => {
    render(<TreeView model={model} focusId="R" onPick={vi.fn()} onFocus={vi.fn()} />);
    expect(screen.getByText('Denne generation')).toBeTruthy(); // variant A-markør
    expect(screen.queryByText('Generation 1')).toBeNull();
  });

  it('skifter til Kolonner-variant: kol 0 = fokus, kol 1 = børn', () => {
    render(<TreeView model={model} focusId="R" onPick={vi.fn()} onFocus={vi.fn()} />);
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText('Generation 1')).toBeTruthy();
    expect(screen.getByText('Generation 2')).toBeTruthy();
    expect(screen.getByText('C1')).toBeTruthy();
    expect(screen.getByText('C2')).toBeTruthy();
    expect(screen.queryByText('Generation 3')).toBeNull(); // intet valgt endnu
  });

  it('drill-down: valg af et barn åbner næste generation + kalder onFocus (uden historik)', () => {
    const onPick = vi.fn();
    const onFocus = vi.fn();
    render(<TreeView model={model} focusId="R" onPick={onPick} onFocus={onFocus} />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('C1')); // vælg barn med børn
    expect(onFocus).toHaveBeenCalledWith('C1'); // drill = historik-fri fokus
    expect(onPick).not.toHaveBeenCalled();      // IKKE historik-hoppet (variant A-vejen)
    expect(screen.getByText('Generation 3')).toBeTruthy();
    expect(screen.getByText('G1')).toBeTruthy();
    expect(screen.getByText('G2')).toBeTruthy();
  });

  it('reset ved EKSTERN fokus-ændring: stien foldes til den nye fokus-person', () => {
    const { rerender } = render(<TreeView model={model} focusId="R" onPick={vi.fn()} onFocus={vi.fn()} />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('C1')); // drill R→C1
    fireEvent.click(screen.getByText('G1')); // drill videre til R→C1→G1 (path-hale = G1)
    expect(screen.getByText('Generation 3')).toBeTruthy();

    // Ekstern navigation (fx via sidebar/detalje) sætter en ny focusId der IKKE er path-halen (G1).
    // Modsat: at navigere til den allerede-drillede hale ville (korrekt) bevare stien.
    rerender(<TreeView model={model} focusId="C1" onPick={vi.fn()} onFocus={vi.fn()} />);
    // Variant B bevares, men stien foldes til C1: kol 0 = [C1], kol 1 = [G1, G2], ingen Generation 3.
    expect(screen.getByText('Generation 1')).toBeTruthy();
    expect(screen.getByText('Generation 2')).toBeTruthy();
    expect(screen.queryByText('Generation 3')).toBeNull();
    expect(screen.getByText('G1')).toBeTruthy(); // C1's barn i den friske Generation 2
    expect(screen.queryByText('C2')).toBeNull(); // R's andet barn er ikke længere i stien
  });
});
