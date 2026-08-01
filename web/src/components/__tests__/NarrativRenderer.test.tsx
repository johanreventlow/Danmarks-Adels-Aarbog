// @vitest-environment jsdom
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { vi } from 'vitest';
import { NarrativRenderer } from '../NarrativRenderer';

const COLORS = { linkColor: '#881A33', inactiveColor: '#9a8f78' };

// Billedstørrelser 2026-07-05, Slice C: fetchMediaByIds ville ellers ramme rigtig Supabase
// (`.env.local` peger på prod til de øvrige data-lag-tests) — mockes her så disse tests forbliver
// offline/deterministiske, ligesom maplibre-gl-mocken ovenfor i test/setup.ts.
vi.mock('../../data/media', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../data/media')>();
  return {
    ...actual,
    fetchMediaByIds: vi.fn(async (ids: number[]) => {
      const out = new Map();
      if (ids.includes(5)) out.set('5', { titel: 'Skjold', mediumUrl: 'https://signed/5-medium.jpg', largeUrl: 'https://signed/5-large.jpg' });
      return out;
    }),
  };
});

describe('NarrativRenderer', () => {
  it('renderer ren tekst uden links', () => {
    render(<NarrativRenderer tekst="bare prosa" onPickPerson={vi.fn()} {...COLORS} />);
    expect(screen.getByText('bare prosa')).toBeTruthy();
  });

  it('renderer person-token som klikbart link der kalder onPickPerson med korrekt id', () => {
    const onPick = vi.fn();
    render(<NarrativRenderer tekst="Se [[person:482|Chr. D. R.]] her." onPickPerson={onPick} {...COLORS} />);
    const link = screen.getByText('Chr. D. R.');
    fireEvent.click(link);
    expect(onPick).toHaveBeenCalledWith('482');
  });

  it('person-token er et ægte anker med default-sti til publikumsfladen', () => {
    render(<NarrativRenderer tekst="Se [[person:482|Chr. D. R.]] her." onPickPerson={vi.fn()} {...COLORS} />);
    const link = screen.getByText('Chr. D. R.');
    expect(link.tagName).toBe('A');
    expect(link.getAttribute('href')).toBe('/person/482');
  });

  it('hrefFor overstyrer stien (redaktørens preview peger på redaktør-posten)', () => {
    render(
      <NarrativRenderer
        tekst="Se [[person:482|Chr. D. R.]] her."
        onPickPerson={vi.fn()}
        hrefFor={(id) => `/redaktion/person/${id}`}
        {...COLORS}
      />,
    );
    expect(screen.getByText('Chr. D. R.').getAttribute('href')).toBe('/redaktion/person/482');
  });

  it('renderer ikke-person-token som inaktiv tekst uden klik-effekt', () => {
    const onPick = vi.fn();
    render(<NarrativRenderer tekst="Se [[estate:7|Gammel Gaard]] her." onPickPerson={onPick} {...COLORS} />);
    const inactive = screen.getByText('Gammel Gaard');
    fireEvent.click(inactive);
    expect(onPick).not.toHaveBeenCalled();
  });

  it('malformet token vises som rå tekst, ikke som knækket link', () => {
    render(<NarrativRenderer tekst="[[person:abc|x]]" onPickPerson={vi.fn()} {...COLORS} />);
    expect(screen.getByText('[[person:abc|x]]')).toBeTruthy();
  });

  it('## Overskrift renderes som egen blok', () => {
    render(<NarrativRenderer tekst="## Slægtens oprindelse" onPickPerson={vi.fn()} {...COLORS} />);
    expect(screen.getByText('Slægtens oprindelse')).toBeTruthy();
  });

  it('blank linje giver to adskilte afsnit (<p>-elementer)', () => {
    // JSX-attributter er IKKE JS-strenge — \n skal komme via en {}-udtryk for reelt at være et linjeskift.
    const { container } = render(<NarrativRenderer tekst={'Første.\n\nAnden.'} onPickPerson={vi.fn()} {...COLORS} />);
    expect(container.querySelectorAll('p')).toHaveLength(2);
  });

  it('opløseligt media-token viser <img> (medium-url) og åbner lightbox ved klik', async () => {
    render(<NarrativRenderer tekst="[[media:5|Skjoldet]]" onPickPerson={vi.fn()} {...COLORS} />);
    await waitFor(() => expect(screen.getByRole('img')).toBeTruthy());
    const img = screen.getByRole('img') as HTMLImageElement;
    expect(img.src).toBe('https://signed/5-medium.jpg');
    fireEvent.click(img);
    const lightboxImgs = screen.getAllByRole('img').filter((el) => (el as HTMLImageElement).src === 'https://signed/5-large.jpg');
    expect(lightboxImgs.length).toBeGreaterThan(0);
  });

  it('uopløseligt media-token (ukendt id) falder tilbage til inaktiv tekst, intet <img>', async () => {
    render(<NarrativRenderer tekst="[[media:999|Ukendt billede]]" onPickPerson={vi.fn()} {...COLORS} />);
    await waitFor(() => expect(screen.getByText('Ukendt billede')).toBeTruthy());
    expect(screen.queryByRole('img')).toBeNull();
  });
});
