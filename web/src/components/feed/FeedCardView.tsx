// Feed-kort — web-udgaven (fase1-design.md §7.1). Én switch over FeedCard.kind, samme
// visuelle idiom som HomeView/primitives.tsx (papir-kort, serif-navne, mono-kickers,
// guld-accenter) — INGEN nye farver/fonte, kun theme.ts's T. Gem-ikon rendres iff kortet
// har et personId (bookmarkPersonId, @daa/feed).
import { bookmarkPersonId, type FeedCard } from '@daa/feed';
import { T } from '../../theme';
import { Avatar, BookmarkFlag } from '../primitives';

type Props = {
  card: FeedCard;
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
};

const cardBase: React.CSSProperties = {
  background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14,
  padding: 18, boxShadow: '0 1px 2px rgba(34,31,26,.04)',
};
const kicker: React.CSSProperties = { fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold };
const headerRow: React.CSSProperties = { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' };

export function FeedCardView({ card, onOpen, onSave, bookmarked }: Props) {
  const pid = bookmarkPersonId(card);
  const save = pid ? <BookmarkFlag active={bookmarked} onClick={() => onSave(pid)} /> : null;

  switch (card.kind) {
    case 'portrait':
    case 'dagensperson': // identisk feltform; kicker skelner ('Portræt' vs. 'Dagens person')
      return (
        <div style={{ ...cardBase, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={headerRow}>
            <span style={kicker}>{card.kicker}</span>
            {save}
          </div>
          <div style={{ fontFamily: T.serif, fontSize: 23, fontWeight: 600, color: T.ink, marginTop: 8 }}>{card.name}</div>
          <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 3 }}>{card.years}</div>
          {card.title ? <div style={{ fontFamily: T.sans, fontSize: 12, fontWeight: 500, color: T.bordeaux, marginTop: 5 }}>{card.title}</div> : null}
          <div style={{ fontFamily: T.sans, fontSize: 13, lineHeight: 1.5, color: T.muted, marginTop: 10, display: '-webkit-box', WebkitLineClamp: 5, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{card.bio}</div>
        </div>
      );

    case 'citat':
      return (
        <div style={{ background: T.ink, borderRadius: 14, padding: 22, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={headerRow}>
            <span style={{ ...kicker, color: T.goldLight }}>{card.kicker}</span>
            {save}
          </div>
          <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 21, lineHeight: 1.4, color: T.panel, marginTop: 12 }}>{card.quote}</div>
          <div style={{ fontFamily: T.sans, fontSize: 11, color: T.cream, marginTop: 14 }}>{card.source}</div>
        </div>
      );

    case 'gods':
      return (
        <div style={{ ...cardBase, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <span style={kicker}>{card.kicker}</span>
          <div style={{ display: 'flex', gap: 13, alignItems: 'center', marginTop: 9 }}>
            <div style={{ width: 46, height: 46, borderRadius: 11, background: T.beige, border: '1px solid rgba(34,31,26,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 20, color: T.bordeaux, flex: 'none' }}>⌂</div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.ink, lineHeight: 1.1 }}>{card.navn}</div>
              <div style={{ fontFamily: T.sans, fontSize: 12.5, color: T.muted2, marginTop: 3 }}>{card.meta}</div>
            </div>
          </div>
        </div>
      );

    case 'forbundet':
      return (
        <div style={{ background: T.beige, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14, padding: 17 }}>
          <span style={kicker}>{card.kicker}</span>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 16, marginTop: 10 }}>
            <div style={{ flex: 1, textAlign: 'center' }}>
              <Avatar n={card.aName} size={48} />
              <div style={{ fontFamily: T.serif, fontSize: 15, marginTop: 7, color: T.ink }}>{card.aName}</div>
            </div>
            <span style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 24, color: T.bordeaux }}>&amp;</span>
            <div style={{ flex: 1, textAlign: 'center' }}>
              <Avatar n={card.bName} size={48} />
              <div style={{ fontFamily: T.serif, fontSize: 15, marginTop: 7, color: T.ink }}>{card.bName}</div>
            </div>
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, textAlign: 'center', marginTop: 12 }}>{card.marBottom}</div>
        </div>
      );

    case 'slaegt':
      return (
        <div style={{ background: T.ink, borderRadius: 14, padding: 18, border: '1px solid rgba(231,201,143,.14)', cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <span style={{ ...kicker, color: T.goldLight }}>{card.kicker}</span>
          <div style={{ fontFamily: T.serif, fontSize: 19, color: T.panel, marginTop: 9, lineHeight: 1.35 }}>
            <span style={{ color: T.goldLight }}>{card.aName}</span> og <span style={{ color: T.goldLight }}>{card.bName}</span> — {card.rel}
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 11.5, fontWeight: 600, color: T.goldLight, marginTop: 11 }}>{card.foot}</div>
        </div>
      );

    case 'embede':
      return (
        <div style={{ ...cardBase, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={headerRow}>
            <span style={kicker}>{card.kicker}</span>
            {save}
          </div>
          <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 18, marginTop: 8, color: T.ink }}>{card.label}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 10 }}>
            <Avatar n={card.name} size={34} />
            <div style={{ minWidth: 0 }}>
              <div style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.ink }}>{card.name}</div>
              <div style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2 }}>{card.period}</div>
            </div>
          </div>
        </div>
      );

    case 'paadennedag':
      return (
        <div style={{ ...cardBase, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={headerRow}>
            <span style={kicker}>{card.kicker}</span>
            {save}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 9 }}>
            <div style={{ width: 44, height: 44, borderRadius: 22, background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.mono, fontSize: 12, color: T.bordeaux, flex: 'none' }}>{card.aarstal}</div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontFamily: T.serif, fontSize: 18, color: T.ink }}>{card.name}</div>
              <div style={{ fontFamily: T.sans, fontSize: 12, color: T.muted2, marginTop: 2 }}>{card.hvad === 'født' ? 'Født' : 'Død'} {card.aarstal}</div>
            </div>
          </div>
        </div>
      );

    case 'jubilaeum':
      return (
        <div style={{ ...cardBase, display: 'flex', gap: 14, alignItems: 'center', cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={{ width: 54, textAlign: 'center', flex: 'none' }}>
            <div style={{ fontFamily: T.serif, fontSize: 30, color: T.bordeaux, lineHeight: 1 }}>{card.num}</div>
            <div style={{ fontFamily: T.mono, fontSize: 8, color: T.muted2, textTransform: 'uppercase', marginTop: 2 }}>år siden</div>
          </div>
          <div style={{ width: 1, height: 40, background: 'rgba(34,31,26,.12)', flex: 'none' }} />
          <div style={{ minWidth: 0, flex: 1 }}>
            <span style={kicker}>{card.kicker}</span>
            <div style={{ fontFamily: T.serif, fontSize: 18, color: T.ink, marginTop: 2 }}>{card.name}</div>
            <div style={{ fontFamily: T.sans, fontSize: 12, color: T.muted2, marginTop: 2 }}>{card.sub}</div>
          </div>
          {save}
        </div>
      );

    case 'vaaben':
      return (
        <div style={{ ...cardBase, display: 'flex', gap: 14, alignItems: 'center', cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <div style={{ width: 60, height: 74, flex: 'none', background: 'repeating-linear-gradient(45deg,#ece4d6 0 8px,#e2d8c8 8px 16px)', borderRadius: 6, border: '1px solid rgba(34,31,26,.1)' }} />
          <div style={{ minWidth: 0 }}>
            <span style={kicker}>{card.kicker}</span>
            <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 15, color: T.ink, marginTop: 5, lineHeight: 1.35 }}>{card.blazon}</div>
            <div style={{ fontFamily: T.sans, fontSize: 11.5, fontWeight: 600, color: T.bordeaux, marginTop: 7 }}>{card.foot}</div>
          </div>
        </div>
      );

    case 'samle':
      return (
        <div style={{ border: '1px dashed rgba(34,31,26,.22)', borderRadius: 14, padding: 16, cursor: 'pointer' }} onClick={() => onOpen(card)}>
          <span style={{ ...kicker, color: T.muted2 }}>{card.kicker}</span>
          <div style={{ fontFamily: T.serif, fontSize: 17, color: '#5a5246', marginTop: 6 }}>
            …og <span style={{ color: T.bordeaux }}>{card.count} flere</span> {card.tail}
          </div>
          <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, marginTop: 6 }}>For sparsomme til et eget blad — se dem samlet i registeret ›</div>
        </div>
      );

    default:
      return null;
  }
}
