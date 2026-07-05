// Slægts/linje-narrativ-editor — redigerings-skærm (billeder-i-narrativer 2026-07-05, Slice C3).
// subjektType 'slaegt' (fast sentinel) eller 'lineage' (rigtig lineage.id, sat af slaegt.tsx).
// Genbruger NarrativEditor uændret (samme komponent som person-editoren) + Materiale-galleri KUN
// for linjer — "Generelt" er en sentinel uden egen billed-samling, jf. schema-noten i plan-doc'et.
import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { Mono, Serif } from '../../../components/Typography';
import { NarrativEditor } from '../../../components/redaktion/NarrativEditor';
import { MediaGallery } from '../../../components/redaktion/MediaGallery';
import { MediaUploadSheet } from '../../../components/redaktion/MediaUploadSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { useMediaAndThumbUris } from '../../../lib/media';
import { fetchObjectMediaRed, type PersonMedia } from '../../../data/redaktionRead';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

export default function SlaegtNarrativ() {
  const { subjektType, subjektId, navn } = useLocalSearchParams<{ subjektType: string; subjektId: string; navn?: string }>();
  const rolle = useStore((s) => s.rolle);
  const erLinje = subjektType === 'lineage';

  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);
  const refreshMedia = () => { if (erLinje && subjektId) fetchObjectMediaRed('lineage', subjektId).then(setMedia).catch(() => {}); };
  useEffect(refreshMedia, [erLinje, subjektId]);
  const { uris: mediaUris, thumbUris: mediaThumbUris } = useMediaAndThumbUris(
    media.map((m) => ({ id: m.id, storage_path: m.storagePath, thumb_storage_path: m.thumbStoragePath })),
    (m) => m.thumb_storage_path,
  );

  const titel = navn ?? '(uden navn)';

  if (!subjektType || !subjektId) return <CenterMsg title="Slægten">Ukendt post.</CenterMsg>;
  if (rolle !== 'redaktion') return <CenterMsg title={titel}>Kræver redaktør-rolle.</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <Serif size={22} style={{ marginBottom: 4 }}>{titel}</Serif>

        {/* Billed-indsættelses-picker'en i NarrativEditor viser DENNE subjekts egne billeder —
            for lineage er det den samme liste som Materiale-galleriet nedenfor. */}
        <NarrativEditor subjektType={subjektType} subjektId={subjektId} media={media} mediaThumbUris={mediaThumbUris} />

        {erLinje && (
          <View style={{ marginTop: 20, paddingTop: 16, borderTopWidth: 1, borderTopColor: Colors.beige2 }}>
            <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Materiale</Mono>
            <MediaGallery
              media={media}
              mediaUris={mediaUris}
              mediaThumbUris={mediaThumbUris}
              onFjern={(m) => setPending({ art: 'sletRelation', subjektType: 'lineage', subjektId, relationId: m.relationId })}
              onSlet={(m) => setPending({ art: 'fjernMedia', subjektType: 'lineage', subjektId, mediaId: m.id })}
            />
            <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
              <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
            </Pressable>
          </View>
        )}
      </ScrollView>

      {uploadSheetOpen ? (
        <MediaUploadSheet
          target={{ objektType: 'lineage', objektId: subjektId }}
          onClose={() => setUploadSheetOpen(false)}
          onGem={(payload) => {
            setPending({ art: 'uploadMedia', subjektType: 'lineage', subjektId, payload });
            setUploadSheetOpen(false);
          }}
        />
      ) : null}
      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={() => { setPending(null); refreshMedia(); }}
      />
    </View>
  );
}
