import { Image } from 'expo-image';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Mono } from '../Typography';
import { Colors } from '../../theme/tokens';
import type { PersonMedia } from '../../data/redaktionRead';

// Kompakt galleri. Tryk åbner filsiden; kun filsiden åbner lightbox, så fjernede medier
// aldrig kan lække ind i preview-navigationen.
export function MediaGallery({ media, mediaUris, mediaThumbUris = {}, onVaelg, onFjern, onGenopret }: {
  media: PersonMedia[];
  mediaUris: Record<string, string>;
  mediaThumbUris?: Record<string, string>;
  onVaelg: (m: PersonMedia) => void;
  onFjern: (m: PersonMedia) => void;
  onGenopret: (m: PersonMedia) => void;
}) {
  if (!media.length) {
    return <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 8 }}>— intet materiale endnu</Mono>;
  }
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, marginBottom: 10 }}>
      {media.map((m) => {
        const erBillede = m.mimeType?.startsWith('image/') === true && !!mediaThumbUris[m.id] && !!mediaUris[m.id];
        return <View key={m.id} style={{ width: 96 }}>
          <Pressable onPress={() => onVaelg(m)}>
            {erBillede ? (
              <Image source={{ uri: mediaThumbUris[m.id] }}
                style={[styles.mediaThumb, m.uploadStatus === 'fjernet' && styles.fjernet]} contentFit="cover" />
            ) : (
              <View style={[styles.mediaThumb, styles.dokument, m.uploadStatus === 'fjernet' && styles.fjernet]}>
                <Mono size={22} color={Colors.textMuted}>▤</Mono><Mono size={8} color={Colors.textMuted}>{m.slags || 'dokument'}</Mono>
              </View>
            )}
          </Pressable>
          <Mono size={8} color={Colors.textMuted} numberOfLines={1} style={{ marginTop: 3 }}>
            {m.slags}{m.uploadStatus !== 'klar' ? ` · ${m.uploadStatus}` : ''}
            {m.maaPubliceres ? '' : ' · ej publiceret'}
          </Mono>
          <View style={{ flexDirection: 'row', gap: 8, marginTop: 3 }}>
            {m.uploadStatus === 'fjernet' ? (
              <Pressable onPress={() => onGenopret(m)}><Mono size={8} color={Colors.konklusionGroen}>Genopret</Mono></Pressable>
            ) : <>
              <Pressable disabled={!m.relationId} onPress={() => onFjern(m)}>
                <Mono size={8} color={m.relationId ? Colors.textSecondary2 : Colors.textMuted3}>Fjern</Mono>
              </Pressable>
            </>}
          </View>
        </View>;
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  mediaThumb: { width: 96, height: 96, borderRadius: 10, backgroundColor: Colors.beige2 },
  dokument: { alignItems: 'center', justifyContent: 'center', gap: 3 },
  fjernet: { opacity: 0.45 },
});
