// @vitest-environment jsdom
import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import type { FeedCard } from '@daa/feed';
import { FeedCardView } from '../feed/FeedCardView';
import { PersonFeedCardView } from '../feed/PersonFeedCardView';
import type { WebFeedMediaItem } from '../../data/feedMedia';

const portrait: Extract<FeedCard, { kind: 'portrait' }> = {
  kind: 'portrait', id: 'portrait:42', personId: '42', name: 'Kortets gamle navn',
  years: '1700–1760', initials: 'KG', title: 'Kammerherre', bio: 'En kort biografi.', kicker: 'Portræt',
};
const person = { name: 'Anna Reventlow', years: '1732–1794' };
const media: WebFeedMediaItem[] = [
  { id: 'm1', slags: 'portræt', titel: 'Portræt fra arkivet', kunstner: 'Maler', datering: '1760', mediumUrl: 'https://example.test/medium-1.jpg', largeUrl: 'https://example.test/large-1.jpg' },
  { id: 'm2', slags: 'maleri', titel: 'Slægtsbillede', kunstner: 'Maler', datering: '1770', mediumUrl: 'https://example.test/medium-2.jpg', largeUrl: 'https://example.test/large-2.jpg' },
];

function renderPersonCard(overrides: Partial<React.ComponentProps<typeof PersonFeedCardView>> = {}) {
  const onOpen = vi.fn();
  const onSave = vi.fn();
  render(<PersonFeedCardView card={portrait} person={person} media={media} onOpen={onOpen} onSave={onSave} bookmarked={false} {...overrides} />);
  return { onOpen, onSave };
}

describe('PersonFeedCardView', () => {
  it('viser den modelafledte identitet, kortets indhold og alle medier', () => {
    renderPersonCard();

    expect(screen.getByText('AR')).toBeTruthy();
    expect(screen.getByText('Anna Reventlow')).toBeTruthy();
    expect(screen.getByText('1732–1794')).toBeTruthy();
    expect(screen.getByText('Portræt')).toBeTruthy();
    expect(screen.getByText('En kort biografi.')).toBeTruthy();
    expect(screen.getByRole('img', { name: 'Portræt fra arkivet' })).toBeTruthy();
    expect(screen.getByRole('img', { name: 'Slægtsbillede' })).toBeTruthy();
  });

  it('åbner personkortet med klik, Enter og Space på den store profilkontrol', async () => {
    const { onOpen } = renderPersonCard();
    const profile = screen.getByRole('button', { name: 'Åbn profil for Anna Reventlow' });
    const user = userEvent.setup();

    fireEvent.click(profile);
    profile.focus();
    await user.keyboard('{Enter}');
    await user.keyboard(' ');

    expect(onOpen).toHaveBeenCalledTimes(3);
    expect(onOpen).toHaveBeenLastCalledWith(portrait);
  });

  it('åbner lightboxen fra et billede uden at navigere til personen', () => {
    const { onOpen } = renderPersonCard();

    fireEvent.click(screen.getByRole('button', { name: 'Åbn billede: Portræt fra arkivet' }));

    expect(screen.getByTitle('Luk (Esc)')).toBeTruthy();
    expect(onOpen).not.toHaveBeenCalled();
  });

  it('gemmer personen uden at åbne dens profil', () => {
    const { onOpen, onSave } = renderPersonCard();

    fireEvent.click(screen.getByRole('button', { name: 'Bogmærk denne person' }));

    expect(onSave).toHaveBeenCalledWith('42');
    expect(onOpen).not.toHaveBeenCalled();
  });

  it('viser flere medier som en vandret stribe og ét som et kort i fuld bredde', () => {
    const { rerender } = render(<PersonFeedCardView card={portrait} person={person} media={media} onOpen={vi.fn()} onSave={vi.fn()} bookmarked={false} />);
    const first = screen.getByRole('button', { name: 'Åbn billede: Portræt fra arkivet' });

    expect(first.parentElement?.style.display).toBe('flex');
    expect(first.parentElement?.style.overflowX).toBe('auto');
    expect(first.style.flexBasis).toBe('78%');

    rerender(<PersonFeedCardView card={portrait} person={person} media={[media[0]]} onOpen={vi.fn()} onSave={vi.fn()} bookmarked={false} />);
    expect(screen.getByRole('button', { name: 'Åbn billede: Portræt fra arkivet' }).style.flexBasis).toBe('100%');
  });

  it('udelader media-striben, når kortet ikke har tilgængelige medier', () => {
    renderPersonCard({ media: [] });

    expect(screen.queryByRole('button', { name: /^Åbn billede:/ })).toBeNull();
  });

  it('giver et arkivkort samme personshell og bevarer klausul, år, kategori og kilde', () => {
    const arkiv: Extract<FeedCard, { kind: 'arkiv' }> = {
      kind: 'arkiv', id: 'arkiv:42', personId: '42', name: 'Kortets gamle navn', kicker: 'Arkivfund',
      klausul: 'Arvede godset i 1764.', aarLabel: '1764', kategori: 'Arv', kilde: 'Familiearkivet',
    };
    render(<FeedCardView card={arkiv} person={person} media={[]} onOpen={vi.fn()} onSave={vi.fn()} bookmarked={false} />);

    expect(screen.getByRole('button', { name: 'Åbn profil for Anna Reventlow' })).toBeTruthy();
    expect(screen.getByText('Arkivfund')).toBeTruthy();
    expect(screen.getByText('Arvede godset i 1764.')).toBeTruthy();
    expect(screen.getByText('1764')).toBeTruthy();
    expect(screen.getByText('Arv')).toBeTruthy();
    expect(screen.getByText('efter Familiearkivet')).toBeTruthy();
  });

  it('bevarer gods-kortets eksisterende gren uden personshell', () => {
    const gods: Extract<FeedCard, { kind: 'gods' }> = {
      kind: 'gods', id: 'gods:1', estateId: '1', navn: 'Pederstrup', meta: 'Lolland', ownerDots: 2, kicker: 'Gods',
    };
    render(<FeedCardView card={gods} onOpen={vi.fn()} onSave={vi.fn()} bookmarked={false} />);

    expect(screen.getByText('Pederstrup')).toBeTruthy();
    expect(screen.queryByRole('button', { name: /^Åbn profil for/ })).toBeNull();
  });
});
