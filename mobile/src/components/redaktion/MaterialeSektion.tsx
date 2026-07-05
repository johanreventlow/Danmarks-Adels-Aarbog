// Delt materiale-galleri + upload/fjern/slet-flow (mediehåndtering Slice 0h) — udtrukket
// (billeder-i-narrativer 2026-07-05, Slice C /simplify) fra entitet/materiale.tsx, da
// entitet/slaegt-narrativ.tsx blev en ANDEN forbruger af nøjagtig samme mønster. Spejler web's
// Redaktion.tsx's renderMateriale(), som allerede er en delt funktion for det tilsvarende.
// Selvstændig (egen media/pending-state + eget SkrivePreviewSheet) — kalderen leverer kun
// objektType/objektId og omgiver den med sin egen skærm-chrome (titel, ScrollView osv.).
import { useEffect, useState } from 'react';
import { Pressable } from 'react-native';
import { MediaGallery } from './MediaGallery';
import { MediaUploadSheet } from './MediaUploadSheet';
import { SkrivePreviewSheet } from './SkrivePreviewSheet';
import { Mono } from '../Typography';
import { useMediaAndThumbUris } from '../../lib/media';
import { fetchObjectMediaRed, type PersonMedia } from '../../data/redaktionRead';
import { type Change } from '../../data/redaktionWrite';
import { Colors } from '../../theme/tokens';

export function MaterialeSektion({ objektType, objektId, onMediaChange }: {
  objektType: string; objektId: string;
  // Valgfri: kalderen kan spejle den hentede liste (fx til NarrativEditors billed-picker, der har
  // brug for DENNE subjekts egne billeder) uden selv at duplikere fetch/refresh-logikken.
  onMediaChange?: (media: PersonMedia[]) => void;
}) {
  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);
  const refreshMedia = () => {
    fetchObjectMediaRed(objektType, objektId).then((m) => { setMedia(m); onMediaChange?.(m); }).catch(() => {});
  };
  useEffect(refreshMedia, [objektType, objektId]);
  const { uris: mediaUris, thumbUris: mediaThumbUris } = useMediaAndThumbUris(
    media.map((m) => ({ id: m.id, storage_path: m.storagePath, thumb_storage_path: m.thumbStoragePath })),
    (m) => m.thumb_storage_path,
  );

  return (
    <>
      <MediaGallery
        media={media}
        mediaUris={mediaUris}
        mediaThumbUris={mediaThumbUris}
        onFjern={(m) => setPending({ art: 'sletRelation', subjektType: objektType, subjektId: objektId, relationId: m.relationId })}
        onSlet={(m) => setPending({ art: 'fjernMedia', subjektType: objektType, subjektId: objektId, mediaId: m.id })}
      />
      <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
        <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
      </Pressable>
      {uploadSheetOpen ? (
        <MediaUploadSheet
          target={{ objektType, objektId }}
          onClose={() => setUploadSheetOpen(false)}
          onGem={(payload) => {
            setPending({ art: 'uploadMedia', subjektType: objektType, subjektId: objektId, payload });
            setUploadSheetOpen(false);
          }}
        />
      ) : null}
      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={() => { setPending(null); refreshMedia(); }}
      />
    </>
  );
}
