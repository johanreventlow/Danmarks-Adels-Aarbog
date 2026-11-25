// Læsermodellen følger den effektive identitet (review 37 M5, spejl af web's brugerId-effekt i Folgesvend.tsx): RLS giver
// kun redaktører levende personer, så modellen ryddes straks ved logout/brugerskift/rolleskift og hentes igen. En
// indlæsning startet under den gamle identitet kasseres. TOKEN_REFRESHED og opstartens rolleopslag giver ingen ny hentning.
type Deferred<T> = { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void };
function deferred<T>(): Deferred<T> {
  let resolve!: (v: T) => void; let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

const mockLoad = jest.fn();
jest.mock('../../data/load', () => ({ loadFromSupabase: (...a: unknown[]) => mockLoad(...a) }));
const mockSignOut = jest.fn();
const mockSignIn = jest.fn();
const mockFetchProfile = jest.fn();
jest.mock('../../lib/auth', () => ({
  signOut: () => mockSignOut(),
  signIn: (...a: unknown[]) => mockSignIn(...a),
  fetchProfile: (...a: unknown[]) => mockFetchProfile(...a),
}));
const mockGetSession = jest.fn();
jest.mock('../../lib/supabase', () => ({ supabase: {
  auth: {
    getSession: () => mockGetSession(),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => undefined } } }),
  },
} }));

import { useStore } from '../useStore';

type Bios = { bioBy: Record<string, string>; komplet: boolean };
// Et svar fra loadFromSupabase med én person ved navn `navn` (»Levende« = redaktørens model, »Gæst« = den offentlige).
const svar = (navn: string, bios: Promise<Bios> = Promise.resolve({ bioBy: {}, komplet: true })) => ({
  db: { persons: [{ id: '1', name: navn, born: null, died: null, years: '', title: '', bio: '', privat: false }],
        unions: [], parentChild: [] },
  aux: {},
  rootId: '1', focusId: '1', relAId: '1', relBId: '1',
  canonicalIdById: {}, mergedFrom: {},
  geo: { points: [] }, loadGeo: async () => ({ points: [] }),
  loadBios: () => bios,
  genCoordsByPerson: {}, parentsUnknownByPerson: {}, livsdatoBy: {}, haendelserBy: {}, storieBy: {}, feedPins: [],
});
const sess = (id: string) => ({ user: { id, email: id + '@x.dk' } }) as never;
const profil = (rolle: 'redaktion' | 'medlem') => ({ rolle, reventlowPersonId: null });
const flush = () => new Promise((r) => setTimeout(r, 0));
const st = () => useStore.getState();
const navn = () => st().model?.persons[0]?.name ?? null;

// Udgangspunkt: redaktøren u1 er logget ind, og læsermodellen (med levende) er hentet under den identitet.
async function redaktoerMedModel() {
  useStore.setState({ session: sess('u1'), rolle: 'redaktion', modelIdentitet: 'u1:redaktion', status: 'idle' });
  mockLoad.mockResolvedValueOnce(svar('Levende'));
  await st().load();
  expect(navn()).toBe('Levende');
  mockLoad.mockClear();
}

beforeEach(() => {
  mockLoad.mockReset(); mockSignOut.mockReset(); mockSignIn.mockReset();
  mockFetchProfile.mockReset(); mockGetSession.mockReset();
  mockSignOut.mockResolvedValue(undefined);
  mockGetSession.mockResolvedValue({ data: { session: null } });
  useStore.setState({
    status: 'idle', source: null, error: null, model: null, biosStatus: 'idle',
    session: null, rolle: 'medlem', reventlowPersonId: null, rolleFejl: null, modelIdentitet: undefined,
  });
  jest.spyOn(console, 'warn').mockImplementation(() => undefined);
});
afterEach(() => jest.restoreAllMocks());

