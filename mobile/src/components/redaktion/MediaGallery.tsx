import { Image } from 'expo-image';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Mono } from '../Typography';
import { Colors } from '../../theme/tokens';
import type { PersonMedia } from '../../data/redaktionRead';
import { Lightbox } from '../Lightbox';

// Materiale-galleri (mediehåndtering Slice 0g+0h) — delt mellem person-editoren og objekt-foto-
// skærmen (gods/våben). Fjern = afkobl KUN dette subjekt (sletRelation, media+Storage upåvirket).
// Slet = blødt fjern OVERALT (fjernMedia, upload_status='fjernet'), fortrydbar via historik.
// Lightbox (Slice A) er selvstændig state her — begge kaldere (person-editor, objekt-materiale)
// får klik-for-at-forstørre gratis uden selv at holde styr på det.
// mediaThumbUris (billedstørrelser 2026-07-05, Slice B3) er valgfri: kalderen kan udelade den (fx
// hvis ingen thumb-variant er hentet), hvorved galleriet falder tilbage til den fulde ('large') uri
// — samme fallback-kontrakt som web's thumbUrl.
export function MediaGallery({ media, mediaUris, mediaThumbUris = {}, onFjern, onSlet }: {
  media: PersonMedia[];
  mediaUris: Record<string, string>;
  mediaThumbUris?: Record<string, string>;
  onFjern: (m: PersonMedia) => void;
  onSlet: (m: PersonMedia) => void;
}) {
  const [lightbox, setLightbox] = useState<number | null>(null);
  if (!media.length) {
    return <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 8 }}>— intet materiale endnu</Mono>;
  }
  const lightboxItems = media
    .filter((m) => mediaUris[m.id])
    .map((m) => ({ id: m.id, uri: mediaUris[m.id], titel: m.titel }));
  return (
    <>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, marginBottom: 10 }}>
      {media.map((m) => (
        <View key={m.id} style={{ width: 96 }}>
          {mediaUris[m.id] ? (
            <Pressable onPress={() => setLightbox(lightboxItems.findIndex((x) => x.id === m.id))}>
              <Image source={{ uri: mediaThumbUris[m.id] ?? mediaUris[m.id] }} style={styles.mediaThumb} contentFit="cover" />
            </Pressable>
          ) : (
            <View style={styles.mediaThumb} />
          )}
          <Mono size={8} color={Colors.textMuted} numberOfLines={1} style={{ marginTop: 3 }}>
            {m.slags}{m.uploadStatus !== 'klar' ? ` · ${m.uploadStatus}` : ''}
            {m.maaPubliceres ? '' : ' · ej publiceret'}
          </Mono>
          <View style={{ flexDirection: 'row', gap: 8, marginTop: 3 }}>
            <Pressable disabled={!m.relationId} onPress={() => onFjern(m)}>
              <Mono size={8} color={m.relationId ? Colors.textSecondary2 : Colors.textMuted3}>Fjern</Mono>
            </Pressable>
            <Pressable onPress={() => onSlet(m)}>
              <Mono size={8} color={Colors.danger}>Slet</Mono>
            </Pressable>
          </View>
        </View>
      ))}
      </ScrollView>
      {lightbox != null ? (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      ) : null}
    </>
  );
}

const styles = StyleSheet.create({
  mediaThumb: { width: 96, height: 96, borderRadius: 10, backgroundColor: Colors.beige2 },
});
