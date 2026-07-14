import { useState } from 'react';
import { Modal, Pressable, View } from 'react-native';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import { Colors } from '../../theme/tokens';
import { BARN_ROLLER } from '../../data/redaktionRead';
import { KonfidensVaelger } from './KonfidensVaelger';
import { SheetButtons } from './SheetButtons';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

export function BarnSheet({ scratch, advarsel, onClose, onGem }: {
  scratch: { familyId: string; personId: string; navn: string };
  advarsel: string | null;
  onClose: () => void;
  onGem: (rolle: string, konfidens: string | null) => void;
}) {
  const [rolle, setRolle] = useState<string>('barn');
  const [konfidens, setKonfidens] = useState<string | null>(null);
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Tilføj barn</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>{scratch.navn}</Body>
        {advarsel ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 10 }}>{advarsel}</Mono>
        ) : null}
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 6 }}>ROLLE</Mono>
        <View style={{ flexDirection: 'row', gap: 6, flexWrap: 'wrap', marginBottom: 12 }}>
          {BARN_ROLLER.map((r) => (
            <Pressable key={r}
              style={[editorStyles.koenPille, rolle === r && editorStyles.koenPilleAktiv]}
              onPress={() => setRolle(r)}>
              <BtnLabel size={11} color={rolle === r ? '#fff' : Colors.textSecondary2}>{r}</BtnLabel>
            </Pressable>
          ))}
        </View>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 6 }}>KONFIDENS</Mono>
        <KonfidensVaelger vaerdi={konfidens} onVael={setKonfidens} />
        <SheetButtons marginTop={14} onGem={() => onGem(rolle, konfidens)} onClose={onClose} />
      </View>
    </Modal>
  );
}
