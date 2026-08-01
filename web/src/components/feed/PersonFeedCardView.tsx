import type { FeedCard } from '@daa/feed';
import { T } from '../../theme';
import { Avatar, BookmarkFlag } from '../primitives';
import type { WebFeedMediaItem } from '../../data/feedMedia';
import { FeedMediaStrip } from './FeedMediaStrip';
import { Link } from '../../Link';
import { personPath } from '../../data/nav';

export type PersonCard = Extract<FeedCard, { personId: string }>;
export type PersonIdentity = { name: string; years: string };

export function PersonFeedCardView({ card, href, person, media, onOpen, onSave, bookmarked }: {
  card: PersonCard;
  href?: string | null;
  person: PersonIdentity;
  media: WebFeedMediaItem[];
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
}) {
  return (
    <article onClick={() => onOpen(card)} style={{ position: 'relative', background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 14, padding: 18, boxShadow: '0 1px 2px rgba(34,31,26,.04)', cursor: 'pointer' }}>
      {/* Ægte link, ikke knap: at åbne en profil ER navigation, så rollen skal være 'link'.
          stopPropagation, så article'ens egen onClick ikke navigerer oveni — heller ikke ved cmd-klik. */}
      <Link href={href ?? personPath(card.personId)} onNavigate={() => onOpen(card)} stopPropagation
        aria-label={`Åbn profil for ${person.name}`}
        style={{ display: 'block', width: '100%', textAlign: 'left' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, paddingRight: 26 }}>
          <Avatar n={person.name} size={42} />
          <div style={{ minWidth: 0 }}>
            <div style={{ fontFamily: T.serif, fontSize: 22, lineHeight: 1.08, fontWeight: 600, color: T.ink }}>{person.name}</div>
            {person.years ? <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 3 }}>{person.years}</div> : null}
          </div>
        </div>
        <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.gold, marginTop: 12 }}>{card.kicker}</div>
        <PersonCardBody card={card} />
      </Link>
      <div style={{ position: 'absolute', top: 18, right: 18 }}><BookmarkFlag active={bookmarked} onClick={() => onSave(card.personId)} /></div>
      <FeedMediaStrip media={media} />
    </article>
  );
}

function PersonCardBody({ card }: { card: PersonCard }) {
  const metaStyle: React.CSSProperties = { fontFamily: T.mono, fontSize: 10.5, color: T.muted2 };
  const source = (kilde: string | null) => kilde ? <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, marginTop: 12 }}>efter {kilde}</div> : null;

  switch (card.kind) {
    case 'portrait':
    case 'dagensperson':
      return <>
        {card.title ? <div style={{ fontFamily: T.sans, fontSize: 13, fontWeight: 500, color: T.bordeaux, marginTop: 7 }}>{card.title}</div> : null}
        <div style={{ fontFamily: T.sans, fontSize: 14, lineHeight: 1.5, color: T.muted, marginTop: 10, display: '-webkit-box', WebkitLineClamp: 5, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{card.bio}</div>
      </>;
    case 'citat':
      return <>
        <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 21, lineHeight: 1.4, color: T.ink, marginTop: 10 }}>{card.quote}</div>
        <div style={{ fontFamily: T.sans, fontSize: 12, color: T.muted2, marginTop: 14 }}>{card.source}</div>
      </>;
    case 'arkiv':
      return <>
        <ArchiveMeta aarLabel={card.aarLabel} kategori={card.kategori} />
        <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 20, lineHeight: 1.4, color: T.ink, marginTop: 9 }}>{card.klausul}</div>
        {source(card.kilde)}
      </>;
    case 'historie':
      return <>
        <ArchiveMeta aarLabel={card.aarLabel} kategori={card.kategori} nyPubliceret={card.nyPubliceret} />
        {card.titel ? <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.ink, marginTop: 8 }}>{card.titel}</div> : null}
        <div style={{ fontFamily: T.sans, fontSize: 14.5, lineHeight: 1.55, color: T.ink, marginTop: 8 }}>{card.tekst}</div>
        {source(card.kilde)}
      </>;
    case 'embede':
      return <>
        <div style={{ fontFamily: T.serif, fontStyle: 'italic', fontSize: 18, marginTop: 8, color: T.ink }}>{card.label}</div>
        <div style={{ ...metaStyle, marginTop: 6 }}>{card.period}</div>
      </>;
    case 'jubilaeum':
      return <>
        <div style={{ fontFamily: T.serif, fontSize: 30, color: T.bordeaux, lineHeight: 1, marginTop: 9 }}>{card.num}</div>
        <div style={{ ...metaStyle, textTransform: 'uppercase', marginTop: 2 }}>år siden</div>
        <div style={{ fontFamily: T.sans, fontSize: 13, color: T.muted2, marginTop: 6 }}>{card.sub}</div>
      </>;
    case 'paadennedag':
      return <>
        <div style={{ fontFamily: T.mono, fontSize: 13, color: T.bordeaux, marginTop: 9 }}>{card.aarstal}</div>
        <div style={{ fontFamily: T.sans, fontSize: 13, color: T.muted2, marginTop: 4 }}>{card.hvad === 'hændelse' ? card.klausul : `${card.hvad === 'født' ? 'Født' : 'Død'} ${card.aarstal}`}</div>
      </>;
  }
}

function ArchiveMeta({ aarLabel, kategori, nyPubliceret }: { aarLabel: string | null; kategori: string | null; nyPubliceret?: boolean }) {
  if (!aarLabel && !kategori && !nyPubliceret) return null;
  return <div style={{ display: 'flex', gap: 9, alignItems: 'center', flexWrap: 'wrap', marginTop: 9 }}>
    {aarLabel ? <span style={{ fontFamily: T.mono, fontSize: 10.5, color: T.bordeaux }}>{aarLabel}</span> : null}
    {kategori ? <span style={{ fontFamily: T.mono, fontSize: 9.5, color: T.muted2 }}>{kategori}</span> : null}
    {nyPubliceret ? <span style={{ fontFamily: T.mono, fontSize: 9.5, color: T.gold }}>Nyt i arkivet</span> : null}
  </div>;
}
