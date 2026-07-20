// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { KandidatDetalje } from '../../data/redaktionRead';

const mocks = vi.hoisted(() => ({
  fetchSources: vi.fn(),
  fetchMatchPersoner: vi.fn(),
  fetchIkkeSammeSomPar: vi.fn(),
  fetchSammeSomPar: vi.fn(),
  fetchFamilyGraph: vi.fn(),
  fetchKandidatDetalje: vi.fn(),
  submitChange: vi.fn(),
}));

vi.mock('../../data/redaktionRead', () => ({
  fetchSources: mocks.fetchSources,
  fetchMatchPersoner: mocks.fetchMatchPersoner,
  fetchIkkeSammeSomPar: mocks.fetchIkkeSammeSomPar,
  fetchSammeSomPar: mocks.fetchSammeSomPar,
  fetchFamilyGraph: mocks.fetchFamilyGraph,
  fetchKandidatDetalje: mocks.fetchKandidatDetalje,
}));

vi.mock('../../data/redaktionWrite', () => ({
  submitChange: mocks.submitChange,
}));

import { SammenlignUdgaver } from '../SammenlignUdgaver';

const tomDetalje: KandidatDetalje = {
  evidence: { felter: {}, koen: 'mand' },
  narrativer: [],
  familie: { somPartner: [], somBarn: [] },
  relationer: [],
};

describe('SammenlignUdgaver lazy kandidatdetalje', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchSources.mockResolvedValue([
      { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
      { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
    ]);
    mocks.fetchMatchPersoner.mockResolvedValue([
      {
        id: '1', navn: 'detlev reventlow', fuldtNavn: 'Detlev Reventlow', koen: 'mand',
        foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
        doed: { date_min: '1730-01-01', date_max: '1730-12-31' }, titel: 'Amtmand',
        bogReferencer: [], sourceIds: [3], staged: true,
      },
      {
        id: '2', navn: 'detlev reventlow', fuldtNavn: 'Detlev Reventlow', koen: 'mand',
        foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
        doed: { date_min: '1730-01-01', date_max: '1730-12-31' }, titel: 'Amtmand',
        bogReferencer: [], sourceIds: [7], staged: false,
      },
    ]);
    mocks.fetchIkkeSammeSomPar.mockResolvedValue([]);
    mocks.fetchSammeSomPar.mockResolvedValue([]);
    mocks.fetchFamilyGraph.mockResolvedValue({ unions: [], parentChild: [] });
    mocks.fetchKandidatDetalje.mockResolvedValue(tomDetalje);
  });

  test('henter først ved ekspansion og genbruger person-cache ved genåbning', async () => {
    render(<SammenlignUdgaver role="redaktor" />);

    const aabn = await screen.findByRole('button', { name: 'Sammenlign' });
    expect(mocks.fetchKandidatDetalje).not.toHaveBeenCalled();

    fireEvent.click(aabn);
    await waitFor(() => expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2));
    expect(mocks.fetchKandidatDetalje.mock.calls.map(([id]) => id).sort()).toEqual(['1', '2']);
    expect(await screen.findByRole('columnheader', { name: /1939/ })).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Luk sammenligning' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sammenlign' }));
    await screen.findByRole('columnheader', { name: /1939/ });
    expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2);
  });
});
