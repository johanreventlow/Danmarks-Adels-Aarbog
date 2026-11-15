// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
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
  detailProps: null as null | { onVisPraesens?: () => void },
  signIn: vi.fn(),
}));

const smal = vi.hoisted(() => ({ v: false }));
vi.mock('../useSmalSkaerm', () => ({ useSmalSkaerm: () => smal.v }));
vi.mock('../router', () => ({
  navigate: vi.fn(),
  usePath: () => window.location.pathname,
  // Stabilt objekt for samme adresse, som den rigtige router (ellers kører [loc]-effekter ved hver render).
  useLocation: () => {
    const c = locCache;
    if (c.v && c.v.path === window.location.pathname && c.v.search === window.location.search) return c.v;
    c.v = { path: window.location.pathname, search: window.location.search };
    return c.v;
  },
}));
const locCache = vi.hoisted(() => ({ v: null as { path: string; search: string } | null }));
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
  signIn: mocks.signIn,
  loginFejlTekst: () => 'Login lykkedes ikke.',
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
vi.mock('../components/PersonSide', () => ({
  PersonSide: (props: { focusId: string; detail: { bio: string } | null }) => <main>Personside {props.focusId}: {props.detail ? props.detail.bio : 'henter'}</main>,
}));
vi.mock('../components/DetailPanel', () => ({
  DetailPanel: (props: { detail: { bio: string } | null; onVisPraesens?: () => void }) => {
    mocks.detailProps = props;
    return <aside>{props.detail ? `Biografi: ${props.detail.bio}` : 'Henter biografi'}</aside>;
  },
}));

import Folgesvend from '../Folgesvend';
import { navigate } from '../router';

beforeEach(() => {
  vi.clearAllMocks();
  // Panelet i stamtræet (personsiden har egne tests nedenfor).
  window.history.replaceState({}, '', '/slaegt/reventlow/stamtrae?fokus=1');
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
  // Fejlkoden er til udvikleren (konsollen), ikke til læseren.
  expect(alert.textContent).not.toContain('PUBLIC_BIO_SOURCE_V2_UNAVAILABLE');
  expect(screen.queryByText('Biografi: ')).toBeNull();

  // »Prøv igen« henter detaljen på ny.
  const kald = mocks.fetchPersonDetail.mock.calls.length;
  mocks.fetchPersonDetail.mockResolvedValue({ bio: 'Hentet', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
  await screen.findByText('Biografi: Hentet');
  expect(mocks.fetchPersonDetail.mock.calls.length).toBeGreaterThan(kald);
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

test('søgesidens linjeknapper viser kun navngivne linjer, aldrig tekniske nøgler', async () => {
  window.history.replaceState({}, '', '/soeg?q=Test');
  const base = buildModel({ persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }], unions: [], parentChild: [] });
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
  const gruppe = (await screen.findByText('Slægt og linje')).closest('fieldset')!;
  const knapper = [...gruppe.querySelectorAll('button')].map((b) => b.textContent);
  expect(knapper).toEqual(['Hele slægten', 'V. Linje']);
  expect(gruppe.textContent).not.toContain('legacy-source');
});

test('anonym læser får ingen indgang til præsenslisten fra personpanelet', async () => {
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  render(<Folgesvend />);
  await screen.findByText(/^Biografi:/);
  expect(mocks.detailProps?.onVisPraesens).toBeUndefined();
});

test('modellen hentes igen efter login, så RLS-beskyttede personer kommer med', async () => {
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  mocks.signIn.mockResolvedValue({ email: 'red@example.test', role: 'redaktion', userId: 'u1' });
  render(<Folgesvend />);
  await screen.findByText(/^Biografi:/);
  expect(mocks.loadModel).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole('button', { name: 'Log ind' })); // sidehovedets knap
  fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'red@example.test' } });
  fireEvent.change(screen.getByLabelText('Adgangskode'), { target: { value: 'hemmeligt' } });
  fireEvent.submit(screen.getByRole('dialog'));
  await waitFor(() => expect(mocks.loadModel).toHaveBeenCalledTimes(2));
});

