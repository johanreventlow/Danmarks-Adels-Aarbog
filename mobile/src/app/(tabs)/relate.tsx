// Er vi i familie? (README §5.4) — tro port af v2-designet (linje 546-597).
// To person-felter A & B (→ person-vælger M1), "sæt mig"-genvej, mørkt resultat-kort med
// relations-etiket + fælles ane, og "Forbindelsen, trin for trin"-tidslinje (A → LCA → B).
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { PersonPicker } from '../../components/PersonPicker';
import { Body, Kicker, Mono, Serif } from '../../components/Typography';
import { computeRelationship } from '../../data/relationship';
import type { Konfidens } from '../../data/types';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius, Shadow } from '../../theme/tokens';

// Vis kun de led der reelt er usikre (formodet/omstridt); sikre/sandsynlige/uangivne flages ikke.
function konfTekst(k?: Konfidens): string {
  return k === 'omstridt' ? 'omstridt' : k === 'formodet' ? 'formodet' : '';
}

export default function RelateScreen() {
  const insets = useSafeAreaInsets();
  const model = useStore((s) => s.model);
  const relA = useStore((s) => s.relA);
  const relB = useStore((s) => s.relB);
  const setRelA = useStore((s) => s.setRelA);
  const setRelB = useStore((s) => s.setRelB);
  const meId = useStore((s) => s.meId);
  const [picking, setPicking] = useState<'A' | 'B' | null>(null);

  const a = relA && model ? model.byId[relA] : null;
  const b = relB && model ? model.byId[relB] : null;
  const rel = useMemo(
    () => (model && relA && relB ? computeRelationship(model, relA, relB) : null),
    [model, relA, relB],
  );
  const me = meId && model ? model.byId[meId] : null;
  const meAvailable = !!me && relA !== meId;

  return (
    <LoadGate>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 18, paddingTop: insets.top + 14, paddingBottom: insets.bottom + 80 }}>
        {/* Sæt mig som første person */}
        {meAvailable ? (
          <Pressable style={styles.meShortcut} onPress={() => setRelA(meId!)}>
            <Body size={12.5} color={Colors.bordeaux} style={{ fontFamily: Fonts.sansSemi }}>
              ★ Sæt mig ({me!.name}) som første person
            </Body>
          </Pressable>
        ) : null}

        {/* A & B felter */}
        <View style={{ flexDirection: 'row', alignItems: 'stretch', gap: 10 }}>
          <PersonField label={a?.name} init={a ? a.name[0]?.toUpperCase() : '?'} onPress={() => setPicking('A')} />
          <View style={{ justifyContent: 'center' }}>
            <Serif size={20} italic color={Colors.gold} style={{ fontFamily: Fonts.serifItalic }}>&</Serif>
          </View>
          <PersonField label={b?.name} init={b ? b.name[0]?.toUpperCase() : '?'} onPress={() => setPicking('B')} />
        </View>

        {/* Resultat-kort */}
        {rel ? (
          <View style={styles.result}>
            <Mono size={9.5} color={Colors.goldLight} style={{ letterSpacing: 9.5 * 0.16, textTransform: 'uppercase' }}>Slægtskab</Mono>
            <Serif size={25} color={Colors.paperBg} style={{ marginTop: 7, lineHeight: 27, textAlign: 'center' }}>{rel.label}</Serif>
            {rel.found && (rel.lines[0]?.coupleNames || rel.lcaName) ? (
              <Body size={12.5} color="#cabfa9" style={{ marginTop: 8 }}>Fælles ane: {rel.lines[0]?.coupleNames || rel.lcaName}</Body>
            ) : null}
            {rel.found && rel.lines[0]?.usikker ? (
              <Body size={11.5} color={Colors.goldLight} style={{ marginTop: 7, textAlign: 'center' }}>
                ⚠ Forbindelsen går gennem et {konfTekst(rel.lines[0].weakestKonfidens)} led
              </Body>
            ) : null}
          </View>
        ) : (
          <View style={styles.resultEmpty}>
            <Body size={13} color={Colors.textMuted}>Vælg to personer for at finde slægtskabet.</Body>
          </View>
        )}

        {/* Øvrige linjer — i en sammengift slægt er to personer ofte beslægtet ad flere veje. */}
        {rel && rel.found && rel.lines.length > 1 ? (
          <View style={styles.alsoBox}>
            <Kicker size={9.5} style={{ marginBottom: 6, letterSpacing: 9.5 * 0.14 }}>Også beslægtet</Kicker>
            {rel.lines.slice(1).map((l) => (
              <View key={l.lcaId} style={styles.alsoRow}>
                <Serif size={14} style={{ flex: 1, lineHeight: 16 }}>{l.label}</Serif>
                {l.usikker ? <Mono size={8} color={Colors.bordeaux} style={{ flexShrink: 0, textTransform: 'uppercase', letterSpacing: 0.5 }}>{konfTekst(l.weakestKonfidens)}</Mono> : null}
                <Body size={11} color={Colors.textMuted} style={{ flexShrink: 0 }}>via {l.coupleNames || l.lcaName}</Body>
              </View>
            ))}
          </View>
        ) : null}

        {/* Trin for trin */}
        {rel && rel.steps.length ? (
          <View style={{ marginTop: 20 }}>
            <Kicker size={9.5} style={{ marginBottom: 4, letterSpacing: 9.5 * 0.14 }}>Forbindelsen, trin for trin</Kicker>
            {rel.steps.map((s, i) => {
              const linkKonf = i < rel.steps.length - 1 ? konfTekst(rel.steps[i + 1]?.edgeKonfidens) : '';
              return (
                <View key={`${s.id}-${i}`}>
                  <View style={styles.stepRow}>
                    <View style={styles.dotCol}>
                      <View style={[styles.dot, { backgroundColor: s.isLca ? Colors.gold : Colors.bordeaux, borderColor: s.isLca ? Colors.gold : 'rgba(136,26,51,0.25)' }]} />
                    </View>
                    <View style={[styles.stepCard, s.isLca ? styles.stepCardLca : styles.stepCardNormal]}>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Serif size={17} style={{ lineHeight: 18 }}>{s.name}</Serif>
                        {s.years ? <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 2 }}>{s.years}</Mono> : null}
                      </View>
                      {s.isLca ? <Mono size={8} color={Colors.gold} style={{ letterSpacing: 0.6, textTransform: 'uppercase' }}>Fælles ane</Mono> : null}
                    </View>
                  </View>
                  {i < rel.steps.length - 1 ? (
                    <View style={styles.stepLink}>
                      <View style={styles.stepArrow} />
                      {linkKonf ? (
                        <Mono size={8} color={Colors.bordeaux} style={{ textTransform: 'uppercase', letterSpacing: 0.5 }}>{linkKonf} led</Mono>
                      ) : null}
                    </View>
                  ) : null}
                </View>
              );
            })}
          </View>
        ) : null}
      </ScrollView>

      <PersonPicker
        visible={picking !== null}
        title={picking === 'A' ? 'Vælg første person' : 'Vælg anden person'}
        onClose={() => setPicking(null)}
        onPick={(id) => {
          if (picking === 'A') setRelA(id);
          else if (picking === 'B') setRelB(id);
          setPicking(null);
        }}
      />
    </LoadGate>
  );
}

