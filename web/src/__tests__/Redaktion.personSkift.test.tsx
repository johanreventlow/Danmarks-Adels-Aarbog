// @vitest-environment jsdom
// W1/W2/W3: personskift i redaktionen.
//  1. Et sent svar for person A må ikke overskrive B's visning (request-generation i loadPerson).
//  2. At model lander efter personlisten må IKKE genhente hele pakken (loadPerson er uafhængig af model).
//  3. En læsefejl i relationer/familie meldes (loadErr) i stedet for at blive til tom state.
//  4. Forældre-ukendt genindlæses først når skrivningen er afsluttet (ingen 700 ms-timer).
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type { RedSession } from '../data/auth';
import { navigate } from '../router';

const mocks = vi.hoisted(() => ({
  currentSession: vi.fn(),
  fetchRedaktionPersoner: vi.fn(),
  fetchSources: vi.fn(),
  fetchPersonEvidence: vi.fn(),
  fetchHaendelserForPerson: vi.fn(),
  fetchStoriesForPerson: vi.fn(),
  fetchNarrativer: vi.fn(),
  fetchPersonFamilie: vi.fn(),
  fetchPersonRelationer: vi.fn(),
  fetchSammeSomLinks: vi.fn(),
  fetchRedPersonMedia: vi.fn(),
  fetchForaeldreUkendtMarkering: vi.fn(),
  fetchForaeldreSlot: vi.fn(),
  fetchBarnFamilie: vi.fn(),
  loadModel: vi.fn(),
  submitChange: vi.fn(),
}));

vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession, signIn: vi.fn(), signOut: vi.fn(),
}));
vi.mock('../data/redaktionRead', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionRead')>()),
  fetchRedaktionPersoner: mocks.fetchRedaktionPersoner,
  fetchSources: mocks.fetchSources,
  fetchPersonEvidence: mocks.fetchPersonEvidence,
  fetchHaendelserForPerson: mocks.fetchHaendelserForPerson,
  fetchStoriesForPerson: mocks.fetchStoriesForPerson,
  fetchNarrativer: mocks.fetchNarrativer,
  fetchPersonFamilie: mocks.fetchPersonFamilie,
  fetchPersonRelationer: mocks.fetchPersonRelationer,
  fetchSammeSomLinks: mocks.fetchSammeSomLinks,
  fetchRedPersonMedia: mocks.fetchRedPersonMedia,
  fetchForaeldreUkendtMarkering: mocks.fetchForaeldreUkendtMarkering,
  fetchForaeldreSlot: mocks.fetchForaeldreSlot,
  fetchBarnFamilie: mocks.fetchBarnFamilie,
}));
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/redaktionWrite', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionWrite')>()),
  submitChange: mocks.submitChange,
}));

import Redaktion from '../Redaktion';

const session = (role: string): RedSession => ({ email: 'red@example.dk', role, userId: 'u1' });
const person = (id: string, navn: string) => ({ id, navn, aar: '', born: null, levende: false, privat: false, efternavnAfledt: false });
const hverv = (navn: string) => [{ relationId: 1, art: 'hverv', objektType: 'organisation', objektId: '9', navn, rolle: '', periode: '' }];

function udsat<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.history.pushState(null, '', '/redaktion/person/1');
  mocks.currentSession.mockResolvedValue(session('redaktion'));
  mocks.fetchRedaktionPersoner.mockResolvedValue([person('1', 'Anna A'), person('2', 'Bent B')]);
  mocks.fetchSources.mockResolvedValue([]);
  mocks.fetchPersonEvidence.mockResolvedValue({ felter: {}, koen: null });
  mocks.fetchHaendelserForPerson.mockResolvedValue([]);
  mocks.fetchStoriesForPerson.mockResolvedValue([]);
  mocks.fetchNarrativer.mockResolvedValue([]);
  mocks.fetchPersonFamilie.mockResolvedValue({ somPartner: [], somBarn: [] });
  mocks.fetchPersonRelationer.mockResolvedValue([]);
  mocks.fetchSammeSomLinks.mockResolvedValue([]);
  mocks.fetchRedPersonMedia.mockResolvedValue([]);
  mocks.fetchForaeldreUkendtMarkering.mockResolvedValue(null);
  mocks.fetchForaeldreSlot.mockResolvedValue(null);
  mocks.fetchBarnFamilie.mockResolvedValue(null);
  mocks.loadModel.mockResolvedValue(null);
  mocks.submitChange.mockResolvedValue({ dryRun: false, call: { fn: 'x', args: {} }, direkte: true });
});

