// Crest-krans — designets slægts-segl: ring (ikke fyldt badge) med dobbelt-kant og
// Cormorant-bogstav i midten. Gengiver inset-box-shadow-tricket fra .dc.html med en
// indre ring-View. Bruges i slægts-chip (31px) m.fl.
import { StyleSheet, View } from 'react-native';
import { Colors, Fonts, Radius } from '../theme/tokens';
import { Serif } from './Typography';

export function CrestRing({
  letter,
  size = 31,
  color = Colors.bordeaux,
  ringColor = 'rgba(136,26,51,0.55)',
  innerRingColor = 'rgba(136,26,51,0.28)',
}: {
  letter: string;
  size?: number;
  color?: string;
  ringColor?: string;
  innerRingColor?: string;
}) {
  return (
    <View
      style={[
        styles.outer,
        { width: size, height: size, borderRadius: Radius.round, borderColor: ringColor },
      ]}>
      <View
        style={[
          styles.inner,
          { borderRadius: Radius.round, borderColor: innerRingColor },
        ]}
      />
      <Serif size={size * 0.5} color={color} style={{ fontFamily: Fonts.serifSemi }}>
        {letter}
      </Serif>
    </View>
  );
}

const styles = StyleSheet.create({
  outer: {
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    backgroundColor: 'transparent',
  },
  inner: {
    position: 'absolute',
    top: 2,
    left: 2,
    right: 2,
    bottom: 2,
    borderWidth: 1,
  },
});
