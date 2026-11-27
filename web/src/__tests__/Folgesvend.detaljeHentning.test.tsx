// @vitest-environment jsdom
// Review 36 P1: persondetaljen (og en besiddelses ejerrække) hentes ÉN gang ved et dybt link — ikke før modellen
// findes, når den lander og igen, når den lazy geo-kæde laver et nyt model-objekt.
import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { buildModel } from '@daa/core';

// Geo-svaret bærer et mærke, så testen ser forskel på modellens tomme start-geo og det landede svar.
const GEO_MAERKE = 'geo-svar';
const mocks = vi.hoisted(() => ({
  loadModel: vi.fn(),
  fetchPersonDetail: vi.fn(),
  fetchEstates: vi.fn(),
  fetchArms: vi.fn(),
  fetchAbout: vi.fn(),
  fetchEstateInfo: vi.fn(),
  fetchEstateOwners: vi.fn(),
  currentSession: vi.fn(),
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
  fetchPersonDetail: mocks.fetchPersonDetail,
  fetchEstates: mocks.fetchEstates,
  fetchArms: mocks.fetchArms,
  fetchAbout: mocks.fetchAbout,
  fetchEstateInfo: mocks.fetchEstateInfo,
  fetchEstateOwners: mocks.fetchEstateOwners,
}));
vi.mock('../data/auth', () => ({
  currentSession: mocks.currentSession,
  signIn: vi.fn(), onAuthChange: () => () => {},
  loginFejlTekst: () => 'Login lykkedes ikke.',
  signOut: vi.fn(),
}));
vi.mock('../data/bookmarks', () => ({
  useBookmarks: () => ({
    canSave: false, ready: true, hydrationVersion: 1, ids: new Set<string>(), has: () => false, toggle: vi.fn(),
  }),
}));
// Personsiden viser, om modellen har fået geo — beviset for, at geo-kæden faktisk er landet i testen.
// Hver render noteres (focusId + detaljens bio), så testen kan se, om en anden persons detalje nåede siden.
const personSideRenders = vi.hoisted(() => [] as { focusId: string; bio: string | null }[]);
vi.mock('../components/PersonSide', () => ({
  PersonSide: (props: { focusId: string; model: { geo?: { maerke?: string } }; detail: { bio: string } | null }) => (
    personSideRenders.push({ focusId: props.focusId, bio: props.detail?.bio ?? null }),
    <main>Personside {props.focusId}: {props.detail ? props.detail.bio : 'henter'} · {props.model.geo?.maerke === GEO_MAERKE ? 'geo landet' : 'uden geo'}</main>
  ),
}));
vi.mock('../components/EstatesView', () => ({
  EstatesView: (props: { ejere: { status: string }; geo?: { maerke?: string } }) => <main>Besiddelse: ejere {props.ejere.status} · {props.geo?.maerke === GEO_MAERKE ? 'geo landet' : 'uden geo'}</main>,
}));

import Folgesvend from '../Folgesvend';

function udskudt<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

const DETALJE = { bio: 'Hentet', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null };
// Foldet person (samme_som): '1' har medlemmerne '1' og '7' — kun modellen ved det.
function lavModel() {
  const base = buildModel({
    persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }],
    unions: [],
    parentChild: [],
  });
  return {
    ...base,
    byId: { ...base.byId, '1': { ...base.byId['1'], mergedFrom: [{ personId: '1', linje: null, nr: null, nr_label: null }, { personId: '7', linje: null, nr: null, nr_label: null }] } },
    sourcesBy: { '1': [{ ref: 'Linje I, nr. 1', work: 'DAA 1939' }] },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  personSideRenders.length = 0;
  locCache.v = null;
  mocks.currentSession.mockResolvedValue(null);
  mocks.fetchPersonDetail.mockResolvedValue(DETALJE);
  mocks.fetchEstates.mockResolvedValue([{ id: '1', navn: 'Wittenberg', slags: 'gods', ownerCount: 1 }]);
  mocks.fetchArms.mockResolvedValue([]);
  mocks.fetchAbout.mockResolvedValue([]);
  mocks.fetchEstateInfo.mockResolvedValue({ narrativ: '', sted: '', media: [] });
  mocks.fetchEstateOwners.mockResolvedValue([]);
});

