// @vitest-environment jsdom
// Læser-visning (medie-metadata Task 6): kreditlinje, kildelink, beskrivelse-fold og alt-tekst
// i Lightbox-overlayet. Kreditlinjen er et juridisk krav ved CC-licenser og vises derfor ALTID
// når udfyldt (aldrig bag et fold) — kilde-linket derimod kun når kildeUrl er en gyldig http(s)-url
// (MM-11), og beskrivelsen ligger bag en native <details>-fold (ingen ny state).
import { render, screen } from '@testing-library/react';
import { Lightbox, type LightboxItem } from '../Lightbox';

const base: LightboxItem = { id: '1', url: 'https://x/large.jpg', titel: 'Et portræt' };

describe('Lightbox — kreditlinje/kildelink/beskrivelse/alt-tekst', () => {
  it('viser kreditlinje når udfyldt', () => {
    render(<Lightbox items={[{ ...base, kreditlinje: 'Luise … | Lizenz: CC BY-SA 4.0' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByText(/Lizenz: CC BY-SA 4.0/)).toBeTruthy();
  });

  it('viser IKKE noget kreditlinje-element når feltet er tomt', () => {
    render(<Lightbox items={[{ ...base, kreditlinje: null }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.queryByText(/Lizenz/)).toBeNull();
  });

  it('kilde-link åbner eksternt med korrekt href/target/rel', () => {
    render(<Lightbox items={[{ ...base, kildeUrl: 'https://ddb.de/item/123', kildeInstitution: 'Deutsche Digitale Bibliothek' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    const link = screen.getByRole('link', { name: /Deutsche Digitale Bibliothek/ });
    expect(link.getAttribute('href')).toBe('https://ddb.de/item/123');
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toContain('noopener');
    expect(link.getAttribute('rel')).toContain('noreferrer');
  });

  it('kilde-link falder tilbage til "kilden" uden institution', () => {
    render(<Lightbox items={[{ ...base, kildeUrl: 'https://ddb.de/item/123', kildeInstitution: null }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByRole('link', { name: /Se hos kilden/ })).toBeTruthy();
  });

  it('renderer INTET kilde-link når kildeUrl ikke matcher http(s) (MM-11)', () => {
    render(<Lightbox items={[{ ...base, kildeUrl: 'javascript:alert(1)', kildeInstitution: 'X' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.queryByRole('link')).toBeNull();
  });

  it('renderer intet kilde-link når kildeUrl mangler', () => {
    render(<Lightbox items={[{ ...base, kildeUrl: null }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.queryByRole('link')).toBeNull();
  });

  it('alt-tekst foretrækkes over titel', () => {
    render(<Lightbox items={[{ ...base, altTekst: 'En dame i sort kjole ved et vindue' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('En dame i sort kjole ved et vindue');
  });

  it('alt falder tilbage til titel uden altTekst', () => {
    render(<Lightbox items={[{ ...base, altTekst: null }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('Et portræt');
  });

  it('beskrivelse ligger i details-fold', () => {
    render(<Lightbox items={[{ ...base, beskrivelse: 'Malet af en ukendt kunstner i 1840.' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByText('Om billedet')).toBeTruthy();
    expect(screen.getByText('Malet af en ukendt kunstner i 1840.')).toBeTruthy();
  });

  it('ingen beskrivelse → ingen details-fold', () => {
    render(<Lightbox items={[{ ...base, beskrivelse: null }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.queryByText('Om billedet')).toBeNull();
  });

  it('caption bruger dateringFakt før datering (Global Constraint)', () => {
    render(<Lightbox items={[{ ...base, kunstner: null, datering: '1900', dateringFakt: 'ca. 1840' }]} index={0} onClose={vi.fn()} onNavigate={vi.fn()} />);
    expect(screen.getByText(/ca\. 1840/)).toBeTruthy();
    expect(screen.queryByText(/1900/)).toBeNull();
  });
});
