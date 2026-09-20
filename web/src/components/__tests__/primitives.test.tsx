// @vitest-environment jsdom
// MediaThumb sætter alt-attributten ét sted (MM-05, medie-metadata Task 6) — dækker alle
// MediaItem-gallerier (DetailPanel/ArmsView/EstatesView) uden at kalderne selv skal håndtere det.
import { render, screen } from '@testing-library/react';
import { MediaThumb } from '../primitives';
import type { MediaItem } from '../../data/media';

const base: MediaItem = {
  id: '1', slags: 'maleri', titel: 'Et portræt', kunstner: '', datering: '',
  url: 'https://x/large.jpg', thumbUrl: 'https://x/thumb.jpg',
  altTekst: null, kreditlinje: null, kildeUrl: null, kildeInstitution: null,
  beskrivelse: null, teknik: null, fysiskeMaal: null, dateringFakt: null,
};

describe('MediaThumb — alt-tekst', () => {
  it('foretrækker altTekst over titel/slags', () => {
    render(<MediaThumb m={{ ...base, altTekst: 'En dame i sort kjole' }} w={80} h={80} onClick={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('En dame i sort kjole');
  });

  it('falder tilbage til titel uden altTekst', () => {
    render(<MediaThumb m={{ ...base, altTekst: null }} w={80} h={80} onClick={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('Et portræt');
  });

  it('falder tilbage til slags uden altTekst/titel', () => {
    render(<MediaThumb m={{ ...base, altTekst: null, titel: '' }} w={80} h={80} onClick={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('maleri');
  });

  it('falder tilbage til "billede" uden noget af det', () => {
    render(<MediaThumb m={{ ...base, altTekst: null, titel: '', slags: '' }} w={80} h={80} onClick={vi.fn()} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('billede');
  });
});
