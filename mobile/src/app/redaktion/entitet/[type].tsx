import { useLocalSearchParams, useRouter } from 'expo-router';
import { Image } from 'expo-image';
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { Body, Mono, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';
import type { MedieKoe } from '../../../data/redaktionRead';
import { useMediaAndThumbUris } from '../../../lib/media';

type Row = { id: string; titel: string; under: string; koeer?: MedieKoe[]; uploadStatus?: string; mimeType?: string };
const TITLER: Record<string, string> = {
  gods: 'Godser', kilde: 'Kilder', organisation: 'Organisationer', medie: 'Medier', vaaben: 'Våben',
};
// Entitetstyper med objekt-foto-materiale (Slice 0h) — eneste tappbare rækker, ingen fuld
// detail-editor findes endnu (jf. materiale.tsx's kommentar).
const HAR_MATERIALE = new Set(['gods', 'vaaben']);

export default function EntitetListe() {
  const { type } = useLocalSearchParams<{ type: string }>();
  const router = useRouter();
  const rolle = useStore((s) => s.rolle);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const aux = useStore((s) => s.redaktionAux);
  const [query, setQuery] = useState('');
  const [mediaKoe, setMediaKoe] = useState<MedieKoe | 'alle'>('alle');
  const { uris: mediaUris, thumbUris: mediaThumbUris } = useMediaAndThumbUris(
    (aux?.medieListe ?? []).map((m) => ({ id: m.id, storage_path: m.storagePath, thumb_storage_path: m.thumbStoragePath })),
    (m) => m.thumb_storage_path,
  );
  const titel = TITLER[type ?? ''] ?? 'Entiteter';

  // type → rækker fra redaktionAux (read-only).
  const rows = useMemo<Row[]>(() => {
    if (!aux) return [];
    if (type === 'gods') return aux.godsListe.map((g) => ({ id: g.id, titel: g.navn, under: `${g.slags || 'gods'} · ${g.ownerCount} ejere` }));
    if (type === 'kilde') return aux.kildeListe.map((k) => ({ id: k.id, titel: k.titel, under: [k.slags, k.udgave].filter(Boolean).join(' · ') }));
    if (type === 'organisation') return aux.orgListe.map((o) => ({ id: o.id, titel: o.navn, under: o.slags }));
    if (type === 'medie') return aux.medieListe.map((m) => ({
      id: m.id, titel: m.titel || '(uden titel)', koeer: m.koeer, uploadStatus: m.uploadStatus, mimeType: m.mimeType,
      under: [[m.slags, m.kunstner, m.datering].filter(Boolean).join(' · '),
        `bruges ${m.antalAfbildet + m.antalMentions} steder`, m.maaPubliceres ? '' : 'ej publiceret'].filter(Boolean).join(' · '),
    }));
    if (type === 'vaaben') return aux.vaabenListe.map((v) => ({ id: v.id, titel: v.blasonering || '(uden blasonering)', under: v.note }));
    return [];
  }, [aux, type]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((r) => (mediaKoe === 'alle' || r.koeer?.includes(mediaKoe)) && (!q || `${r.titel} ${r.under}`.toLowerCase().includes(q)));
  }, [rows, query, mediaKoe]);
  const erTappbar = HAR_MATERIALE.has(type ?? '') || type === 'medie';

  // Ukendt type-param → eksplicit besked (ikke en tavs tom liste). TITLER = allowlist.
  // Placeret EFTER alle hooks (ellers betinget hook-eksekvering ved param-skift) — cycle 05 M1.
  if (!TITLER[type ?? '']) return <CenterMsg title="Entiteter">Ukendt entitetstype.</CenterMsg>;
  // Auth-state (spec §4b): "Henter…" ALDRIG permanent for ikke-redaktører.
  if (rolle !== 'redaktion') return <CenterMsg title={titel}>Kræver redaktør-rolle.</CenterMsg>;
  if (redaktionStatus === 'error') return <CenterMsg title={titel}>Kunne ikke hente redaktion-data.</CenterMsg>;
  if (redaktionStatus !== 'ready') return <CenterMsg title={titel}>Henter…</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <TextInput style={styles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
        value={query} onChangeText={setQuery} autoCorrect={false} />
      {type === 'medie' && aux ? <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.koeer}>
        {([['alle', 'Alle'], ['rettigheder', 'Rettigheder'], ['loese', 'Løse'], ['strandede', 'Strandede'], ['papirkurv', 'Papirkurv']] as const).map(([key, label]) => {
          const aktiv = mediaKoe === key;
          const antal = key === 'alle' ? aux.medieListe.length : aux.medieKoeTaellere[key];
          return <Pressable key={key} onPress={() => setMediaKoe(key)} style={[styles.koe, aktiv && styles.koeAktiv]}>
            <Mono size={8.5} color={aktiv ? '#fff' : Colors.textSecondary2}>{label} ({antal})</Mono>
          </Pressable>;
        })}
      </ScrollView> : null}
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {/* gods/vaaben: tappbar → minimal materiale-skærm (Slice 0h). Øvrige typer har stadig
            ingen detail-editor (D1). Konstant for hele listen — beregnes én gang, ikke pr. række. */}
        {filtered.length === 0 ? (
          <Body color={Colors.textMuted}>Ingen {titel.toLowerCase()}.</Body>
        ) : (
          filtered.map((r) => {
            const erBillede = type === 'medie' && r.mimeType?.startsWith('image/') === true && !!mediaThumbUris[r.id] && !!mediaUris[r.id];
            return <Pressable key={r.id} disabled={!erTappbar} style={[styles.row, r.uploadStatus === 'fjernet' && { opacity: .5 }]}
              onPress={() => router.push({ pathname: type === 'medie' ? '/redaktion/entitet/medie/[id]' : '/redaktion/entitet/materiale', params: { type, id: r.id, navn: r.titel } })}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                {type === 'medie' ? erBillede
                  ? <Image source={{ uri: mediaThumbUris[r.id] }} style={styles.thumb} contentFit="cover" />
                  : <View style={[styles.thumb, styles.dokument]}><Mono size={18} color={Colors.textMuted}>▤</Mono></View>
                  : null}
                <View style={{ flex: 1 }}><Serif size={16}>{r.titel}{erTappbar ? ' ↗' : ''}</Serif>
                  {r.under ? <Mono size={9} color={Colors.textMuted}>{r.under}</Mono> : null}</View>
              </View>
            </Pressable>;
          })
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, marginHorizontal: 16, marginTop: 8, paddingHorizontal: 12, paddingVertical: 9,
    fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, padding: 12, marginBottom: 7 },
  koeer: { gap: 6, paddingHorizontal: 16, paddingTop: 10 },
  koe: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 10, paddingVertical: 6 },
  koeAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  thumb: { width: 44, height: 44, borderRadius: Radius.field, backgroundColor: Colors.beige2 },
  dokument: { alignItems: 'center', justifyContent: 'center' },
});
