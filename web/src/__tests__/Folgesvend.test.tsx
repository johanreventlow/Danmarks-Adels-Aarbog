// @vitest-environment jsdom
import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { buildModel } from '@daa/core';

const mocks = vi.hoisted(() => ({
  loadModel: vi.fn(),
  fetchPersonDetail: vi.fn(),
  fetchEstates: vi.fn(),
  fetchArms: vi.fn(),
  fetchAbout: vi.fn(),
  fetchEstateInfo: vi.fn(),
  fetchEstateOwners: vi.fn(),
}));

vi.mock('../router', () => ({
  navigate: vi.fn(),
  usePath: () => window.location.pathname,
}));
vi.mock('../data/model', () => ({ loadModel: mocks.loadModel }));
vi.mock('../data/public', async (importOriginal) => ({
  ...await importOriginal<typeof import('../data/public')>(),
  fetchPersonDetail: mocks.fetchPersonDetail,
  fetchEstates: mocks.fetchEstates,
  fetchArms: mocks.fetchArms,
  fetchAbout: mocks.fetchAbout,
  fetchEstateInfo: mocks.fetchEstateInfo,
  fetchEstateOwners: mocks.fetchEstateOwners,
}));
vi.mock('../data/auth', () => ({
  currentSession: () => Promise.resolve(null),
  signIn: vi.fn(),
  signOut: vi.fn(),
}));
vi.mock('../data/bookmarks', () => ({
  useBookmarks: () => ({
    canSave: false,
    ready: true,
    hydrationVersion: 1,
    ids: new Set<string>(),
    has: () => false,
    toggle: vi.fn(),
  }),
}));
vi.mock('../components/TreeView', () => ({ TreeView: () => <div>Stamtræ</div> }));
vi.mock('../components/DetailPanel', () => ({
  DetailPanel: ({ detail }: { detail: { bio: string } | null }) => <aside>{detail ? `Biografi: ${detail.bio}` : 'Henter biografi'}</aside>,
}));

import Folgesvend from '../Folgesvend';

beforeEach(() => {
  vi.clearAllMocks();
  window.history.replaceState({}, '', '/person/1');
  const base = buildModel({
    persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }],
    unions: [],
    parentChild: [],
  });
  mocks.loadModel.mockResolvedValue({ ...base, loadGeo: () => new Promise(() => {}) });
  mocks.fetchEstates.mockResolvedValue([]);
  mocks.fetchArms.mockResolvedValue([]);
  mocks.fetchAbout.mockResolvedValue([]);
  mocks.fetchEstateInfo.mockResolvedValue({ narrativ: '', sted: '', media: [] });
  mocks.fetchEstateOwners.mockResolvedValue([]);
});

test('viser personens biografi-fejl eksplicit i stedet for en gyldig tom detalje', async () => {
  mocks.fetchPersonDetail.mockRejectedValue(new Error('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE'));

  render(<Folgesvend />);

  await waitFor(() => expect(mocks.fetchPersonDetail).toHaveBeenCalledTimes(2));
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toContain('Kunne ikke hente personens biografi');
  expect(alert.textContent).toContain('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
  expect(screen.queryByText('Biografi: ')).toBeNull();
});
