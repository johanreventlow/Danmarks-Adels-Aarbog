// @vitest-environment jsdom
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FeedCard, FeedInputs } from '@daa/feed';
import { hrefForCard } from '../feed/FeedStreamView';

const mediaMocks = vi.hoisted(() => ({
  fetchFeedMediaCandidates: vi.fn(),
  resolveFeedMediaForCards: vi.fn(),
}));
const streamMocks = vi.hoisted(() => ({ createFeedStream: vi.fn(), resumeStream: vi.fn() }));
const feedAuxMocks = vi.hoisted(() => ({ fetchFeedBios: vi.fn() }));
const grundlagMocks = vi.hoisted(() => ({ fetchNaevntGrundlag: vi.fn() }));
const loaderMocks = vi.hoisted(() => ({ loadHaendelserBy: vi.fn() }));
const seenMocks = vi.hoisted(() => ({ markSeen: vi.fn(), weights: {} as Record<string, number> }));

vi.mock('../../data/feedMedia', () => mediaMocks);
vi.mock('../../data/feedAux', () => ({
  buildWebFeedAux: () => ({ godsListe: [], vaabenListe: [], officesBy: {} }),
  fetchFeedBios: feedAuxMocks.fetchFeedBios,
  withFeedBios: (model: unknown) => model,
}));
vi.mock('../../data/feedGrundlag', () => grundlagMocks);
vi.mock('../../data/livsdato', () => ({ loadLivsdatoBy: () => Promise.resolve({}) }));
vi.mock('../../data/haendelser', () => loaderMocks);
vi.mock('../../data/story', () => ({ loadStorieBy: () => Promise.resolve({}) }));
vi.mock('../../data/seenCards', () => ({
  createSeenStore: () => ({ load: () => Promise.resolve([]), markSeen: seenMocks.markSeen }),
  toSeenWeights: () => seenMocks.weights,
}));
vi.mock('../../data/feedSession', () => ({ epochDay: () => 1, newSeed: () => 1, todayISO: () => '2026-07-26' }));
vi.mock('@daa/feed', async (importOriginal) => ({
  ...await importOriginal<typeof import('@daa/feed')>(),
  TEMP_DISABLED_KINDS: new Set(),
  bookmarkPersonId: (card: FeedCard) => 'personId' in card ? card.personId : null,
  createFeedStream: streamMocks.createFeedStream,
  resumeStream: streamMocks.resumeStream,
}));

const { FeedStreamView } = await import('../feed/FeedStreamView');

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

const portraet = (id: string): Extract<FeedCard, { kind: 'portrait' }> => ({
  kind: 'portrait', id: 'portrait:' + id, personId: id, name: 'Person ' + id, years: '', initials: 'P',
  title: null, bio: '', kicker: 'Portræt',
});
const SYV = Array.from({ length: 7 }, (_, i) => portraet(String(i + 1)));
const model = { persons: SYV.map((c) => ({ id: c.personId })), byId: {}, indexes: {} } as any;

function listStream(cards: FeedCard[]) {
  let i = 0;
  return {
    next: vi.fn((n: number) => { const ud = cards.slice(i, i + n); i += ud.length; return ud; }),
    done: vi.fn(() => i >= cards.length),
    total: () => cards.length,
  };
}

function feedProps(bookmarkOwnerId: string | null) {
  return {
    model, estates: null, arms: null, meId: null, focusId: null, feedPins: [],
    bookmarkedIds: [], bookmarksReady: true, bookmarkHydrationVersion: 1, bookmarkOwnerId,
    hasBookmark: () => false, onSaveBookmark: vi.fn(), onOpenPerson: vi.fn(), onOpenEstate: vi.fn(),
    onOpenArms: vi.fn(), onOpenSlaegt: vi.fn(), onBrowseAll: vi.fn(),
  };
}

const ids1til6 = ['1', '2', '3', '4', '5', '6'];

beforeEach(() => {
  streamMocks.createFeedStream.mockReset().mockImplementation(() => listStream(SYV));
  streamMocks.resumeStream.mockReset().mockImplementation((stream) => stream);
  feedAuxMocks.fetchFeedBios.mockReset().mockResolvedValue({ '1': 'En biografi.' });
  grundlagMocks.fetchNaevntGrundlag.mockReset().mockResolvedValue({ personerMedMereEndNavn: new Set() });
  loaderMocks.loadHaendelserBy.mockReset().mockResolvedValue({});
  seenMocks.markSeen.mockReset();
  seenMocks.weights = {};
  mediaMocks.fetchFeedMediaCandidates.mockReset().mockResolvedValue({});
  mediaMocks.resolveFeedMediaForCards.mockReset().mockImplementation(async (requests, candidates) => Object.fromEntries(
    requests.map((request: { cardId: string; personId: string }) => [request.cardId, (candidates[request.personId] ?? []).map((candidate: { id: string; titel: string }) => ({
      id: candidate.id, slags: 'portræt', titel: candidate.titel, kunstner: '', datering: '',
      mediumUrl: `https://example.test/${candidate.id}.jpg`, largeUrl: `https://example.test/${candidate.id}.jpg`,
    }))]),
  ));
});

