// Forsidens top-bar (spec §4.1, design isHome-topbar). Hamburger venstre, kompakt brand
// (fader ind på scroll), bogmærke-ikon m. badge højre.
import { Image } from 'expo-image';
import { useEffect } from 'react';
import { Pressable, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Border, Colors, Fonts } from '../theme/tokens';
import { BookmarkIcon } from './BookmarkIcon';
import { Mono, Serif } from './Typography';

export function HomeTopBar({
  onMenu,
  onBookmarks,
  savedCount,
  showBrand,
}: {
  onMenu: () => void;
  onBookmarks: () => void;
  savedCount: number;
  showBrand: boolean;
}) {
  const insets = useSafeAreaInsets();
  const brand = useSharedValue(0);
  useEffect(() => {
    brand.value = withTiming(showBrand ? 1 : 0, { duration: 180 });
  }, [showBrand, brand]);
  const brandStyle = useAnimatedStyle(() => ({ opacity: brand.value }));

  return (
    <View
      style={{
        paddingTop: insets.top,
        height: 52 + insets.top,
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 8,
        borderBottomWidth: 1,
        borderBottomColor: Border.faint,
        backgroundColor: 'rgba(244,239,230,0.94)',
      }}>
      <Pressable onPress={onMenu} hitSlop={8} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center', gap: 4 }}>
        <View style={{ width: 17, height: 1.6, backgroundColor: Colors.ink, borderRadius: 2 }} />
        <View style={{ width: 17, height: 1.6, backgroundColor: Colors.ink, borderRadius: 2 }} />
        <View style={{ width: 11, height: 1.6, backgroundColor: Colors.ink, borderRadius: 2 }} />
      </Pressable>

      <Animated.View style={[{ flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 }, brandStyle]}>
        <Image source={require('../../assets/daf-logo.png')} style={{ width: 22, height: 22 }} contentFit="contain" />
        <Serif size={19} style={{ lineHeight: 19, fontFamily: Fonts.serifSemi }}>Reventlow</Serif>
      </Animated.View>

      <Pressable onPress={onBookmarks} hitSlop={8} style={{ width: 40, height: 40, alignItems: 'center', justifyContent: 'center' }}>
        <BookmarkIcon width={17} height={19} />
        {savedCount > 0 ? (
          <View style={{ position: 'absolute', top: 4, right: 4, minWidth: 14, height: 14, paddingHorizontal: 3, borderRadius: 8, backgroundColor: Colors.bordeaux, alignItems: 'center', justifyContent: 'center' }}>
            <Mono size={8} color={Colors.paperBg}>{savedCount}</Mono>
          </View>
        ) : null}
      </Pressable>
    </View>
  );
}
