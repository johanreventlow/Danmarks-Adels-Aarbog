// Stribet medie-pladsholder — designets repeating-linear-gradient(45deg, #ece4d6/#e2d8c8).
// RN-core har ingen repeating-gradient; gengivet med react-native-svg Pattern (45° striber).
// README §3: stribede pladsholdere er bevidst tom-tilstand — genskab dem, ikke tilfældige billeder.
import { StyleSheet, View } from 'react-native';
import Svg, { Defs, Line, Pattern, Rect } from 'react-native-svg';
import { Border, Colors, Fonts } from '../theme/tokens';
import { Mono } from './Typography';

export function StripedPlaceholder({
  width,
  height,
  radius = 11,
  label,
  style,
}: {
  width?: number;
  height?: number;
  radius?: number;
  label?: string;
  style?: object;
}) {
  return (
    <View
      style={[
        styles.box,
        { borderRadius: radius, borderColor: Border.medium },
        width != null ? { width } : null,
        height != null ? { height } : null,
        style,
      ]}>
      <Svg width="100%" height="100%" style={StyleSheet.absoluteFill}>
        <Defs>
          <Pattern id="stripe" width={18} height={18} patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <Rect width={18} height={18} fill="#ece4d6" />
            <Line x1={4.5} y1={0} x2={4.5} y2={18} stroke="#e2d8c8" strokeWidth={9} />
          </Pattern>
        </Defs>
        <Rect x={0} y={0} width="100%" height="100%" fill="url(#stripe)" rx={radius} />
      </Svg>
      {label ? (
        <Mono size={8.5} color={Colors.textSecondary2} style={{ fontFamily: Fonts.mono }}>
          {label}
        </Mono>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  box: {
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
    justifyContent: 'flex-end',
    padding: 8,
  },
});
