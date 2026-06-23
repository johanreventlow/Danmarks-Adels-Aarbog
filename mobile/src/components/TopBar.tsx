// Top bar — README §4: 52px, tilbage-pil (‹) når relevant + centreret titel i Cormorant.
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Border, Colors, Fonts } from '../theme/tokens';
import { Serif } from './Typography';

export function TopBar({ title, showBack = true }: { title: string; showBack?: boolean }) {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.wrap, { paddingTop: insets.top }]}>
      <View style={styles.bar}>
        <View style={styles.side}>
          {showBack && router.canGoBack() ? (
            <Pressable hitSlop={12} onPress={() => router.back()}>
              <Ionicons name="chevron-back" size={26} color={Colors.bordeaux} />
            </Pressable>
          ) : null}
        </View>
        <Serif size={19} style={styles.title} numberOfLines={1}>
          {title}
        </Serif>
        <View style={styles.side} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    backgroundColor: Colors.paperBg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.light,
  },
  bar: {
    height: 52,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
  },
  side: { width: 40, justifyContent: 'center' },
  title: { flex: 1, textAlign: 'center', fontFamily: Fonts.serifSemi },
});
