// Dashboard-worklist (Problem 2 §6): personer m. konkurrerende forældre-påstande
// (red_foraeldre_konflikt). Klik → åbn personen, hvor ForaeldrePaastandePanel adjudicerer.
import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, View } from 'react-native';
import { useRouter } from 'expo-router';
import { CenterMsg } from '../../components/CenterMsg';
import { TopBar } from '../../components/TopBar';
import { Body, Mono, Serif } from '../../components/Typography';
import { fetchForaeldreKonflikter, type ForaeldreKonflikt } from '../../data/redaktionRead';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

export default function ForaeldreKonflikter() {
  const rolle = useStore((s) => s.rolle);
  const router = useRouter();
  const [rows, setRows] = useState<ForaeldreKonflikt[] | undefined>(undefined);
  const [fejl, setFejl] = useState<string | null>(null); // review 30/Codex #2: fejl må ikke maskeres som "ingen konflikter"
  useEffect(() => {
    let alive = true;
    fetchForaeldreKonflikter().then((r) => { if (alive) setRows(r); }).catch((e) => { if (alive) setFejl(String((e as { message?: string })?.message ?? e)); });
    return () => { alive = false; };
  }, []);

  if (rolle !== 'redaktion') return <CenterMsg title="Forældre-konflikter">Kræver redaktør-rolle.</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Forældre-konflikter" />
      <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 32 }}>
        <Body size={13} color={Colors.textMuted} style={{ marginBottom: 14 }}>
          Personer hvor to udgaver påstår forskellige forældrefamilier. Åbn personen for at se påstandene og vælge den kanoniske (begge bevares, kildebundet).
        </Body>
        {fejl ? (
          <View style={{ borderWidth: 1, borderColor: Colors.bordeaux, borderRadius: Radius.card, backgroundColor: Colors.bordeauxFillLight, padding: 12 }}>
            <Body size={13} color={Colors.danger}>Kunne ikke hente konflikt-listen: {fejl}. (Konflikter kan ikke vises — ikke nødvendigvis fordi der ingen er.)</Body>
          </View>
        ) : rows === undefined ? <ActivityIndicator style={{ marginTop: 24 }} /> : rows.length === 0 ? (
          <Body color={Colors.textMuted}>Ingen forældre-konflikter — alle personer har én afklaret forældrefamilie.</Body>
        ) : null}
        {(rows ?? []).map((r) => (
          <Pressable key={r.factId} onPress={() => router.push(`/redaktion/person/${r.personId}` as never)}
            style={{ flexDirection: 'row', alignItems: 'center', gap: 10, padding: 12, marginBottom: 8,
              borderWidth: 1, borderColor: Colors.bordeaux, borderRadius: Radius.card, backgroundColor: Colors.bordeauxFillLight }}>
            <Mono size={9} color={Colors.bordeaux} style={{ letterSpacing: 1 }}>{(r.status ?? 'omstridt').toUpperCase()}</Mono>
            <Serif size={15} style={{ flex: 1 }}>{r.navn ?? `Person ${r.personId}`}</Serif>
            <Mono size={11} color={Colors.textMuted}>{r.antalFamilier} fam · {r.antalPaastande} påst.</Mono>
            <Body size={16} color={Colors.bordeaux}>→</Body>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}