describe('logout og SIGNED_OUT rydder læsermodellen og henter igen', () => {
  test('doSignOut: modellen er null straks, og en ny indlæsning er startet', async () => {
    await redaktoerMedModel();
    const gaest = deferred<unknown>();
    mockLoad.mockReturnValueOnce(gaest.promise);
    const epoke = st().loadEpoch;
    await st().doSignOut();
    expect(st().model).toBeNull();
    expect(st().aux).toBeNull();
    expect(st().biosStatus).toBe('idle');
    expect(st().status).toBe('loading');
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBeNull();
    gaest.resolve(svar('Gæst'));
    await flush();
    expect(navn()).toBe('Gæst');
    expect(st().loadEpoch).toBe(epoke + 1); // forsidens strøm starter forfra
  });

  test('SIGNED_OUT-event: modellen er null synkront, og en ny indlæsning er startet', async () => {
    await redaktoerMedModel();
    mockLoad.mockReturnValueOnce(deferred<unknown>().promise);
    st().haandterAuthEvent('SIGNED_OUT', null);
    expect(st().model).toBeNull();
    expect(st().session).toBeNull();
    expect(st().status).toBe('loading');
    expect(mockLoad).toHaveBeenCalledTimes(1);
  });

  test('SIGNED_OUT under doSignOut giver kun én ny indlæsning', async () => {
    await redaktoerMedModel();
    mockLoad.mockReturnValue(deferred<unknown>().promise);
    // Supabase sender SIGNED_OUT, før signOut() er færdig.
    mockSignOut.mockImplementationOnce(async () => { st().haandterAuthEvent('SIGNED_OUT', null); });
    await st().doSignOut();
    expect(st().model).toBeNull();
    expect(mockLoad).toHaveBeenCalledTimes(1);
  });

  test('bio-svar fra den gamle model lander ikke efter logout', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'redaktion', modelIdentitet: 'u1:redaktion' });
    const bios = deferred<Bios>();
    mockLoad.mockResolvedValueOnce(svar('Levende', bios.promise));
    await st().load();
    mockLoad.mockResolvedValueOnce(svar('Gæst'));
    await st().doSignOut();
    await flush();
    expect(navn()).toBe('Gæst');
    bios.resolve({ bioBy: { '1': 'Redaktørens tekst' }, komplet: true });
    await flush();
    expect(st().model?.byId['1'].bio).toBe('');
  });
});

describe('forældede indlæsninger kasseres', () => {
  test('en indlæsning startet før logout lander ikke bagefter', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'redaktion', modelIdentitet: 'u1:redaktion' });
    const gammel = deferred<unknown>();
    const ny = deferred<unknown>();
    mockLoad.mockReturnValueOnce(gammel.promise).mockReturnValueOnce(ny.promise);
    const p = st().load();
    await st().doSignOut();
    expect(mockLoad).toHaveBeenCalledTimes(2); // den nye starter, selv om den gamle stadig er undervejs
    gammel.resolve(svar('Levende'));
    await p;
    expect(st().model).toBeNull();
    expect(st().status).toBe('loading');
    ny.resolve(svar('Gæst'));
    await flush();
    expect(navn()).toBe('Gæst');
  });

  test('lander den gamle efter den nye, bliver den nye stående', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'redaktion', modelIdentitet: 'u1:redaktion' });
    const gammel = deferred<unknown>();
    mockLoad.mockReturnValueOnce(gammel.promise).mockResolvedValueOnce(svar('Gæst'));
    const p = st().load();
    await st().doSignOut();
    await flush();
    expect(navn()).toBe('Gæst');
    const epoke = st().loadEpoch;
    gammel.resolve(svar('Levende'));
    await p;
    expect(navn()).toBe('Gæst');
    expect(st().loadEpoch).toBe(epoke);
  });

  test('en forældet fejl lægger ikke offline-seed oven på den nye indlæsning', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'redaktion', modelIdentitet: 'u1:redaktion' });
    const gammel = deferred<unknown>();
    mockLoad.mockReturnValueOnce(gammel.promise).mockReturnValueOnce(deferred<unknown>().promise);
    const p = st().load();
    await st().doSignOut();
    gammel.reject(new Error('net'));
    await p;
    expect(st().source).toBeNull();
    expect(st().status).toBe('loading');
    expect(mockLoad).toHaveBeenCalledTimes(2); // intet genforsøg for den forældede
  });
});

