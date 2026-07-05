// Objekt-foto (mediehåndtering Slice 0h): minimal materiale-skærm for entiteter uden nogen
// detail-editor endnu (gods/våben). Bevidst IKKE en fuld editor — kun galleri + upload/fjern/slet,
// samme mønster som person-editorens Materiale-sektion, genbruger samme sheet + galleri + RPC'er.
import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { Mono, Serif } from '../../../components/Typography';
import { MediaGallery } from '../../../components/redaktion/MediaGallery';
import { MediaUploadSheet } from '../../../components/redaktion/MediaUploadSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { useMediaUris } from '../../../lib/media';
import { fetchObjectMediaRed, type PersonMedia } from '../../../data/redaktionRead';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

// UI-entitetsnøgle (matcher entitet/[type].tsx) → objekt_type i basen (matcher tabelnavnet, jf.
// red_upload_media/red_relation's polymorfe objekt_type-konvention: 'estate', 'organisation', ...).
const OBJEKT_TYPE: Record<string, string> = { gods: 'estate', vaaben: 'coat_of_arms' };

export default function ObjektMateriale() {
  const { type, id, navn } = useLocalSearchParams<{ type: string; id: string; navn?: string }>();
  const rolle = useStore((s) => s.rolle);
  const objektType = OBJEKT_TYPE[type ?? ''];

  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);
  const refreshMedia = () => { if (objektType && id) fetchObjectMediaRed(objektType, id).then(setMedia).catch(() => {}); };
  useEffect(refreshMedia, [objektType, id]);
  const mediaUris = useMediaUris(media.map((m) => ({ id: m.id, storage_path: m.storagePath })));
  const mediaThumbUris = useMediaUris(media.map((m) => ({ id: m.id, storage_path: m.thumbStoragePath })));

  const titel = navn ?? '(uden navn)';

  if (!objektType) return <CenterMsg title="Materiale">Ukendt entitetstype.</CenterMsg>;
  if (rolle !== 'redaktion') return <CenterMsg title={titel}>Kræver redaktør-rolle.</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <Serif size={20} style={{ marginBottom: 4 }}>{titel}</Serif>
        <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 14 }}>Materiale</Mono>
        <MediaGallery
          media={media}
          mediaUris={mediaUris}
          mediaThumbUris={mediaThumbUris}
          onFjern={(m) => setPending({ art: 'sletRelation', subjektType: objektType, subjektId: id!, relationId: m.relationId })}
          onSlet={(m) => setPending({ art: 'fjernMedia', subjektType: objektType, subjektId: id!, mediaId: m.id })}
        />
        <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
          <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
        </Pressable>
      </ScrollView>

      {uploadSheetOpen ? (
        <MediaUploadSheet
          target={{ objektType, objektId: id! }}
          onClose={() => setUploadSheetOpen(false)}
          onGem={(payload) => {
            setPending({ art: 'uploadMedia', subjektType: objektType, subjektId: id!, payload });
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
