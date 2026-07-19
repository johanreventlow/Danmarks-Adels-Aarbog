import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { CenterMsg } from '../../../../components/CenterMsg';
import { TopBar } from '../../../../components/TopBar';
import { Body, BtnLabel, Mono, Serif } from '../../../../components/Typography';
import { MediaDetaljeSheet } from '../../../../components/redaktion/MediaDetaljeSheet';
import { SkrivePreviewSheet } from '../../../../components/redaktion/SkrivePreviewSheet';
import { pickerSheetStyles } from '../../../../components/redaktion/pickerSheetStyles';
import {
  fetchLineages, fetchMediaAnvendelse, fetchMediaBibliotek,
  type MediaAnvendelse, type MediaBibliotekPost,
} from '../../../../data/redaktionRead';
import type { Change } from '../../../../data/redaktionWrite';
import { useMediaAndThumbUris } from '../../../../lib/media';
import { useStore } from '../../../../store/useStore';
import { Border, Colors, Radius } from '../../../../theme/tokens';

type MaalType = 'person' | 'estate' | 'coat_of_arms' | 'lineage';
type PickerItem = { id: string; label: string; sub: string };

function MediaTilknytPicker({ mediaId, udelukkedeMaal, onClose, onVaelg }: {
  mediaId: string;
  udelukkedeMaal?: ReadonlySet<string>;
  onClose: () => void;
  onVaelg: (change: Change) => void;
}) {
  const [maalType, setMaalType] = useState<MaalType>('person');
  const [query, setQuery] = useState('');
  const [items, setItems] = useState<PickerItem[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const model = useStore((s) => s.redaktionModel);
  const aux = useStore((s) => s.redaktionAux);

  useEffect(() => {
    let aktiv = true; setStatus('loading'); setItems([]);
    const hent: Promise<PickerItem[]> = maalType === 'person'
      ? Promise.resolve((model?.persons ?? []).map((p) => ({ id: p.id, label: p.name, sub: [p.born, p.died].filter(Boolean).join('–') || '—' })))
      : maalType === 'lineage'
        ? fetchLineages().then((rows) => rows.map((l) => ({ id: String(l.id), label: l.navn ?? `Linje ${l.kode}`, sub: `Linje ${l.kode}` })))
        : maalType === 'estate'
          ? Promise.resolve((aux?.godsListe ?? []).map((g) => ({ id: g.id, label: g.navn, sub: g.slags })))
          : Promise.resolve((aux?.vaabenListe ?? []).map((v) => ({ id: v.id, label: v.blasonering || '(uden blasonering)', sub: v.note })));
    hent.then((rows) => { if (aktiv) { setItems(rows); setStatus('ready'); } })
      .catch(() => { if (aktiv) setStatus('error'); });
    return () => { aktiv = false; };
  }, [maalType, model, aux]);

  const synlige = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items
      .filter((it) => !udelukkedeMaal?.has(`${maalType}:${it.id}`))
      .filter((it) => !q || `${it.label} ${it.sub}`.toLowerCase().includes(q)).slice(0, 60);
  }, [items, query, maalType, udelukkedeMaal]);
  const typer: { key: MaalType; label: string }[] = [
    { key: 'person', label: 'Person' }, { key: 'estate', label: 'Gods' },
    { key: 'coat_of_arms', label: 'Våben' }, { key: 'lineage', label: 'Linje' },
  ];

  return <Modal visible transparent animationType="slide" onRequestClose={onClose}>
    <Pressable style={pickerSheetStyles.backdrop} onPress={onClose} />
    <View style={pickerSheetStyles.sheet}>
      <Serif size={20} style={{ marginBottom: 10 }}>Tilknyt medie</Serif>
      <View style={styles.typer}>{typer.map((t) => <Pressable key={t.key} onPress={() => { setMaalType(t.key); setQuery(''); }} style={[styles.typeChip, maalType === t.key && styles.typeChipAktiv]}>
        <BtnLabel size={10} color={maalType === t.key ? '#fff' : Colors.textSecondary2}>{t.label}</BtnLabel>
      </Pressable>)}</View>
      <TextInput style={pickerSheetStyles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
        value={query} onChangeText={setQuery} autoFocus autoCorrect={false} />
      <ScrollView style={{ maxHeight: 380 }} keyboardShouldPersistTaps="handled">
        {status === 'loading' ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Henter…</Body> : null}
        {status === 'error' ? <Body color={Colors.danger} style={{ padding: 12 }}>Kunne ikke hente mål.</Body> : null}
        {status === 'ready' && !synlige.length ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen træffere.</Body> : null}
        {synlige.map((it) => <Pressable key={it.id} style={pickerSheetStyles.row} onPress={() => onVaelg({
          art: 'tilknytMedia', subjektType: 'media', subjektId: mediaId, mediaId,
          payload: { maalType, maalId: it.id },
        })}>
          <Body size={14}>{it.label}</Body><Mono size={9} color={Colors.textMuted}>{it.sub}</Mono>
        </Pressable>)}
      </ScrollView>
    </View>
  </Modal>;
}

