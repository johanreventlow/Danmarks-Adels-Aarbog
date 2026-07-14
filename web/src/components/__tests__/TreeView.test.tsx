// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { TreeView } from '../../Folgesvend';
import { buildModel } from '@daa/core';
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
// Minimal søge-bundle (§4): showResults:false → TreeSearch viser kun bjælken, træet renderes.
const search = {
  query: '', setQuery: () => {}, browse: { grouped: false as const, flat: [], letters: [], groups: [] },
  sort: 'navn' as const, setSort: () => {}, activeLetter: null, setActiveLetter: () => {},
  linjeList: [], activeLinje: null, setActiveLinje: () => {},
  bmOnly: false, setBmOnly: () => {}, hasBookmarks: false,
  browsing: false, setBrowsing: () => {}, showResults: false, focusToken: 0, onPick: () => {},
};
const props = { model, onPick: () => {}, onFocus: () => {}, hasBookmark: () => false, onToggleBookmark: () => {}, search };

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
    render(<TreeView model={model} focusId="A" onPick={(id) => (picked = id)} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
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
    rerender(<TreeView model={model} focusId="C1" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    expect(screen.queryByText('Oldebørn')).toBeNull(); // drill foldet
    expect(screen.getByText('Forældre')).toBeTruthy(); // Bo's forældre (Anna)
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.getByText('Ida')).toBeTruthy();       // Bo's barn i frisk Børn-kolonne
  });

  it('ingen ugated kandidat-kolonne: founder uden beviste forældre + genCoords → INGEN "muligt slægtled" (marker-gating kræves, Phase C)', () => {
    const fbModel = buildModel(db([P('P', 'Poul'), P('N1', 'Nabo Et')], []));
    (fbModel as typeof fbModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
      P: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
      N1: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
    };
    render(<TreeView model={fbModel} focusId="P" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.queryByText('muligt slægtled')).toBeNull();
    expect(screen.queryByText('Nabo Et')).toBeNull(); // ingen kandidat vist uden markering
  });
});

describe('TreeView — marker-gatet kandidat-kolonne (Phase C)', () => {
  // Poul (markeret 'forælder ukendt') uden beviste forældre; N1/N2 i forrige slægtled (III/11).
  const mk = (id: string, name: string) => P(id, name);
  const cModel = buildModel(db([mk('P', 'Poul'), mk('N1', 'Nabo Et'), mk('N2', 'Nabo To')], []));
  (cModel as typeof cModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
    P: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null }],
    N1: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
    N2: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
  };
  (cModel as typeof cModel & { parentsUnknownByPerson: unknown }).parentsUnknownByPerson = {
    P: { grade: 'forælder ukendt', kilde: 'DAA 1939 s.97' },
  };

  it('viser kandidat-kolonne med ordlyd, proveniens, kuld-grupper og "muligt slægtled"-tags', () => {
    render(<TreeView model={cModel} focusId="P" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText(/11\. slægtled · III-linjen/)).toBeTruthy();
    expect(screen.getByText('Mulige forældre — kilden navngiver dem ikke')).toBeTruthy();
    expect(screen.getByText('Kilde: DAA 1939 s.97')).toBeTruthy();
    expect(screen.getByText('Nabo Et')).toBeTruthy();
    expect(screen.getByText('Nabo To')).toBeTruthy();
    expect(screen.getByText('Kuld I')).toBeTruthy();
    expect(screen.getByText('Kuld II')).toBeTruthy();
    expect(screen.getAllByText('muligt slægtled').length).toBe(2);
  });

  it('klik på kandidat re-ankrer via onFocus (ren navigation, ingen skrivning)', () => {
    let picked: string | null = null, focused: string | null = null;
    render(<TreeView model={cModel} focusId="P" onPick={(id) => (picked = id)} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Nabo Et'));
    expect(focused).toBe('N1');
    expect(picked).toBeNull();
  });
});

describe('TreeView — nedad-projektion (uforbundne i næste slægtled)', () => {
  // Gottschalk (mand) med sikkert barn; Wulf markeret uforbunden i næste slægtled (samme linje).
  const dModel = buildModel(db(
    [P('G', 'Gottschalk'), P('A', 'Sikkert Barn'), P('W', 'Wulf')],
    [{ child: 'A', parent: 'G', union: 'u' }],
  ));
  (dModel as typeof dModel & { koenSet?: unknown });
  dModel.byId['G'].koen = 'mand';
  (dModel as typeof dModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
    G: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 1, gennem: 1, kuld: null }],
    W: [{ sourceId: '1', linje: 'I', lineageId: '10', parentLineageId: null, lokal: 2, gennem: 2, kuld: null }],
  };
  (dModel as typeof dModel & { parentsUnknownByPerson: unknown }).parentsUnknownByPerson = {
    W: { grade: 'ingen forbindelse angivet', kilde: 'DAA 1939 s.6' },
  };

  it('børne-kolonnen viser de sikre børn OG en "uforbundne i dette slægtled"-sektion med neutral ordlyd', () => {
    render(<TreeView model={dModel} focusId="G" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText('Sikkert Barn')).toBeTruthy();      // bevist barn urørt
    expect(screen.getByText('Uforbundne — placeret efter slægtled, ikke forældreskab')).toBeTruthy();
    expect(screen.getByText('Kilden forbinder dem ikke opad — står i næste slægtled i linjen')).toBeTruthy();
    expect(screen.getByText('Wulf')).toBeTruthy();
    expect(screen.getByText('Kilde: DAA 1939 s.6')).toBeTruthy();
  });

  it('klik på en uforbunden re-ankrer via onFocus (ren navigation)', () => {
    let focused: string | null = null;
    render(<TreeView model={dModel} focusId="G" onPick={() => {}} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} search={search} />);
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Wulf'));
    expect(focused).toBe('W');
  });
});
