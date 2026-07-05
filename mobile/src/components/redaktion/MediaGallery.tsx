import { Image } from 'expo-image';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Mono } from '../Typography';
import { Colors } from '../../theme/tokens';
import type { PersonMedia } from '../../data/redaktionRead';

// Materiale-galleri (mediehåndtering Slice 0g+0h) — delt mellem person-editoren og objekt-foto-
// skærmen (gods/våben). Fjern = afkobl KUN dette subjekt (sletRelation, media+Storage upåvirket).
// Slet = blødt fjern OVERALT (fjernMedia, upload_status='fjernet'), fortrydbar via historik.
export function MediaGallery({ media, mediaUris, onFjern, onSlet }: {
  media: PersonMedia[];
  mediaUris: Record<string, string>;
  onFjern: (m: PersonMedia) => void;
  onSlet: (m: PersonMedia) => void;
}) {
  if (!media.length) {
    return <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 8 }}>— intet materiale endnu</Mono>;
  }
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, marginBottom: 10 }}>
      {media.map((m) => (
        <View key={m.id} style={{ width: 96 }}>
          {mediaUris[m.id] ? (
            <Image source={{ uri: mediaUris[m.id] }} style={styles.mediaThumb} contentFit="cover" />
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
  );
}

const styles = StyleSheet.create({
  mediaThumb: { width: 96, height: 96, borderRadius: 10, backgroundColor: Colors.beige2 },
});
