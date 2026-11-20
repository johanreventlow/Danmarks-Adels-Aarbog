// @vitest-environment jsdom
// Review 37 W5: ved logout ryddes modellen (med redaktørens levende personer) straks, og et sent
// svar fra en tidligere hentning overskriver ikke den nyeste model.
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { buildModel } from '@daa/core';

const mocks = vi.hoisted(() => ({ loadModel: vi.fn(), currentSession: vi.fn(), signOut: vi.fn() }));

vi.mock('../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
    from: () => { throw new Error('ikke i brug'); },
    rpc: () => Promise.resolve({ data: [], error: null }),
  },
}));
vi.mock('../useSmalSkaerm', () => ({ useSmalSkaerm: () => false }));
const locCache = vi.hoisted(() => ({ v: null as { path: string; search: string } | null }));
vi.mock('../router', () => ({
  navigate: vi.fn(),
  usePath: () => window.location.pathname,
  useLocation: () => {
    const c = locCache;
    if (c.v && c.v.path === window.location.pathname && c.v.search === window.location.search) return c.v;
    c.v = { path: window.location.pathname, search: window.location.search };
    return c.v;
  },
}));
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/public', async (importOriginal) => ({
  ...await importOriginal<typeof import('../data/public')>(),
  fetchEstates: async () => [], fetchArms: async () => [], fetchAbout: async () => [],
  fetchEstateInfo: async () => ({ narrativ: '', sted: '', media: [] }),
  fetchEstateOwners: async () => [],
  fetchPersonDetail: async () => ({ bio: '', offices: [] }),
}));
vi.mock('../data/media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => new Map() }));
vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession, signIn: vi.fn(), loginFejlTekst: () => 'x', signOut: mocks.signOut,
}));
vi.mock('../data/bookmarks', () => ({
  useBookmarks: () => ({ canSave: false, ready: true, hydrationVersion: 1, ids: new Set<string>(), has: () => false, toggle: vi.fn() }),
}));
vi.mock('../components/TreeView', () => ({
  TreeView: (props: { model: { persons: { name: string }[] } | null }) => <div>{'Stamtræ: ' + (props.model?.persons ?? []).map((p) => p.name).join(',')}</div>,
}));
vi.mock('../components/DetailPanel', () => ({ DetailPanel: () => <aside>panel</aside> }));

import Folgesvend from '../Folgesvend';

const model = (navn: string) => ({
  ...buildModel({
    persons: [{ id: '1', name: navn, born: null, died: null, years: '', title: '', bio: '', privat: false }],
    unions: [], parentChild: [],
  }),
  loadGeo: () => new Promise(() => {}),
});

function udsat<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

beforeEach(() => {
  vi.clearAllMocks();
  locCache.v = null;
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  window.history.replaceState({}, '', '/slaegt/reventlow/stamtrae?fokus=1');
  mocks.currentSession.mockResolvedValue({ email: 'red@example.dk', role: 'redaktion', userId: 'u1' });
  mocks.signOut.mockResolvedValue(undefined);
});

test('logout rydder den indlæste model med levende personer, før den offentlige model er hentet', async () => {
  const offentlig = udsat<unknown>();
  mocks.loadModel.mockResolvedValueOnce(model('Levende Lars')).mockReturnValueOnce(offentlig.promise);
  render(<Folgesvend />);
  expect(await screen.findByText(/Levende Lars/)).toBeTruthy();
  fireEvent.click(await screen.findByRole('button', { name: 'Log ud' }));
  await waitFor(() => expect(mocks.loadModel).toHaveBeenCalledTimes(2));
  expect(screen.queryByText(/Levende Lars/)).toBeNull();
  await act(async () => { offentlig.resolve(model('Afdød Anna')); });
  expect(await screen.findByText(/Afdød Anna/)).toBeTruthy();
});

test('et sent svar fra den tidligere (redaktør-)hentning overskriver ikke den nyeste model', async () => {
  const gammel = udsat<unknown>();
  mocks.loadModel.mockReturnValueOnce(gammel.promise).mockResolvedValueOnce(model('Afdød Anna'));
  render(<Folgesvend />);
  await waitFor(() => expect(mocks.currentSession).toHaveBeenCalled());
  fireEvent.click(await screen.findByRole('button', { name: 'Log ud' }));
  expect(await screen.findByText(/Afdød Anna/)).toBeTruthy();
  await act(async () => { gammel.resolve(model('Levende Lars')); });
  expect(screen.queryByText(/Levende Lars/)).toBeNull();
  expect(screen.getByText(/Afdød Anna/)).toBeTruthy();
});
