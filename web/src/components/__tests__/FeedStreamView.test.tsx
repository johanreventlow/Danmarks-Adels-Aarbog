// @vitest-environment jsdom
import { act, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FeedCard } from '@daa/feed';
import { hrefForCard } from '../feed/FeedStreamView';

const mediaMocks = vi.hoisted(() => ({
  fetchFeedMediaCandidates: vi.fn(),
  resolveFeedMediaForCards: vi.fn(),
}));
const streamMocks = vi.hoisted(() => ({ createFeedStream: vi.fn(), resumeStream: vi.fn() }));

vi.mock('../../data/feedMedia', () => mediaMocks);
vi.mock('../../data/feedAux', () => ({
  buildWebFeedAux: () => ({ godsListe: [], vaabenListe: [], officesBy: {} }),
  fetchFeedBios: () => Promise.resolve({}),
  withFeedBios: (model: unknown) => model,
}));
vi.mock('../../data/livsdato', () => ({ loadLivsdatoBy: () => Promise.resolve({}) }));
vi.mock('../../data/haendelser', () => ({ loadHaendelserBy: () => Promise.resolve({}) }));
vi.mock('../../data/story', () => ({ loadStorieBy: () => Promise.resolve({}) }));
vi.mock('../../data/seenCards', () => ({
  createSeenStore: () => ({ load: () => Promise.resolve([]), markSeen: vi.fn() }),
  toSeenWeights: () => ({}),
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

const firstCard: Extract<FeedCard, { kind: 'portrait' }> = {
  kind: 'portrait', id: 'portrait:1', personId: '1', name: 'Første', years: '', initials: 'F', title: null, bio: '', kicker: 'Portræt',
};
const secondCard: Extract<FeedCard, { kind: 'portrait' }> = {
  kind: 'portrait', id: 'portrait:2', personId: '2', name: 'Anden', years: '', initials: 'A', title: null, bio: '', kicker: 'Portræt',
};
const model = {
  persons: [
    { id: '1', name: 'Første', years: '', born: null, died: 1700, title: '', bio: '', privat: false },
    { id: '2', name: 'Anden', years: '', born: null, died: 1700, title: '', bio: '', privat: false },
  ],
  byId: {
    '1': { id: '1', name: 'Første', years: '', born: null, died: 1700, title: '', bio: '', privat: false },
    '2': { id: '2', name: 'Anden', years: '', born: null, died: 1700, title: '', bio: '', privat: false },
  },
  indexes: {},
} as any;

function feedProps(bookmarkOwnerId: string | null) {
  return {
    model, estates: null, arms: null, meId: null, focusId: null, feedPins: [],
    bookmarkedIds: [], bookmarksReady: true, bookmarkHydrationVersion: 1, bookmarkOwnerId,
    hasBookmark: () => false, onSaveBookmark: vi.fn(), onOpenPerson: vi.fn(), onOpenEstate: vi.fn(),
    onOpenArms: vi.fn(), onOpenSlaegt: vi.fn(), onBrowseAll: vi.fn(),
  };
}

describe('FeedStreamView media lifecycle', () => {
  beforeEach(() => {
    streamMocks.createFeedStream.mockReset().mockImplementation(() => {
      let nextCall = 0;
      return {
        next: vi.fn(() => (nextCall++ === 0 ? [firstCard] : [secondCard])),
        done: vi.fn(() => nextCall >= 2),
      };
    });
    streamMocks.resumeStream.mockReset().mockImplementation((stream) => stream);
    mediaMocks.fetchFeedMediaCandidates.mockReset();
    mediaMocks.resolveFeedMediaForCards.mockReset().mockImplementation(async (requests, candidates) => Object.fromEntries(
      requests.map((request: { cardId: string; personId: string }) => [request.cardId, (candidates[request.personId] ?? []).map((candidate: { id: string; titel: string }) => ({
        id: candidate.id, slags: 'portræt', titel: candidate.titel, kunstner: '', datering: '',
        mediumUrl: `https://example.test/${candidate.id}.jpg`, largeUrl: `https://example.test/${candidate.id}.jpg`,
      }))]),
    ));
  });

  it('bevarer det igangværende kandidatfetch, når næste side appendes', async () => {
    const firstFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates.mockImplementation((ids: string[]) => (
      ids[0] === '1' ? firstFetch.promise : Promise.resolve({ '2': [] })
    ));

    render(<FeedStreamView {...feedProps(null)} />);

    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2));
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(1, ['1'], {});
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(2, ['2'], {});
    firstFetch.resolve({ '1': [{ id: 'media-1', titel: 'Første portræt' }] });

    await waitFor(() => expect(screen.getByRole('button', { name: 'Åbn billede: Første portræt' })).toBeTruthy());
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2);
  });

  it('viser ikke et sent kandidatresultat fra den forrige bogmærke-ejer', async () => {
    const ownerAFetch = deferred<Record<string, unknown[]>>();
    const ownerBFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates.mockImplementation((ids: string[]) => {
      if (ids[0] === '1' && ids.length === 1) return ownerAFetch.promise;
      if (ids[0] === '2') return Promise.resolve({ '2': [] });
      return ownerBFetch.promise;
    });

    const view = render(<FeedStreamView {...feedProps('owner-a')} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(2));
    view.rerender(<FeedStreamView {...feedProps('owner-b')} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledTimes(3));
    expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenNthCalledWith(3, ['1', '2'], {});

    await act(async () => { ownerAFetch.resolve({ '1': [{ id: 'owner-a', titel: 'Ejer A portræt' }] }); });
    expect(screen.queryByRole('button', { name: 'Åbn billede: Ejer A portræt' })).toBeNull();

    ownerBFetch.resolve({ '1': [{ id: 'owner-b', titel: 'Ejer B portræt' }], '2': [] });
    await waitFor(() => expect(screen.getByRole('button', { name: 'Åbn billede: Ejer B portræt' })).toBeTruthy());
  });

  it('starter ikke en ny media-resolution efter unmount fra et sent kandidatresultat', async () => {
    const pendingFetch = deferred<Record<string, unknown[]>>();
    mediaMocks.fetchFeedMediaCandidates.mockImplementation((ids: string[]) => (
      ids[0] === '1' ? pendingFetch.promise : Promise.resolve({ '2': [] })
    ));

    const view = render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledWith(['1'], {}));
    view.unmount();
    await act(async () => { pendingFetch.resolve({ '1': [{ id: 'unmounted', titel: 'Må ikke vises' }] }); });

    expect(mediaMocks.resolveFeedMediaForCards.mock.calls.some(([, candidates]) => (
      candidates['1']?.some((candidate: { titel: string }) => candidate.titel === 'Må ikke vises')
    ))).toBe(false);
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
  it('gods-kort peger på godsets side', () => {
    const kort: Extract<FeedCard, { kind: 'gods' }> = {
      kind: 'gods', id: 'gods:7', estateId: '7', navn: 'Gammel Gaard', meta: 'herregård', ownerDots: 3, kicker: 'Gods',
    };
    expect(hrefForCard(kort)).toBe('/estate/7');
  });
  it('våben-kort peger på våben-fanen', () => {
    const kort: Extract<FeedCard, { kind: 'vaaben' }> = {
      kind: 'vaaben', id: 'vaaben:1', armsId: '1', blazon: 'to skjolde', foot: 'DAA', kicker: 'Våben',
    };
    expect(hrefForCard(kort)).toBe('/arms');
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
