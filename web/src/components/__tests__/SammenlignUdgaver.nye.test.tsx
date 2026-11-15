// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  fetchSources: vi.fn(),
  fetchMatchPersoner: vi.fn(),
  fetchIkkeSammeSomPar: vi.fn(),
  fetchSammeSomPar: vi.fn(),
  fetchMatchAudit: vi.fn(),
  fetchFamilyGraph: vi.fn(),
  fetchKandidatDetalje: vi.fn(),
  submitChange: vi.fn(),
}));

vi.mock('../../data/redaktionRead', () => ({
  fetchSources: mocks.fetchSources,
  fetchMatchPersoner: mocks.fetchMatchPersoner,
  fetchIkkeSammeSomPar: mocks.fetchIkkeSammeSomPar,
  fetchSammeSomPar: mocks.fetchSammeSomPar,
  fetchMatchAudit: mocks.fetchMatchAudit,
  fetchFamilyGraph: mocks.fetchFamilyGraph,
  fetchKandidatDetalje: mocks.fetchKandidatDetalje,
}));

vi.mock('../../data/redaktionWrite', () => ({
  submitChange: mocks.submitChange,
}));

import { SammenlignUdgaver } from '../SammenlignUdgaver';

const person = (id: string, sourceId: number, navn = 'detlev', foedt = '1660', doed = '1730') => ({
  id, navn, fuldtNavn: `${navn[0].toUpperCase()}${navn.slice(1)} Reventlow`, koen: 'mand',
  foedsel: { date_min: `${foedt}-01-01`, date_max: `${foedt}-12-31` },
  doed: { date_min: `${doed}-01-01`, date_max: `${doed}-12-31` }, titel: null,
  bogReferencer: [], sourceIds: [sourceId], staged: sourceId === 3, udenforMatchning: false,
});

const tomDetalje = {
  evidence: { felter: {}, koen: 'mand' },
  narrativer: [],
  familie: { somPartner: [], somBarn: [] },
  relationer: [],
};

describe('SammenlignUdgaver: person med alle forslag afvist', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    mocks.fetchMatchPersoner.mockResolvedValue([person('1', 3), person('2', 7)]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([{ relationId: '9', aId: '1', bId: '2' }]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchMatchAudit.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
  });

  test('står under Nye — ikke som "X = (ukendt)" under Bekræftede', async () => {
    render(<SammenlignUdgaver role="redaktor" />);
    // Udgaven med højest årstal vælges som standard; vælg 1939 som ny udgave.
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });

    expect(await screen.findByRole('button', { name: 'Bekræftede (0)' })).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Nye (1)' }));
    expect(screen.getByRole('heading', { name: '1 markeret som ny person' })).toBeTruthy();
    expect(screen.getByText(/Detlev Reventlow/)).toBeTruthy();
    expect(screen.queryByText(/\(ukendt\)/)).toBeNull();
  });
});

describe('SammenlignUdgaver: svage forslag', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    // Navn ligner, men begge årstal modsiger → under tærsklen (svagt forslag).
    mocks.fetchMatchPersoner.mockResolvedValue([person('1', 3), person('2', 7, 'detmar', '1663', '1790')]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchMatchAudit.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
    mocks.fetchKandidatDetalje.mockResolvedValue(tomDetalje);
  });

  test('»Sammenlign« på et svagt forslag åbner sammenligningen (regression: åbnede intet)', async () => {
    render(<SammenlignUdgaver role="redaktor" />);
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });
    await screen.findByText(/1 uden kandidat over tærsklen/);

    fireEvent.click(screen.getByRole('button', { name: 'Sammenlign' }));
    await waitFor(() => expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2));
    expect(await screen.findByRole('button', { name: 'Luk sammenligning' })).toBeTruthy();
    expect(await screen.findByRole('columnheader', { name: /1939/ })).toBeTruthy();
  });
});

