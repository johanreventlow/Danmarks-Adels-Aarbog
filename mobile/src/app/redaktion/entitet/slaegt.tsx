// Slægts/linje-narrativ-editor — vælger-skærm (billeder-i-narrativer 2026-07-05, Slice C3).
// Viser den faste "Generelt"-post (subjekt_type='slaegt', subjekt_id=1 — en delt sentinel-
// konstant, IKKE en fremmednøgle) + én post pr. navngiven linje (subjekt_type='lineage',
// subjekt_id=<lineage.id>). Spejler web's Redaktion.tsx's tilsvarende slaegt-liste.
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { Body, Mono, Serif } from '../../../components/Typography';
import { fetchLineages, type LineageRow } from '../../../data/redaktionRead';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

// Sentinel-konstant (ikke en fremmednøgle) — se NarrativEditor/schema-note i plan-dokumentet.
const SLAEGT_SUBJEKT_ID = 1;

export default function SlaegtListe() {
  const router = useRouter();
  const rolle = useStore((s) => s.rolle);
  const [lineages, setLineages] = useState<LineageRow[]>([]);
  useEffect(() => { fetchLineages().then(setLineages).catch(() => setLineages([])); }, []);

  if (rolle !== 'redaktion') return <CenterMsg title="Slægten">Kræver redaktør-rolle.</CenterMsg>;

  const rows = [
    { subjektType: 'slaegt', subjektId: String(SLAEGT_SUBJEKT_ID), navn: 'Generelt', under: 'hele slægten' },
    ...lineages.map((l) => ({ subjektType: 'lineage', subjektId: String(l.id), navn: l.navn ?? `Linje ${l.kode}`, under: 'linje' })),
  ];

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Slægten" showBack={false} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {rows.map((r) => (
          <Pressable key={`${r.subjektType}:${r.subjektId}`}
            onPress={() => router.push({ pathname: '/redaktion/entitet/slaegt-narrativ', params: { subjektType: r.subjektType, subjektId: r.subjektId, navn: r.navn } })}
            style={{ backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field, padding: 12, marginBottom: 7 }}>
            <Serif size={16}>{r.navn}</Serif>
            <Mono size={9} color={Colors.textMuted}>{r.under}</Mono>
          </Pressable>
        ))}
        {!lineages.length && <Body color={Colors.textMuted} style={{ marginTop: 8 }}>Henter linjer…</Body>}
      </ScrollView>
    </View>
  );
}