export default function MedieDetalje() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const rolle = useStore((s) => s.rolle);
  const loadRedaktionModel = useStore((s) => s.loadRedaktionModel);
  const [media, setMedia] = useState<MediaBibliotekPost | null>(null);
  const [anvendelse, setAnvendelse] = useState<MediaAnvendelse | undefined>();
  const [anvendelseFejl, setAnvendelseFejl] = useState('');
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pending, setPending] = useState<Change | null>(null);
  const [picker, setPicker] = useState(false);
  const hentSekvens = useRef(0);

  const hent = useCallback(() => {
    if (!id) return;
    const sekvens = ++hentSekvens.current;
    setStatus('loading'); setAnvendelse(undefined); setAnvendelseFejl('');
    fetchMediaBibliotek().then((rows) => {
      if (sekvens !== hentSekvens.current) return;
      const fundet = rows.find((m) => m.id === id) ?? null;
      setMedia(fundet); setStatus(fundet ? 'ready' : 'error');
    }).catch(() => { if (sekvens === hentSekvens.current) setStatus('error'); });
    fetchMediaAnvendelse(id).then((a) => {
      if (sekvens === hentSekvens.current) setAnvendelse(a);
    }).catch(() => {
      if (sekvens === hentSekvens.current) setAnvendelseFejl('Kunne ikke kontrollere anvendelser. Sletning er blokeret.');
    });
  }, [id]);
  useFocusEffect(useCallback(() => {
    hent();
    return () => { hentSekvens.current += 1; };
  }, [hent]));

  const { uris, thumbUris } = useMediaAndThumbUris(media ? [{
    id: media.id, storage_path: media.storagePath, thumb_storage_path: media.thumbStoragePath,
  }] : [], (m) => m.thumb_storage_path);
  const tilknyttedeMaal = useMemo(
    () => new Set((anvendelse?.afbildet ?? []).map((a) => `${a.type}:${a.id}`)),
    [anvendelse],
  );

  if (rolle !== 'redaktion') return <CenterMsg title="Medie">Kræver redaktør-rolle.</CenterMsg>;
  if (!id || status === 'error') return <CenterMsg title="Medie">Mediet kunne ikke hentes.</CenterMsg>;
  if (status === 'loading' || !media) return <CenterMsg title="Medie">Henter…</CenterMsg>;

  return <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
    <TopBar title={media.titel || 'Medie'} />
    <View style={{ padding: 18 }}><Body color={Colors.textMuted}>Filsiden er åben.</Body></View>
    {!picker && !pending ? <MediaDetaljeSheet media={media} uri={uris[media.id]} thumbUri={thumbUris[media.id]}
      anvendelse={anvendelse} anvendelseFejl={anvendelseFejl} onClose={() => router.back()}
      onGemMetadata={(payload) => setPending({ art: 'opdaterMedia', subjektType: 'media', subjektId: media.id, mediaId: media.id, payload })}
      onGemRettigheder={(payload) => setPending({ art: 'mediaRettigheder', subjektType: 'media', subjektId: media.id, mediaId: media.id, payload })}
      onFjern={() => {}}
      onFjernTilknytning={(relationId) => setPending({ art: 'sletRelation', subjektType: 'media', subjektId: media.id, relationId })}
      onTilknyt={() => setPicker(true)}
      onSlet={() => setPending({ art: 'fjernMedia', subjektType: 'media', subjektId: media.id, mediaId: media.id })}
      onGenopret={() => setPending({ art: 'genopretMedia', subjektType: 'media', subjektId: media.id, mediaId: media.id })} /> : null}
    {picker ? <MediaTilknytPicker mediaId={media.id} udelukkedeMaal={tilknyttedeMaal}
      onClose={() => setPicker(false)} onVaelg={(change) => { setPicker(false); setPending(change); }} /> : null}
    <SkrivePreviewSheet change={pending} onClose={() => setPending(null)} onApplied={() => {
      setPending(null); hent(); loadRedaktionModel(true).catch(() => {});
    }} />
  </View>;
}

const styles = StyleSheet.create({
  typer: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginBottom: 10 },
  typeChip: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 10, paddingVertical: 6 },
  typeChipAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
});
