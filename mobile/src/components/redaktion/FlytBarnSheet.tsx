import { Modal, Pressable, View } from 'react-native';
import { Body, Serif } from '../Typography';
import type { FamilieUnion } from '../../data/redaktionRead';
import { Colors } from '../../theme/tokens';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

export function FlytBarnSheet({ barnNavn, andreUnioner, onClose, onVael }: {
  barnNavn: string;
  andreUnioner: FamilieUnion[];
  onClose: () => void;
  onVael: (tilFamilyId: string) => void;
}) {
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Flyt {barnNavn} til…</Serif>
        {andreUnioner.length === 0 ? (
          <Body size={13} color={Colors.textMuted}>Personen har ingen andre registrerede forhold at flytte til.</Body>
        ) : andreUnioner.map((u) => (
          <Pressable key={u.familyId} style={editorStyles.relRad} onPress={() => onVael(u.familyId)}>
            <Body size={14}>{u.partnere.map((p) => p.navn).join(' & ') || '(ukendt partner)'} · {u.type}</Body>
          </Pressable>
        ))}
      </View>
    </Modal>
  );
}
