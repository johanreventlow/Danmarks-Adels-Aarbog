import { Modal, Pressable, View } from 'react-native';
import { Body, Mono, Serif } from '../Typography';
import { Colors } from '../../theme/tokens';
import { SheetButtons } from './SheetButtons';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

// Retningsvælger + rådgivende pre-flight for et samme_som-identitets-link.
export function SammeSomSheet({ redigeret, valgt, kanoniskId, onByt, preview, onClose, onGem }: {
  redigeret: { id: string; navn: string };
  valgt: { id: string; navn: string };
  kanoniskId: string;
  onByt: () => void;
  preview: { folder: boolean; grund: string | null };
  onClose: () => void;
  onGem: () => void;
}) {
  const kanonisk = kanoniskId === redigeret.id ? redigeret : valgt;
  const alias = kanoniskId === redigeret.id ? valgt : redigeret;
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 12 }}>Samme person</Serif>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 4 }}>KANONISK (beholdes)</Mono>
        <Body size={15} style={{ marginBottom: 10 }}>{kanonisk.navn}</Body>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 4 }}>FOLDES IND I OVENSTÅENDE</Mono>
        <Body size={15} style={{ marginBottom: 12 }}>{alias.navn}</Body>
        <Pressable style={{ paddingVertical: 6, marginBottom: 8 }} onPress={onByt}>
          <Mono size={10} color={Colors.bordeaux}>⇅ Byt retning</Mono>
        </Pressable>
        {!preview.folder ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 10, lineHeight: 14 }}>
            ⚠ Foldes ikke endnu — {preview.grund}. Linket oprettes, men personerne vises separat til
            konflikten er løst. (redaktionel projektion — offentlig visning kan afvige)
          </Mono>
        ) : null}
        <SheetButtons marginTop={6} onGem={onGem} onClose={onClose} />
      </View>
    </Modal>
  );
}