test('gammel sti (/stamtrae) erstattes med den nye, og history.state bevares', async () => {
  window.history.replaceState({ prevFocusId: '9' }, '', '/stamtrae');
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  render(<Folgesvend />);
  await waitFor(() => expect(navigate).toHaveBeenCalledWith('/slaegt/reventlow/stamtrae', { replace: true, state: { prevFocusId: '9' } }));
});

test('/slaegtskab?a=<alias> erstattes med det kanoniske id; et ukendt id bliver stående', async () => {
  window.history.replaceState({}, '', '/slaegtskab?a=7&b=999');
  const base = buildModel({ persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }], unions: [], parentChild: [] });
  mocks.loadModel.mockResolvedValue({ ...base, canonicalIdById: { '7': '1' }, loadGeo: () => new Promise(() => {}) });
  render(<Folgesvend />);
  await waitFor(() => expect(navigate).toHaveBeenCalledWith('/slaegtskab?a=1&b=999', expect.objectContaining({ replace: true })));
});

test('/besiddelse/<id>: en fejlet ejer-hentning er en fejl med »Prøv igen«; et ukendt id bliver stående og siges', async () => {
  mocks.fetchEstates.mockResolvedValue([{ id: '1', navn: 'Wittenberg', slags: 'gods', ownerCount: 1 }]);
  mocks.fetchEstateOwners.mockRejectedValue(new Error('netværk'));
  window.history.replaceState({}, '', '/besiddelse/1');
  const { unmount } = render(<Folgesvend />);
  expect((await screen.findByRole('alert')).textContent).toContain('Ejerrækken kunne ikke hentes');
  mocks.fetchEstateOwners.mockResolvedValue([{ personId: '1', periode: '(1606-†)' }]);
  fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
  expect((await screen.findByRole('link', { name: 'Testperson' })).getAttribute('href')).toBe('/person/1');
  expect(screen.getByText('1606-†')).toBeTruthy();
  unmount();
  vi.mocked(navigate).mockClear();
  window.history.replaceState({}, '', '/besiddelse/99999');
  render(<Folgesvend />);
  expect(await screen.findByRole('heading', { name: 'Besiddelsen findes ikke i Aarbogen' })).toBeTruthy();
  expect(navigate).not.toHaveBeenCalledWith('/slaegt/reventlow/besiddelser', expect.anything());
});

