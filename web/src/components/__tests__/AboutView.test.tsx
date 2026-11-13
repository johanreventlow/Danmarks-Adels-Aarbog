// @vitest-environment jsdom
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { FeedPinInput } from '@daa/feed';
import type { Model, ModelPerson } from '../../data/types';
import type { AboutSection } from '../../data/public';

const pins = vi.hoisted(() => ({ value: [] as FeedPinInput[] }));
vi.mock('../../router', () => ({ navigate: vi.fn() }));
vi.mock('../../data/feedPins', () => ({ fetchFeedPins: () => Promise.resolve(pins.value) }));
vi.mock('../feed/FeedStreamView', () => ({ FeedStreamView: () => <div data-testid="feed" /> }));
vi.mock('../NarrativRenderer', () => ({
  NarrativRenderer: ({ tekst, kunFoersteAfsnit }: { tekst: string; kunFoersteAfsnit?: boolean }) => <span>{kunFoersteAfsnit ? tekst.split('\n\n')[0] : tekst}</span>,
}));

import { AboutView, indledningHarMere, indledningKilde } from '../AboutView';

const REVENTLOW = { slug: 'reventlow', navn: 'Reventlow', vaaben: { src: '/vaaben/reventlow.png' } };
const person = (id: string, name: string, o: Partial<ModelPerson> = {}) =>
  ({ id, name, born: 1600, died: 1660, years: '1600–1660', title: '', bio: '', privat: false, parentId: null, spouse: '', ...o }) as ModelPerson;
const ps = [person('1', 'Henning Reventlow'), person('2', 'Conrad Reventlow', { title: 'Storkansler', years: '† 1708', died: 1708 })];
const model = {
  persons: ps, byId: Object.fromEntries(ps.map((p) => [p.id, p])), indexes: { childIdx: {} },
  lineage: { byPerson: {}, navn: {}, list: [{ linje: 'slaegt:1:lineage:1:scheme:canonical', count: 120, headId: '1', navn: 'I. linje' }, { linje: 'slaegt:1:lineage:2:scheme:canonical', count: 80, headId: null, navn: null }, { linje: 'legacy-source:9:X', count: 3, headId: null, navn: 'Teknisk' }] },
} as unknown as Model;
const about: AboutSection[] = [
  { lineageId: null, lineageNavn: null, lineageKode: null, tekst: 'Første afsnit om slægten.\n\nAndet afsnit.', kilde: 'DAA 2018-20', aar: 2020 },
  { lineageId: '1', lineageNavn: 'I. linje', lineageKode: 'I', tekst: 'Om første linje.', kilde: 'Reventlow, stamtavle', aar: 1939 },
];
const feed = {
  estates: [], arms: [], meId: null, focusId: null, bookmarkedIds: [], bookmarksReady: true, bookmarkHydrationVersion: 0,
  bookmarkOwnerId: null, hasBookmark: () => false, onSaveBookmark: vi.fn(), onOpenPerson: vi.fn(), onOpenEstate: vi.fn(),
  onOpenArms: vi.fn(), onOpenSlaegt: vi.fn(), onBrowseAll: vi.fn(),
};
const vis = (o: Partial<Parameters<typeof AboutView>[0]> = {}) =>
  render(<AboutView slaegt={REVENTLOW} model={model} about={about} personCount={673} estateCount={186} onPick={vi.fn()} feed={feed} {...o} />);

beforeEach(() => { pins.value = []; });

describe('AboutView (slægtens forside)', () => {
  it('viser våbnet uden note og slægtens navn som overskrift', async () => {
    const { container } = vis();
    expect(screen.getByRole('img', { name: 'Reventlows våben' }).getAttribute('src')).toBe('/vaaben/reventlow.png');
    expect(container.querySelector('figcaption')).toBeNull();
    expect(screen.getByRole('heading', { level: 1, name: 'Reventlow' })).toBeTruthy();
    await screen.findByTestId('feed');
  });

  it('viser en våbennote, når slægten har en', async () => {
    vis({ slaegt: { ...REVENTLOW, vaaben: { src: '/vaaben/reventlow.png', note: 'Tegnet 2026' } } });
    expect(screen.getByText('Tegnet 2026').tagName).toBe('FIGCAPTION');
    await screen.findByTestId('feed');
  });

  it('indledningen viser uddrag og kilde, og kan foldes helt ud', async () => {
    vis();
    expect(screen.getByText('Første afsnit om slægten.')).toBeTruthy();
    expect(screen.getByText('Kilde: DAA 2018-20')).toBeTruthy();
    const knap = screen.getByRole('button', { name: 'Læs hele indledningen' });
    expect(knap.getAttribute('aria-expanded')).toBe('false');
    fireEvent.click(knap);
    expect(screen.getByText(/Andet afsnit\./)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Vis kun begyndelsen' }).getAttribute('aria-expanded')).toBe('true');
    await screen.findByTestId('feed');
  });

  it('linjerne med antal og stamfader som link; linjens indledning kan foldes ud', async () => {
    vis();
    const linjer = screen.getByRole('region', { name: 'Linjerne' });
    expect(within(linjer).getByText('I. linje')).toBeTruthy();
    expect(within(linjer).getByText('Linje uden navn')).toBeTruthy();
    expect(within(linjer).queryByText('Teknisk')).toBeNull();
    expect(within(linjer).queryByText(/slaegt:1:lineage/)).toBeNull();
    expect(within(linjer).getByText('120 personer')).toBeTruthy();
    expect(within(linjer).getByRole('link', { name: 'Henning Reventlow' }).getAttribute('href')).toBe('/person/1');
    expect(within(linjer).getByText('Om I. linje')).toBeTruthy();
    expect(within(linjer).getByText('Om første linje.')).toBeTruthy();
    await screen.findByTestId('feed');
  });

  it('»Redaktionen foreslår« kun når redaktionen har fastgjort portrætter', async () => {
    const { unmount } = vis();
    await screen.findByTestId('feed');
    expect(screen.queryByText('Redaktionen foreslår')).toBeNull();
    unmount();
    pins.value = [{ kortNoegle: 'portrait:2', handling: 'pin' }];
    vis();
    const sektion = await screen.findByRole('region', { name: 'Redaktionen foreslår' });
    const link = within(sektion).getByRole('link', { name: /Conrad Reventlow/ });
    expect(link.getAttribute('href')).toBe('/person/2');
    expect(within(link).getByText('Storkansler')).toBeTruthy();
  });

  it('siger det med ord, når slægten ingen indledning har', async () => {
    vis({ about: [] });
    expect(screen.getByText('Aarbogen har endnu ingen indledning til slægten.')).toBeTruthy();
    await waitFor(() => expect(screen.getByTestId('feed')).toBeTruthy());
  });
});

describe('indledningens hjælpere', () => {
  it('kilde er udgavens etiket alene; året bruges kun, når etiketten mangler', () => {
    expect(indledningKilde({ kilde: 'DAA 2018-20', aar: 2020 })).toBe('Kilde: DAA 2018-20');
    expect(indledningKilde({ kilde: null, aar: 1939 })).toBe('Kilde: Danmarks Adels Aarbog 1939');
    expect(indledningKilde({ kilde: null, aar: null })).toBe('Kilde ikke registreret');
  });
  it('kan foldes ud, når der er mere end første afsnit (efter rendererens blokke)', () => {
    expect(indledningHarMere('Kun ét afsnit.')).toBe(false);
    expect(indledningHarMere('## Indledning\nFørste afsnit.')).toBe(true);
    expect(indledningHarMere('Første.\n\nAndet.')).toBe(true);
  });
});
