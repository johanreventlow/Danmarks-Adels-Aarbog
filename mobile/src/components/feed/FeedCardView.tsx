// Feed-kort-komponent (spec §4.2). Én switch over FeedCard.kind. Markup porteret fra
// Reventlow-folgesvend-v3.dc.html (sc-if card.isXxx-blokke), styles fra tokens.ts.
// Gem-ikon rendres iff kortet har personId (portrait/citat/embede/jubilaeum).
import { Pressable, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import type { FeedCard } from '../../data/buildFeed';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';
import { StripedPlaceholder } from '../StripedPlaceholder';
import { Body, Kicker, Mono, Serif } from '../Typography';

type Props = {
  card: FeedCard;
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
};

function hasPerson(card: FeedCard): card is Extract<FeedCard, { personId: string }> {
  return 'personId' in card;
}

function SaveIcon({ filled, light, onPress }: { filled: boolean; light?: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} hitSlop={8}>
      <Svg width={15} height={17} viewBox="0 0 17 19">
        <Path
          d="M3 2.2h11a1 1 0 0 1 1 1V16.4a.6.6 0 0 1-.94.5L8.5 13.4l-4.56 3.5A.6.6 0 0 1 3 16.4V3.2a1 1 0 0 1 1-1Z"
          fill={filled ? Colors.bordeaux : 'none'}
          stroke={filled ? Colors.bordeaux : light ? '#cabfa9' : '#7a7060'}
          strokeWidth={1.3}
        />
      </Svg>
    </Pressable>
  );
}

const cardBase = {
  backgroundColor: Colors.paperCard,
  borderWidth: 1,
  borderColor: Border.light,
  borderRadius: Radius.card,
  ...Shadow.card,
} as const;

