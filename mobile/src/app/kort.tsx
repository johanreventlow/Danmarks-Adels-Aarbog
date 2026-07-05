// Slægtens kort — overbliks-kort (README kort-plan, 3. flade). Fuldskærms-kort over ALLE
// geo-punkter (personhændelser + godser), filtrerbart pr. linje. v1: kun linje-filter
// (type-filter/år-slider/"nær mig" er senere skiver). Lokal filter-tilstand — påvirker
// BEVIDST ikke den globale activeLinje (stamtræets linje-filter), da dette er en separat visning.
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { GeoMap } from '../components/GeoMap';
import { LoadGate } from '../components/LoadGate';
import { TopBar } from '../components/TopBar';
import { Body, BtnLabel } from '../components/Typography';
import { filterByLineage } from '../data/geoSelectors';
import { useStore } from '../store/useStore';
import { Border, Colors } from '../theme/tokens';

export default function KortScreen() {
  const router = useRouter();
  const aux = useStore((s) => s.aux);
  const geo = useStore((s) => s.geo);
  const [linje, setLinje] = useState<string | null>(null);
  const linjeList = aux?.linjeList ?? [];
  const points = linje ? filterByLineage(geo.points, aux?.linjeByPerson ?? {}, linje, { includeNonPerson: true }) : geo.points;
  const linjeNavn = linjeList.find((l) => l.linje === linje)?.navn;

  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Slægtens kort" />
      <LoadGate>
        <View style={{ flex: 1 }}>
          <View style={styles.chipRow}>
            <Pressable onPress={() => setLinje(null)} style={[styles.chip, !linje ? styles.chipActive : styles.chipIdle]}>
              <BtnLabel size={12} color={!linje ? Colors.paperCard : Colors.textSecondary2}>Hele slægten</BtnLabel>
            </Pressable>
            {linjeList.map((l) => (
              <Pressable key={l.linje} onPress={() => setLinje(l.linje)} style={[styles.chip, linje === l.linje ? styles.chipActive : styles.chipIdle]}>
                <BtnLabel size={12} color={linje === l.linje ? Colors.paperCard : Colors.textSecondary2}>{l.navn ?? `Linje ${l.linje}`}</BtnLabel>
              </Pressable>
            ))}
          </View>
          <Body size={12.5} color={Colors.textMuted} style={{ paddingHorizontal: 18, marginBottom: 8 }}>
            {points.length} {points.length === 1 ? 'sted' : 'steder'} kortlagt{linjeNavn ? ` for ${linjeNavn}` : ''}.
          </Body>
          {points.length ? (
            <GeoMap
              points={points}
              mode="explorer"
              onPointPress={(p) => {
                if (p.personId) router.push(`/person/${p.personId}`);
                else if (p.estateId) router.push(`/estate/${p.estateId}`);
              }}
            />
          ) : (
            <View style={{ padding: 22 }}>
              <Body size={13} color={Colors.textMuted}>Ingen steder kortlagt endnu{linjeNavn ? ' for denne linje' : ''}.</Body>
            </View>
          )}
        </View>
      </LoadGate>
    </View>
  );
}

const styles = StyleSheet.create({
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 7, paddingHorizontal: 18, paddingTop: 14, paddingBottom: 8 },
  chip: { paddingHorizontal: 13, paddingVertical: 6, borderRadius: 16, borderWidth: StyleSheet.hairlineWidth },
  chipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  chipIdle: { backgroundColor: Colors.beige, borderColor: Border.light },
});
