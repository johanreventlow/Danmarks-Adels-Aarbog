import { useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body, Mono, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

type Row = { id: string; titel: string; under: string };
const TITLER: Record<string, string> = {
  gods: 'Godser', kilde: 'Kilder', organisation: 'Organisationer', medie: 'Medier', vaaben: 'Våben',
};

export default function EntitetListe() {
  const { type } = useLocalSearchParams<{ type: string }>();
  const rolle = useStore((s) => s.rolle);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const aux = useStore((s) => s.redaktionAux);
  const [query, setQuery] = useState('');
  const titel = TITLER[type ?? ''] ?? 'Entiteter';

  // type → rækker fra redaktionAux (read-only).
  const rows = useMemo<Row[]>(() => {
    if (!aux) return [];
    if (type === 'gods') return aux.godsListe.map((g) => ({ id: g.id, titel: g.navn, under: `${g.slags || 'gods'} · ${g.ownerCount} ejere` }));
    if (type === 'kilde') return aux.kildeListe.map((k) => ({ id: k.id, titel: k.titel, under: [k.slags, k.udgave].filter(Boolean).join(' · ') }));
    if (type === 'organisation') return aux.orgListe.map((o) => ({ id: o.id, titel: o.navn, under: o.slags }));
    if (type === 'medie') return aux.medieListe.map((m) => ({ id: m.id, titel: m.titel || '(uden titel)', under: [m.slags, m.kunstner, m.datering].filter(Boolean).join(' · ') }));
    if (type === 'vaaben') return aux.vaabenListe.map((v) => ({ id: v.id, titel: v.blasonering || '(uden blasonering)', under: v.note }));
    return [];
  }, [aux, type]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? rows.filter((r) => r.titel.toLowerCase().includes(q)) : rows;
  }, [rows, query]);

  // Auth-state (spec §4b): "Henter…" ALDRIG permanent for ikke-redaktører.
  if (rolle !== 'redaktion') return <Msg title={titel}>Kræver redaktør-rolle.</Msg>;
  if (redaktionStatus === 'error') return <Msg title={titel}>Kunne ikke hente redaktion-data.</Msg>;
  if (redaktionStatus !== 'ready') return <Msg title={titel}>Henter…</Msg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <TextInput style={styles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
        value={query} onChangeText={setQuery} autoCorrect={false} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {filtered.length === 0 ? (
          <Body color={Colors.textMuted}>Ingen {titel.toLowerCase()}.</Body>
        ) : (
          filtered.map((r) => (
            // Ikke-tappbar (D1) — ingen detail-editor endnu.
            <View key={r.id} style={styles.row}>
              <Serif size={16}>{r.titel}</Serif>
              {r.under ? <Mono size={9} color={Colors.textMuted}>{r.under}</Mono> : null}
            </View>
          ))
        )}
      </ScrollView>
    </View>
  );
}

function Msg({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={title} />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>{children}</Body>
    </View>
  );
}

const styles = StyleSheet.create({
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, marginHorizontal: 16, marginTop: 8, paddingHorizontal: 12, paddingVertical: 9,
    fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, padding: 12, marginBottom: 7 },
});