test('dybt link /person/<id>: detaljen hentes præcis én gang gennem model=null → model lander → geo lander', async () => {
  window.history.replaceState({}, '', '/person/1');
  const modelSvar = udskudt<unknown>();
  const geoSvar = udskudt<unknown>();
  mocks.loadModel.mockReturnValue(modelSvar.promise);
  render(<Folgesvend />);

  // Før modellen findes, hentes intet (medlems-id'er og bog-nummer kendes ikke endnu).
  await waitFor(() => expect(mocks.loadModel).toHaveBeenCalledTimes(1));
  expect(mocks.fetchPersonDetail).not.toHaveBeenCalled();

  modelSvar.resolve({ ...lavModel(), loadGeo: () => geoSvar.promise });
  await screen.findByText(/Personside 1: Hentet · uden geo/);
  expect(mocks.fetchPersonDetail).toHaveBeenCalledTimes(1);
  // Hentet med modellens viden: begge medlems-id'er, og ingen kildeopslag (personen har et bog-nummer).
  const [id, members, hentKilder, , redaktoer] = mocks.fetchPersonDetail.mock.calls[0];
  expect(id).toBe('1');
  expect(members).toEqual(['1', '7']);
  expect(hentKilder).toBe(false);
  expect(redaktoer).toBe(false);

  geoSvar.resolve({ placesById: {}, factsByPerson: {}, maerke: GEO_MAERKE });
  await screen.findByText(/geo landet/);
  expect(mocks.fetchPersonDetail).toHaveBeenCalledTimes(1);
});

test('et rolleskift (gendannet redaktør-session) henter detaljen igen — med kladder', async () => {
  window.history.replaceState({}, '', '/person/1');
  const sessionSvar = udskudt<unknown>();
  mocks.currentSession.mockReturnValue(sessionSvar.promise);
  mocks.loadModel.mockResolvedValue({ ...lavModel(), loadGeo: () => new Promise(() => {}) });
  render(<Folgesvend />);
  await screen.findByText(/Personside 1: Hentet/);
  expect(mocks.fetchPersonDetail).toHaveBeenCalledTimes(1);
  expect(mocks.fetchPersonDetail.mock.calls[0][4]).toBe(false);

  sessionSvar.resolve({ email: 'r@x', role: 'redaktion', userId: 'u1' });
  await waitFor(() => expect(mocks.fetchPersonDetail).toHaveBeenCalledTimes(2));
  expect(mocks.fetchPersonDetail.mock.calls[1][4]).toBe(true);
});

test('dybt link /besiddelse/<id>: ejerrækken hentes præcis én gang gennem model=null → model lander → geo lander', async () => {
  window.history.replaceState({}, '', '/besiddelse/1');
  const modelSvar = udskudt<unknown>();
  const geoSvar = udskudt<unknown>();
  let geoBedt = false;
  mocks.loadModel.mockReturnValue(modelSvar.promise);
  render(<Folgesvend />);
  await waitFor(() => expect(mocks.loadModel).toHaveBeenCalledTimes(1));
  expect(mocks.fetchEstateOwners).not.toHaveBeenCalled();

  modelSvar.resolve({ ...lavModel(), loadGeo: () => { geoBedt = true; return geoSvar.promise; } });
  await screen.findByText('Besiddelse: ejere ok · uden geo');
  expect(mocks.fetchEstateOwners).toHaveBeenCalledTimes(1);
  expect(geoBedt).toBe(true);

  geoSvar.resolve({ placesById: {}, factsByPerson: {}, maerke: GEO_MAERKE });
  await screen.findByText('Besiddelse: ejere ok · geo landet');
  expect(mocks.fetchEstateOwners).toHaveBeenCalledTimes(1);
});

test('personskift: den forrige persons detalje når aldrig den nye persons side (heller ikke i én render)', async () => {
  window.history.replaceState({}, '', '/person/1');
  const base = buildModel({
    persons: [
      { id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false },
      { id: '2', name: 'Anden person', born: null, died: 1900, years: '', title: '', bio: '', privat: false },
    ],
    unions: [],
    parentChild: [],
  });
  mocks.loadModel.mockResolvedValue({ ...base, loadGeo: () => new Promise(() => {}) });
  const { rerender } = render(<Folgesvend />);
  await screen.findByText(/Personside 1: Hentet/);
  // Person 2's detalje kommer aldrig: siden må vise »henter«, ikke person 1's detalje.
  mocks.fetchPersonDetail.mockReturnValue(new Promise(() => {}));
  window.history.replaceState({}, '', '/person/2');
  rerender(<Folgesvend />);
  await screen.findByText(/Personside 2: henter/);
  const forkerte = personSideRenders.filter((r) => r.focusId === '2' && r.bio !== null);
  expect(forkerte).toEqual([]);
});
