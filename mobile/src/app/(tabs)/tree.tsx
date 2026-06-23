// Stamtræ — variant A · Fokus (README §5.2) + §9.2 linje-hop. Tro port af v2-designet
// (linje 243-318): segment-kontrol (Fokus aktiv; Kolonner/Spor udskudt), linje-chip-række,
// "Aner" → bedsteforælder-pille → forælder-kort → snap-række søskende (178px, "I fokus" +
// "Åbn profil") → ⚭ gift med → "Børn & grene" (138px kort). Connector-linjer mellem lag.
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { childrenOf, treeFocusA } from '../../data/selectors';
import type { ModelPerson } from '../../data/types';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';

export default function TreeScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const focusId = useStore((s) => s.focusId);
  const activeLinje = useStore((s) => s.activeLinje);
  const pickLinje = useStore((s) => s.pickLinje);
  const clearLinje = useStore((s) => s.clearLinje);
  const setFocus = useStore((s) => s.setFocus);

  const linjeList = aux?.linjeList ?? [];
  const view = model && focusId ? treeFocusA(model, focusId) : null;

  return (
    <LoadGate>
      <View style={{ flex: 1, paddingTop: insets.top }}>
        {/* Sticky topbar: segment-kontrol + linje-chips */}
        <View style={styles.head}>
          <View style={styles.segment}>
            <Segment label="Fokus" active onPress={() => {}} />
            <Segment label="Kolonner" active={false} disabled onPress={() => {}} />
            <Segment label="Spor" active={false} disabled onPress={() => {}} />
          </View>
          {linjeList.length ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.linjeRow}>
              <LinjeChip label="Hele slægten" active={!activeLinje} onPress={() => clearLinje()} />
              {linjeList.map((l) => (
                <LinjeChip key={l.linje} label={`Linje ${l.linje}`} active={activeLinje === l.linje} onPress={() => pickLinje(l.linje, l.headId)} />
              ))}
            </ScrollView>
          ) : null}
        </View>

        {!view || !view.focus ? (
          <View style={{ padding: 24 }}>
            <Kicker color={Colors.textMuted}>Vælg en linje eller person for at se træet.</Kicker>
          </View>
        ) : (
          <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: insets.bottom + 80 }}>
            {/* Aner */}
            <CenterKicker text="Aner" style={{ marginTop: 6, marginBottom: 2 }} />

            {/* Bedsteforælder-pille */}
            {view.grandparent ? (
              <>
                <Pressable style={styles.grandPill} onPress={() => setFocus(view.grandparent!.id)}>
                  <Mono size={13} color={Colors.textMuted}>▲</Mono>
                  <Serif size={15} color="#5a5246">{view.grandparent.name}</Serif>
                </Pressable>
                <Connector height={14} />
              </>
            ) : null}

            {/* Forælder-kort */}
            {view.parent ? (
              <>
                <Pressable style={styles.parentCard} onPress={() => setFocus(view.parent!.id)}>
                  <View style={styles.parentAvatar}>
                    <Serif size={18} color={Colors.bordeaux}>{view.parent.name[0]?.toUpperCase() ?? '?'}</Serif>
                  </View>
                  <View>
                    <Kicker size={8.5} color={Colors.gold} style={{ letterSpacing: 8.5 * 0.12 }}>Forælder ▲</Kicker>
                    <Serif size={19} style={{ marginTop: 1, lineHeight: 20 }}>{view.parent.name}</Serif>
                    {view.parent.years ? <Mono size={10} color={Colors.textMuted} style={{ marginTop: 2 }}>{view.parent.years}</Mono> : null}
                  </View>
                </Pressable>
                <Connector height={18} />
              </>
            ) : null}

            {/* Denne generation */}
            <CenterKicker text="Denne generation ◂ ▸" style={{ marginVertical: 8 }} />
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 11, paddingHorizontal: 2, paddingBottom: 6 }}>
              {view.siblings.map((s) => (
                <SiblingCard
                  key={s.id}
                  person={s}
                  childCount={model ? childrenOf(model, s.id).length : 0}
                  selected={s.id === view.focus!.id}
                  onFocus={() => setFocus(s.id)}
                  onOpen={() => router.push(`/person/${s.id}`)}
                />
              ))}
            </ScrollView>

            {/* Gift med */}
            {view.spouseName ? (
              <Serif size={15} italic color={Colors.textSecondary2} style={{ textAlign: 'center', marginTop: 10, fontFamily: Fonts.serifItalic }}>
                ⚭ gift med {view.spouseName}
              </Serif>
            ) : null}

            {/* Børn & grene */}
            {view.children.length ? (
              <>
                <Connector height={18} style={{ marginTop: 14 }} />
                <CenterKicker text="Børn & grene ▾" style={{ marginVertical: 8 }} />
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10, paddingHorizontal: 2, paddingBottom: 6 }}>
                  {view.children.map((c) => (
                    <Pressable key={c.id} style={styles.childCard} onPress={() => setFocus(c.id)}>
                      <View style={styles.childAvatar}>
                        <Serif size={17} color={Colors.bordeaux}>{c.name[0]?.toUpperCase() ?? '?'}</Serif>
                      </View>
                      <Serif size={18} style={{ marginTop: 9, lineHeight: 19 }}>{c.name}</Serif>
                      {c.years ? <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 3 }}>{c.years}</Mono> : null}
                    </Pressable>
                  ))}
                </ScrollView>
              </>
            ) : null}
          </ScrollView>
        )}
      </View>
    </LoadGate>
  );
}

