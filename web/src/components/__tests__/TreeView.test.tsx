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

describe('TreeView — fallback-ring (D1: render af C1s genCoords-baserede ubeviste ring)', () => {
  // Founder 'P' uden beviste forældre; 'Nabo1'/'Nabo2' deler forrige slægtled via genCoords
  // (samme opsætning som src/data/__tests__/tree.test.ts's fallback-ring-suite).
  const fbModel = buildModel(
    db([P('P', 'Poul'), P('N1', 'Nabo Et'), P('N2', 'Nabo To')], []),
  );
  // P er en collapset founder der bærer BEGGE koordinater (V-1 + III-12) — samme opsætning som
  // src/data/__tests__/tree.test.ts's fallback-ring-suite; founder-hop'et lander på III lokal 11,
  // som N1/N2 deler (kuld-adskilt).
  (fbModel as typeof fbModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
    P: [
      { sourceId: '1', linje: 'V', lineageId: '50', parentLineageId: '10', lokal: 1, gennem: 12, kuld: null },
      { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 12, gennem: 12, kuld: null },
    ],
    N1: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'I' }],
    N2: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: 'II' }],
  };

  it('viser genLabel + undertekst + "muligt slægtled"-tags for en fallback-ring', () => {
    render(
      <TreeView model={fbModel} focusId="P" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText(/slægtled.*III-linjen/)).toBeTruthy(); // genLabel
    expect(screen.getByText('slægtled-naboer — ingen bevist som forælder')).toBeTruthy();
    expect(screen.getByText('Nabo Et')).toBeTruthy();
    expect(screen.getByText('Nabo To')).toBeTruthy();
    expect(screen.getAllByText('muligt slægtled').length).toBe(2);
    expect(screen.getByText('Kuld I')).toBeTruthy();
    expect(screen.getByText('Kuld II')).toBeTruthy();
  });

  it('klik på fallback-kort kalder onFocus (re-ankrer) — IKKE onPick, ingen skrivning', () => {
    let picked: string | null = null, focused: string | null = null;
    render(
      <TreeView model={fbModel} focusId="P" onPick={(id) => (picked = id)} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Nabo Et'));
    expect(focused).toBe('N1');
    expect(picked).toBeNull();
  });
});

