// @vitest-environment jsdom
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FeedCard, FeedInputs } from '@daa/feed';
import { FEED_FOERSTE_UDDELING_FRIST_MS, hrefForCard } from '../feed/FeedStreamView';

const mediaMocks = vi.hoisted(() => ({
  fetchFeedMediaCandidates: vi.fn(),
  resolveFeedMediaForCards: vi.fn(),
}));
const streamMocks = vi.hoisted(() => ({ createFeedStream: vi.fn(), resumeStream: vi.fn() }));
const feedAuxMocks = vi.hoisted(() => ({ hentFeedBios: vi.fn() }));
const grundlagMocks = vi.hoisted(() => ({ fetchNaevntGrundlag: vi.fn() }));
const loaderMocks = vi.hoisted(() => ({ loadHaendelserBy: vi.fn() }));
const seenMocks = vi.hoisted(() => ({ markSeen: vi.fn(), weights: {} as Record<string, number> }));
// Den færdigpakkede fil: standard null (→ direkte hentning), så de øvrige tests uddeler som før.
const forsideMocks = vi.hoisted(() => ({ hentForsideData: vi.fn(), udpakForsideData: vi.fn() }));

vi.mock('../../data/feedMedia', () => mediaMocks);
vi.mock('../../data/forside/klient', () => ({ hentForsideData: forsideMocks.hentForsideData }));
vi.mock('../../data/forside/udpak', () => ({ udpakForsideData: forsideMocks.udpakForsideData }));
vi.mock('../../data/feedAux', () => ({
  buildWebFeedAux: () => ({ godsListe: [], vaabenListe: [], officesBy: {} }),
  hentFeedBios: feedAuxMocks.hentFeedBios,
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
  feedAuxMocks.hentFeedBios.mockReset().mockResolvedValue({ bioBy: { '1': 'En biografi.' }, komplet: true });
  forsideMocks.hentForsideData.mockReset().mockResolvedValue(null);
  forsideMocks.udpakForsideData.mockReset();
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

describe('FeedStreamView — færdigpakket forside-data', () => {
  it('med fil: ingen direkte hentning, første uddeling straks med fuld data', async () => {
    forsideMocks.hentForsideData.mockResolvedValue({ version: 1 });
    forsideMocks.udpakForsideData.mockReturnValue({
      bios: { bioBy: { '1': 'Fra filen.' }, komplet: true }, livsdatoBy: {}, haendelserBy: {}, storieBy: {},
      naevntGrundlag: { personerMedMereEndNavn: new Set(['1']) },
    });
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalledTimes(1));
    const inputs = streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs;
    expect(inputs.naevntGrundlag?.personerMedMereEndNavn.has('1')).toBe(true);
    expect(feedAuxMocks.hentFeedBios).not.toHaveBeenCalled();
    expect(loaderMocks.loadHaendelserBy).not.toHaveBeenCalled();
    expect(grundlagMocks.fetchNaevntGrundlag).not.toHaveBeenCalled();
  });

  it('fil, der ikke kan pakkes ud (ugyldige rækker): direkte hentning i stedet for en hængende forside', async () => {
    const spy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    forsideMocks.hentForsideData.mockResolvedValue({ version: 1 });
    forsideMocks.udpakForsideData.mockImplementation(() => { throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_person_id'); });
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(feedAuxMocks.hentFeedBios).toHaveBeenCalledTimes(1));
    spy.mockRestore();
  });

  it('tilbagefald efter en langsom fil: den direkte hentning får hele fristen, regnet fra dens start', async () => {
    vi.useFakeTimers();
    try {
      // Filen giver op efter 2 s (kold cache); biografier og hændelser kommer aldrig i testen.
      forsideMocks.hentForsideData.mockImplementation(() => new Promise((res) => setTimeout(() => res(null), 2000)));
      feedAuxMocks.hentFeedBios.mockReturnValue(new Promise(() => undefined));
      loaderMocks.loadHaendelserBy.mockReturnValue(new Promise(() => undefined));
      render(<FeedStreamView {...feedProps(null)} />);
      await act(async () => { await vi.advanceTimersByTimeAsync(2000 + FEED_FOERSTE_UDDELING_FRIST_MS - 1); });
      expect(streamMocks.createFeedStream).not.toHaveBeenCalled();
      await act(async () => { await vi.advanceTimersByTimeAsync(1); });
      expect(streamMocks.createFeedStream).toHaveBeenCalledTimes(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('uden fil (null): direkte hentning som i dag', async () => {
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    expect(feedAuxMocks.hentFeedBios).toHaveBeenCalledTimes(1);
    expect(loaderMocks.loadHaendelserBy).toHaveBeenCalledTimes(1);
    expect(forsideMocks.udpakForsideData).not.toHaveBeenCalled();
  });
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

  it('deler ud efter fristen, selv om biografierne og hændelserne ikke er kommet, og bygger om når de kommer', async () => {
    vi.useFakeTimers();
    try {
      const bios = deferred<{ bioBy: Record<string, string>; komplet: boolean }>();
      const haendelser = deferred<Record<string, unknown>>();
      feedAuxMocks.hentFeedBios.mockReturnValue(bios.promise);
      loaderMocks.loadHaendelserBy.mockReturnValue(haendelser.promise);
      render(<FeedStreamView {...feedProps(null)} />);
      await act(async () => { await vi.advanceTimersByTimeAsync(FEED_FOERSTE_UDDELING_FRIST_MS - 1); });
      expect(streamMocks.createFeedStream).not.toHaveBeenCalled();

      await act(async () => { await vi.advanceTimersByTimeAsync(1); });
      expect(streamMocks.createFeedStream).toHaveBeenCalledTimes(1);
      expect(screen.getAllByRole('article')).toHaveLength(6);

      await act(async () => { bios.resolve({ bioBy: { '1': 'En biografi.' }, komplet: true }); haendelser.resolve({}); });
      expect(streamMocks.createFeedStream.mock.calls.length).toBeGreaterThan(1);
      expect(streamMocks.resumeStream).toHaveBeenCalled();
      expect(screen.getAllByRole('article')).toHaveLength(6); // viste blade nulstilles ikke
    } finally {
      vi.useRealTimers();
    }
  });

  it('deler ikke et rent samlekort ud ved fristen, men venter og deler rigtige blade ud, når data kommer', async () => {
    // Prod 22/11: uden biografier og hændelser gav puljen kun samlekortet. Det blev vist ved fristen, fjernet
    // ved genopbygningen (preserveShownForResume), og så stod feedet med 0 blade og »Henter blade« for evigt.
    vi.useFakeTimers();
    try {
      const samle: FeedCard = { kind: 'samle', id: 'samle:personer', count: 919, tail: 'personer', kicker: 'Registeret' };
      const bios = deferred<{ bioBy: Record<string, string>; komplet: boolean }>();
      const haendelser = deferred<Record<string, unknown>>();
      feedAuxMocks.hentFeedBios.mockReturnValue(bios.promise);
      loaderMocks.loadHaendelserBy.mockReturnValue(haendelser.promise);
      let medData = false;
      streamMocks.createFeedStream.mockImplementation(() => listStream(medData ? [...SYV, samle] : [samle]));
      render(<FeedStreamView {...feedProps(null)} />);
      await act(async () => { await vi.advanceTimersByTimeAsync(FEED_FOERSTE_UDDELING_FRIST_MS); });
      expect(screen.queryAllByRole('article')).toHaveLength(0);
      expect(screen.getByRole('status').textContent).toContain('Henter blade');
      expect(screen.queryByText(/vendt alle dagens blade/)).toBeNull();

      medData = true;
      await act(async () => { bios.resolve({ bioBy: { '1': 'En biografi.' }, komplet: true }); haendelser.resolve({}); });
      expect(screen.getAllByRole('article')).toHaveLength(6);
      expect(screen.queryByRole('status')).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it('viser ikke »vendt alle blade« ved en tidlig uddeling, mens kilder stadig mangler', async () => {
    vi.useFakeTimers();
    try {
      const samle: FeedCard = { kind: 'samle', id: 'samle:personer', count: 919, tail: 'personer', kicker: 'Registeret' };
      const bios = deferred<{ bioBy: Record<string, string>; komplet: boolean }>();
      feedAuxMocks.hentFeedBios.mockReturnValue(bios.promise);
      streamMocks.createFeedStream.mockImplementation(() => listStream([portraet('1'), samle]));
      streamMocks.resumeStream.mockImplementation((_s: unknown, vist: Set<string>) =>
        listStream([portraet('1'), samle].filter((c) => !vist.has(c.id))));
      render(<FeedStreamView {...feedProps(null)} />);
      await act(async () => { await vi.advanceTimersByTimeAsync(FEED_FOERSTE_UDDELING_FRIST_MS); });
      expect(screen.getAllByRole('article')).toHaveLength(1);
      expect(screen.queryByText(/919/)).toBeNull(); // samlekortet hører til den endelige pulje
      expect(screen.queryByText(/vendt alle dagens blade/)).toBeNull();

      await act(async () => { bios.resolve({ bioBy: { '1': 'En biografi.' }, komplet: true }); });
      expect(screen.getByText(/919/)).toBeTruthy();
      expect(screen.getByText(/vendt alle dagens blade/)).toBeTruthy();
    } finally {
      vi.useRealTimers();
    }
  });

  it('fylder første portion op til seks, når data kommer efter en tynd uddeling ved fristen', async () => {
    // Prod-bygget 22/11 med første rettelse: fristen gav ét blad, og det blev stående alene.
    vi.useFakeTimers();
    try {
      const bios = deferred<{ bioBy: Record<string, string>; komplet: boolean }>();
      feedAuxMocks.hentFeedBios.mockReturnValue(bios.promise);
      let medData = false;
      streamMocks.createFeedStream.mockImplementation(() => listStream(medData ? SYV : [portraet('1')]));
      streamMocks.resumeStream.mockImplementation((_s: unknown, vist: Set<string>) =>
        listStream(SYV.filter((c) => !vist.has(c.id))));
      render(<FeedStreamView {...feedProps(null)} />);
      await act(async () => { await vi.advanceTimersByTimeAsync(FEED_FOERSTE_UDDELING_FRIST_MS); });
      expect(screen.getAllByRole('article')).toHaveLength(1);

      medData = true;
      await act(async () => { bios.resolve({ bioBy: { '1': 'En biografi.' }, komplet: true }); });
      expect(screen.getAllByRole('article')).toHaveLength(6);
      expect(screen.getByRole('region', { name: 'Blade 1–6' })).toBeTruthy();
    } finally {
      vi.useRealTimers();
    }
  });

  it('sender intet nævnt-grundlag, når grundlaget fejler eller biografierne er tomme', async () => {
    grundlagMocks.fetchNaevntGrundlag.mockRejectedValue(new Error('permission denied'));
    const view = render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    expect((streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs).naevntGrundlag).toBeUndefined();
    view.unmount();

    streamMocks.createFeedStream.mockClear();
    grundlagMocks.fetchNaevntGrundlag.mockResolvedValue({ personerMedMereEndNavn: new Set() });
    feedAuxMocks.hentFeedBios.mockResolvedValue({ bioBy: {}, komplet: true });
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    expect((streamMocks.createFeedStream.mock.calls[0][2] as FeedInputs).naevntGrundlag).toBeUndefined();
  });

  it('ufuldstændige biografier: intet nævnt-grundlag (en manglende tekst er ikke bevis for, at der ingen er) og intet fejlbanner', async () => {
    feedAuxMocks.hentFeedBios.mockResolvedValue({ bioBy: { '1': 'En biografi.' }, komplet: false });
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(streamMocks.createFeedStream).toHaveBeenCalled());
    const inputs = streamMocks.createFeedStream.mock.calls.at(-1)![2] as FeedInputs;
    expect(inputs.naevntGrundlag).toBeUndefined();
    expect(screen.queryByText(/Kunne ikke hente feedets biografier/)).toBeNull();
  });

  it('markerer et blad som set, først når det er synligt — ikke ved uddelingen', async () => {
    class FakeObserver {
      static seneste: FakeObserver | null = null;
      elementer = new Set<Element>();
      constructor(private cb: (entries: unknown[], obs: unknown) => void) { FakeObserver.seneste = this; }
      observe(el: Element) { this.elementer.add(el); }
      unobserve(el: Element) { this.elementer.delete(el); }
      disconnect() { this.elementer.clear(); }
      vis(ids: string[]) {
        const entries = [...this.elementer]
          .filter((el) => ids.includes((el as HTMLElement).dataset.kortId ?? ''))
          .map((target) => ({ target, isIntersecting: true, intersectionRatio: 0.6 }));
        this.cb(entries, this);
      }
    }
    vi.stubGlobal('IntersectionObserver', FakeObserver);
    try {
      render(<FeedStreamView {...feedProps(null)} />);
      await waitFor(() => expect(screen.getByRole('region', { name: 'Blade 1–6' })).toBeTruthy());
      expect(seenMocks.markSeen).not.toHaveBeenCalled();

      act(() => { FakeObserver.seneste!.vis(['portrait:1', 'portrait:2']); });
      expect(seenMocks.markSeen).toHaveBeenCalledWith(['portrait:1', 'portrait:2'], 1);
      // Et blad markeres kun én gang.
      act(() => { FakeObserver.seneste!.vis(['portrait:1']); });
      expect(seenMocks.markSeen).toHaveBeenCalledTimes(1);
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it('viser seks blade, og knappen vender de næste som ny blok med fokus', async () => {
    render(<FeedStreamView {...feedProps(null)} />);
    await waitFor(() => expect(screen.getAllByRole('region')).toHaveLength(1));
    expect(screen.getByRole('region', { name: 'Blade 1–6' })).toBeTruthy();
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
    feedAuxMocks.hentFeedBios.mockRejectedValue(new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE'));

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
    expect(hrefForCard(kort)).toBe('/besiddelse/7');
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