function Segment({ label, active, disabled = false, onPress }: { label: string; active: boolean; disabled?: boolean; onPress: () => void }) {
  return (
    <Pressable disabled={disabled} onPress={onPress} style={[styles.seg, active && styles.segActive, disabled && { opacity: 0.4 }]}>
      <BtnLabel size={12.5} color={active ? Colors.bordeaux : '#8a8170'}>{label}</BtnLabel>
    </Pressable>
  );
}

function LinjeChip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.linjeChip, active ? styles.linjeChipActive : styles.linjeChipIdle]}>
      <BtnLabel size={12} color={active ? Colors.paperCard : Colors.textSecondary2}>{label}</BtnLabel>
    </Pressable>
  );
}

function CenterKicker({ text, style }: { text: string; style?: object }) {
  return (
    <Kicker size={9.5} color={Colors.textMuted2} style={[{ textAlign: 'center', letterSpacing: 9.5 * 0.14 }, style]}>
      {text}
    </Kicker>
  );
}

function Connector({ height, style }: { height: number; style?: object }) {
  return <View style={[styles.connector, { height }, style]} />;
}

function SiblingCard({ person, childCount, selected, onFocus, onOpen }: {
  person: ModelPerson; childCount: number; selected: boolean; onFocus: () => void; onOpen: () => void;
}) {
  return (
    <Pressable onPress={onFocus} style={[styles.sibCard, selected ? styles.sibCardSelected : styles.sibCardIdle]}>
      {selected ? (
        <Mono size={8} color={Colors.bordeaux} style={{ position: 'absolute', top: 11, right: 12, letterSpacing: 0.8 }}>I FOKUS</Mono>
      ) : null}
      <View style={styles.sibAvatar}>
        <Serif size={26} color={Colors.bordeaux}>{person.name[0]?.toUpperCase() ?? '?'}</Serif>
      </View>
      <Serif size={23} style={{ marginTop: 12, lineHeight: 24 }}>{person.name}</Serif>
      {person.years ? <Mono size={10.5} color={Colors.textMuted} style={{ marginTop: 4 }}>{person.years}</Mono> : null}
      {person.title ? <BtnLabel size={12} color={Colors.bordeaux} style={{ marginTop: 6, fontFamily: Fonts.sansMedium }}>{person.title}</BtnLabel> : null}
      {childCount ? <Mono size={11} color={Colors.textSecondary2} style={{ marginTop: 8 }}>↓ {childCount} {childCount === 1 ? 'barn' : 'børn'}</Mono> : null}
      {selected ? (
        <Pressable onPress={onOpen} style={styles.openBtn}>
          <BtnLabel size={12} color={Colors.paperCard}>Åbn profil ›</BtnLabel>
        </Pressable>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  head: { paddingHorizontal: 16, paddingTop: 14, paddingBottom: 4, backgroundColor: Colors.paperBg, zIndex: 20 },
  segment: { flexDirection: 'row', backgroundColor: Colors.beige3, borderRadius: 11, padding: 3, gap: 3 },
  seg: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 8 },
  segActive: { backgroundColor: Colors.paperCard, ...Shadow.card },
  linjeRow: { gap: 7, paddingVertical: 10, paddingRight: 16 },
  linjeChip: { paddingHorizontal: 13, paddingVertical: 6, borderRadius: 16, borderWidth: StyleSheet.hairlineWidth },
  linjeChipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  linjeChipIdle: { backgroundColor: Colors.beige, borderColor: Border.light },
  connector: { width: 1, backgroundColor: 'rgba(34,31,26,0.22)', alignSelf: 'center', marginVertical: 5 },
  grandPill: {
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(34,31,26,0.07)',
    borderRadius: 20,
    paddingVertical: 7,
    paddingHorizontal: 14,
    opacity: 0.78,
    marginTop: 6,
  },
  parentCard: {
    alignSelf: 'center',
    maxWidth: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 14,
    paddingVertical: 11,
    paddingLeft: 12,
    paddingRight: 16,
    ...Shadow.card,
  },
  parentAvatar: {
    width: 42, height: 42, borderRadius: Radius.round, backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
  sibCard: {
    width: 178,
    borderRadius: 16,
    paddingVertical: 16,
    paddingHorizontal: 15,
    borderWidth: 1.5,
  },
  sibCardIdle: { backgroundColor: Colors.paperCard, borderColor: Border.light, ...Shadow.card },
  sibCardSelected: { backgroundColor: Colors.paperCard, borderColor: Colors.bordeaux, ...Shadow.cardSelected },
  sibAvatar: {
    width: 62, height: 62, borderRadius: Radius.round, backgroundColor: '#f4ece0',
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
  openBtn: { marginTop: 13, alignSelf: 'flex-start', backgroundColor: Colors.bordeaux, borderRadius: 9, paddingVertical: 8, paddingHorizontal: 14 },
  childCard: {
    width: 138,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 13,
    padding: 13,
    ...Shadow.card,
  },
  childAvatar: {
    width: 40, height: 40, borderRadius: Radius.round, backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
});
