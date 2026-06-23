// Rund initial-badge — bruges på person-kort, lister, avatarer (README §5).
import { StyleSheet, View } from 'react-native';
import { Colors, Fonts, Radius } from '../theme/tokens';
import { Serif } from './Typography';

function initial(name: string): string {
  const t = (name || '').trim();
  if (!t) return '?';
  return t[0].toUpperCase();
}

export function InitialBadge({
  name,
  size = 44,
  bg = Colors.beige,
  color = Colors.bordeaux,
}: {
  name: string;
  size?: number;
  bg?: string;
  color?: string;
}) {
  return (
    <View
      style={[
        styles.badge,
        { width: size, height: size, borderRadius: Radius.round, backgroundColor: bg },
      ]}>
      <Serif size={size * 0.42} color={color} style={{ fontFamily: Fonts.serifSemi }}>
        {initial(name)}
      </Serif>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: { alignItems: 'center', justifyContent: 'center' },
});