test('stamtræet med ?fokus=<id> åbner personpanelet', async () => {
  window.history.replaceState({}, '', '/slaegt/reventlow/stamtrae?fokus=1');
  mocks.fetchPersonDetail.mockResolvedValue({ bio: 'Fra fokus', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  render(<Folgesvend />);
  await screen.findByText('Biografi: Fra fokus');
  expect(mocks.fetchPersonDetail.mock.calls[0][0]).toBe('1');
});

test('slægtsbjælken vises under /slaegt/<slug>, ikke på /person/<id>', async () => {
  mocks.fetchPersonDetail.mockResolvedValue({ bio: 'x', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  window.history.replaceState({}, '', '/slaegt/reventlow/stamtrae?fokus=1');
  const { unmount } = render(<Folgesvend />);
  expect(await screen.findByRole('navigation', { name: 'Slægten Reventlow' })).toBeTruthy();
  unmount();
  window.history.replaceState({}, '', '/person/1');
  render(<Folgesvend />);
  await screen.findByText('Personside 1: x');
  expect(screen.queryByRole('navigation', { name: 'Slægten Reventlow' })).toBeNull();
});

test('/soeg?q= viser resultater, og søgeordet skrives i adressen med replace', async () => {
  window.history.replaceState({}, '', '/soeg?q=Test');
  render(<Folgesvend />);
  // Søgeordet er fremhævet i navnet (<mark>), så navnet findes som linkets navn.
  expect((await screen.findByRole('link', { name: /Testperson/ })).getAttribute('href')).toBe('/person/1');
  const felt = screen.getByLabelText('Søgeord') as HTMLInputElement;
  expect(felt.value).toBe('Test');
  fireEvent.change(felt, { target: { value: 'Testp' } });
  expect(navigate).toHaveBeenCalledWith('/soeg?q=Testp', expect.objectContaining({ replace: true }));
  expect(screen.queryByRole('navigation', { name: 'Slægten Reventlow' })).toBeNull(); // over slægterne
});

test('/person/<id> er personsiden, ikke træet', async () => {
  window.history.replaceState({}, '', '/person/1');
  mocks.fetchPersonDetail.mockResolvedValue({ bio: 'Om testpersonen', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  render(<Folgesvend />);
  expect(await screen.findByText('Personside 1: Om testpersonen')).toBeTruthy();
  expect(screen.queryByText('Stamtræ')).toBeNull(); // TreeView-mocken vises ikke
  expect(screen.getByRole('link', { name: 'Personer' }).getAttribute('aria-current')).toBe('page');
});

test('ukendt person siger det neutralt, ikke træet', async () => {
  window.history.replaceState({}, '', '/person/999');
  render(<Folgesvend />);
  expect(await screen.findByText('Personen kan ikke vises')).toBeTruthy();
  expect(screen.getByText(/vises kun for indloggede/)).toBeTruthy();
});

test('Esc giver fokus til en knap, der stadig findes: Menu → Slægter, skift til bred skærm, Esc → Slægter-knappen', async () => {
  smal.v = true;
  try {
    window.history.replaceState({}, '', '/slaegt/reventlow');
    const { rerender } = render(<Folgesvend />);
    fireEvent.click(await screen.findByRole('button', { name: 'Menu' }));
    fireEvent.click(screen.getByRole('button', { name: /^Slægter/ }));
    expect(screen.getByLabelText('Find slægt')).toBeTruthy();
    smal.v = false;
    rerender(<Folgesvend />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByLabelText('Find slægt')).toBeNull();
    const nav = screen.getByRole('navigation', { name: 'Hovedmenu' });
    expect(document.activeElement).toBe(within(nav).getByRole('button', { name: /Slægter/ }));
  } finally { smal.v = false; }
});

test('»Skift slægt« i slægtsbjælken får fokus tilbage, når vælgeren lukkes med Esc', async () => {
  window.history.replaceState({}, '', '/slaegt/reventlow');
  render(<Folgesvend />);
  const skift = await screen.findByRole('button', { name: 'Skift slægt' });
  fireEvent.click(skift);
  expect(screen.getByLabelText('Find slægt')).toBeTruthy();
  fireEvent.keyDown(document, { key: 'Escape' });
  expect(document.activeElement).toBe(skift);
});

test('fanens titel bærer personens navn på personsiden', async () => {
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  window.history.replaceState({}, '', '/person/1');
  render(<Folgesvend />);
  await waitFor(() => expect(document.title).toBe('Testperson · Danmarks Adels Aarbog'));
});

test('fejler en ny hentning (fx efter login/logout), viser fanen kun værkets navn — ikke navnet fra den gamle model', async () => {
  // Den gamle model beholdes ved fejl (Folgesvend loadData), så titlen må ikke bygges af den, mens fejlskærmen vises.
  mocks.fetchPersonDetail.mockResolvedValue({ bio: '', bioVersions: [], offices: [], estates: [], media: [], sources: [], facts: [], factsError: false, faktaInput: null });
  mocks.signIn.mockResolvedValue({ email: 'red@example.test', role: 'redaktion', userId: 'u1' });
  window.history.replaceState({}, '', '/person/1');
  render(<Folgesvend />);
  await waitFor(() => expect(document.title).toBe('Testperson · Danmarks Adels Aarbog'));
  mocks.loadModel.mockRejectedValue(new Error('netværk'));
  fireEvent.click(screen.getByRole('button', { name: 'Log ind' }));
  fireEvent.change(screen.getByLabelText('E-mail'), { target: { value: 'red@example.test' } });
  fireEvent.change(screen.getByLabelText('Adgangskode'), { target: { value: 'hemmeligt' } });
  fireEvent.submit(screen.getByRole('dialog'));
  await waitFor(() => expect(mocks.loadModel).toHaveBeenCalledTimes(2));
  await waitFor(() => expect(document.title).toBe('Danmarks Adels Aarbog'));
});
