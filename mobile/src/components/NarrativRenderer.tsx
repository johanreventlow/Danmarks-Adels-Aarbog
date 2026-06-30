// Klikbar visning af fri-tekst med hyperlink-tokens (spec §5.2). Mirror'er Typography.Body's
// API (size/color/style/numberOfLines) så den kan substituere en ren <Body>-brug 1:1 uden at
// ændre klamp- eller font-adfærd (fx bio-klamp i app/person/[id].tsx).
import React from 'react';
import { Text, StyleSheet, type TextStyle } from 'react-native';
import { useRouter } from 'expo-router';
import { parseNarrativ } from '../lib/mentions';
import { Colors, Fonts } from '../theme/tokens';

export function NarrativRenderer(props: {
  tekst: string;
  size?: number;
  color?: string;
  style?: TextStyle;
  numberOfLines?: number;
}) {
  const { tekst, size = 14, color = Colors.textSecondary, style, numberOfLines } = props;
  const router = useRouter();
  const segs = parseNarrativ(tekst);
  const body: TextStyle = { fontFamily: Fonts.sans, fontSize: size, lineHeight: size * 1.5, color };
  return (
    <Text style={[body, style]} numberOfLines={numberOfLines}>
      {segs.map((s, i) => {
        if (s.kind === 'text') return <Text key={i}>{s.text}</Text>;
        if (s.maalType === 'person') {
          return (
            <Text key={i} style={styles.link} onPress={() => router.push(`/person/${s.maalId}`)}
              accessibilityRole="link">
              {s.label}
            </Text>
          );
        }
        return <Text key={i} style={styles.linkInaktiv}>{s.label}</Text>;
      })}
    </Text>
  );
}

const styles = StyleSheet.create({
  link: { color: Colors.bordeaux, textDecorationLine: 'underline' },
  linkInaktiv: { color: Colors.textMuted },
});
