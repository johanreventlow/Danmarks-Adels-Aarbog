// @vitest-environment jsdom
import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FeedCard } from '@daa/feed';

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

describe('FeedStreamView media lifecycle', () => {
  beforeEach(() => {
    let nextCall = 0;
    const stream = {
      next: vi.fn(() => (nextCall++ === 0 ? [firstCard] : [secondCard])),
      done: vi.fn(() => nextCall >= 2),
    };
    streamMocks.createFeedStream.mockReset().mockReturnValue(stream);
    streamMocks.resumeStream.mockReset().mockReturnValue(stream);
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

    render(<FeedStreamView
      model={model} estates={null} arms={null} meId={null} focusId={null} feedPins={[]}
      bookmarkedIds={[]} bookmarksReady bookmarkHydrationVersion={1} bookmarkOwnerId={null}
      hasBookmark={() => false} onSaveBookmark={vi.fn()} onOpenPerson={vi.fn()} onOpenEstate={vi.fn()}
      onOpenArms={vi.fn()} onOpenSlaegt={vi.fn()} onBrowseAll={vi.fn()}
    />);

    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledWith(['1'], {}));
    await waitFor(() => expect(mediaMocks.fetchFeedMediaCandidates).toHaveBeenCalledWith(['2'], {}));
    firstFetch.resolve({ '1': [{ id: 'media-1', titel: 'Første portræt' }] });

    await waitFor(() => expect(screen.getByRole('button', { name: 'Åbn billede: Første portræt' })).toBeTruthy());
  });
});
