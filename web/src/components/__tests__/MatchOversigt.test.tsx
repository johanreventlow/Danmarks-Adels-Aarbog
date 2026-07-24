// @vitest-environment jsdom
import { useState } from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { RedMatchPerson } from '@daa/core';
import type { KandidatDetalje, MatchAuditPost, SourceRow } from '../../data/redaktionRead';

const mocks = vi.hoisted(() => ({ fetchKandidatDetalje: vi.fn() }));

vi.mock('../../data/redaktionRead', async (importOriginal) => ({
  ...await importOriginal<typeof import('../../data/redaktionRead')>(),
  fetchKandidatDetalje: mocks.fetchKandidatDetalje,
}));

import { MatchOversigt } from '../MatchOversigt';

function person(id: string, navn: string, sourceId: number, linje: string, grenNavn: string): RedMatchPerson {
  return {
    id, navn: navn.toLocaleLowerCase('da-DK'), fuldtNavn: navn, koen: 'mand',
    foedsel: { date_min: '1660-01-01', date_max: '1660-12-31' },
    doed: { date_min: '1730-01-01', date_max: '1730-12-31' }, titel: null,
    bogReferencer: [{ sourceId, linje, nr: Number(id), slaegtledLokal: null, slaegtledGennem: null, kuld: null, grenNavn }],
    sourceIds: [sourceId], staged: false,
  };
}

const personer = [
  person('1', 'Detlev Reventlow', 3, 'III', 'Holstenske linje'),
  person('2', 'Detlev Reventlow', 7, 'V', 'Danske linje'),
  person('4', 'Charlotte Reventlow', 4, 'II', 'Ældre gren'),
  person('9', 'Sophie Reventlow', 8, 'VI', 'Yngre gren'),
];

const sources: SourceRow[] = [
  { id: 3, titel: 'Danmarks Adels Aarbog', udgave: '1939', slags: 'bog', aar: 1939 },
  { id: 4, titel: 'Danmarks Adels Aarbog', udgave: '1910', slags: 'bog', aar: 1910 },
  { id: 7, titel: 'Danmarks Adels Aarbog', udgave: '2018-20', slags: 'bog', aar: 2018 },
  { id: 8, titel: 'Danmarks Adels Aarbog', udgave: '1920', slags: 'bog', aar: 1920 },
];

const audit: MatchAuditPost[] = [
  {
    relationId: '91', aId: '1', bId: '2', beslutning: 'samme_som',
    actorNavn: 'Johan', actorRolle: 'redaktion', createdAt: '2026-07-20T15:00:00Z', operation: 'red_samme_som',
  },
  {
    relationId: '92', aId: '4', bId: '9', beslutning: 'ikke_samme_som',
    actorNavn: 'Karen', actorRolle: 'administrator', createdAt: '2026-07-19T12:00:00Z', operation: 'red_ikke_samme_som',
  },
];

const tomDetalje: KandidatDetalje = {
  evidence: { felter: {}, koen: 'mand' }, narrativer: [],
  familie: { somPartner: [], somBarn: [] }, relationer: [],
};

function MatchOversigtHarness({
  auditData = audit,
  onFortryd,
  onFortrydAfvisning,
}: {
  auditData?: MatchAuditPost[];
  onFortryd: ReturnType<typeof vi.fn>;
  onFortrydAfvisning: ReturnType<typeof vi.fn>;
}) {
  const [detaljeCache, setDetaljeCache] = useState<Map<string, KandidatDetalje>>(() => new Map());
  const hentKandidatDetalje = (personId: string) => mocks.fetchKandidatDetalje(personId)
    .then((detalje: KandidatDetalje) => {
      setDetaljeCache((prev) => new Map(prev).set(personId, detalje));
      return detalje;
    });
  return <MatchOversigt
      audit={auditData}
      personer={personer}
      sources={sources}
      karantaeneByPersonId={new Map([['1', 'konkurrerende forældre (1 vs. 2)']])}
      detaljeCache={detaljeCache}
      busy={false}
      hentKandidatDetalje={hentKandidatDetalje}
      onFortryd={onFortryd}
      onFortrydAfvisning={onFortrydAfvisning}
    />;
}

function renderOversigt(
  onFortryd = vi.fn(),
  onFortrydAfvisning = vi.fn(),
  auditData: MatchAuditPost[] = audit,
) {
  return {
    onFortryd,
    onFortrydAfvisning,
    ...render(<MatchOversigtHarness
      auditData={auditData}
      onFortryd={onFortryd}
      onFortrydAfvisning={onFortrydAfvisning}
    />),
  };
}

