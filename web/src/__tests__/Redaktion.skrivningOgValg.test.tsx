// @vitest-environment jsdom
// Review 37 W1/W2/W3: skrivning, historik og slægts/linje-editor på tværs af valg.
//  W1: en afsluttet skrivning for person A genindlæser ikke A under B's navn.
//  W2: A's historik (og »Fortryd«) vises ikke under B.
//  W3: slægt/linje-editoren viser ikke en tidligere linjes udkast; en fejlet hentning er en fejl.
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
  fetchLineages: vi.fn(),
  fetchHistorik: vi.fn(),
  loadModel: vi.fn(),
  submitChange: vi.fn(),
}));

// Udbakken hentes ved mount for redaktion; uden mock rammer den et rigtigt netværkskald (ustabil under belastning).
vi.mock('../data/personPurge', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/personPurge')>()),
  fetchPurgeUdbakke: vi.fn().mockResolvedValue([]),
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
  fetchLineages: mocks.fetchLineages,
}));
vi.mock('../data/historik', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/historik')>()),
  fetchHistorik: mocks.fetchHistorik,
}));
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/redaktionWrite', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionWrite')>()),
  submitChange: mocks.submitChange,
}));

import Redaktion from '../Redaktion';

const session = (role: string): RedSession => ({ email: 'red@example.dk', role, userId: 'u1' });
const person = (id: string, navn: string) => ({ id, navn, aar: '', born: null, levende: false, privat: false, efternavnAfledt: false });

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
  mocks.fetchLineages.mockResolvedValue([{ id: 10, source_id: 1, kode: 'A', navn: 'Linje-A', udenforMatchning: false }, { id: 11, source_id: 1, kode: 'B', navn: 'Linje-B', udenforMatchning: false }]);
  mocks.fetchHistorik.mockResolvedValue([]);
  mocks.loadModel.mockResolvedValue(null);
  mocks.submitChange.mockResolvedValue({ dryRun: false, call: { fn: 'x', args: {} }, direkte: true });
});


const narr = (tekst: string) => [{ id: 1, sourceId: 1, side: null, tekst, privat: false, udgave: null, sourceTitel: 'K' }];
const post = (id: string, resume: string) => ({ id, hvem: 'x', hvornaar: 'nu', resume, reverteret: false, erFortryd: false, undoKind: 'change_set' as const, canReverse: true });

describe('W1 — skrivning afsluttes efter personskift', () => {
  test('A\'s skrivning genindlæser ikke A, når B er valgt; B\'s data står urørt', async () => {
    const skriv = udsat<unknown>();
    mocks.submitChange.mockReturnValue(skriv.promise);
    render(<Redaktion />);
    fireEvent.click(await screen.findByText('Dry-run · skriver ikke'));
    fireEvent.click(await screen.findByText('Markér'));
    await waitFor(() => expect(mocks.submitChange).toHaveBeenCalled());
    const evidensForA = mocks.fetchPersonEvidence.mock.calls.filter((c) => c[0] === '1').length;

    act(() => navigate('/redaktion/person/2'));
    await waitFor(() => expect(mocks.fetchPersonEvidence).toHaveBeenCalledWith('2'));
    const evidensForB = mocks.fetchPersonEvidence.mock.calls.filter((c) => c[0] === '2').length;

    await act(async () => { skriv.resolve({ dryRun: false, call: { fn: 'x', args: {} }, direkte: true }); });
    await new Promise((r) => setTimeout(r, 50));
    expect(mocks.fetchPersonEvidence.mock.calls.filter((c) => c[0] === '1').length).toBe(evidensForA);
    expect(mocks.fetchPersonEvidence.mock.calls.filter((c) => c[0] === '2').length).toBe(evidensForB);
  });
});

describe('W2 — historik på tværs af personer', () => {
  test('et sent historiksvar for A vises ikke under B', async () => {
    const a = udsat<ReturnType<typeof post>[]>();
    const b = udsat<ReturnType<typeof post>[]>();
    mocks.fetchHistorik.mockImplementation((id: string) => (id === '1' ? a.promise : b.promise));
    render(<Redaktion />);
    await waitFor(() => expect(mocks.fetchHistorik).toHaveBeenCalledWith('1'));
    act(() => navigate('/redaktion/person/2'));
    await waitFor(() => expect(mocks.fetchHistorik).toHaveBeenCalledWith('2'));
    await act(async () => { b.resolve([post('20', 'Hist-B')]); });
    expect(await screen.findByText('Hist-B')).toBeTruthy();
    await act(async () => { a.resolve([post('10', 'Hist-A')]); });
    expect(screen.queryByText('Hist-A')).toBeNull();
    expect(screen.getByText('Hist-B')).toBeTruthy();
  });
});

describe('W3 — slægt/linje-editoren', () => {
  test('et sent narrativsvar for linje A lander ikke i udkastet for linje B', async () => {
    const a = udsat<ReturnType<typeof narr>>();
    const b = udsat<ReturnType<typeof narr>>();
    mocks.fetchNarrativer.mockImplementation((_t: string, id: number) => (id === 10 ? a.promise : b.promise));
    window.history.pushState(null, '', '/redaktion/slaegt/10');
    render(<Redaktion />);
    await waitFor(() => expect(mocks.fetchNarrativer).toHaveBeenCalledWith('lineage', 10));
    act(() => navigate('/redaktion/slaegt/11'));
    await waitFor(() => expect(mocks.fetchNarrativer).toHaveBeenCalledWith('lineage', 11));
    await act(async () => { b.resolve(narr('Tekst-B')); });
    expect(await screen.findByDisplayValue('Tekst-B')).toBeTruthy();
    await act(async () => { a.resolve(narr('Tekst-A')); });
    expect(screen.queryByDisplayValue('Tekst-A')).toBeNull();
    expect(screen.getByDisplayValue('Tekst-B')).toBeTruthy();
  });

  test('en fejlet hentning vises som fejl, ikke som tomt udkast', async () => {
    mocks.fetchNarrativer.mockRejectedValue(new Error('permission denied for table narrative'));
    window.history.pushState(null, '', '/redaktion/slaegt/10');
    render(<Redaktion />);
    expect(await screen.findByText(/Narrativet kunne ikke hentes/)).toBeTruthy();
    expect(screen.queryByPlaceholderText(/./)).toBeNull;
  });
});