describe('TreeView — v2 slægtled-naboer i anker-kolonnen (T6: aktiv-linje-koordinat + peer-render)', () => {
  // Anna (fokus) er i III/G11; Xenia er en slægtled-nabo (samme III/G11) der OGSÅ bærer et andet,
  // LAVERE `lokal` i en anden linje (V/G3) — bevidst opsat så en re-ankring til Xenia kun bevarer
  // III-konteksten hvis klik-handleren rent faktisk bærer den aktive linje videre (§2/Codex HIGH-2);
  // en naiv "laveste lokal"-default ville forkert skifte til V/3.
  const peerModel = buildModel(
    db(
      [P('A', 'Anna'), P('F', 'Far'), P('M', 'Mor'), P('C1', 'Bo'), P('C2', 'Cille'), P('X', 'Xenia')],
      [
        { child: 'A', parent: 'F', union: 'u1' },
        { child: 'A', parent: 'M', union: 'u1' },
        { child: 'C1', parent: 'A', union: 'u2' },
        { child: 'C2', parent: 'A', union: 'u2' },
      ],
    ),
  );
  (peerModel as typeof peerModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
    A: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null }],
    // Far er Annas EGEN forælder i samme linje (naturligt ét slægtled lavere) — bruges til at teste
    // at en drill IKKE genskriver ankerets egen label (se testen nedenfor).
    F: [{ sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 10, gennem: 10, kuld: null }],
    X: [
      { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null },
      { sourceId: '1', linje: 'V', lineageId: '20', parentLineageId: null, lokal: 3, gennem: 3, kuld: null },
    ],
  };

  it('anker viser fokus dominant + slægtled-nabo dæmpet, kombineret label, og klik re-ankrer (ingen skrivning)', () => {
    let focused: string | null = null;
    render(
      <TreeView model={peerModel} focusId="A" onPick={() => {}} onFocus={(id) => (focused = id)} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText('Anna')).toBeTruthy();
    expect(screen.getByText('Xenia')).toBeTruthy(); // dæmpet nabo-kort, jf. buildAnchorPeers
    expect(screen.getByText(/^11\. slægtled · III-linjen$/)).toBeTruthy(); // §5 kombinations-label
    fireEvent.click(screen.getByText('Xenia'));
    expect(focused).toBe('X'); // re-ankrer via onFocus, ikke onPick
  });

  it('aktiv linje-koordinat bevares ved re-ankring til naboen (vælger IKKE naboens andet, lavere-lokal koordinat)', () => {
    let focusId = 'A';
    const onFocus = (id: string) => { focusId = id; };
    const { rerender } = render(
      <TreeView model={peerModel} focusId={focusId} onPick={() => {}} onFocus={onFocus} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    fireEvent.click(screen.getByText('Xenia')); // sætter activeCoord til Xenias III/G11-koordinat (matcher Annas linje)
    rerender(
      <TreeView model={peerModel} focusId={focusId} onPick={() => {}} onFocus={onFocus} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    // Ankeret er nu Xenia; anker-labelen skal STADIG vise III-linjen/11. slægtled — havde re-ankrings-
    // effekten overskrevet klikkets koordinat med Xenias laveste `lokal` (3, V-linjen), ville denne
    // assertion fejle (Codex HIGH-2-regressionstest).
    expect(screen.getByText(/^11\. slægtled · III-linjen$/)).toBeTruthy();
    expect(screen.queryByText(/3\. slægtled · V-linjen/)).toBeNull();
  });

  it('drill til en bevist forælder ændrer IKKE ankerets egen kombinations-label (activeCoord er bundet til ankeret, ikke det drillede kort — advisor-fund)', () => {
    render(
      <TreeView model={peerModel} focusId="A" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText(/^11\. slægtled · III-linjen$/)).toBeTruthy(); // Annas egen anker-label
    fireEvent.click(screen.getByText('Far')); // drill op i Forældre-kolonnen — IKKE en re-ankring
    // Ankeret er STADIG Anna (uændret kort/position). Havde drillet fejlagtigt genskrevet
    // activeCoord til Fars EGEN koordinat (III/G10, jf. `buildDirection`s fælles
    // `activeLokal ∓ depth`-formel der bruges til ALLE kolonners labels, ankeret inklusive), ville
    // ankerets egen label forkert vise "10. slægtled" i stedet for Annas rigtige "11".
    expect(screen.getByText(/^11\. slægtled · III-linjen$/)).toBeTruthy();
    expect(screen.queryByText(/^10\. slægtled · III-linjen$/)).toBeNull();
  });
});

describe('TreeView — v2 "+N flere i slægtledet" (cap/udfoldning, §4 Codex MEDIUM-6)', () => {
  const naboer = Array.from({ length: 9 }, (_, i) => P(`Q${i}`, `Nabo ${i}`));
  const overflowModel = buildModel(db([P('A', 'Anna'), ...naboer], []));
  const coord = { sourceId: '1', linje: 'III', lineageId: '10', parentLineageId: null, lokal: 11, gennem: 11, kuld: null };
  (overflowModel as typeof overflowModel & { genCoordsByPerson: unknown }).genCoordsByPerson = {
    A: [coord],
    ...Object.fromEntries(naboer.map((p) => [p.id, [coord]])),
  };

  it('capper til 7 naboer + "+2 flere"-kort; klik udfolder resten (ingen skrivning)', () => {
    render(
      <TreeView model={overflowModel} focusId="A" onPick={() => {}} onFocus={() => {}} hasBookmark={() => false} onToggleBookmark={() => {}} />,
    );
    fireEvent.click(screen.getByText('Kolonner'));
    expect(screen.getByText(/\+ ?2 flere i slægtledet/)).toBeTruthy();
    expect(screen.queryByText('Nabo 7')).toBeNull(); // uden for cap
    expect(screen.queryByText('Nabo 8')).toBeNull();
    fireEvent.click(screen.getByText(/\+ ?2 flere i slægtledet/));
    expect(screen.getByText('Nabo 7')).toBeTruthy();
    expect(screen.getByText('Nabo 8')).toBeTruthy();
  });
});
