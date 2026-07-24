// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { KandidatDetalje } from '../../data/redaktionRead';

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
    mocks.fetchMatchAudit.mockResolvedValue([]);
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

  test('bekræfter lokalt uden at genhente de globale datasæt', async () => {
    mocks.submitChange.mockResolvedValue({
      dryRun: false,
      call: { fn: 'red_samme_som', args: {} },
      direkte: true,
      result: 123,
    });

    render(<SammenlignUdgaver role="redaktor" dryRun={false} />);

    expect(await screen.findByRole('heading', { name: 'Til gennemgang (1)' })).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Sammenlign' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Bekræft samme person' }));

    await waitFor(() => {
      expect(screen.getByRole('heading', { name: 'Til gennemgang (0)' })).toBeTruthy();
      expect(screen.queryByRole('button', { name: 'Sammenlign' })).toBeNull();
    });
    expect(mocks.fetchMatchPersoner).toHaveBeenCalledTimes(1);
    expect(mocks.fetchSources).toHaveBeenCalledTimes(1);
    expect(mocks.fetchFamilyGraph).toHaveBeenCalledTimes(1);
  });

  test('bekræfter direkte fra kandidatrækken uden at indlæse sammenligningen', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    mocks.submitChange.mockResolvedValue({
      dryRun: false,
      call: { fn: 'red_samme_som', args: {} },
      direkte: true,
      result: 123,
    });

    render(<SammenlignUdgaver role="redaktor" dryRun={false} />);

    fireEvent.click(await screen.findByRole('button', { name: '✓ Bekræft' }));

    expect(confirm).toHaveBeenCalledWith(
      'Bekræft Detlev Reventlow · Amtmand (1660–1730) = Detlev Reventlow · Amtmand (1660–1730) som samme person uden at se sammenligningen?',
    );
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledWith({
      art: 'sammeSom', subjektType: 'person', subjektId: '2',
      payload: { aliasId: '2', objektId: '1' },
    }, { dryRun: false, role: 'redaktor' }));
    await screen.findByRole('heading', { name: 'Til gennemgang (0)' });
    expect(mocks.fetchKandidatDetalje).not.toHaveBeenCalled();
  });

  test('sender ikke bekræftelse fra kandidatrækken, når dialogen annulleres', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);

    render(<SammenlignUdgaver role="redaktor" dryRun={false} />);

    fireEvent.click(await screen.findByRole('button', { name: '✓ Bekræft' }));

    expect(mocks.submitChange).not.toHaveBeenCalled();
    expect(mocks.fetchKandidatDetalje).not.toHaveBeenCalled();
  });

  test('deler person-cache mellem arbejdslisten og audit-oversigten', async () => {
    mocks.fetchMatchAudit.mockResolvedValue([{
      relationId: '91', aId: '1', bId: '2', beslutning: 'samme_som',
      actorNavn: 'Johan', actorRolle: 'redaktion', createdAt: '2026-07-20T15:00:00Z',
      operation: 'red_samme_som',
    }]);

    render(<SammenlignUdgaver role="redaktor" />);

    fireEvent.click(await screen.findByRole('button', { name: 'Sammenlign' }));
    await waitFor(() => expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2));
    fireEvent.click(screen.getByRole('button', { name: 'Luk sammenligning' }));

    fireEvent.click(screen.getByRole('button', { name: 'Se sammenligning' }));
    await screen.findByRole('button', { name: 'Luk sammenligning' });
    expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2);
  });

  test('sender Fortryd gennem den eksisterende fjernSammeSom-change', async () => {
    const sammeSom = [{ relationId: '91', aId: '1', bId: '2' }];
    mocks.fetchSammeSomPar.mockResolvedValue(sammeSom);
    mocks.fetchMatchAudit.mockResolvedValue([{
      relationId: '91', aId: '1', bId: '2', beslutning: 'samme_som',
      actorNavn: 'Johan', actorRolle: 'redaktion', createdAt: '2026-07-20T15:00:00Z',
      operation: 'red_samme_som',
    }]);
    mocks.submitChange.mockResolvedValue({});

    render(<SammenlignUdgaver role="redaktor" dryRun={false} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Fortryd' }));

    expect(mocks.fetchMatchAudit).toHaveBeenCalledWith(sammeSom, []);
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledWith({
      art: 'fjernSammeSom', subjektType: 'person', subjektId: '1', relationId: '91',
    }, { dryRun: false, role: 'redaktor' }));
  });

  test('respekterer dryRun=true fra redaktions-fladens globale kontakt (regression: var hardkodet til false)', async () => {
    const sammeSom = [{ relationId: '91', aId: '1', bId: '2' }];
    mocks.fetchSammeSomPar.mockResolvedValue(sammeSom);
    mocks.fetchMatchAudit.mockResolvedValue([{
      relationId: '91', aId: '1', bId: '2', beslutning: 'samme_som',
      actorNavn: 'Johan', actorRolle: 'redaktion', createdAt: '2026-07-20T15:00:00Z',
      operation: 'red_samme_som',
    }]);
    mocks.submitChange.mockResolvedValue({});

    // dryRun ikke angivet → default true (samme sikre default som Redaktion.tsx's egen useState).
    render(<SammenlignUdgaver role="redaktor" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Fortryd' }));

    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledWith(
      expect.anything(),
      { dryRun: true, role: 'redaktor' },
    ));
  });
});
