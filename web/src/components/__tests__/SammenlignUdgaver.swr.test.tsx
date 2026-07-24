// @vitest-environment jsdom
import { render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, test, vi } from 'vitest';

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

vi.mock('../../data/redaktionWrite', () => ({ submitChange: mocks.submitChange }));

const kilde = [{ id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 }];
const graf = { unions: [], parentChild: [] };

function personer(navn: string) {
  return [{
    id: '1', navn: navn.toLocaleLowerCase('da-DK'), fuldtNavn: navn, koen: 'mand',
    foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
    doed: null, titel: null, bogReferencer: [], sourceIds: [3], staged: true,
  }];
}

function klargoerHentning(navn: string) {
  mocks.fetchSources.mockResolvedValue(kilde);
  mocks.fetchMatchPersoner.mockResolvedValue(personer(navn));
  mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
  mocks.fetchSammeSomPar.mockResolvedValue([]);
  mocks.fetchFamilyGraph.mockResolvedValue(graf);
  mocks.fetchMatchAudit.mockResolvedValue([]);
}

async function hentKomponent() {
  vi.resetModules();
  return (await import('../SammenlignUdgaver')).SammenlignUdgaver;
}

afterEach(() => {
  vi.clearAllMocks();
});

describe('SammenlignUdgaver stale-while-revalidate-cache', () => {
  test('viser skeleton ved ægte første indlæsning uden cache', async () => {
    const SammenlignUdgaver = await hentKomponent();
    mocks.fetchSources.mockImplementation(() => new Promise(() => undefined));
    render(<SammenlignUdgaver role="redaktor" />);

    expect(screen.getByTestId('sammenlign-skeleton')).toBeTruthy();
    expect(screen.queryByText('Indlæser redaktions-datasæt…')).toBeNull();
  });

  test('viser straks tidligere data ved genmontering med warm cache', async () => {
    klargoerHentning('Første Reventlow');
    const SammenlignUdgaver = await hentKomponent();
    const første = render(<SammenlignUdgaver role="redaktor" />);
    await screen.findByText(/Første Reventlow/);
    første.unmount();

    mocks.fetchMatchPersoner.mockImplementation(() => new Promise(() => undefined));
    const anden = render(<SammenlignUdgaver role="redaktor" />);

    expect(screen.getByText(/Første Reventlow/)).toBeTruthy();
    expect(screen.queryByTestId('sammenlign-skeleton')).toBeNull();
    expect(screen.getByText('· opdaterer…')).toBeTruthy();
    anden.unmount();
  });

  test('gemmer det baggrundsrevaliderede resultat til næste genmontering', async () => {
    klargoerHentning('Første Reventlow');
    const SammenlignUdgaver = await hentKomponent();
    const første = render(<SammenlignUdgaver role="redaktor" />);
    await screen.findByText(/Første Reventlow/);
    første.unmount();

    klargoerHentning('Opdateret Reventlow');
    const anden = render(<SammenlignUdgaver role="redaktor" />);
    await screen.findByText(/Opdateret Reventlow/);
    anden.unmount();

    mocks.fetchMatchPersoner.mockImplementation(() => new Promise(() => undefined));
    render(<SammenlignUdgaver role="redaktor" />);

    expect(screen.getByText(/Opdateret Reventlow/)).toBeTruthy();
    expect(screen.queryByTestId('sammenlign-skeleton')).toBeNull();
    await waitFor(() => expect(mocks.fetchMatchPersoner).toHaveBeenCalledTimes(3));
  });
});
