// Review 37 W6: et udfald i rolleopslaget må ikke stille gøre en redaktør til »medlem«.
import { beforeEach, describe, expect, test, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  profil: vi.fn(),
  signInWithPassword: vi.fn(),
  getSession: vi.fn(),
  signOut: vi.fn(),
}));

vi.mock('../supabase', () => ({
  supabase: {
    auth: { signInWithPassword: mocks.signInWithPassword, getSession: mocks.getSession, signOut: mocks.signOut },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => mocks.profil() }) }) }),
  },
}));

import { ROLLE_UDFALD, currentSession, loginFejlTekst, signIn } from '../data/auth';

const bruger = { id: 'u1', email: 'red@example.dk' };

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  mocks.signInWithPassword.mockResolvedValue({ data: { user: bruger }, error: null });
  mocks.getSession.mockResolvedValue({ data: { session: { user: bruger } } });
  mocks.signOut.mockResolvedValue({ error: null });
});

describe('rolleopslag', () => {
  test('redaktion-profil giver redaktion', async () => {
    mocks.profil.mockResolvedValue({ data: { rolle: 'redaktion' }, error: null });
    expect((await signIn('red@example.dk', 'x')).role).toBe('redaktion');
  });

  test('en rigtig, tom profil giver medlem', async () => {
    mocks.profil.mockResolvedValue({ data: null, error: null });
    expect((await signIn('red@example.dk', 'x')).role).toBe('medlem');
  });

  test('en databasefejl degraderer ikke til medlem: login afvises, sessionen lukkes, fejltekst kan vises', async () => {
    mocks.profil.mockResolvedValue({ data: null, error: { message: 'statement timeout' } });
    const fejl = await signIn('red@example.dk', 'x').catch((e) => e);
    expect(fejl).toBeInstanceOf(Error);
    expect((fejl as Error).message).toBe(ROLLE_UDFALD);
    expect(mocks.signOut).toHaveBeenCalled();
    expect(loginFejlTekst(fejl)).toMatch(/rolle/i);
  });

  test('et kastet netværksudfald degraderer heller ikke', async () => {
    mocks.profil.mockRejectedValue(new Error('fetch failed'));
    await expect(signIn('red@example.dk', 'x')).rejects.toThrow(ROLLE_UDFALD);
  });

  test('genskabelse af session ved sideindlæsning: fejl kastes i stedet for medlem', async () => {
    mocks.profil.mockResolvedValue({ data: null, error: { message: 'statement timeout' } });
    await expect(currentSession()).rejects.toThrow(ROLLE_UDFALD);
  });
});
