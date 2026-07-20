import { useEffect, useState } from 'react';
import { Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { MediaGallery } from './MediaGallery';
import { MediaDetaljeSheet } from './MediaDetaljeSheet';
import { MediaUploadSheet } from './MediaUploadSheet';
import { SkrivePreviewSheet } from './SkrivePreviewSheet';
import { Mono } from '../Typography';
import { useMediaAndThumbUris } from '../../lib/media';
import { fetchMediaAnvendelse, fetchObjectMediaRed, type MediaAnvendelse, type PersonMedia } from '../../data/redaktionRead';
import { type Change } from '../../data/redaktionWrite';
import { Colors } from '../../theme/tokens';

export function MaterialeSektion({ objektType, objektId, onMediaChange }: {
  objektType: string; objektId: string;
  onMediaChange?: (media: PersonMedia[]) => void;
}) {
  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [valgt, setValgt] = useState<PersonMedia | null>(null);
  const [anvendelse, setAnvendelse] = useState<MediaAnvendelse | undefined>();
  const [anvendelseFejl, setAnvendelseFejl] = useState('');
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);
  const router = useRouter();
  const refreshMedia = () => {
    fetchObjectMediaRed(objektType, objektId).then((m) => { setMedia(m); onMediaChange?.(m); }).catch(() => {});
  };
  useEffect(refreshMedia, [objektType, objektId]);
  const { uris: mediaUris, thumbUris: mediaThumbUris } = useMediaAndThumbUris(
    media.map((m) => ({ id: m.id, storage_path: m.storagePath, thumb_storage_path: m.thumbStoragePath })),
    (m) => m.thumb_storage_path,
  );
  useEffect(() => {
    if (!valgt) { setAnvendelse(undefined); setAnvendelseFejl(''); return; }
    let aktiv = true; setAnvendelse(undefined); setAnvendelseFejl('');
    fetchMediaAnvendelse(valgt.id).then((a) => { if (aktiv) setAnvendelse(a); })
      .catch(() => { if (aktiv) setAnvendelseFejl('Kunne ikke kontrollere anvendelser. Sletning er blokeret.'); });
    return () => { aktiv = false; };
  }, [valgt?.id]);
  const change = (c: Change) => { setPending(c); setValgt(null); };

  return <>
    <MediaGallery media={media} mediaUris={mediaUris} mediaThumbUris={mediaThumbUris}
      onVaelg={setValgt}
      onFjern={(m) => change({ art: 'sletRelation', subjektType: objektType, subjektId: objektId, relationId: m.relationId })}
      onGenopret={(m) => change({ art: 'genopretMedia', subjektType: objektType, subjektId: objektId, mediaId: m.id })} />
    <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
      <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
    </Pressable>
    {valgt ? <MediaDetaljeSheet media={valgt} uri={mediaUris[valgt.id]} thumbUri={mediaThumbUris[valgt.id]}
      anvendelse={anvendelse} anvendelseFejl={anvendelseFejl} onClose={() => setValgt(null)}
      onGemMetadata={(payload) => change({ art: 'opdaterMedia', subjektType: objektType, subjektId: objektId, mediaId: valgt.id, payload })}
      onGemRettigheder={(payload) => change({ art: 'mediaRettigheder', subjektType: objektType, subjektId: objektId, mediaId: valgt.id, payload })}
      onFjern={() => change({ art: 'sletRelation', subjektType: objektType, subjektId: objektId, relationId: valgt.relationId })}
      onFjernTilknytning={(relationId) => change({ art: 'sletRelation', subjektType: 'media', subjektId: valgt.id, relationId })}
      onTilknyt={() => { const mediaId = valgt.id; setValgt(null); router.push({ pathname: '/redaktion/entitet/medie/[id]', params: { id: mediaId } }); }}
      onSlet={() => change({ art: 'fjernMedia', subjektType: objektType, subjektId: objektId, mediaId: valgt.id })}
      onGenopret={() => change({ art: 'genopretMedia', subjektType: objektType, subjektId: objektId, mediaId: valgt.id })} /> : null}
    {uploadSheetOpen ? <MediaUploadSheet target={{ objektType, objektId }} onClose={() => setUploadSheetOpen(false)}
      onApplied={refreshMedia}
      onGem={(payload) => { setPending({ art: 'uploadMedia', subjektType: objektType, subjektId: objektId, payload }); setUploadSheetOpen(false); }} /> : null}
    <SkrivePreviewSheet change={pending} onClose={() => setPending(null)} onApplied={() => { setPending(null); refreshMedia(); }} />
  </>;
}
