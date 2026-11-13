// @vitest-environment jsdom
import { fireEvent, render, screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../../router', () => ({ navigate: vi.fn() }));
vi.mock('../lazyMaps', () => ({ GeoMap: () => null, ExpandableMiniMap: () => <div>Kort</div>, MapFallback: () => <div>Henter kort</div> }));
const { EstatesView } = await import('../EstatesView');

const estates = [{ id: '6', navn: 'Wittenberg', slags: 'gods', ownerCount: 3 }];
const raekke = {
  raekker: [
    { personId: 'b', navn: 'Bartram Reventlow', years: '1590–1640', linje: 'I. linje', periode: '1606-†', aar: 1606 },
    { personId: 'o', navn: 'Otto Reventlow', years: '', linje: null, periode: '1690-1712 og 1744-†', aar: 1690 },
  ],
  udenAar: [{ personId: 'd', navn: 'Detlef Reventlow', years: '', linje: null, periode: '', aar: null }],
};
const vis = (o: Partial<Parameters<typeof EstatesView>[0]> = {}) => {
  const p = {
    estates, estatesFejl: false, onRetryEstates: vi.fn(), estateId: '6', estate: estates[0], info: { narrativ: '', sted: 'Holsten', media: [] },
    ejere: { status: 'ok' as const, raekke }, onRetryEjere: vi.fn(), slaegt: { slug: 'reventlow', navn: 'Reventlow' },
    geoLoading: false, onOpen: vi.fn(), onPickOwner: vi.fn(), besiddelserHref: '/slaegt/reventlow/besiddelser', onBesiddelser: vi.fn(),
    slaegtensKortHref: '/slaegt/reventlow/besiddelser?visning=kort', ...o,
  };
  return { ...render(<EstatesView {...p} />), p };
};

describe('besiddelsens side', () => {
  it('brødkrumme, overskrift med sted, ejerrækken i rækkefølge med perioden som bogen skriver den', () => {
    vis();
    const krumme = screen.getByRole('navigation', { name: 'Brødkrumme' });
    expect(within(krumme).getAllByRole('link').map((a) => a.getAttribute('href'))).toEqual(['/', '/slaegt/reventlow', '/slaegt/reventlow/besiddelser']);
    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('Wittenberg');
    expect(screen.getByText('Besiddelse · Holsten')).toBeTruthy();
    const lister = screen.getAllByRole('list');
    expect(within(lister[0]).getAllByRole('link').map((a) => a.textContent)).toEqual(['Bartram Reventlow', 'Otto Reventlow']);
    expect(within(lister[0]).getByText('1690-1712 og 1744-†')).toBeTruthy();
    expect(within(lister[0]).getByText('1590–1640 · I. linje')).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Bartram Reventlow' }).getAttribute('href')).toBe('/person/b');
  });

  it('ejere uden årstal står for sig', () => {
    vis();
    expect(screen.getByRole('heading', { name: 'Uden årstal i bogen' })).toBeTruthy();
    expect(within(screen.getAllByRole('list')[1]).getByText('ingen periode')).toBeTruthy();
  });

  it('ingen ejere siges med ord; fejl er en fejl med »Prøv igen«', () => {
    const { unmount } = vis({ ejere: { status: 'ok', raekke: { raekker: [], udenAar: [] } } });
    expect(screen.getByText('Aarbogen nævner ingen ejere af Wittenberg.')).toBeTruthy();
    unmount();
    const { p } = vis({ ejere: { status: 'fejl' } });
    expect(screen.getByRole('alert').textContent).toContain('Ejerrækken kunne ikke hentes');
    fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
    expect(p.onRetryEjere).toHaveBeenCalled();
  });

  it('ukendt besiddelse: »findes ikke« med vej tilbage, ikke et tavst skift til listen', () => {
    vis({ estateId: '99999', estate: null });
    expect(screen.getByRole('heading', { name: 'Besiddelsen findes ikke i Aarbogen' })).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Alle slægtens besiddelser' }).getAttribute('href')).toBe('/slaegt/reventlow/besiddelser');
  });

  it('listen kunne ikke hentes: fejl, ikke »ingen besiddelser«', () => {
    const { p } = vis({ estateId: null, estate: null, estates: [], estatesFejl: true });
    expect(screen.getByRole('alert').textContent).toContain('Besiddelserne kunne ikke hentes');
    expect(screen.queryByText('Ingen besiddelser registreret.')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Prøv igen' }));
    expect(p.onRetryEstates).toHaveBeenCalled();
  });
});
