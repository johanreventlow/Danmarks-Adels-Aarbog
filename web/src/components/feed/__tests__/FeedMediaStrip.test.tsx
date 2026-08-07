// @vitest-environment jsdom
// FeedMediaStrip bruger den feed-berigede altTekst som img-alt (medie-metadata Task 6) — falder
// tilbage til titel/slags-labelen når fakten mangler (fx et upubliceret medie, RLS-gatet).
import { render, screen } from '@testing-library/react';
import { FeedMediaStrip } from '../FeedMediaStrip';
import type { WebFeedMediaItem } from '../../../data/feedMedia';

const item = (overrides: Partial<WebFeedMediaItem>): WebFeedMediaItem => ({
  id: '1', slags: 'maleri', titel: 'Et portræt', kunstner: '', datering: '',
  mediumUrl: 'https://x/medium.jpg', largeUrl: 'https://x/large.jpg', ...overrides,
});

describe('FeedMediaStrip — alt-tekst', () => {
  it('bruger altTekst som img-alt når sat', () => {
    render(<FeedMediaStrip media={[item({ altTekst: 'En dame i sort kjole' })]} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('En dame i sort kjole');
  });

  it('falder tilbage til titel uden altTekst', () => {
    render(<FeedMediaStrip media={[item({ altTekst: null })]} />);
    expect(screen.getByRole('img').getAttribute('alt')).toBe('Et portræt');
  });
});
