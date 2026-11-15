// @vitest-environment jsdom
// Review 36 K4 (læserdelen), hele vejen: en databasefejl i den RIGTIGE fetchPersonDetail (kun supabase er mocket)
// når personpanelets fejl-tilstand med »Prøv igen« — ikke en tom biografi uden fejl.
import { fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, expect, test, vi } from 'vitest';
import { buildModel } from '@daa/core';

const mocks = vi.hoisted(() => ({
  loadModel: vi.fn(),
  relationFejler: true,
}));

function table(name: string) {
  const svar = () => (name === 'relation' && mocks.relationFejler
    ? { data: null, error: { message: 'canceling statement due to statement timeout', code: '57014' } }
    : { data: [], error: null });
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'is', 'in', 'order', 'limit']) q[m] = () => q;
  q.range = async () => svar();
  q.maybeSingle = async () => svar();
  q.then = (ok: (v: unknown) => unknown, ko: (e: unknown) => unknown) => Promise.resolve(svar()).then(ok, ko);
  return q;
}
vi.mock('../supabase', () => ({
  supabase: {
    auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) },
    from: (n: string) => table(n),
    rpc: (n: string) => Promise.resolve(n === 'narrative_record_contract_version' ? { data: 2, error: null } : { data: [], error: null }),
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
// Kun fetchPersonDetail er den rigtige; de øvrige læserhentninger er uden betydning her.
vi.mock('../data/public', async (importOriginal) => ({
  ...await importOriginal<typeof import('../data/public')>(),
  fetchEstates: async () => [],
  fetchArms: async () => [],
  fetchAbout: async () => [],
  fetchEstateInfo: async () => ({ narrativ: '', sted: '', media: [] }),
  fetchEstateOwners: async () => [],
}));
vi.mock('../data/media', () => ({ fetchPersonMedia: async () => [], fetchObjectMedia: async () => new Map() }));
vi.mock('../data/auth', () => ({
  currentSession: () => Promise.resolve(null),
  signIn: vi.fn(),
  loginFejlTekst: () => 'Login lykkedes ikke.',
  signOut: vi.fn(),
}));
vi.mock('../data/bookmarks', () => ({
  useBookmarks: () => ({
    canSave: false, ready: true, hydrationVersion: 1, ids: new Set<string>(), has: () => false, toggle: vi.fn(),
  }),
}));
vi.mock('../components/TreeView', () => ({ TreeView: () => <div>Stamtræ</div> }));
vi.mock('../components/DetailPanel', () => ({
  DetailPanel: (props: { detail: { bio: string; offices: unknown[] } | null }) => (
    <aside>{props.detail ? `Biografi hentet (${props.detail.offices.length} embeder)` : 'Henter biografi'}</aside>
  ),
}));

import Folgesvend from '../Folgesvend';

beforeEach(() => {
  locCache.v = null;
  mocks.relationFejler = true;
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  window.history.replaceState({}, '', '/slaegt/reventlow/stamtrae?fokus=1');
  const base = buildModel({
    persons: [{ id: '1', name: 'Testperson', born: null, died: 1900, years: '', title: '', bio: '', privat: false }],
    unions: [],
    parentChild: [],
  });
  mocks.loadModel.mockResolvedValue({ ...base, loadGeo: () => new Promise(() => {}) });
});

test('en databasefejl i persondetaljens relationsopslag vises som fejl med »Prøv igen« — ikke som en tom person', async () => {
  render(<Folgesvend />);
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toContain('Kunne ikke hente personens biografi');
  expect(screen.queryByText(/Biografi hentet/)).toBeNull();

  // Databasen svarer igen → »Prøv igen« henter detaljen.
  mocks.relationFejler = false;
  fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
  await screen.findByText('Biografi hentet (0 embeder)');
  expect(screen.queryByRole('alert')).toBeNull();
});
