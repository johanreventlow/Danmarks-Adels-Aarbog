// Godser & ejendomme — liste (README §5.7). Port af v2-designet (linje 170-185).
// Intro + liste af gods-kort (⌂-badge, navn, "N registrerede ejere", chevron). Data fra
// aux.estateList (relation rolle 'ejer' → estate). Tryk → gods-detalje.
// Liste/Kort-toggle (spejler web/src/Folgesvend.tsx's EstatesView): kort-tilstand bruger
// geo.byEstate (estate.sted_id → place) — kun godser med koordinater vises som nåle.
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { FlatList, Pressable, StyleSheet, View } from 'react-native';
import { GeoMap } from '../components/GeoMap';
import { LoadGate } from '../components/LoadGate';
import { TopBar } from '../components/TopBar';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { estatePoints } from '../data/geoSelectors';
import { useStore } from '../store/useStore';
import { Border, Colors, Shadow } from '../theme/tokens';

export default function EstatesScreen() {
  const router = useRouter();
  const aux = useStore((s) => s.aux);
  const geo = useStore((s) => s.geo);
  const estateList = aux?.estateList ?? [];
  const [viewMode, setViewMode] = useState<'liste' | 'kort'>('liste');
  const points = estatePoints(geo);

  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Godser & ejendomme" />
      <View style={styles.toggleRow}>
        {(['liste', 'kort'] as const).map((m) => (
          <Pressable key={m} onPress={() => setViewMode(m)} style={[styles.toggleBtn, viewMode === m && styles.toggleBtnActive]}>
            <BtnLabel size={11.5} color={viewMode === m ? Colors.bordeaux : Colors.textSecondary2}>
              {m === 'liste' ? 'Liste' : 'Kort'}
            </BtnLabel>
          </Pressable>
        ))}
      </View>
      <LoadGate>
        {viewMode === 'kort' ? (
          points.length ? (
            <GeoMap
              points={points}
              mode="explorer"
              onPointPress={(p) => p.estateId && router.push(`/estate/${p.estateId}`)}
            />
          ) : (
            <View style={{ padding: 22 }}>
              <Body size={13} color={Colors.textMuted}>Ingen godser er kortlagt endnu.</Body>
            </View>
          )
        ) : (
          <FlatList
            style={{ flex: 1 }}
            data={estateList}
            keyExtractor={(e) => e.id}
            contentContainerStyle={{ padding: 18, paddingBottom: 40 }}
            ListHeaderComponent={
              <Body size={13} color={Colors.textSecondary2} style={{ marginBottom: 14 }}>
                Godser, herregårde og len knyttet til slægten — med de slægtsmedlemmer der har ejet dem.
              </Body>
            }
            renderItem={({ item }) => (
              <Pressable style={styles.card} onPress={() => router.push(`/estate/${item.id}`)}>
                <View style={styles.crest}>
                  <Serif size={17} color={Colors.bordeaux}>⌂</Serif>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={20} style={{ lineHeight: 21 }}>{item.navn}</Serif>
                  <Body size={12} color={Colors.textSecondary2} style={{ marginTop: 2 }}>
                    {item.ownerCount} {item.ownerCount === 1 ? 'registreret ejer' : 'registrerede ejere'}
                  </Body>
                </View>
                <Serif size={18} color="#bcae93">›</Serif>
              </Pressable>
            )}
          />
        )}
      </LoadGate>
    </View>
  );
}

const styles = StyleSheet.create({
  toggleRow: {
    flexDirection: 'row', gap: 2, backgroundColor: Colors.beige2, borderRadius: 8,
    padding: 2, marginHorizontal: 18, marginBottom: 4, alignSelf: 'flex-start',
  },
  toggleBtn: { paddingVertical: 6, paddingHorizontal: 12, borderRadius: 6 },
  toggleBtnActive: { backgroundColor: Colors.paperCard },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 13,
    paddingVertical: 13,
    paddingHorizontal: 15,
    marginBottom: 9,
    ...Shadow.card,
  },
  crest: {
    width: 38, height: 38, borderRadius: 8, backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
});
