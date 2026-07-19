// Billed-vælger til narrativ-indsættelse (billeder-i-narrativer 2026-07-05, Slice C2). Søster til
// MentionPicker.tsx, men uden søgning/netværk: viser DENNE subjekts allerede indlæste egne
// uploadede billeder (samme data + signerede URI'er som Materiale-galleriet allerede har hentet
// via fetchPersonMedia/useMediaAndThumbUris — genbruges her via props, intet nyt fetch-kald).
import { Image } from 'expo-image';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import type { PersonMedia } from '../../data/redaktionRead';
import { makeToken } from '@daa/core';
import { Colors } from '../../theme/tokens';
import { Body, Serif } from '../Typography';
import { pickerSheetStyles } from './pickerSheetStyles';

export function MediaMentionPicker({ media, thumbUris, onVælg, onClose }: {
  media: PersonMedia[];
  thumbUris: Record<string, string>;
  onVælg: (token: string) => void;
  onClose: () => void;
}) {
  const brugbar = media.filter((m) => m.uploadStatus === 'klar' && m.mimeType?.startsWith('image/') === true && thumbUris[m.id]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={pickerSheetStyles.backdrop} onPress={onClose} />
      <View style={pickerSheetStyles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Indsæt billede</Serif>
        <ScrollView style={{ maxHeight: 420 }}>
          {brugbar.length === 0 ? (
            <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen billeder uploadet endnu.</Body>
          ) : (
            <View style={styles.grid}>
              {brugbar.map((m) => (
                <Pressable key={m.id} style={styles.cell}
                  onPress={() => { onVælg(makeToken('media', Number(m.id), m.titel ?? '')); onClose(); }}>
                  <Image source={{ uri: thumbUris[m.id] }} style={styles.thumb} contentFit="cover" />
                  {m.titel ? <Body size={10} numberOfLines={1}>{m.titel}</Body> : null}
                </Pressable>
              ))}
            </View>
          )}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  cell: { width: 96 },
  thumb: { width: 96, height: 96, borderRadius: 8, backgroundColor: Colors.beige2, marginBottom: 2 },
});
