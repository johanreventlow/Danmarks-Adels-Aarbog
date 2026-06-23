// Stamtræ — variant A · Fokus (README §5.2) + §9.2 linje-hop.
// Lodret kort-fokus: bedsteforælder-pille → forælder-kort → vandret række af denne generations
// søskende (valgte i bordeaux ramme m. "Åbn profil") → evt. ⚭ gift med → vandret række børn & grene.
// Linje-chip-række: klik hopper fokus til linjens stamfader + highlighter chip; "Hele slægten" rydder.
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { Body, Kicker, Mono, Serif } from '../../components/Typography';
import { treeFocusA } from '../../data/selectors';
import type { ModelPerson } from '../../data/types';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius, Shadow } from '../../theme/tokens';

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
      <View style={{ flex: 1, paddingTop: insets.top + 8 }}>
        {/* Sticky-ish topbar: titel + linje-chips */}
        <View style={styles.head}>
          <Serif size={22} style={{ paddingHorizontal: 20 }}>Stamtræ</Serif>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.linjeRow}>
            <LinjeChip
              label="Hele slægten"
              active={!activeLinje}
              onPress={() => clearLinje()}
            />
            {linjeList.map((l) => (
              <LinjeChip
                key={l.linje}
                label={`Linje ${l.linje}`}
                active={activeLinje === l.linje}
                onPress={() => pickLinje(l.linje, l.headId)}
              />
            ))}
          </ScrollView>
        </View>

        {!view || !view.focus ? (
          <View style={{ padding: 24 }}>
            <Body color={Colors.textMuted}>Vælg en linje eller en person for at se træet.</Body>
          </View>
        ) : (
          <ScrollView contentContainerStyle={{ padding: 20, paddingBottom: insets.bottom + 80 }}>
            {/* Bedsteforælder-pille */}
            {view.grandparent ? (
              <Pressable style={styles.grandPill} onPress={() => setFocus(view.grandparent!.id)}>
                <Mono size={10} color={Colors.textMuted}>{view.grandparent.name}</Mono>
              </Pressable>
            ) : null}

            {/* Forælder-kort */}
            {view.parent ? (
              <Pressable style={styles.parentCard} onPress={() => setFocus(view.parent!.id)}>
                <Kicker size={8}>Forælder</Kicker>
                <Serif size={18}>{view.parent.name}</Serif>
                {view.parent.years ? <Mono size={10}>{view.parent.years}</Mono> : null}
              </Pressable>
            ) : null}

            {/* Denne generations søskende */}
            <Kicker size={9} style={{ marginTop: 18, marginBottom: 8 }}>Denne generation</Kicker>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12 }}>
              {view.siblings.map((s) => (
                <SiblingCard
                  key={s.id}
                  person={s}
                  selected={s.id === view.focus!.id}
                  onFocus={() => setFocus(s.id)}
                  onOpen={() => router.push(`/person/${s.id}`)}
                />
              ))}
            </ScrollView>

            {/* Gift med */}
            {view.spouseName ? (
              <View style={{ marginTop: 16 }}>
                <Serif size={15} italic color={Colors.textSecondary}>⚭ gift med {view.spouseName}</Serif>
              </View>
            ) : null}

            {/* Børn & grene */}
            {view.children.length ? (
              <>
                <Kicker size={9} style={{ marginTop: 20, marginBottom: 8 }}>Børn & grene</Kicker>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 10 }}>
                  {view.children.map((c) => (
                    <Pressable key={c.id} style={styles.childCard} onPress={() => setFocus(c.id)}>
                      <Serif size={15}>{c.name}</Serif>
                      {c.years ? <Mono size={9}>{c.years}</Mono> : null}
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

function LinjeChip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.linjeChip, active && styles.linjeChipActive]}>
      <Mono size={10} color={active ? Colors.paperBg : Colors.textSecondary2}>{label}</Mono>
    </Pressable>
  );
}

function SiblingCard({
  person,
  selected,
  onFocus,
  onOpen,
}: {
  person: ModelPerson;
  selected: boolean;
  onFocus: () => void;
  onOpen: () => void;
}) {
  return (
    <Pressable onPress={onFocus} style={[styles.sibCard, selected && styles.sibCardSelected]}>
      <Serif size={17}>{person.name}</Serif>
      {person.years ? <Mono size={10}>{person.years}</Mono> : null}
      {person.title ? <Mono size={9} color={Colors.textMuted}>{person.title}</Mono> : null}
      {selected ? (
        <Pressable onPress={onOpen} style={styles.openBtn}>
          <Mono size={10} color={Colors.paperBg}>Åbn profil ›</Mono>
        </Pressable>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  head: { paddingBottom: 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light },
  linjeRow: { gap: 6, paddingHorizontal: 20, paddingTop: 10 },
  linjeChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: Radius.chip,
    backgroundColor: Colors.beige,
  },
  linjeChipActive: { backgroundColor: Colors.bordeaux },
  grandPill: {
    alignSelf: 'flex-start',
    backgroundColor: Colors.beige2,
    borderRadius: Radius.chip,
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginBottom: 12,
  },
  parentCard: {
    backgroundColor: Colors.paperCard,
    borderRadius: Radius.card,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    padding: 14,
    ...Shadow.card,
  },
  sibCard: {
    width: 178,
    backgroundColor: Colors.paperCard,
    borderRadius: Radius.card,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    padding: 14,
    gap: 3,
    ...Shadow.card,
  },
  sibCardSelected: {
    borderWidth: 1.5,
    borderColor: Colors.bordeaux,
    ...Shadow.cardSelected,
  },
  openBtn: {
    marginTop: 10,
    backgroundColor: Colors.bordeaux,
    borderRadius: Radius.field,
    paddingVertical: 8,
    alignItems: 'center',
  },
  childCard: {
    width: 138,
    backgroundColor: Colors.beige,
    borderRadius: Radius.card,
    padding: 12,
    gap: 2,
  },
});
