import type { FeedCard } from '@daa/feed';
import { Pressable, View } from 'react-native';
import type { RawMedia } from '../../data/types';
import { useMobileFeedMedia } from '../../lib/feedMedia';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';
import { BookmarkIcon } from '../BookmarkIcon';
import { InitialBadge } from '../InitialBadge';
import { Body, Kicker, Mono, Serif } from '../Typography';
import { FeedMediaStrip } from './FeedMediaStrip';

export type PersonCard = Extract<FeedCard, { personId: string }>;
export type PersonIdentity = { name: string; years: string };

const cardBase = {
  backgroundColor: Colors.paperCard,
  borderWidth: 1,
  borderColor: Border.light,
  borderRadius: Radius.card,
  padding: 15,
  ...Shadow.card,
} as const;

export function PersonFeedCardView({ card, person, rawMedia, onOpen, onSave, bookmarked }: {
  card: PersonCard;
  person: PersonIdentity;
  rawMedia: RawMedia[];
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
}) {
  const media = useMobileFeedMedia(card, card.personId, rawMedia);

  return (
    <View style={[cardBase, { position: 'relative' }]}>
      <Pressable accessibilityRole="button" accessibilityLabel={`Åbn profil for ${person.name}`} onPress={() => onOpen(card)} style={{ paddingRight: 28 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 11 }}>
          <InitialBadge name={person.name} size={42} bg={Colors.beige} borderColor={Border.light} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Serif size={22} style={{ lineHeight: 24 }}>{person.name}</Serif>
            {person.years ? <Mono size={10} color={Colors.textMuted2} style={{ marginTop: 3 }}>{person.years}</Mono> : null}
          </View>
        </View>
        <Kicker size={8.5} color={Colors.gold} style={{ marginTop: 12 }}>{card.kicker}</Kicker>
        <PersonCardBody card={card} />
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={bookmarked ? `Fjern gemning af ${person.name}` : `Gem ${person.name}`}
        onPress={() => onSave(card.personId)}
        hitSlop={8}
        style={{ position: 'absolute', top: 15, right: 15, padding: 2 }}
      >
        <BookmarkIcon filled={bookmarked} />
      </Pressable>
      <FeedMediaStrip media={media} />
    </View>
  );
}

function PersonCardBody({ card }: { card: PersonCard }) {
  const source = (kilde: string | null) => kilde ? <Body size={10.5} color={Colors.textMuted2} style={{ marginTop: 12 }}>efter {kilde}</Body> : null;

  switch (card.kind) {
    case 'portrait':
    case 'dagensperson':
      return <>
        {card.title ? <Body size={12} color={Colors.bordeaux} style={{ marginTop: 7, fontFamily: Fonts.sansMedium }}>{card.title}</Body> : null}
        <Body size={13} color={Colors.textSecondary} numberOfLines={5} style={{ marginTop: 10, lineHeight: 20 }}>{card.bio}</Body>
      </>;
    case 'citat':
      return <>
        <Serif size={21} italic style={{ marginTop: 10, lineHeight: 29, fontFamily: Fonts.serifItalic }}>{card.quote}</Serif>
        <Body size={11} color={Colors.textMuted2} style={{ marginTop: 14 }}>{card.source}</Body>
      </>;
    case 'arkiv':
      return <>
        <ArchiveMeta aarLabel={card.aarLabel} kategori={card.kategori} />
        <Serif size={20} italic style={{ marginTop: 9, lineHeight: 27, fontFamily: Fonts.serifItalic }}>{card.klausul}</Serif>
        {source(card.kilde)}
      </>;
    case 'historie':
      return <>
        <ArchiveMeta aarLabel={card.aarLabel} kategori={card.kategori} nyPubliceret={card.nyPubliceret} />
        {card.titel ? <Serif size={22} style={{ marginTop: 8, lineHeight: 25 }}>{card.titel}</Serif> : null}
        <Body size={13.5} color={Colors.ink} style={{ marginTop: 8, lineHeight: 21 }}>{card.tekst}</Body>
        {source(card.kilde)}
      </>;
    case 'embede':
      return <>
        <Serif size={18} italic style={{ marginTop: 8, fontFamily: Fonts.serifItalic }}>{card.label}</Serif>
        <Mono size={9.5} color={Colors.textMuted2} style={{ marginTop: 6 }}>{card.period}</Mono>
      </>;
    case 'jubilaeum':
      return <>
        <Serif size={30} color={Colors.bordeaux} style={{ marginTop: 9, lineHeight: 30 }}>{card.num}</Serif>
        <Mono size={8} color={Colors.textMuted2} style={{ marginTop: 2, textTransform: 'uppercase' }}>år siden</Mono>
        <Body size={12} color={Colors.textSecondary2} style={{ marginTop: 6 }}>{card.sub}</Body>
      </>;
    case 'paadennedag':
      return <>
        <Mono size={12} color={Colors.bordeaux} style={{ marginTop: 9 }}>{card.aarstal}</Mono>
        <Body size={12} color={Colors.textSecondary2} style={{ marginTop: 4 }}>
          {card.hvad === 'hændelse' ? card.klausul : `${card.hvad === 'født' ? 'Født' : 'Død'} ${card.aarstal}`}
        </Body>
      </>;
  }
}

function ArchiveMeta({ aarLabel, kategori, nyPubliceret }: { aarLabel: string | null; kategori: string | null; nyPubliceret?: boolean }) {
  if (!aarLabel && !kategori && !nyPubliceret) return null;
  return (
    <View style={{ flexDirection: 'row', gap: 8, marginTop: 9, alignItems: 'center', flexWrap: 'wrap' }}>
      {aarLabel ? <Mono size={9.5} color={Colors.bordeaux}>{aarLabel}</Mono> : null}
      {kategori ? <Mono size={8.5} color={Colors.textMuted2}>{kategori}</Mono> : null}
      {nyPubliceret ? <Mono size={8.5} color={Colors.gold}>Nyt i arkivet</Mono> : null}
    </View>
  );
}
