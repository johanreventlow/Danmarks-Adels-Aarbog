import { fireEvent, render, screen } from '@testing-library/react-native';
import type { FeedCard } from '@daa/feed';
import { FeedCardView } from '../FeedCardView';
import { PersonFeedCardView } from '../PersonFeedCardView';
import { useMobileFeedMedia, type MobileFeedMediaItem } from '../../../lib/feedMedia';

jest.mock('../../../lib/feedMedia', () => ({
  useMobileFeedMedia: jest.fn(),
}));

const portrait: Extract<FeedCard, { kind: 'portrait' }> = {
  kind: 'portrait', id: 'portrait:42', personId: '42', name: 'Kortets gamle navn',
  years: '1700–1760', initials: 'KG', title: 'Kammerherre', bio: 'En kort biografi.', kicker: 'Portræt',
};
const person = { name: 'Anna Reventlow', years: '1732–1794' };
const media: MobileFeedMediaItem[] = [
  { id: 'm1', slags: 'portræt', titel: 'Portræt fra arkivet', kunstner: 'Maler', datering: '1760', mediumUri: 'https://example.test/medium-1.jpg', largeUri: 'https://example.test/large-1.jpg' },
  { id: 'm2', slags: 'maleri', titel: 'Slægtsbillede', kunstner: 'Maler', datering: '1770', mediumUri: 'https://example.test/medium-2.jpg', largeUri: 'https://example.test/large-2.jpg' },
];

const mockUseMobileFeedMedia = jest.mocked(useMobileFeedMedia);

function renderPersonCard(overrides: Partial<React.ComponentProps<typeof PersonFeedCardView>> = {}) {
  const onOpen = jest.fn();
  const onSave = jest.fn();
  render(<PersonFeedCardView card={portrait} person={person} rawMedia={[]} onOpen={onOpen} onSave={onSave} bookmarked={false} {...overrides} />);
  return { onOpen, onSave };
}

describe('PersonFeedCardView', () => {
  beforeEach(() => {
    mockUseMobileFeedMedia.mockReturnValue(media);
  });

  test('viser modelidentitet, indhold og to billedkontroller', () => {
    renderPersonCard();

    expect(screen.getByText('A')).toBeTruthy();
    expect(screen.getByText('Anna Reventlow')).toBeTruthy();
    expect(screen.getByText('1732–1794')).toBeTruthy();
    expect(screen.getByText('Portræt')).toBeTruthy();
    expect(screen.getByText('En kort biografi.')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Åbn billede: Portræt fra arkivet' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Åbn billede: Slægtsbillede' })).toBeTruthy();
  });

  test('åbner profilen fra den store profilkontrol', () => {
    const { onOpen } = renderPersonCard();

    fireEvent.press(screen.getByRole('button', { name: 'Åbn profil for Anna Reventlow' }));

    expect(onOpen).toHaveBeenCalledWith(portrait);
  });

  test('åbner lightbox fra billede uden profilnavigation', () => {
    const { onOpen } = renderPersonCard();

    fireEvent.press(screen.getByRole('button', { name: 'Åbn billede: Portræt fra arkivet' }));

    expect(screen.getByRole('button', { name: 'Luk billedevisning' })).toBeTruthy();
    expect(onOpen).not.toHaveBeenCalled();
  });

  test('gemmer uden profilnavigation', () => {
    const { onOpen, onSave } = renderPersonCard();

    fireEvent.press(screen.getByRole('button', { name: 'Gem Anna Reventlow' }));

    expect(onSave).toHaveBeenCalledWith('42');
    expect(onOpen).not.toHaveBeenCalled();
  });

  test('lader vandret scroll være uafhængig af profilnavigation', () => {
    const { onOpen } = renderPersonCard();
    const strip = screen.getByLabelText('Billeder tilknyttet personen');

    fireEvent.scroll(strip, { nativeEvent: { contentOffset: { x: 80, y: 0 } } });
    fireEvent(strip, 'momentumScrollEnd', { nativeEvent: { contentOffset: { x: 80, y: 0 } } });

    expect(onOpen).not.toHaveBeenCalled();
  });

  test('udelader billedstriben, når signering ikke gav nogen medier', () => {
    mockUseMobileFeedMedia.mockReturnValue([]);
    renderPersonCard();

    expect(screen.queryByLabelText('Billeder tilknyttet personen')).toBeNull();
    expect(screen.queryByRole('button', { name: /^Åbn billede:/ })).toBeNull();
  });

  test('erstatter Læs mere med den store profilkontrol', () => {
    renderPersonCard();

    expect(screen.queryByText('Læs mere ›')).toBeNull();
  });

  test('bevarer arkivets klausul, år, kategori og kilde i personshellen', () => {
    const arkiv: Extract<FeedCard, { kind: 'arkiv' }> = {
      kind: 'arkiv', id: 'arkiv:42', personId: '42', name: 'Kortets gamle navn', kicker: 'Arkivfund',
      klausul: 'Arvede godset i 1764.', aarLabel: '1764', kategori: 'Arv', kilde: 'Familiearkivet',
    };
    render(<FeedCardView card={arkiv} person={person} rawMedia={[]} onOpen={jest.fn()} onSave={jest.fn()} bookmarked={false} />);

    expect(screen.getByRole('button', { name: 'Åbn profil for Anna Reventlow' })).toBeTruthy();
    expect(screen.getByText('Arkivfund')).toBeTruthy();
    expect(screen.getByText('Arvede godset i 1764.')).toBeTruthy();
    expect(screen.getByText('1764')).toBeTruthy();
    expect(screen.getByText('Arv')).toBeTruthy();
    expect(screen.getByText('efter Familiearkivet')).toBeTruthy();
  });

  test('bevarer gods som eksisterende ikke-persongren', () => {
    const gods: Extract<FeedCard, { kind: 'gods' }> = {
      kind: 'gods', id: 'gods:1', estateId: '1', navn: 'Pederstrup', meta: 'Lolland', ownerDots: 2, kicker: 'Gods',
    };
    render(<FeedCardView card={gods} onOpen={jest.fn()} onSave={jest.fn()} bookmarked={false} />);

    expect(screen.getByText('Pederstrup')).toBeTruthy();
    expect(screen.queryByRole('button', { name: /^Åbn profil for/ })).toBeNull();
  });
});
