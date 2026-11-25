import { useState } from 'react';
import { SignedImage } from '../SignedImage';
import { Pressable, ScrollView, View, type LayoutChangeEvent } from 'react-native';
import { Lightbox } from '../Lightbox';
import { Border, Colors, Radius } from '../../theme/tokens';
import type { MobileFeedMediaItem } from '../../lib/feedMedia';

export function FeedMediaStrip({ media }: { media: MobileFeedMediaItem[] }) {
  const [width, setWidth] = useState(0);
  const [ratios, setRatios] = useState<Record<string, number>>({});
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  if (media.length === 0) return null;

  const onLayout = (event: LayoutChangeEvent) => setWidth(event.nativeEvent.layout.width);

  return (
    <>
      <View style={{ marginTop: 14 }} onLayout={onLayout}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          decelerationRate="fast"
          contentContainerStyle={{ gap: 8 }}
          accessibilityLabel="Billeder tilknyttet personen"
        >
          {media.map((item, index) => {
            const label = item.titel || item.slags || 'medie';
            const ratio = ratios[item.id];
            const natural = ratio ? Math.round(220 * ratio) : 160;
            const itemWidth = width > 0 ? Math.min(natural, width) : natural;
            return (
              <Pressable
                key={item.id}
                accessibilityRole="button"
                accessibilityLabel={`Åbn billede: ${label}`}
                onPress={() => setOpenIndex(index)}
                style={{ width: itemWidth, height: 220, backgroundColor: Colors.surfaceSunken, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.card, overflow: 'hidden' }}
              >
                <SignedImage
                  uri={item.mediumUri}
                  style={{ width: '100%', height: '100%' }}
                  contentFit="contain"
                  onLoad={(event) => {
                    const { width: w, height: h } = event.source;
                    if (w > 0 && h > 0) setRatios((prev) => (prev[item.id] ? prev : { ...prev, [item.id]: w / h }));
                  }}
                />
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
