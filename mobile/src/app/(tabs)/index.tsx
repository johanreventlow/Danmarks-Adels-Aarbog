// Forside — Slægts-portal (README §5.1). Slægts-chip, hero m. tællere, fremhævet person,
// "din plads", udforsk-liste 01–06, footer. Live-data fra store.
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../../components/InitialBadge';
import { LoadGate } from '../../components/LoadGate';
import { Rise } from '../../components/Rise';
import { Body, Kicker, Mono, Serif } from '../../components/Typography';
import { counts } from '../../data/selectors';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';

const SLAEGT = 'Reventlow';

// ready=false er udskudte skærme (README §scope) — vises men navigerer ikke endnu.
const EXPLORE: { no: string; title: string; sub: string; href: string; ready: boolean }[] = [
  { no: 'I', title: 'Stamtræ', sub: 'Naviger slægten op, ned og til siden', href: '/tree', ready: true },
  { no: 'II', title: 'Om slægten', sub: 'Historisk indledning', href: '/about', ready: false },
  { no: 'III', title: 'Godser & ejendomme', sub: 'Besiddelser gennem tiden', href: '/estates', ready: false },
  { no: 'IV', title: 'Slægtens våben', sub: 'Heraldik og segl', href: '/arms', ready: false },
  { no: 'V', title: 'Er vi i familie?', sub: 'Find slægtskab mellem to personer', href: '/relate', ready: true },
  { no: 'VI', title: 'Søg', sub: 'Bladr og søg i alle personer', href: '/search', ready: true },
];

export default function HomeScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const featuredId = useStore((s) => s.focusId);
  const meId = useStore((s) => s.meId);

  const c = counts(model, aux);
  const featured = featuredId && model ? model.byId[featuredId] : null;
  const me = meId && model ? model.byId[meId] : null;

  return (
    <LoadGate>
      <ScrollView
        style={{ backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top + 12, paddingBottom: 40, paddingHorizontal: 20 }}>
        {/* Slægts-chip */}
        <Rise index={0}>
          <Pressable style={styles.slaegtChip} onPress={() => router.push('/search')}>
            <InitialBadge name={SLAEGT} size={34} bg={Colors.bordeaux} color={Colors.paperCard} />
            <View style={{ flex: 1 }}>
              <Kicker size={8}>Slægt</Kicker>
              <Serif size={18}>{SLAEGT}</Serif>
            </View>
            <Mono color={Colors.bordeaux} size={11}>skift ▾</Mono>
          </Pressable>
        </Rise>

        {/* Hero */}
        <Rise index={1} style={{ marginTop: 28 }}>
          <Kicker color={Colors.gold} size={10}>Danmarks Adels Aarbog</Kicker>
          <View style={{ flexDirection: 'row', alignItems: 'flex-end', flexWrap: 'wrap', marginTop: 6 }}>
            <Serif size={46} italic color={Colors.textMuted2}>Slægten </Serif>
            <Serif size={46} color={Colors.ink}>{SLAEGT}</Serif>
          </View>
          <View style={styles.rule} />
          <Body size={14} style={{ maxWidth: 280, marginTop: 14 }}>
            En digital følgesvend til det trykte værk — naviger stamtræet, læs persondetaljer og
            find slægtskab på tværs af generationerne.
          </Body>
        </Rise>

        {/* Tællere */}
        <Rise index={2} style={{ marginTop: 22 }}>
          <View style={styles.counters}>
            <Counter value={c.personer} label="Personer" />
            <Counter value={c.linjer} label="Linjer" />
            <Counter value={c.godser} label="Godser" />
          </View>
        </Rise>

        {/* Fremhævet person */}
        {featured ? (
          <Rise index={3} style={{ marginTop: 26 }}>
            <Pressable style={styles.featured} onPress={() => router.push(`/person/${featured.id}`)}>
              <InitialBadge name={featured.name} size={46} />
              <View style={{ flex: 1 }}>
                <Kicker size={8}>Fremhævet</Kicker>
                <Serif size={20}>{featured.name}</Serif>
                {featured.title ? <Mono size={10}>{featured.title}</Mono> : null}
              </View>
              <Ionicons name="chevron-forward" size={18} color={Colors.textMuted} />
            </Pressable>
          </Rise>
        ) : null}

        {/* Din plads */}
        <Rise index={4} style={{ marginTop: 14 }}>
          {me ? (
            <Pressable style={styles.mePlaceFilled} onPress={() => router.push(`/person/${me.id}`)}>
              <Kicker color={Colors.bordeaux} size={9}>★ Din plads i slægten</Kicker>
              <Serif size={19} style={{ marginTop: 2 }}>{me.name}</Serif>
            </Pressable>
          ) : (
            <Pressable style={styles.mePlaceDark} onPress={() => router.push('/search')}>
              <Serif size={19} color={Colors.paperCard}>Hvem er du i slægten?</Serif>
              <Body size={12} color={Colors.beige2} style={{ marginTop: 2 }}>
                Find dig selv og markér din plads i træet.
              </Body>
            </Pressable>
          )}
        </Rise>

        {/* Udforsk-liste */}
        <View style={{ marginTop: 30 }}>
          <Kicker style={{ marginBottom: 8 }}>Udforsk slægten</Kicker>
          {EXPLORE.map((row, i) => (
            <Pressable
              key={row.no}
              style={[styles.exploreRow, !row.ready && { opacity: 0.45 }]}
              disabled={!row.ready}
              onPress={() => router.push(row.href as never)}>
              <Serif size={18} italic color={Colors.gold} style={{ width: 34 }}>{row.no}</Serif>
              <View style={{ flex: 1 }}>
                <Serif size={21}>{row.title}</Serif>
                <Body size={12} color={Colors.textMuted}>
                  {row.ready ? row.sub : 'Kommer snart'}
                </Body>
              </View>
              <Ionicons name="chevron-forward" size={18} color={Colors.textMuted} />
            </Pressable>
          ))}
        </View>

        {/* Footer */}
        <View style={styles.footer}>
          <Serif size={15} color={Colors.textSecondary}>Danmarks Adels Aarbog</Serif>
          <Body size={12} color={Colors.textMuted}>Udgivet af Dansk Adels Forening</Body>
          <Mono size={9} style={{ marginTop: 8, textAlign: 'center' }}>
            Live-data fra Adelsårbogens base · proof of concept
          </Mono>
        </View>
      </ScrollView>
    </LoadGate>
  );
}

function Counter({ value, label }: { value: number; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Serif size={27} color={Colors.bordeaux}>{value}</Serif>
      <Kicker size={9}>{label}</Kicker>
    </View>
  );
}

const styles = StyleSheet.create({
  slaegtChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: Radius.chip,
    paddingVertical: 8,
    paddingHorizontal: 12,
  },
  rule: { width: 46, height: 1.5, backgroundColor: Colors.bordeaux, marginTop: 12 },
  counters: {
    flexDirection: 'row',
    gap: 28,
  },
  featured: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: Colors.beige,
    borderRadius: Radius.card,
    padding: 14,
  },
  mePlaceFilled: {
    borderWidth: 1.5,
    borderColor: Colors.bordeaux,
    borderRadius: Radius.card,
    padding: 14,
  },
  mePlaceDark: {
    backgroundColor: Colors.ink,
    borderRadius: Radius.card,
    padding: 16,
  },
  exploreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.light,
  },
  footer: { alignItems: 'center', marginTop: 40, gap: 2 },
});
