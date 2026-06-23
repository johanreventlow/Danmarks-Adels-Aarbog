// Tekstur-overlay — README §6. Lægges øverst i z-stakken, pointer-events none.
// Vignet: radial-gradient (tro mod §6-værdier) via react-native-svg.
// Film-korn: opacity-tilnærmelse (beslutning 1b) — RN-core har ikke mix-blend-mode:multiply
// eller pålidelig feTurbulence på tværs af Hermes/iOS/Android. Vi lægger et meget svagt,
// fladt korn-lag som pladsholder; kan opgraderes til Skia-baseret blend hvis æstetikken kræver.
import { StyleSheet, View } from 'react-native';
import Svg, { Defs, RadialGradient, Rect, Stop } from 'react-native-svg';

export function TextureOverlay() {
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none">
      {/* Vignet: radial(118% 90% at 50% 22%, transparent 56% → rgba(54,40,22,.09) 100%).
          pointerEvents="none" SKAL sættes direkte på Svg — RN-svg's native lag arver ikke
          parentens pointerEvents pålideligt på iOS, og opfanger ellers scroll-pan-gestus. */}
      <Svg style={StyleSheet.absoluteFill} width="100%" height="100%" pointerEvents="none">
        <Defs>
          <RadialGradient id="vignet" cx="50%" cy="22%" rx="59%" ry="45%">
            <Stop offset="56%" stopColor="rgb(54,40,22)" stopOpacity={0} />
            <Stop offset="100%" stopColor="rgb(54,40,22)" stopOpacity={0.09} />
          </RadialGradient>
        </Defs>
        <Rect x="0" y="0" width="100%" height="100%" fill="url(#vignet)" />
      </Svg>
      {/* Film-korn (opacity-tilnærmelse, 1b) — meget svagt, ingen blend. */}
      <View style={styles.grain} pointerEvents="none" />
    </View>
  );
}

const styles = StyleSheet.create({
  grain: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(54,40,22,0.015)',
  },
});