function PersonField({ label, init, onPress }: { label?: string; init?: string; onPress: () => void }) {
  return (
    <Pressable style={styles.field} onPress={onPress}>
      <View style={styles.fieldAvatar}><Serif size={20} color={Colors.bordeaux}>{init ?? '?'}</Serif></View>
      <Serif size={17} style={{ marginTop: 9, lineHeight: 18, textAlign: 'center' }}>{label ?? 'Vælg person'}</Serif>
      <Body size={11} color={Colors.bordeaux} style={{ marginTop: 6, fontFamily: Fonts.sansSemi }}>skift ▾</Body>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  meShortcut: {
    alignItems: 'center',
    marginBottom: 12,
    backgroundColor: Colors.bordeauxFillLight,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(136,26,51,0.2)',
    borderRadius: Radius.field,
    paddingVertical: 10,
  },
  field: {
    flex: 1,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 14,
    padding: 14,
    alignItems: 'center',
    ...Shadow.card,
  },
  fieldAvatar: {
    width: 48, height: 48, borderRadius: Radius.round, backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
  result: { marginTop: 18, backgroundColor: Colors.ink, borderRadius: 14, paddingVertical: 18, paddingHorizontal: 18, alignItems: 'center' },
  resultEmpty: { marginTop: 18, backgroundColor: Colors.paperCard, borderRadius: 14, padding: 18, alignItems: 'center', borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light },
  alsoBox: { marginTop: 14, backgroundColor: Colors.paperCard, borderRadius: 12, paddingVertical: 12, paddingHorizontal: 14, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light },
  alsoRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 5 },
  stepRow: { flexDirection: 'row', alignItems: 'center', gap: 13, paddingVertical: 3 },
  dotCol: { width: 26, alignItems: 'center' },
  dot: { width: 11, height: 11, borderRadius: Radius.round, borderWidth: 2 },
  stepCard: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 8, borderRadius: 11, paddingVertical: 10, paddingHorizontal: 13, borderWidth: StyleSheet.hairlineWidth },
  stepCardNormal: { backgroundColor: Colors.paperCard, borderColor: Border.light },
  stepCardLca: { backgroundColor: '#f3ecdb', borderColor: 'rgba(185,160,106,0.5)' },
  stepArrow: { marginLeft: 12, width: 2, height: 9, backgroundColor: 'rgba(34,31,26,0.18)' },
  stepLink: { flexDirection: 'row', alignItems: 'center', gap: 8 },
});
