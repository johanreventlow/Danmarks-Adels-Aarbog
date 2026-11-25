const mockMaybeSingle = jest.fn();
const mockSignInPw = jest.fn();
const mockSignOutSb = jest.fn();
jest.mock('../supabase', () => ({ supabase: {
  from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => mockMaybeSingle() }) }) }),
  auth: { signInWithPassword: (...a: unknown[]) => mockSignInPw(...a), signOut: () => mockSignOutSb() },
} }));

import { fetchProfile, mapProfileRow, ROLLE_UDFALD, signIn } from '../auth';

describe('mapProfileRow', () => {
  it('defaulter til medlem når row mangler', () => {
    expect(mapProfileRow(null)).toEqual({ rolle: 'medlem', reventlowPersonId: null });
  });
  it('mapper redaktion-row', () => {
    expect(mapProfileRow({ rolle: 'redaktion', reventlow_person_id: 42 }))
      .toEqual({ rolle: 'redaktion', reventlowPersonId: '42' });
  });
  it('ukendt rolle falder til medlem', () => {
    expect(mapProfileRow({ rolle: 'noget', reventlow_person_id: null }).rolle).toBe('medlem');
  });
});

describe('fetchProfile / signIn — fejlet rolleopslag (review 37 W6)', () => {
  beforeEach(() => {
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    mockMaybeSingle.mockReset(); mockSignInPw.mockReset(); mockSignOutSb.mockReset();
    mockSignOutSb.mockResolvedValue({});
  });
  afterEach(() => jest.restoreAllMocks());

  it('ingen profilrække er legitimt medlem', async () => {
    mockMaybeSingle.mockResolvedValue({ data: null, error: null });
    await expect(fetchProfile('u1')).resolves.toEqual({ rolle: 'medlem', reventlowPersonId: null });
  });
  it('forespørgselsfejl kastes i stedet for at give medlem', async () => {
    mockMaybeSingle.mockResolvedValue({ data: null, error: { message: 'timeout' } });
    await expect(fetchProfile('u1')).rejects.toThrow(ROLLE_UDFALD);
  });
  it('netværksfejl (kastet) bliver også til rolle-fejl', async () => {
    mockMaybeSingle.mockRejectedValue(new Error('offline'));
    await expect(fetchProfile('u1')).rejects.toThrow(ROLLE_UDFALD);
  });
  it('signIn logger ud og kaster når rollen ikke kan hentes', async () => {
    mockSignInPw.mockResolvedValue({ data: { user: { id: 'u1' } }, error: null });
    mockMaybeSingle.mockResolvedValue({ data: null, error: { message: 'x' } });
    await expect(signIn('a@b.dk', 'pw')).rejects.toThrow(ROLLE_UDFALD);
    expect(mockSignOutSb).toHaveBeenCalledTimes(1);
  });
  it('signIn lykkes med rolle', async () => {
    mockSignInPw.mockResolvedValue({ data: { user: { id: 'u1' } }, error: null });
    mockMaybeSingle.mockResolvedValue({ data: { rolle: 'redaktion', reventlow_person_id: 3 }, error: null });
    await expect(signIn('a@b.dk', 'pw')).resolves.toEqual({ userId: 'u1', rolle: 'redaktion', reventlowPersonId: '3' });
    expect(mockSignOutSb).not.toHaveBeenCalled();
  });
});