describe('MatchOversigt', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchKandidatDetalje.mockResolvedValue(tomDetalje);
  });

  test('viser begge beslutningstyper med audit, rekomputeret score, bogreference og fold-status', () => {
    const { container, onFortryd, onFortrydAfvisning } = renderOversigt();

    expect(screen.getByText('Bekræftet samme person')).toBeTruthy();
    expect(screen.getByText('Afvist som forskellige')).toBeTruthy();
    expect(screen.getByText(/Detlev Reventlow \(1660–1730\)/)).toBeTruthy();
    expect(screen.getByText(/III-1, Holstenske linje/)).toBeTruthy();
    expect(screen.getByText(/Score 1\.000/)).toBeTruthy();
    expect(screen.getByText(/Johan · redaktion/)).toBeTruthy();
    expect(screen.getByText(/folder ikke endnu/)).toBeTruthy();
    expect(screen.getByText(/Fold-status er ikke relevant for en afvisning/)).toBeTruthy();
    expect(container.querySelector('time')?.getAttribute('datetime')).toBe('2026-07-20T15:00:00Z');

    const fortryd = screen.getAllByRole('button', { name: 'Fortryd' });
    fireEvent.click(fortryd[0]);
    expect(onFortryd).toHaveBeenCalledWith('91', '1');
    fireEvent.click(fortryd[1]);
    expect(onFortrydAfvisning).toHaveBeenCalledWith('92', '4');
    expect(fortryd).toHaveLength(2);
  });

  test('filtrerer klient-side på navn, kildeudgave, linje/gren og ikke-foldende links', () => {
    renderOversigt();

    fireEvent.change(screen.getByLabelText('Søg på navn'), { target: { value: 'Charlotte' } });
    expect(screen.getByTestId('audit-post-92')).toBeTruthy();
    expect(screen.queryByTestId('audit-post-91')).toBeNull();

    fireEvent.change(screen.getByLabelText('Søg på navn'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('Kildeudgave'), { target: { value: '3' } });
    expect(screen.getByTestId('audit-post-91')).toBeTruthy();
    expect(screen.queryByTestId('audit-post-92')).toBeNull();

    fireEvent.change(screen.getByLabelText('Kildeudgave'), { target: { value: '' } });
    fireEvent.change(screen.getByLabelText('Linje/gren'), { target: { value: 'Yngre gren' } });
    expect(screen.getByTestId('audit-post-92')).toBeTruthy();
    expect(screen.queryByTestId('audit-post-91')).toBeNull();

    fireEvent.change(screen.getByLabelText('Linje/gren'), { target: { value: '' } });
    fireEvent.click(screen.getByLabelText('Vis kun links der ikke folder endnu'));
    expect(screen.getByTestId('audit-post-91')).toBeTruthy();
    expect(screen.queryByTestId('audit-post-92')).toBeNull();
  });

  test('henter kandidatdetaljer lazy gennem parentens cachefunktion', async () => {
    renderOversigt();
    expect(mocks.fetchKandidatDetalje).not.toHaveBeenCalled();

    fireEvent.click(screen.getAllByRole('button', { name: 'Se sammenligning' })[0]);
    await waitFor(() => expect(mocks.fetchKandidatDetalje).toHaveBeenCalledTimes(2));
    expect(await screen.findByRole('columnheader', { name: /1939/ })).toBeTruthy();
  });

  test('viser de 20 nyeste beslutninger først og kan vise flere', () => {
    const mangePoster: MatchAuditPost[] = Array.from({ length: 25 }, (_, index) => ({
      relationId: String(100 + index),
      aId: '1',
      bId: '2',
      beslutning: 'samme_som',
      actorNavn: 'Johan',
      actorRolle: 'redaktion',
      createdAt: `2026-07-${String(index + 1).padStart(2, '0')}T12:00:00Z`,
      operation: 'red_samme_som',
    }));

    renderOversigt(vi.fn(), vi.fn(), mangePoster);

    expect(screen.getAllByTestId(/^audit-post-/)).toHaveLength(20);
    expect(screen.getByTestId('audit-post-124')).toBeTruthy();
    expect(screen.queryByTestId('audit-post-100')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Vis flere' }));
    expect(screen.getAllByTestId(/^audit-post-/)).toHaveLength(25);
  });
});