describe('FeedStreamView — uddeling', () => {
  it('deler først ud, når alle kilder er afgjort, og sender da nævnt-grundlaget med', async () => {
    const haendelser = deferred<Record<string, unknown>>();
    loaderMocks.loadHaendelserBy.mockReturnValue(haendelser.promise);
    render(<FeedStreamView {...feedProps(null)} />);
    await act(async () => { await Promise.resolve(); });
    expect(streamMocks.createFeedStream).not.toHaveBeenCalled();
    expect(screen.getByRole('status').textContent).toContain('Henter blade');

    await act(async () => { haendelser.resolve({}); });
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalledTimes(1));
    const inputs = streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs;
    expect(inputs.naevntGrundlag?.personerMedMereEndNavn).toBeInstanceOf(Set);
  });

  it('sender intet nævnt-grundlag, når grundlaget fejler eller biografierne er tomme', async () => {
    grundlagMocks.fetchNaevntGrundlag.mockRejectedValue(new Error('permission denied'));
    const view = render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    expect((streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs).naevntGrundlag).toBeUndefined();
    view.unmount();

    streamMocks.createFeedStream.mockClear();
    grundlagMocks.fetchNaevntGrundlag.mockResolvedValue({ personerMedMereEndNavn: new Set() });
    feedAuxMocks.fetchFeedBios.mockResolvedValue({});
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    expect((streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs).naevntGrundlag).toBeUndefined();
  });

  it('viser seks blade, og knappen vender de næste som ny blok med fokus', async () => {
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(screen.getAllByRole('region')).toHaveLength(1));
    expect(screen.getByRole('region', { name: 'Blade 1–6' })).toBeTruthy();
    expect(seenMocks.markSeen).toHaveBeenLastCalledWith(ids1til6.map((id) => 'portrait:' + id), 1);
    expect(screen.queryByText(/fortsætter, hvor du slap/)).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Vend seks blade mere' }));
    const nyBlok = await screen.findByRole('region', { name: 'Blade 7–7' });
    await waitFor(() => expect(document.activeElement).toBe(nyBlok));
    expect(screen.queryByRole('button', { name: 'Vend seks blade mere' })).toBeNull();
    expect(screen.getByText(/Du har vendt alle dagens blade/)).toBeTruthy();
  });

  it('nævner kun »fortsætter, hvor du slap«, når læseren har set blade før', async () => {
    seenMocks.weights = { 'portrait:9': 0.25 };
    render(<FeedStreamView {...feedProps(null)} />);
    expect(await screen.findByText('Feedet fortsætter, hvor du slap.')).toBeTruthy();
  });
});

