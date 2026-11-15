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
