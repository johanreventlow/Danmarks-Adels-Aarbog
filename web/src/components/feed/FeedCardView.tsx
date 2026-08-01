// Feed-kort — personkort delegerer til den fælles sociale shell; øvrige kort beholder deres
// eksisterende særformater og navigation.
import type { FeedCard } from '@daa/feed';
import { T } from '../../theme';
import { Avatar } from '../primitives';
import { Link } from '../../Link';
import { PersonFeedCardView, type PersonIdentity } from './PersonFeedCardView';
import type { WebFeedMediaItem } from '../../data/feedMedia';

type Props = {
  card: FeedCard;
  href?: string | null;
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
  person?: PersonIdentity;
  media?: WebFeedMediaItem[];
};

const cardBase: React.CSSProperties = {
  background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14,
  padding: 18, boxShadow: '0 1px 2px rgba(34,31,26,.04)',
};
const kicker: React.CSSProperties = { fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold };

// Kortets ydre skal: et anker når målet er adresserbart, ellers den hidtidige <div onClick>.
const KortSkal = ({ href, onOpen, style, children }: { href?: string | null; onOpen: () => void; style: React.CSSProperties; children: React.ReactNode }) =>
  href
    ? <Link href={href} onNavigate={onOpen} style={{ ...style, display: 'block' }}>{children}</Link>
    : <div onClick={onOpen} style={{ ...style, cursor: 'pointer' }}>{children}</div>;

export function FeedCardView({ card, href, onOpen, onSave, bookmarked, person, media = [] }: Props) {
  if ('personId' in card) {
    const fallbackName = 'name' in card ? card.name : `#${card.personId}`;
    const fallbackYears = 'years' in card ? card.years : '';
    return <PersonFeedCardView card={card} href={href} person={person ?? { name: fallbackName, years: fallbackYears }} media={media} onOpen={onOpen} onSave={onSave} bookmarked={bookmarked} />;
  }

  switch (card.kind) {
    case 'gods':
      return (
        <KortSkal href={href} onOpen={() => onOpen(card)} style={cardBase}>
          <span style={kicker}>{card.kicker}</span>
          <div style={{ display: 'flex', gap: 13, alignItems: 'center', marginTop: 9 }}>
            <div style={{ width: 46, height: 46, borderRadius: 11, background: T.beige, border: '1px solid rgba(34,31,26,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 20, color: T.bordeaux, flex: 'none' }}>⌂</div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.ink, lineHeight: 1.1 }}>{card.navn}</div>
              <div style={{ fontFamily: T.sans, fontSize: 13.5, color: T.muted2, marginTop: 3 }}>{card.meta}</div>
            </div>
          </div>
        </KortSkal>
      );

    case 'forbundet':
      return (
        <div style={{ background: T.beige, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14, padding: 17 }}>
          <span style={kicker}>{card.kicker}</span>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 16, marginTop: 10 }}>
            <div style={{ flex: 1, textAlign: 'center' }}>
              <Avatar n={card.aName} size={48} />
              <div style={{ fontFamily: T.serif, fontSize: 16, marginTop: 7, color: T.ink }}>{card.aName}</div>
            </div>
            <span style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 24, color: T.bordeaux }}>&amp;</span>
            <div style={{ flex: 1, textAlign: 'center' }}>
              <Avatar n={card.bName} size={48} />
              <div style={{ fontFamily: T.serif, fontSize: 16, marginTop: 7, color: T.ink }}>{card.bName}</div>
            </div>
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 12.5, color: T.muted2, textAlign: 'center', marginTop: 12 }}>{card.marBottom}</div>
        </div>
      );

    case 'slaegt':
      return (
        <KortSkal href={href} onOpen={() => onOpen(card)} style={{ background: T.ink, borderRadius: 14, padding: 18, border: '1px solid rgba(231,201,143,.14)' }}>
          <span style={{ ...kicker, color: T.goldLight }}>{card.kicker}</span>
          <div style={{ fontFamily: T.serif, fontSize: 19, color: T.panel, marginTop: 9, lineHeight: 1.35 }}>
            <span style={{ color: T.goldLight }}>{card.aName}</span> og <span style={{ color: T.goldLight }}>{card.bName}</span> — {card.rel}
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.goldLight, marginTop: 11 }}>{card.foot}</div>
        </KortSkal>
      );

    case 'vaaben':
      return (
        <KortSkal href={href} onOpen={() => onOpen(card)} style={{ ...cardBase, display: 'flex', gap: 14, alignItems: 'center' }}>
          <div style={{ width: 60, height: 74, flex: 'none', background: 'repeating-linear-gradient(45deg,#ece4d6 0 8px,#e2d8c8 8px 16px)', borderRadius: 6, border: '1px solid rgba(34,31,26,.1)' }} />
          <div style={{ minWidth: 0 }}>
            <span style={kicker}>{card.kicker}</span>
            <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 16, color: T.ink, marginTop: 5, lineHeight: 1.35 }}>{card.blazon}</div>
            <div style={{ fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, color: T.bordeaux, marginTop: 7 }}>{card.foot}</div>
          </div>
        </KortSkal>
      );

    case 'samle':
      return (
        <KortSkal href={href} onOpen={() => onOpen(card)} style={{ border: '1px dashed rgba(34,31,26,.22)', borderRadius: 14, padding: 16 }}>
          <span style={{ ...kicker, color: T.muted2 }}>{card.kicker}</span>
          <div style={{ fontFamily: T.serif, fontSize: 17, color: '#5a5246', marginTop: 6 }}>
            …og <span style={{ color: T.bordeaux }}>{card.count} flere</span> {card.tail}
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 12.5, color: T.muted2, marginTop: 6 }}>For sparsomme til et eget blad — se dem samlet i registeret ›</div>
        </KortSkal>
      );
  }
}
