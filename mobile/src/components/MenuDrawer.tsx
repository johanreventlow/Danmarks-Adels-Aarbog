// Venstre menu-drawer (spec §5, design drawerX-blok). Slægt-header + nummereret nav-liste
// (flyttet ud af forsiden) + konto-footer. Åbnes fra HomeTopBar's hamburger.
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useStore } from '../store/useStore';
import { Border, Colors, Fonts } from '../theme/tokens';
import { CrestRing } from './CrestRing';
import { SlaegtPicker } from './SlaegtPicker';
import { Body, BtnLabel, Kicker, Serif } from './Typography';

const DRAWER_W = 314;

type NavItem = { no: string; title: string; sub: string; href: string };
const NAV: NavItem[] = [
  { no: '01', title: 'Stamtræ', sub: 'Naviger op, ned og til siden', href: '/tree' },
  { no: '02', title: 'Om slægten', sub: 'Historisk indledning', href: '/about' },
  { no: '03', title: 'Godser & ejendomme', sub: 'Besiddelser og deres ejere', href: '/estates' },
  { no: '04', title: 'Slægtens kort', sub: 'Steder på kort', href: '/kort' },
  { no: '05', title: 'Slægtens våben', sub: 'Autoriseret våben og gengivelser', href: '/arms' },
  { no: '06', title: 'Er vi i familie?', sub: 'Find slægtskabet', href: '/relate' },
  { no: '07', title: 'Søg', sub: 'Bladr blandt personer', href: '/search' },
  { no: '08', title: 'Bogmærker', sub: 'Blade du har gemt', href: '/bogmaerker' },
  { no: '09', title: 'Præsensliste', sub: 'Levende medlemmer efter linje og gren', href: '/praesens' },
];

export function MenuDrawer({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const session = useStore((s) => s.session);
  const personCount = useStore((s) => s.model?.persons.length ?? 0);
  const doSignOut = useStore((s) => s.doSignOut);

  const [slaegtOpen, setSlaegtOpen] = useState(false);
  const prog = useSharedValue(0); // 0 = lukket, 1 = åben
  useEffect(() => {
    prog.value = withTiming(visible ? 1 : 0, { duration: 320 });
  }, [visible, prog]);
  const scrimStyle = useAnimatedStyle(() => ({ opacity: prog.value }));
  const drawerStyle = useAnimatedStyle(() => ({ transform: [{ translateX: (prog.value - 1) * DRAWER_W }] }));

  const go = (href: string) => {
    onClose();
    router.push(href as never);
  };

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose}>
      <Animated.View style={[{ position: 'absolute', top: 0, bottom: 0, left: 0, right: 0, backgroundColor: 'rgba(20,17,13,0.4)' }, scrimStyle]}>
        <Pressable style={{ flex: 1 }} onPress={onClose} />
      </Animated.View>

      <Animated.View
        style={[{
          position: 'absolute', top: 0, bottom: 0, left: 0, width: DRAWER_W,
          backgroundColor: Colors.paperBg, borderRightWidth: 1, borderRightColor: Border.light,
        }, drawerStyle]}>
        <ScrollView contentContainerStyle={{ paddingTop: insets.top + 12, paddingBottom: insets.bottom + 20 }}>
          {/* Slægt-header */}
          <View style={{ paddingHorizontal: 22, paddingBottom: 16, borderBottomWidth: 1, borderBottomColor: Border.faint }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 11 }}>
              <CrestRing letter="R" size={38} />
              <View>
                <Kicker size={8} color={Colors.textMuted2}>Slægt</Kicker>
                <Serif size={22} style={{ lineHeight: 22 }}>Reventlow</Serif>
              </View>
            </View>
            <Pressable onPress={() => setSlaegtOpen(true)} style={{ marginTop: 11 }}>
              <BtnLabel size={12} color={Colors.bordeaux}>Skift slægt ▾</BtnLabel>
            </Pressable>
          </View>

          {/* Nav-liste */}
          <View style={{ paddingVertical: 8 }}>
            {NAV.map((n) => (
              <Pressable key={n.no} onPress={() => go(n.href)} style={{ flexDirection: 'row', alignItems: 'center', gap: 14, paddingVertical: 12, paddingHorizontal: 22 }}>
                <Serif size={15} italic color={Colors.gold} style={{ width: 22, fontFamily: Fonts.serifItalic }}>{n.no}</Serif>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={19} style={{ lineHeight: 20 }}>{n.title}</Serif>
                  <Body size={11} color={Colors.textSecondary2}>{n.sub}</Body>
                </View>
                <Serif size={16} color={Colors.textMuted2}>›</Serif>
              </Pressable>
            ))}
          </View>

          {/* Konto-footer */}
          <View style={{ paddingHorizontal: 22, paddingTop: 14, marginTop: 6, borderTopWidth: 1, borderTopColor: Border.faint }}>
            {session ? (
              <>
                <Body size={13} color={Colors.ink} style={{ marginBottom: 8 }}>{session.user?.email ?? 'Logget ind'}</Body>
                <Pressable onPress={() => { void doSignOut(); }}>
                  <BtnLabel size={12} color={Colors.bordeaux}>Log ud</BtnLabel>
                </Pressable>
              </>
            ) : (
              <Pressable onPress={() => go('/konto')}>
                <BtnLabel size={13} color={Colors.bordeaux}>Log ind som medlem eller redaktør ›</BtnLabel>
              </Pressable>
            )}
          </View>
        </ScrollView>
      </Animated.View>

      <SlaegtPicker visible={slaegtOpen} personCount={personCount} onClose={() => setSlaegtOpen(false)} />
    </Modal>
  );
}