export function FeedCardView({ card, onOpen, onSave, bookmarked }: Props) {
  const save = hasPerson(card) ? (
    <SaveIcon filled={bookmarked} onPress={() => onSave(card.personId)} />
  ) : null;

  switch (card.kind) {
    case 'portrait':
      return (
        <View style={[cardBase, { padding: 15 }]}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <Kicker size={8.5} color={Colors.bordeaux}>{card.kicker}</Kicker>
            {save}
          </View>
          <Serif size={24} style={{ marginTop: 5, lineHeight: 24 }}>{card.name}</Serif>
          <Mono size={10} color={Colors.textMuted2} style={{ marginTop: 4 }}>{card.years}</Mono>
          {card.title ? (
            <Body size={12} color={Colors.bordeaux} style={{ marginTop: 4, fontFamily: Fonts.sansMedium }}>{card.title}</Body>
          ) : null}
          <Body size={13} color={Colors.textSecondary} numberOfLines={5} style={{ marginTop: 11, lineHeight: 20 }}>{card.bio}</Body>
          <Pressable onPress={() => onOpen(card)} style={{ paddingVertical: 8 }}>
            <Body size={12.5} color={Colors.bordeaux} style={{ fontFamily: Fonts.sansSemi }}>Læs mere ›</Body>
          </Pressable>
        </View>
      );

    case 'citat':
      return (
        <View style={{ backgroundColor: Colors.ink, borderRadius: Radius.card, padding: 20 }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <Kicker size={8} color={Colors.gold}>{card.kicker}</Kicker>
            {hasPerson(card) ? <SaveIcon filled={bookmarked} light onPress={() => onSave(card.personId)} /> : null}
          </View>
          <Pressable onPress={() => onOpen(card)}>
            <Serif size={21} italic color={Colors.paperBg} style={{ marginTop: 12, lineHeight: 28, fontFamily: Fonts.serifItalic }}>
              {card.quote}
            </Serif>
          </Pressable>
          <Body size={11} color="#cabfa9" style={{ marginTop: 14 }}>{card.source}</Body>
        </View>
      );

    case 'gods':
      return (
        <Pressable onPress={() => onOpen(card)} style={[cardBase, { padding: 15 }]}>
          <Kicker size={8.5} color={Colors.gold}>{card.kicker}</Kicker>
          <View style={{ flexDirection: 'row', gap: 12, alignItems: 'center', marginTop: 8 }}>
            <View style={{ width: 44, height: 44, borderRadius: 11, backgroundColor: Colors.beige, borderWidth: 1, borderColor: Border.light, alignItems: 'center', justifyContent: 'center' }}>
              <Serif size={20} color={Colors.bordeaux}>⌂</Serif>
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Serif size={23} style={{ lineHeight: 24 }}>{card.navn}</Serif>
              <Body size={12.5} color={Colors.textSecondary2} style={{ marginTop: 2 }}>{card.meta}</Body>
            </View>
            <Serif size={20} color={Colors.bordeaux}>›</Serif>
          </View>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 13, flexWrap: 'wrap' }}>
            {Array.from({ length: card.ownerDots }).map((_, i) => (
              <View key={i} style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: '#d8ccb4' }} />
            ))}
            <Mono size={8.5} color={Colors.textMuted2} style={{ marginLeft: 4 }}>ejer-tidslinje</Mono>
          </View>
        </Pressable>
      );

    case 'forbundet':
      return (
        <View style={{ backgroundColor: Colors.beige, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.card, padding: 16 }}>
          <Kicker size={8.5} color={Colors.gold}>{card.kicker}</Kicker>
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 14, marginTop: 8 }}>
            <View style={{ flex: 1, alignItems: 'center' }}>
              <View style={styles.pairAvatar}><Serif size={18} color={Colors.bordeaux}>{card.aInit}</Serif></View>
              <Serif size={15} style={{ marginTop: 6, textAlign: 'center', lineHeight: 16 }}>{card.aName}</Serif>
            </View>
            <Serif size={24} italic color={Colors.bordeaux} style={{ fontFamily: Fonts.serifItalic }}>&amp;</Serif>
            <View style={{ flex: 1, alignItems: 'center' }}>
              <View style={styles.pairAvatar}><Serif size={18} color={Colors.bordeaux}>{card.bInit}</Serif></View>
              <Serif size={15} style={{ marginTop: 6, textAlign: 'center', lineHeight: 16 }}>{card.bName}</Serif>
            </View>
          </View>
          <Body size={11.5} color={Colors.textSecondary2} style={{ textAlign: 'center', marginTop: 11 }}>{card.marBottom}</Body>
        </View>
      );

    case 'slaegt':
      return (
        <Pressable onPress={() => onOpen(card)} style={{ backgroundColor: Colors.ink, borderRadius: Radius.card, padding: 17, borderWidth: 1, borderColor: 'rgba(231,201,143,0.14)' }}>
          <Kicker size={8} color={Colors.gold}>{card.kicker}</Kicker>
          <Serif size={20} color={Colors.paperBg} style={{ marginTop: 9, lineHeight: 26 }}>
            <Serif size={20} color={Colors.goldLight}>{card.aName}</Serif> og <Serif size={20} color={Colors.goldLight}>{card.bName}</Serif> — {card.rel}
          </Serif>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 12 }}>
            <Body size={11.5} color={Colors.goldLight} style={{ fontFamily: Fonts.sansSemi }}>{card.foot}</Body>
          </View>
        </Pressable>
      );

    case 'embede':
      return (
        <View style={[cardBase, { padding: 15 }]}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <Kicker size={8.5} color={Colors.gold}>{card.kicker}</Kicker>
            {save}
          </View>
          <Serif size={19} italic style={{ marginTop: 7, lineHeight: 25, fontFamily: Fonts.serifItalic }}>{card.label}</Serif>
          <Pressable onPress={() => onOpen(card)} style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 11 }}>
            <View style={{ width: 34, height: 34, borderRadius: Radius.round, backgroundColor: Colors.beige, borderWidth: 1, borderColor: Border.light, alignItems: 'center', justifyContent: 'center' }}>
              <Serif size={14} color={Colors.bordeaux}>{card.init}</Serif>
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Body size={13} color={Colors.ink} style={{ fontFamily: Fonts.sansSemi }}>{card.name}</Body>
              <Mono size={9.5} color={Colors.textMuted2}>{card.period}</Mono>
            </View>
            <Serif size={16} color={Colors.bordeaux}>›</Serif>
          </Pressable>
        </View>
      );

    case 'jubilaeum':
      return (
        <View style={[cardBase, { padding: 15, flexDirection: 'row', gap: 14, alignItems: 'center' }]}>
          <View style={{ width: 58, alignItems: 'center' }}>
            <Serif size={32} color={Colors.bordeaux} style={{ lineHeight: 32 }}>{card.num}</Serif>
            <Mono size={8} color={Colors.textMuted2} style={{ marginTop: 2, textTransform: 'uppercase' }}>år siden</Mono>
          </View>
          <View style={{ width: 1, height: 44, backgroundColor: Border.medium }} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Kicker size={8.5} color={Colors.gold}>{card.kicker}</Kicker>
            <Pressable onPress={() => onOpen(card)}>
              <Serif size={20} style={{ marginTop: 3, lineHeight: 21 }}>{card.name}</Serif>
            </Pressable>
            <Body size={12} color={Colors.textSecondary2} style={{ marginTop: 2 }}>{card.sub}</Body>
          </View>
          {save}
        </View>
      );

    case 'vaaben':
      return (
        <Pressable onPress={() => onOpen(card)} style={[cardBase, { padding: 15, flexDirection: 'row', gap: 14, alignItems: 'center' }]}>
          <StripedPlaceholder width={66} height={82} label="våben" />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Kicker size={8.5} color={Colors.gold}>{card.kicker}</Kicker>
            <Serif size={16} italic style={{ marginTop: 6, lineHeight: 21, fontFamily: Fonts.serifItalic }}>{card.blazon}</Serif>
            <Body size={11.5} color={Colors.bordeaux} style={{ marginTop: 8, fontFamily: Fonts.sansMedium }}>{card.foot}</Body>
          </View>
        </Pressable>
      );

    case 'samle':
      return (
        <Pressable onPress={() => onOpen(card)} style={{ borderWidth: 1, borderStyle: 'dashed', borderColor: 'rgba(34,31,26,0.22)', borderRadius: Radius.card, padding: 14 }}>
          <Kicker size={8} color={Colors.textMuted2}>{card.kicker}</Kicker>
          <Serif size={18} color="#5a5246" style={{ marginTop: 6, lineHeight: 23 }}>
            …og <Serif size={18} color={Colors.bordeaux}>{card.count} flere</Serif> {card.tail}
          </Serif>
          <Body size={11.5} color={Colors.textSecondary2} style={{ marginTop: 7 }}>
            For sparsomme til et eget blad — se dem samlet i registeret ›
          </Body>
        </Pressable>
      );

    default:
      return null;
  }
}

const styles = {
  pairAvatar: {
    width: 48, height: 48, borderRadius: Radius.round, backgroundColor: Colors.paperCard,
    borderWidth: 1, borderColor: Border.light, alignItems: 'center', justifyContent: 'center',
  },
} as const;
