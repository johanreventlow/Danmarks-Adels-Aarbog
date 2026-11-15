// @vitest-environment jsdom
import { fireEvent, render, screen } from '@testing-library/react';
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

const person = (id: string, sourceId: number) => ({
  id, navn: 'detlev', fuldtNavn: 'Detlev Reventlow', koen: 'mand',
  foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
  doed: { date_min: '1730-01-01', date_max: '1730-12-31' }, titel: null,
  bogReferencer: [], sourceIds: [sourceId], staged: sourceId === 3, udenforMatchning: false,
});

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