describe('Redaktion — personskift', () => {
  test('A vælges, så B; A svarer sidst → B\'s data står', async () => {
    const a = udsat<ReturnType<typeof hverv>>();
    const b = udsat<ReturnType<typeof hverv>>();
    mocks.fetchPersonRelationer.mockImplementation((id: string) => (id === '1' ? a.promise : b.promise));
    render(<Redaktion />);
    await waitFor(() => expect(mocks.fetchPersonRelationer).toHaveBeenCalledWith('1'));
    act(() => navigate('/redaktion/person/2'));
    await waitFor(() => expect(mocks.fetchPersonRelationer).toHaveBeenCalledWith('2'));

    await act(async () => { b.resolve(hverv('Hverv-B')); });
    expect(await screen.findByText('Hverv-B')).toBeTruthy();
    await act(async () => { a.resolve(hverv('Hverv-A')); });
    expect(screen.queryByText('Hverv-A')).toBeNull();
    expect(screen.getByText('Hverv-B')).toBeTruthy();
  });

  test('model der lander efter personen genhenter kun familien, ikke hele pakken', async () => {
    const m = udsat<unknown>();
    mocks.loadModel.mockReturnValue(m.promise);
    render(<Redaktion />);
    await waitFor(() => expect(mocks.fetchPersonRelationer).toHaveBeenCalledTimes(1));
    await act(async () => { m.resolve({ byId: {}, byExt: {} }); });
    await waitFor(() => expect(mocks.fetchPersonFamilie).toHaveBeenCalledTimes(2));
    expect(mocks.fetchPersonEvidence).toHaveBeenCalledTimes(1);
    expect(mocks.fetchPersonRelationer).toHaveBeenCalledTimes(1);
    expect(mocks.fetchSammeSomLinks).toHaveBeenCalledTimes(1);
  });

  test('en læsefejl i relationer meldes i stedet for at blive "ingen data"', async () => {
    mocks.fetchPersonRelationer.mockRejectedValue(new Error('permission denied for table relation'));
    render(<Redaktion />);
    expect(await screen.findByText(/permission denied for table relation/)).toBeTruthy();
  });
});

describe('Redaktion — forældre-ukendt genindlæses efter skrivningen', () => {
  test('ingen genhentning før submitChange er færdig', async () => {
    mocks.fetchForaeldreUkendtMarkering.mockResolvedValue(null);
    const skriv = udsat<unknown>();
    mocks.submitChange.mockReturnValue(skriv.promise);
    render(<Redaktion />);
    // Prøvekørsel er default; slå den fra så run() reelt venter på skrivningen.
    fireEvent.click(await screen.findByText('Dry-run · skriver ikke'));
    const knap = await screen.findByText('Markér');
    const foer = mocks.fetchForaeldreUkendtMarkering.mock.calls.length;
    fireEvent.click(knap);
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalled());
    await new Promise((r) => setTimeout(r, 900)); // længere end den gamle 700 ms-timer
    expect(mocks.fetchForaeldreUkendtMarkering.mock.calls.length).toBe(foer);
    await act(async () => { skriv.resolve({ dryRun: false, call: { fn: 'x', args: {} }, direkte: true }); });
    await waitFor(() => expect(mocks.fetchForaeldreUkendtMarkering.mock.calls.length).toBe(foer + 1));
  });
});