describe('SammenlignUdgaver: svage forslag hos en åben person (A2)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    mocks.fetchMatchPersoner.mockResolvedValue([
      person('1', 3), person('2', 7), person('3', 7, 'detmar', '1663', '1790'),
    ]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchMatchAudit.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
    mocks.fetchKandidatDetalje.mockResolvedValue(tomDetalje);
  });

  test('kan folde svage forslag ud under et åbent arbejdsemne', async () => {
    render(<SammenlignUdgaver role="redaktor" />);
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });
    expect(await screen.findByRole('heading', { name: 'Til gennemgang (1)' })).toBeTruthy();
    expect(screen.queryByText(/Detmar Reventlow/)).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Vis 1 svagt forslag' }));
    expect(screen.getByText(/Detmar Reventlow/)).toBeTruthy();
    expect(screen.getAllByRole('button', { name: 'Sammenlign' })).toHaveLength(2);
  });
});

describe('SammenlignUdgaver: Find modpart (A1)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    // Andet forbogstav → matcheren stiller dem aldrig op; kun søgningen kan finde modparten.
    mocks.fetchMatchPersoner.mockResolvedValue([
      person('1', 3, 'ditlev'), person('2', 7, 'christian'), person('3', 7, 'conrad', '1700', '1760'),
      person('4', 3, 'christian', '1900', '1950'), // 1939-navnebror uden kandidat (årsvinduet)
    ]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchMatchAudit.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
    mocks.submitChange.mockResolvedValue({ dryRun: true, call: { fn: 'red_samme_som', args: {} } });
  });

  test('finder en person matcheren ikke foreslog og kan bekræfte den', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<SammenlignUdgaver role="redaktor" />);
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });
    await screen.findByText(/uden kandidat over tærsklen/);

    // Personen 'ditlev' (id 1) er den første i listen over formodet nye.
    fireEvent.click(screen.getAllByRole('button', { name: 'Find modpart' })[0]);
    fireEvent.change(screen.getByRole('searchbox', { name: 'Søg modpart' }), { target: { value: 'christian' } });

    // Kun 2018-20-personen findes — ikke 1939's egen Christian (id 4) og ikke Conrad.
    expect(screen.getAllByText(/Christian Reventlow \(1660/)).toHaveLength(1);
    expect(screen.getAllByText(/Christian Reventlow \(1900/)).toHaveLength(1); // kun i A-listen
    expect(screen.queryByText(/Conrad Reventlow/)).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: '✓ Bekræft' }));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
    expect(mocks.submitChange.mock.calls[0][0]).toMatchObject({
      art: 'sammeSom', payload: { aliasId: '1', objektId: '2' },
    });
    confirm.mockRestore();
  });

  test('viser besked når intet matcher', async () => {
    render(<SammenlignUdgaver role="redaktor" />);
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });
    await screen.findByText(/uden kandidat over tærsklen/);
    fireEvent.click(screen.getAllByRole('button', { name: 'Find modpart' })[0]);
    fireEvent.change(screen.getByRole('searchbox', { name: 'Søg modpart' }), { target: { value: 'zacharias' } });
    expect(screen.getByText('Ingen personer matcher søgningen.')).toBeTruthy();
  });
});

describe('SammenlignUdgaver: bekræftelse uden for matcherens forslag (LIVE)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    mocks.fetchMatchPersoner.mockResolvedValue([person('1', 3, 'ditlev'), person('2', 7, 'christian')]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchMatchAudit.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
    mocks.submitChange.mockResolvedValue({
      dryRun: false, call: { fn: 'red_samme_som', args: {} }, direkte: true, result: 123,
    });
  });

  test('et søgeresultat bekræftet LIVE afklarer personen og står under Bekræftede', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<SammenlignUdgaver role="redaktor" dryRun={false} />);
    fireEvent.change(await screen.findByRole('combobox'), { target: { value: '3' } });
    await screen.findByText(/1 uden kandidat over tærsklen/);

    fireEvent.click(screen.getByRole('button', { name: 'Find modpart' }));
    fireEvent.change(screen.getByRole('searchbox', { name: 'Søg modpart' }), { target: { value: 'christian' } });
    fireEvent.click(screen.getByRole('button', { name: '✓ Bekræft' }));

    fireEvent.click(await screen.findByRole('button', { name: 'Bekræftede (1)' }));
    expect(screen.getByText(/Ditlev Reventlow .* = Christian Reventlow/)).toBeTruthy();
    confirm.mockRestore();
  });
});
