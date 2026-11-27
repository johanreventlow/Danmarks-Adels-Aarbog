// Besiddelser — liste (README §5.7, ord og regler som web's EstatesView). Intro + liste af gods-kort (⌂-badge, navn,
// »N ejere i Aarbogen«, chevron). Data fra aux.estateList: ALLE godser, også uden ejere; ejertallet tælles om mod
// modellen (besiddelserVist). Tryk → gods-detalje.
// Liste/Kort-toggle (spejler web/src/Folgesvend.tsx's EstatesView): kort-tilstand bruger
// geo.byEstate (estate.sted_id → place) — kun godser med koordinater vises som nåle.
import { useRouter } from 'expo-router';
import { useMemo, useState } from 'react';
import { FlatList, Pressable, StyleSheet, View } from 'react-native';
import { GeoMap } from '../components/GeoMap';
import { LoadGate } from '../components/LoadGate';
import { TopBar } from '../components/TopBar';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { estatePoints } from '@daa/core';
import { besiddelserVist, ejerTekst } from '../data/besiddelser';
import { useGeoOnMount } from '../hooks/useGeoOnMount';
import { useStore } from '../store/useStore';
import { Border, Colors, Shadow } from '../theme/tokens';

export default function EstatesScreen() {
  const router = useRouter();
  const aux = useStore((s) => s.aux);
  const model = useStore((s) => s.model);
  const geo = useStore((s) => s.geo);
  const geoLoading = useStore((s) => s.geoLoading);
  const estateList = useMemo(() => besiddelserVist(aux?.estateList ?? [], model), [aux, model]);
  const [viewMode, setViewMode] = useState<'liste' | 'kort'>('liste');
  const points = estatePoints(geo);

  // Lazy geo-kæde (review 27 P3): Godser-fladen bruger geo (kort-toggle + gods-minikort på
  // detalje) — udløs hentningen ved mount af hele fladen, ikke kun når kort-toggle vælges
  // (mirror af web's Folgesvend.tsx, hvor 'estates'-mode dækker begge under-visninger).
  useGeoOnMount();

  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Besiddelser" />
      <View style={styles.toggleRow}>
        {(['liste', 'kort'] as const).map((m) => (
          <Pressable key={m} onPress={() => setViewMode(m)} style={[styles.toggleBtn, viewMode === m && styles.toggleBtnActive]}>
            <BtnLabel size={11.5} color={viewMode === m ? Colors.bordeaux : Colors.inkMuted}>
              {m === 'liste' ? 'Liste' : 'Kort'}
            </BtnLabel>
          </Pressable>
        ))}
      </View>
      <LoadGate>
        {viewMode === 'kort' ? (
          geoLoading ? (
            <View style={{ padding: 22 }}>
              <Body size={13} color={Colors.inkMuted}>Indlæser kort…</Body>
            </View>
          ) : points.length ? (
            <GeoMap
              points={points}
              mode="explorer"
              onPointPress={(p) => p.estateId && router.push(`/estate/${p.estateId}`)}
            />
          ) : (
            <View style={{ padding: 22 }}>
              <Body size={13} color={Colors.inkMuted}>Ingen besiddelser er kortlagt endnu.</Body>
            </View>
          )
        ) : (
          <FlatList
            style={{ flex: 1 }}
            data={estateList}
            keyExtractor={(e) => e.id}
            contentContainerStyle={{ padding: 18, paddingBottom: 40 }}
            ListEmptyComponent={<Body size={13} color={Colors.inkMuted}>Ingen besiddelser registreret.</Body>}
            ListHeaderComponent={
              <Body size={13} color={Colors.inkMuted} style={{ marginBottom: 14 }}>
                Godser, gårde, len og stamhuse, slægten har ejet. Vælg en for ejerrækken gennem tiden.
              </Body>
            }
            renderItem={({ item }) => (
              <Pressable style={styles.card} onPress={() => router.push(`/estate/${item.id}`)}>
                <View style={styles.crest}>
                  <Serif size={17} color={Colors.bordeaux}>⌂</Serif>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={20} style={{ lineHeight: 21 }}>{item.navn}</Serif>
                  <Body size={12} color={Colors.inkMuted} style={{ marginTop: 2 }}>
                    {ejerTekst(item.ownerCount)}
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
    flexDirection: 'row', gap: 2, backgroundColor: Colors.surfaceSunken, borderRadius: 8,
    padding: 2, marginHorizontal: 18, marginBottom: 4, alignSelf: 'flex-start',
  },
  toggleBtn: { paddingVertical: 6, paddingHorizontal: 12, borderRadius: 6 },
  toggleBtnActive: { backgroundColor: Colors.surfaceRaised },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 13,
    paddingVertical: 13,
    paddingHorizontal: 15,
    marginBottom: 9,
    ...Shadow.card,
  },
  crest: {
    width: 38, height: 38, borderRadius: 8, backgroundColor: Colors.surfaceSunken,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
});
