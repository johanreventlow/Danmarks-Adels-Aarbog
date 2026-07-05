// Forsidens top-bar (spec §4.1, design isHome-topbar). Hamburger venstre, kompakt brand
// (fader ind på scroll), bogmærke-ikon m. badge højre.
import { Image } from 'expo-image';
import { useEffect } from 'react';
import { Pressable, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import Svg, { Path } from 'react-native-svg';
import { Border, Colors, Fonts } from '../theme/tokens';
import { Mono, Serif } from './Typography';

export function HomeTopBar({
  onMenu,
  onBookmarks,
  savedCount,
  showBrand,
  topInset,
}: {
  onMenu: () => void;
  onBookmarks: () => void;
  savedCount: number;
  showBrand: boolean;
  topInset: number;
}) {
  const brand = useSharedValue(0);
  useEffect(() => {
    brand.value = withTiming(showBrand ? 1 : 0, { duration: 180 });
  }, [showBrand, brand]);
  const brandStyle = useAnimatedStyle(() => ({ opacity: brand.value }));

  return (
    <View
      style={{
        paddingTop: topInset,
        height: 52 + topInset,
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
        <Svg width={17} height={19} viewBox="0 0 17 19">
          <Path d="M3 2.2h11a1 1 0 0 1 1 1V16.4a.6.6 0 0 1-.94.5L8.5 13.4l-4.56 3.5A.6.6 0 0 1 3 16.4V3.2a1 1 0 0 1 1-1Z" stroke="#7a7060" strokeWidth={1.3} fill="none" />
        </Svg>
        {savedCount > 0 ? (
          <View style={{ position: 'absolute', top: 4, right: 4, minWidth: 14, height: 14, paddingHorizontal: 3, borderRadius: 8, backgroundColor: Colors.bordeaux, alignItems: 'center', justifyContent: 'center' }}>
            <Mono size={8} color={Colors.paperBg}>{savedCount}</Mono>
          </View>
        ) : null}
      </Pressable>
    </View>
  );
}
