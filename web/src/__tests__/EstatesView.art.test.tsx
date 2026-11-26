// @vitest-environment jsdom
// #471: gods-detaljen viser art, »Hørte under …« på en gård og »Omfattede: …« på et majorat; billede står på gården.
import { render, screen } from '@testing-library/react';
import { expect, test, vi } from 'vitest';
import { EstatesView } from '../components/EstatesView';
import type { EstateItem } from '../data/public';

vi.mock('../components/lazyMaps', () => ({ GeoMap: () => null, ExpandableMiniMap: () => null, MapFallback: () => null }));
vi.mock('../components/NarrativRenderer', () => ({ NarrativRenderer: ({ tekst }: { tekst: string }) => <span>{tekst}</span> }));
vi.mock('../components/Lightbox', () => ({ Lightbox: () => null }));
vi.mock('../components/primitives', () => ({
  ViewHeader: ({ title }: { title: string }) => <h1>{title}</h1>,
  MediaThumb: ({ m }: { m: { titel: string } }) => <figure>billede: {m.titel}</figure>,
}));

const ESTATES: EstateItem[] = [
  { id: '5', navn: 'Christianssæde', slags: 'grevskab', ownerCount: 0 },
  { id: '7', navn: 'Bukkehave', slags: 'gård', ownerCount: 0 },
  { id: '8', navn: 'Uden art', slags: '', ownerCount: 0 },
];
const HOERER = [{ gaard: '7', majorat: '5', periode: '(1700-1800)' }];

function vis(id: string, info = { narrativ: '', sted: '', media: [] as never[] }, hoererUnder = HOERER) {
  return render(<EstatesView estates={ESTATES} hoererUnder={hoererUnder} estatesFejl={false} onRetryEstates={() => {}} estateId={id}
    estate={ESTATES.find((e) => e.id === id) ?? null} info={info} ejere={{ status: 'ok', raekke: { raekker: [], udenAar: [] } }} onRetryEjere={() => {}}
    slaegt={{ slug: 'reventlow', navn: 'Reventlow' }} geoLoading={false} onOpen={() => {}} onPickOwner={() => {}} besiddelserHref="/b" onBesiddelser={() => {}} />);
}

test('en gård viser sin art og »Hørte under <majorat> (<periode>)« med link', () => {
  vis('7');
  expect(screen.getByText('Gård')).toBeTruthy();
  expect(screen.getByText(/Hørte under/).textContent).toBe('Hørte under Christianssæde (1700-1800)');
  expect(screen.getByRole('link', { name: 'Christianssæde' }).getAttribute('href')).toBe('/besiddelse/5');
});

test('et majorat viser sin art og »Omfattede: <gårde>« med links', () => {
  vis('5');
  expect(screen.getByText('Grevskab')).toBeTruthy();
  expect(screen.getByText(/Omfattede/).textContent).toBe('Omfattede: Bukkehave');
  expect(screen.getByRole('link', { name: 'Bukkehave' }).getAttribute('href')).toBe('/besiddelse/7');
});

test('uden relationer og uden art vises ingen af linjerne', () => {
  vis('8', undefined, []);
  expect(screen.queryByText(/Hørte under|Omfattede/)).toBeNull();
  expect(screen.getByText('Besiddelse')).toBeTruthy();
});

test('et billede på en gård vises på gården', () => {
  vis('7', { narrativ: '', sted: '', media: [{ id: 'm1', titel: 'Hovedbygning', url: 'https://x/y.jpg' }] as never[] });
  expect(screen.getByText('billede: Hovedbygning')).toBeTruthy();
});

test('listen viser art på kortene', () => {
  render(<EstatesView estates={ESTATES} estatesFejl={false} onRetryEstates={() => {}} estateId={null} estate={null} info={null}
    ejere={{ status: 'henter' }} onRetryEjere={() => {}} slaegt={{ slug: 'reventlow', navn: 'Reventlow' }} geoLoading={false} onOpen={() => {}}
    onPickOwner={() => {}} besiddelserHref="/b" onBesiddelser={() => {}} />);
  expect(screen.getByText('Grevskab')).toBeTruthy();
  expect(screen.getByText('Gård')).toBeTruthy();
});
