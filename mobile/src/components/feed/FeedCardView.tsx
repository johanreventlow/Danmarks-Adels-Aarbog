// Feed-kort — personkort går gennem den fælles sociale shell; de øvrige kort beholder deres
// eksisterende særformater og navigation.
import { memo } from 'react';
import { Pressable, View } from 'react-native';
import type { FeedCard } from '@daa/feed';
import type { RawMedia } from '../../data/types';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';
import { InitialBadge } from '../InitialBadge';
import { StripedPlaceholder } from '../StripedPlaceholder';
import { Body, Kicker, Mono, Serif } from '../Typography';
import { PersonFeedCardView, type PersonIdentity } from './PersonFeedCardView';

type Props = {
  card: FeedCard;
  onOpen: (card: FeedCard) => void;
  onSave: (personId: string) => void;
  bookmarked: boolean;
  person?: PersonIdentity;
  rawMedia?: RawMedia[];
  ownerKey?: string | null;
};

const cardBase = {
  backgroundColor: Colors.paperCard,
  borderWidth: 1,
  borderColor: Border.light,
  borderRadius: Radius.card,
  ...Shadow.card,
} as const;
const cardBase15 = { ...cardBase, padding: 15 } as const;

function FeedCardViewImpl({ card, onOpen, onSave, bookmarked, person, rawMedia = [], ownerKey }: Props) {
  if ('personId' in card) {
    const fallbackName = 'name' in card ? card.name : `#${card.personId}`;
    const fallbackYears = 'years' in card ? card.years : '';
    return <PersonFeedCardView card={card} person={person ?? { name: fallbackName, years: fallbackYears }} rawMedia={rawMedia} ownerKey={ownerKey} onOpen={onOpen} onSave={onSave} bookmarked={bookmarked} />;
  }

  switch (card.kind) {
    case 'gods':
      return (
        <Pressable onPress={() => onOpen(card)} style={cardBase15}>
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
            {Array.from({ length: card.ownerDots }).map((_, i) => <View key={i} style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: '#d8ccb4' }} />)}
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
              <InitialBadge name={card.aInit} size={48} bg={Colors.paperCard} borderColor={Border.light} />
              <Serif size={15} style={{ marginTop: 6, textAlign: 'center', lineHeight: 16 }}>{card.aName}</Serif>
            </View>
            <Serif size={24} italic color={Colors.bordeaux} style={{ fontFamily: Fonts.serifItalic }}>&amp;</Serif>
            <View style={{ flex: 1, alignItems: 'center' }}>
              <InitialBadge name={card.bInit} size={48} bg={Colors.paperCard} borderColor={Border.light} />
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
          <Serif size={20} color={Colors.paperBg} style={{ marginTop: 9, lineHeight: 26 }}><Serif size={20} color={Colors.goldLight}>{card.aName}</Serif> og <Serif size={20} color={Colors.goldLight}>{card.bName}</Serif> — {card.rel}</Serif>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 12 }}><Body size={11.5} color={Colors.goldLight} style={{ fontFamily: Fonts.sansSemi }}>{card.foot}</Body></View>
        </Pressable>
      );
    case 'vaaben':
      return (
        <Pressable onPress={() => onOpen(card)} style={{ ...cardBase15, flexDirection: 'row', gap: 14, alignItems: 'center' }}>
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
          <Serif size={18} color="#5a5246" style={{ marginTop: 6, lineHeight: 23 }}>…og <Serif size={18} color={Colors.bordeaux}>{card.count} flere</Serif> {card.tail}</Serif>
          <Body size={11.5} color={Colors.textSecondary2} style={{ marginTop: 7 }}>For sparsomme til et eget blad — se dem samlet i registeret ›</Body>
        </Pressable>
      );
  }
}

export const FeedCardView = memo(FeedCardViewImpl);