describe('FeedStreamView media lifecycle', () => {
  it('bevarer det igangværende kandidatfetch, når næste parti vendes', async () => {
    const firstFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates.mockImplementation((ids: string[]) => (
      ids[0] === '1' ? firstFetch.promise : Promise.resolve({ '7': [] })
    ));

    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: 'Vend seks blade mere' }));
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2));
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(1, ids1til6, {});
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(2, ['7'], {});
    firstFetch.resolve({ '1': [{ id: 'media-1', titel: 'Første portræt' }] });

    await waitFor(() => expect(screen.getByRole('button', { name: 'Åbn billede: Første portræt' })).toBeTruthy());
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2);
  });

  it('viser ikke et sent kandidatresultat fra den forrige bogmærke-ejer', async () => {
    const ownerAFetch = deferred<Record<string, unknown[]>>();
    const ownerBFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates
      .mockImplementationOnce(() => ownerAFetch.promise)
      .mockImplementationOnce(() => ownerBFetch.promise);

    const view = render(<FeedStreamView {...feedProps('owner-a')} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(1));
    view.rerender(<FeedStreamView {...feedProps('owner-b')} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2));
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(2, ids1til6, {});

    await act(async () => { ownerAFetch.resolve({ '1': [{ id: 'owner-a', titel: 'Ejer A portræt' }] }); });
    expect(screen.queryByRole('button', { name: 'Åbn billede: Ejer A portræt' })).toBeNull();

    ownerBFetch.resolve({ '1': [{ id: 'owner-b', titel: 'Ejer B portræt' }] });
    await waitFor(() => expect(screen.getByRole('button', { name: 'Åbn billede: Ejer B portræt' })).toBeTruthy());
  });

  it('starter ikke en ny media-resolution efter unmount fra et sent kandidatresultat', async () => {
    const pendingFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates.mockImplementation(() => pendingFetch.promise);

    const view = render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledWith(ids1til6, {}));
    view.unmount();
    await act(async () => { pendingFetch.resolve({ '1': [{ id: 'unmounted', titel: 'Må ikke vises' }] }); });

    expect(mediaMocks.resolveFeedMediaForCards.mock.calls.some(([, candidates]) => (
      candidates['1']?.some((candidate: { titel: string }) => candidate.titel === 'Må ikke vises')
    ))).toBe(false);
  });

  it('beder ikke om billeder til et nævnt-kort', async () => {
    const naevnt: FeedCard = {
      kind: 'naevnt', id: 'naevnt:9', personId: '9', name: 'Person 9', years: '', relation: null,
      kilde: 'nr. 9', kicker: 'Nævnt i Aarbogen',
    };
    streamMocks.createFeedStream.mockImplementation(() => listStream([portraet('1'), naevnt]));
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledWith(['1'], {}));
  });

  it('viser en eksplicit biografi-fejl i stedet for en tavs tom feed-model', async () => {
    feedAuxMocks.fetchFeedBios.mockRejectedValue(new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE'));

    render(<FeedStreamView {...feedProps(null)} />);

    expect((await screen.findByRole('alert')).textContent).toContain('Kunne ikke hente feedets biografier');
    // Fejlkoden går til konsollen, ikke til læseren.
    expect(screen.getByRole('alert').textContent).not.toContain('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
  });
});

describe('hrefForCard', () => {
  it('person-kort peger på personens side', () => {
    const kort: Extract<FeedCard, { kind: 'dagensperson' }> = {
      kind: 'dagensperson', id: 'dagensperson:42', personId: '42', name: 'Anna', years: '1700–1760',
      initials: 'A', title: null, bio: '', kicker: 'Dagens person',
    };
    expect(hrefForCard(kort)).toBe('/person/42');
  });
  it('nævnt-kort peger på personens side', () => {
    expect(hrefForCard({
      kind: 'naevnt', id: 'naevnt:5', personId: '5', name: 'B', years: '', relation: null,
      kilde: 'nr. 5', kicker: 'Nævnt i Aarbogen',
    })).toBe('/person/5');
  });
  it('gods-kort peger på godsets side', () => {
    const kort: Extract<FeedCard, { kind: 'gods' }> = {
      kind: 'gods', id: 'gods:7', estateId: '7', navn: 'Gammel Gaard', meta: 'herregård', ownerDots: 3, kicker: 'Gods',
    };
    expect(hrefForCard(kort)).toBe('/gods/7');
  });
  it('våben-kort peger på våben-fanen', () => {
    const kort: Extract<FeedCard, { kind: 'vaaben' }> = {
      kind: 'vaaben', id: 'vaaben:1', armsId: '1', blazon: 'to skjolde', foot: 'DAA', kicker: 'Våben',
    };
    expect(hrefForCard(kort)).toBe('/slaegt/reventlow/vaaben');
  });
  it('slægtskabs-, forbundet- og samle-kort får intet href (målet ligger uden for URL-grammatikken)', () => {
    const slaegt: Extract<FeedCard, { kind: 'slaegt' }> = {
      kind: 'slaegt', id: 'slaegt:1', aId: '1', bId: '2', aName: 'A', bName: 'B',
      rel: 'fætre', foot: '', kicker: 'Slægtskab',
    };
    expect(hrefForCard(slaegt)).toBeNull();
    const forbundet: Extract<FeedCard, { kind: 'forbundet' }> = {
      kind: 'forbundet', id: 'forbundet:1', aName: 'A', bName: 'B', aInit: 'A', bInit: 'B',
      marBottom: '0', kicker: 'Forbundet',
    };
    expect(hrefForCard(forbundet)).toBeNull();
    const samle: Extract<FeedCard, { kind: 'samle' }> = {
      kind: 'samle', id: 'samle:1', count: 3, tail: 'mere', kicker: 'Saml',
    };
    expect(hrefForCard(samle)).toBeNull();
  });
});
