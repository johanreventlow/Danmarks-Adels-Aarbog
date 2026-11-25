// Generationsværn for redaktions-modellen: forældede loadRedaktionModel-svar kasseres efter
// logout, brugerskift og nyere (tvungne) reloads. I/O simuleres med manuelt styrede løfter.
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
jest.mock('../../lib/supabase', () => ({ supabase: {
  auth: { getSession: async () => ({ data: { session: { user: { id: 'u2' } } } }) },
} }));

import { useStore } from '../useStore';

// Et svar fra loadFromSupabase, mærket så vi kan se HVILKEN indlæsning der landede.
const svar = (maerke: string) => ({
  db: { persons: [{ id: maerke, name: maerke, born: null, died: null, years: '', title: '', bio: '', privat: false }],
        unions: [], parentChild: [] },
  aux: { maerke },
});
const landetMaerke = () => useStore.getState().redaktionModel?.persons[0]?.id ?? null;
const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(() => {
  mockLoad.mockReset(); mockSignOut.mockReset(); mockSignIn.mockReset();
  mockSignOut.mockResolvedValue(undefined);
  mockFetchProfile.mockReset();
  mockFetchProfile.mockResolvedValue({ rolle: 'redaktion', reventlowPersonId: null });
  useStore.setState({ redaktionModel: null, redaktionAux: null, redaktionStatus: 'idle',
    session: { user: { id: 'u1' } } as never, rolle: 'redaktion' });
});

describe('loadRedaktionModel — generationsværn', () => {
  test('logout mens indlæsningen kører: modellen lægges IKKE tilbage', async () => {
    const d = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d.promise);
    const p = useStore.getState().loadRedaktionModel();
    expect(useStore.getState().redaktionStatus).toBe('loading');
    await useStore.getState().doSignOut();
    expect(useStore.getState().redaktionStatus).toBe('idle');
    d.resolve(svar('gammel'));
    await p;
    expect(useStore.getState().redaktionModel).toBeNull();
    expect(useStore.getState().redaktionAux).toBeNull();
    expect(useStore.getState().redaktionStatus).toBe('idle');
  });

  test('svar der lander mens signOut afventes, er væk når logout er færdig', async () => {
    const d = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d.promise);
    const so = deferred<void>();
    mockSignOut.mockReturnValueOnce(so.promise);
    const p = useStore.getState().loadRedaktionModel();
    const ud = useStore.getState().doSignOut();
    await flush();
    d.resolve(svar('gammel'));
    await p;
    so.resolve();
    await ud;
    expect(useStore.getState().redaktionModel).toBeNull();
    expect(useStore.getState().redaktionStatus).toBe('idle');
  });

  test('fejlet signOut efterlader ikke status hængende på loading', async () => {
    const d = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d.promise);
    mockSignOut.mockRejectedValueOnce(new Error('net'));
    const p = useStore.getState().loadRedaktionModel();
    await expect(useStore.getState().doSignOut()).rejects.toThrow('net');
    d.resolve(svar('stadig-logget-ind'));
    await p;
    expect(useStore.getState().redaktionStatus).toBe('ready');
    expect(landetMaerke()).toBe('stadig-logget-ind');
  });

  test('forældet fejl efter logout sætter ikke status til error', async () => {
    const d = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d.promise);
    const p = useStore.getState().loadRedaktionModel();
    await useStore.getState().doSignOut();
    d.reject(new Error('net'));
    await p;
    expect(useStore.getState().redaktionStatus).toBe('idle');
  });

  test('to tvungne reloads der slutter i omvendt rækkefølge: den nyeste vinder', async () => {
    const d1 = deferred<ReturnType<typeof svar>>();
    const d2 = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d1.promise).mockReturnValueOnce(d2.promise);
    const p1 = useStore.getState().loadRedaktionModel(true);
    const p2 = useStore.getState().loadRedaktionModel(true);
    d2.resolve(svar('ny'));
    await p2;
    expect(landetMaerke()).toBe('ny');
    d1.resolve(svar('gammel'));
    await p1;
    expect(landetMaerke()).toBe('ny');
    expect(useStore.getState().redaktionStatus).toBe('ready');
  });

  test('ældre reload der fejler efter et nyere succesfuldt, ændrer ikke status', async () => {
    const d1 = deferred<ReturnType<typeof svar>>();
    const d2 = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d1.promise).mockReturnValueOnce(d2.promise);
    const p1 = useStore.getState().loadRedaktionModel(true);
    const p2 = useStore.getState().loadRedaktionModel(true);
    d2.resolve(svar('ny'));
    await p2;
    d1.reject(new Error('net'));
    await p1;
    expect(useStore.getState().redaktionStatus).toBe('ready');
    expect(landetMaerke()).toBe('ny');
  });

  test('brugerskift ved login: forrige brugers model nulstilles og igangværende svar kasseres', async () => {
    useStore.setState({ redaktionModel: { persons: [] } as never, redaktionStatus: 'ready' });
    const d = deferred<ReturnType<typeof svar>>();
    mockLoad.mockReturnValueOnce(d.promise);
    const p = useStore.getState().loadRedaktionModel(true);
    mockSignIn.mockResolvedValueOnce({ userId: 'u2', rolle: 'redaktion', reventlowPersonId: null });
    await useStore.getState().doSignIn('a@b', 'x');
    expect(useStore.getState().redaktionModel).toBeNull();
    expect(useStore.getState().redaktionStatus).toBe('idle'); // ikke hængende 'loading'
    d.resolve(svar('u1-model'));
    await p;
    expect(useStore.getState().redaktionModel).toBeNull();
    // Ny indlæsning for den nye bruger lander normalt.
    mockLoad.mockResolvedValueOnce(svar('u2-model'));
    await useStore.getState().loadRedaktionModel();
    expect(landetMaerke()).toBe('u2-model');
  });

  test('login som samme bruger nulstiller ikke en færdig model', async () => {
    mockLoad.mockResolvedValueOnce(svar('u1-model'));
    await useStore.getState().loadRedaktionModel();
    mockSignIn.mockResolvedValueOnce({ userId: 'u1', rolle: 'redaktion', reventlowPersonId: null });
    await useStore.getState().doSignIn('a@b', 'x');
    // getSession-attrappen returnerer u2 som session, men modellen er kun nulstillet ved userId-skift.
    expect(landetMaerke()).toBe('u1-model');
  });
});

