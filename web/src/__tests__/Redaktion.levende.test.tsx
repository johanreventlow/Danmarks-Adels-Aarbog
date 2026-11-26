// @vitest-environment jsdom
// Review 37 R37P11-2 (review-fund): personlisten hentes kun én gang, så knapperne »Levende« og »Privat« skal opdateres
// efter en direkte ændring. Ellers viste knappen den gamle tilstand og tilbød samme retning igen (tomt ændringssæt).
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import type { RedSession } from '../data/auth';

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
}));
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/redaktionWrite', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../data/redaktionWrite')>()),
  submitChange: mocks.submitChange,
}));

import Redaktion from '../Redaktion';

const session = (role: string): RedSession => ({ email: 'red@example.dk', role, userId: 'u1' });

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.history.pushState(null, '', '/redaktion/person/1559');
  mocks.currentSession.mockResolvedValue(session('redaktion'));
  mocks.fetchRedaktionPersoner.mockResolvedValue([
    { id: '1559', navn: 'Sophie von Sperling', aar: '', born: null, levende: true, privat: false, efternavnAfledt: false },
  ]);
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
  mocks.submitChange.mockImplementation(async (_c: unknown, o: { dryRun: boolean }) => (
    o.dryRun ? { dryRun: true, call: { fn: 'red_set_levende', args: {} }, direkte: true }
      : { dryRun: false, call: { fn: 'red_set_levende', args: {} }, direkte: true, result: null }));
});

test('efter »Ja, sæt som afdød« i LIVE viser knappen afdød og tilbyder kun levende-retningen', async () => {
  render(<Redaktion />);
  const knap = await screen.findByRole('button', { name: 'Levende' });
  expect(knap.getAttribute('aria-pressed')).toBe('true');
  fireEvent.click(screen.getByText('Dry-run · skriver ikke'));
  fireEvent.click(knap);
  fireEvent.click(screen.getByRole('button', { name: 'Ja, sæt som afdød' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Levende' }).getAttribute('aria-pressed')).toBe('false'));
  expect(mocks.submitChange.mock.calls[0][0]).toMatchObject({ art: 'setLevende', payload: { levende: false } });
  // Næste klik går den anden vej (skjul) uden advarsel.
  fireEvent.click(screen.getByRole('button', { name: 'Levende' }));
  expect(screen.queryByRole('alertdialog')).toBeNull();
  await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(2));
  expect(mocks.submitChange.mock.calls[1][0]).toMatchObject({ art: 'setLevende', payload: { levende: true } });
});

test('i dry-run ændres knappens tilstand ikke', async () => {
  render(<Redaktion />);
  fireEvent.click(await screen.findByRole('button', { name: 'Levende' }));
  fireEvent.click(screen.getByRole('button', { name: 'Ja, sæt som afdød' }));
  await waitFor(() => expect(mocks.submitChange).toHaveBeenCalledTimes(1));
  expect(screen.getByRole('button', { name: 'Levende' }).getAttribute('aria-pressed')).toBe('true');
});