describe('login og rolleskift', () => {
  test('login medlem → redaktør: modellen ryddes og hentes igen', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'medlem', modelIdentitet: 'u1:medlem' });
    mockLoad.mockResolvedValueOnce(svar('Gæst'));
    await st().load();
    mockLoad.mockClear();
    const ny = deferred<unknown>();
    mockLoad.mockReturnValueOnce(ny.promise);
    mockSignIn.mockResolvedValueOnce({ userId: 'u1', session: sess('u1'), rolle: 'redaktion', reventlowPersonId: null });
    await st().doSignIn('a@b', 'x');
    expect(st().model).toBeNull();
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBe('u1:redaktion');
    ny.resolve(svar('Levende'));
    await flush();
    expect(navn()).toBe('Levende');
  });

  test('login som gæst → medlem: ny identitet giver ny indlæsning', async () => {
    useStore.setState({ modelIdentitet: null });
    mockLoad.mockReturnValue(deferred<unknown>().promise);
    mockSignIn.mockResolvedValueOnce({ userId: 'u2', session: sess('u2'), rolle: 'medlem', reventlowPersonId: null });
    await st().doSignIn('a@b', 'x');
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBe('u2:medlem');
  });

  test('TOKEN_REFRESHED for samme bruger rører hverken model eller indlæsning', async () => {
    await redaktoerMedModel();
    const model = st().model;
    st().haandterAuthEvent('TOKEN_REFRESHED', sess('u1'));
    await flush();
    expect(st().model).toBe(model);
    expect(mockLoad).not.toHaveBeenCalled();
  });

  test('USER_UPDATED uden rolleskift giver ingen ny indlæsning', async () => {
    await redaktoerMedModel();
    mockGetSession.mockResolvedValue({ data: { session: sess('u1') } });
    mockFetchProfile.mockResolvedValue(profil('redaktion'));
    st().haandterAuthEvent('USER_UPDATED', sess('u1'));
    await flush(); await flush();
    expect(mockFetchProfile).toHaveBeenCalledWith('u1');
    expect(navn()).toBe('Levende');
    expect(mockLoad).not.toHaveBeenCalled();
  });

  test('brugerskift: ryddes straks; den nye rolle giver endnu en indlæsning, og SIGNED_OUT rydder igen', async () => {
    await redaktoerMedModel();
    mockLoad.mockReturnValue(deferred<unknown>().promise);
    mockGetSession.mockResolvedValue({ data: { session: sess('u2') } });
    mockFetchProfile.mockResolvedValue(profil('medlem'));
    st().haandterAuthEvent('SIGNED_IN', sess('u2'));
    expect(st().model).toBeNull();
    expect(mockLoad).toHaveBeenCalledTimes(1);
    await flush(); await flush();
    expect(st().modelIdentitet).toBe('u2:medlem');
    expect(mockLoad).toHaveBeenCalledTimes(2);
    st().haandterAuthEvent('SIGNED_OUT', null);
    expect(mockLoad).toHaveBeenCalledTimes(3);
    expect(st().modelIdentitet).toBeNull();
  });
});

describe('opstart', () => {
  test('hydrateAuth + load som i _layout: én indlæsning, når identiteten er den gemte sessions', async () => {
    mockGetSession.mockResolvedValue({ data: { session: sess('u1') } });
    mockFetchProfile.mockResolvedValue(profil('redaktion'));
    mockLoad.mockResolvedValueOnce(svar('Levende'));
    const h = st().hydrateAuth();
    const l = st().load();
    await Promise.all([h, l]);
    await flush();
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBe('u1:redaktion');
    expect(navn()).toBe('Levende');
  });

  test.each(['SIGNED_IN', 'TOKEN_REFRESHED'] as const)(
    'supabase-js sender %s for den gemte session ved opstart: stadig kun én indlæsning',
    async (event) => {
      const g = deferred<{ data: { session: unknown } }>();
      mockGetSession.mockReturnValueOnce(g.promise).mockResolvedValue({ data: { session: sess('u1') } });
      mockFetchProfile.mockResolvedValue(profil('redaktion'));
      mockLoad.mockResolvedValueOnce(svar('Levende'));
      const h = st().hydrateAuth();
      const l = st().load();
      st().haandterAuthEvent(event, sess('u1')); // før hydrateAuth har sat sessionen i storen
      g.resolve({ data: { session: sess('u1') } });
      await Promise.all([h, l]);
      await flush(); await flush();
      expect(mockLoad).toHaveBeenCalledTimes(1);
      expect(st().modelIdentitet).toBe('u1:redaktion');
      expect(st().session?.user.id).toBe('u1');
      expect(navn()).toBe('Levende');
    },
  );

  test('opstart uden gemt session: ingen ekstra indlæsning, identiteten bliver gæst', async () => {
    mockLoad.mockResolvedValueOnce(svar('Gæst'));
    const h = st().hydrateAuth();
    const l = st().load();
    await Promise.all([h, l]);
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBeNull();
  });

  test('et senere rolleopslag med en anden rolle henter igen', async () => {
    useStore.setState({ session: sess('u1'), rolle: 'medlem', modelIdentitet: 'u1:medlem', status: 'ready' });
    mockGetSession.mockResolvedValue({ data: { session: sess('u1') } });
    mockFetchProfile.mockResolvedValue(profil('redaktion'));
    mockLoad.mockReturnValue(deferred<unknown>().promise);
    await st().hydrateAuth();
    expect(st().model).toBeNull();
    expect(mockLoad).toHaveBeenCalledTimes(1);
    expect(st().modelIdentitet).toBe('u1:redaktion');
  });
});