describe('hydrateAuth — rolleopslag (review 37 W6)', () => {
  test('fejlet opslag beholder sessionen, røre ikke rollen og sætter rolleFejl', async () => {
    useStore.setState({ session: { user: { id: 'u2' } } as never, rolle: 'redaktion', rolleFejl: null });
    mockFetchProfile.mockRejectedValueOnce(new Error('Rollen kunne ikke hentes — prøv igen'));
    await useStore.getState().hydrateAuth();
    const s = useStore.getState();
    expect(s.session?.user.id).toBe('u2');
    expect(s.rolle).toBe('redaktion');
    expect(s.rolleFejl).toBe('Rollen kunne ikke hentes — prøv igen');
  });
  test('fejlet opslag ved brugerskift giver medlem (ingen arvet redaktørrolle)', async () => {
    useStore.setState({ session: { user: { id: 'u1' } } as never, rolle: 'redaktion', rolleFejl: null });
    mockFetchProfile.mockRejectedValueOnce(new Error('x'));
    await useStore.getState().hydrateAuth();
    expect(useStore.getState().rolle).toBe('medlem');
    expect(useStore.getState().rolleFejl).toBe('x');
  });
  test('vellykket opslag rydder rolleFejl', async () => {
    useStore.setState({ rolleFejl: 'gammel' });
    await useStore.getState().hydrateAuth();
    expect(useStore.getState().rolleFejl).toBeNull();
    expect(useStore.getState().rolle).toBe('redaktion');
  });
});
