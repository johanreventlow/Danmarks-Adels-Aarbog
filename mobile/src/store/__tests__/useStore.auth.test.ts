// Auth-skift når storen, og sene login-/rolleopslag kasseres (review 37 W4+W5, spejl af web's Folgesvend.auth-tests).
// Supabase-events simuleres ved at kalde haandterAuthEvent direkte; I/O styres med manuelle løfter.
type Deferred<T> = { promise: Promise<T>; resolve: (v: T) => void; reject: (e: unknown) => void };
function deferred<T>(): Deferred<T> {
  let resolve!: (v: T) => void; let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

jest.mock('../../data/load', () => ({ loadFromSupabase: jest.fn() }));
const mockSignOut = jest.fn();
const mockSignIn = jest.fn();
const mockFetchProfile = jest.fn();
jest.mock('../../lib/auth', () => ({
  signOut: () => mockSignOut(),
  signIn: (...a: unknown[]) => mockSignIn(...a),
  fetchProfile: (...a: unknown[]) => mockFetchProfile(...a),
}));
const mockGetSession = jest.fn();
const mockUnsubscribe = jest.fn();
const mockOnAuth = jest.fn();
jest.mock('../../lib/supabase', () => ({ supabase: {
  auth: {
    getSession: () => mockGetSession(),
    onAuthStateChange: (cb: unknown) => { mockOnAuth(cb); return { data: { subscription: { unsubscribe: mockUnsubscribe } } }; },
  },
} }));

import { lytPaaAuth, useStore } from '../useStore';

const sess = (id: string) => ({ user: { id, email: id + '@x.dk' } }) as never;
const profil = (rolle: 'redaktion' | 'medlem' = 'redaktion') => ({ rolle, reventlowPersonId: null });
const flush = () => new Promise((r) => setTimeout(r, 0));
const st = () => useStore.getState();

beforeEach(() => {
  mockSignOut.mockReset(); mockSignIn.mockReset(); mockFetchProfile.mockReset(); mockGetSession.mockReset();
  mockSignOut.mockResolvedValue(undefined);
  mockFetchProfile.mockResolvedValue(profil());
  mockGetSession.mockResolvedValue({ data: { session: null } });
  useStore.setState({
    session: sess('u1'), rolle: 'redaktion', reventlowPersonId: '7', rolleFejl: null,
    redaktionModel: { persons: [] } as never, redaktionStatus: 'ready',
  });
});

describe('lytPaaAuth', () => {
  test('abonnerer og sender events videre til storen; afmelding virker', async () => {
    const af = lytPaaAuth();
    const cb = mockOnAuth.mock.calls.at(-1)![0] as (e: string, s: unknown) => void;
    cb('SIGNED_OUT', null);
    expect(st().session).toBeNull();
    af();
    expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
  });
});

describe('haandterAuthEvent', () => {
  test('SIGNED_OUT (udløb/mislykket fornyelse) rydder session, rolle, rollefejl og redaktions-slicen', () => {
    useStore.setState({ rolleFejl: 'gammel' });
    st().haandterAuthEvent('SIGNED_OUT', null);
    const s = st();
    expect(s.session).toBeNull();
    expect(s.rolle).toBe('medlem');
    expect(s.reventlowPersonId).toBeNull();
    expect(s.rolleFejl).toBeNull();
    expect(s.redaktionModel).toBeNull();
    expect(s.redaktionStatus).toBe('idle');
  });

  test('TOKEN_REFRESHED for samme bruger bevarer rolle, session og redaktions-model', () => {
    const foer = st().session;
    st().haandterAuthEvent('TOKEN_REFRESHED', sess('u1'));
    expect(st().rolle).toBe('redaktion');
    expect(st().session).toBe(foer);
    expect(st().redaktionStatus).toBe('ready');
  });

  test('INITIAL_SESSION ignoreres (hydrateAuth tager opstarten)', () => {
    st().haandterAuthEvent('INITIAL_SESSION', null);
    expect(st().session).not.toBeNull();
  });

  test('anden bruger: rydder straks og slår den nye brugers rolle op', async () => {
    mockGetSession.mockResolvedValue({ data: { session: sess('u2') } });
    mockFetchProfile.mockResolvedValue(profil('medlem'));
    st().haandterAuthEvent('SIGNED_IN', sess('u2'));
    expect(st().session).toBeNull();
    expect(st().rolle).toBe('medlem');
    expect(st().redaktionModel).toBeNull();
    await flush(); await flush();
    expect(st().session?.user.id).toBe('u2');
    expect(mockFetchProfile).toHaveBeenCalledWith('u2');
  });
});

describe('hydrateAuth — generationsværn', () => {
  test('SIGNED_OUT mens rolleopslaget kører: det sene svar logger ikke brugeren ind igen', async () => {
    useStore.setState({ session: null, rolle: 'medlem' });
    mockGetSession.mockResolvedValue({ data: { session: sess('u1') } });
    const p = deferred<ReturnType<typeof profil>>();
    mockFetchProfile.mockReturnValueOnce(p.promise);
    const h = st().hydrateAuth();
    await flush();
    st().haandterAuthEvent('SIGNED_OUT', null);
    p.resolve(profil('redaktion'));
    await h;
    expect(st().session).toBeNull();
    expect(st().rolle).toBe('medlem');
  });

  test('logout mens getSession kører: det sene svar kasseres', async () => {
    const g = deferred<{ data: { session: unknown } }>();
    mockGetSession.mockReturnValueOnce(g.promise);
    const h = st().hydrateAuth();
    await st().doSignOut();
    g.resolve({ data: { session: sess('u1') } });
    await h;
    expect(st().session).toBeNull();
    expect(mockFetchProfile).not.toHaveBeenCalled();
  });

  test('forældet rollefejl overskriver ikke en nyere tilstand', async () => {
    mockGetSession.mockResolvedValue({ data: { session: sess('u1') } });
    const p = deferred<ReturnType<typeof profil>>();
    mockFetchProfile.mockReturnValueOnce(p.promise);
    const h = st().hydrateAuth();
    await flush();
    st().haandterAuthEvent('SIGNED_OUT', null);
    p.reject(new Error('net'));
    await h;
    expect(st().rolleFejl).toBeNull();
  });

  test('ingen Supabase-session: en forældet session i storen ryddes', async () => {
    await st().hydrateAuth();
    expect(st().session).toBeNull();
    expect(st().rolle).toBe('medlem');
  });
});

describe('doSignIn — generationsværn', () => {
  test('eget SIGNED_IN under login giver ikke en nulstilling eller et ekstra opslag', async () => {
    useStore.setState({ session: null, rolle: 'medlem' });
    const d = deferred<unknown>();
    mockSignIn.mockReturnValueOnce(d.promise);
    const p = st().doSignIn('a@b', 'x');
    st().haandterAuthEvent('SIGNED_IN', sess('u2'));
    d.resolve({ userId: 'u2', session: sess('u2'), rolle: 'redaktion', reventlowPersonId: null });
    await p;
    await flush();
    expect(st().session?.user.id).toBe('u2');
    expect(st().rolle).toBe('redaktion');
    expect(mockGetSession).not.toHaveBeenCalled();
    expect(mockFetchProfile).not.toHaveBeenCalled();
  });

  test('logout mens login kører: det sene login-svar kasseres', async () => {
    const d = deferred<unknown>();
    mockSignIn.mockReturnValueOnce(d.promise);
    const p = st().doSignIn('a@b', 'x');
    await st().doSignOut();
    d.resolve({ userId: 'u1', session: sess('u1'), rolle: 'redaktion', reventlowPersonId: null });
    await p;
    expect(st().session).toBeNull();
    expect(st().rolle).toBe('medlem');
  });

  test('anden bruger loggede ind undervejs: svaret kasseres, og den faktiske session genskabes', async () => {
    useStore.setState({ session: null, rolle: 'medlem' });
    const d = deferred<unknown>();
    mockSignIn.mockReturnValueOnce(d.promise);
    mockGetSession.mockResolvedValue({ data: { session: sess('u3') } });
    mockFetchProfile.mockResolvedValue(profil('medlem'));
    const p = st().doSignIn('a@b', 'x');
    st().haandterAuthEvent('SIGNED_IN', sess('u3'));
    d.resolve({ userId: 'u2', session: sess('u2'), rolle: 'redaktion', reventlowPersonId: null });
    await p;
    await flush(); await flush();
    expect(st().session?.user.id).toBe('u3');
    expect(st().rolle).toBe('medlem');
  });

  test('fejlet login kastes videre til login-arket', async () => {
    mockSignIn.mockRejectedValueOnce(new Error('Invalid login credentials'));
    await expect(st().doSignIn('a@b', 'x')).rejects.toThrow('Invalid login credentials');
  });
});
