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
  treeSearch: null as null | { linjeList: { linje: string; navn: string | null }[] },
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
vi.mock('../components/TreeView', () => ({
  TreeView: ({ search }: { search: { linjeList: { linje: string; navn: string | null }[] } }) => {
    mocks.treeSearch = search;
    return <div>Stamtræ</div>;
  },
}));
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

test('søgefladens linjechips får aldrig tekniske linjenøgler (legacy-source:)', async () => {
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  const base = buildModel({
    persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }],
    unions: [],
    parentChild: [],
  });
  mocks.loadModel.mockResolvedValue({
    ...base,
    lineage: {
      byPerson: { '1': ['legacy-source:3:II', 'slaegt:1:lineage:5:scheme:canonical'] },
      navn: { 'slaegt:1:lineage:5:scheme:canonical': 'V. Linje' },
      list: [
        { linje: 'legacy-source:3:II', count: 1, headId: '1', navn: null },
        { linje: 'slaegt:1:lineage:5:scheme:canonical', count: 1, headId: '1', navn: 'V. Linje' },
      ],
    },
    loadGeo: () => new Promise(() => {}),
  });

  render(<Folgesvend />);

  await waitFor(() => expect(mocks.treeSearch?.linjeList.length).toBeGreaterThan(0));
  expect(mocks.treeSearch!.linjeList.map((l) => l.linje)).toEqual(['slaegt:1:lineage:5:scheme:canonical']);
});
