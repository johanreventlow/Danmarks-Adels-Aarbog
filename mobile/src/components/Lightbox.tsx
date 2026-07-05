// Lightbox (mediehåndtering Slice A — planlagt i docs/superpowers/plans/
// 2026-07-05-billedstoerrelser-artikler-lightbox.md). Fuldskærms-modal til at se et billede i
// fuld størrelse. Bevidst KUN statisk visning (bruger-afklaring 2026-07-05: intet pinch-zoom,
// ingen swipe-dismiss-gestus — "bare større" er nok). Selvstændig implementering (ikke delt kode
// med web) — samme princip som buildBidirectionalColumns: ét beskrevet interaktionsmønster, to
// uafhængige implementeringer. Tap hvor som helst (inkl. selve billedet) lukker, matcher hvordan
// fotovisninger normalt opfører sig på mobil (modsat web, hvor klik på selve billedet er inert).
// `uri` er i dag den samme fil som thumbnailen (kun én størrelse findes endnu) — Slice B
// (media_variant, planen §1-2) skifter kaldernes uri til en 'large'-variant; denne komponent
// rører ikke ved dét, den viser bare den uri den får.
import { Image } from 'expo-image';
import { Modal, Pressable, StyleSheet, View } from 'react-native';
import { Mono, Body } from './Typography';
import { Colors } from '../theme/tokens';

export type LightboxItem = { id: string; uri: string; titel?: string | null; kunstner?: string | null; datering?: string | null };

export function Lightbox({ items, index, onClose, onNavigate }: {
  items: LightboxItem[];
  index: number;
  onClose: () => void;
  onNavigate: (nextIndex: number) => void;
}) {
  const m = items[index];
  const harForrige = index > 0;
  const harNaeste = index < items.length - 1;
  if (!m) return null;
  const cap = [m.titel, m.kunstner, m.datering].filter(Boolean).join(' · ');

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Image source={{ uri: m.uri }} style={styles.image} contentFit="contain" />
        {(cap || items.length > 1) && (
          <View style={styles.captionWrap} pointerEvents="none">
            {cap ? <Body size={13} color={Colors.paperCard} style={{ textAlign: 'center' }}>{cap}</Body> : null}
            {items.length > 1 ? (
              <Mono size={10} color={Colors.textMuted3} style={{ textAlign: 'center', marginTop: 4 }}>{index + 1} / {items.length}</Mono>
            ) : null}
          </View>
        )}
        {harForrige ? (
          <Pressable style={[styles.navBtn, styles.navLeft]} onPress={() => onNavigate(index - 1)} hitSlop={16}>
            <Mono size={30} color={Colors.paperCard}>‹</Mono>
          </Pressable>
        ) : null}
        {harNaeste ? (
          <Pressable style={[styles.navBtn, styles.navRight]} onPress={() => onNavigate(index + 1)} hitSlop={16}>
            <Mono size={30} color={Colors.paperCard}>›</Mono>
          </Pressable>
        ) : null}
        <Pressable style={styles.closeBtn} onPress={onClose} hitSlop={16}>
          <Mono size={24} color={Colors.paperCard}>×</Mono>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(10,8,6,.94)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  image: { width: '92%', height: '75%' },
  captionWrap: { position: 'absolute', bottom: 40, left: 24, right: 24 },
  closeBtn: { position: 'absolute', top: 52, right: 20, padding: 8 },
  navBtn: { position: 'absolute', top: '50%', marginTop: -22, padding: 10 },
  navLeft: { left: 8 },
  navRight: { right: 8 },
});
