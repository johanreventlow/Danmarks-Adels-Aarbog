import { useState } from 'react';
import { Modal, Pressable, TextInput, View } from 'react-native';
import { Body, Serif } from '../Typography';
import { Colors } from '../../theme/tokens';
import { SheetButtons } from './SheetButtons';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

export function RelTilfoejSheet({ scratch, onClose, onGem }: {
  scratch: { objektType: string; objektId: string; navn: string; rolle: string; periode: string };
  onClose: () => void;
  onGem: (rolle: string, periode: string) => void;
}) {
  const [rolle, setRolle] = useState(scratch.rolle);
  const [periode, setPeriode] = useState(scratch.periode);
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Tilføj relation</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>{scratch.navn}</Body>
        <TextInput
          style={editorStyles.addInput}
          placeholder="Rolle (valgfri)"
          placeholderTextColor={Colors.textMuted2}
          value={rolle}
          onChangeText={setRolle}
        />
        <TextInput
          style={[editorStyles.addInput, { marginTop: 8 }]}
          placeholder="Periode (valgfri)"
          placeholderTextColor={Colors.textMuted2}
          value={periode}
          onChangeText={setPeriode}
        />
        <SheetButtons onGem={() => onGem(rolle, periode)} onClose={onClose} />
      </View>
    </Modal>
  );
}
