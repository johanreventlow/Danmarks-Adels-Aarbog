import { useState } from 'react';
import { Image } from 'expo-image';
import { Pressable, ScrollView, View, type LayoutChangeEvent } from 'react-native';
import { Lightbox } from '../Lightbox';
import { Border, Colors, Radius } from '../../theme/tokens';
import type { MobileFeedMediaItem } from '../../lib/feedMedia';

export function FeedMediaStrip({ media }: { media: MobileFeedMediaItem[] }) {
  const [width, setWidth] = useState(0);
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  if (media.length === 0) return null;

  const itemWidth = width > 0 ? (media.length === 1 ? width : Math.round(width * 0.78)) : undefined;
  const onLayout = (event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width);

  return (
    <>
      <View style={{ marginTop: 14 }} onLayout={onLayout}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          decelerationRate="fast"
          snapToAlignment="start"
          snapToInterval={media.length > 1 && itemWidth ? itemWidth + 8 : undefined}
          contentContainerStyle={{ gap: 8 }}
          accessibilityLabel="Billeder tilknyttet personen"
        >
          {media.map((item, index) => {
            const label = item.titel || item.slags || 'medie';
            return (
              <Pressable
                key={item.id}
                accessibilityRole="button"
                accessibilityLabel={`Åbn billede: ${label}`}
                onPress={() => setOpenIndex(index)}
                style={{ width: itemWidth, height: 220, backgroundColor: Colors.beige, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.card, overflow: 'hidden' }}
              >
                <Image source={{ uri: item.mediumUri }} style={{ width: '100%', height: '100%' }} contentFit="contain" />
              </Pressable>
            );
          })}
        </ScrollView>
      </View>
      {openIndex !== null ? (
        <Lightbox
          items={media.map((item) => ({ id: item.id, uri: item.largeUri, titel: item.titel, kunstner: item.kunstner, datering: item.datering }))}
          index={openIndex}
          onClose={() => setOpenIndex(null)}
          onNavigate={setOpenIndex}
        />
      ) : null}
    </>
  );
}
