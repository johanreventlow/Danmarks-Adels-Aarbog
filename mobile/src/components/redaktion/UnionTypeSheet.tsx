import { useState } from 'react';
import { Modal, Pressable, TextInput, View } from 'react-native';
import { Body, BtnLabel, Serif } from '../Typography';
import { Colors } from '../../theme/tokens';
import { SheetButtons } from './SheetButtons';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

const UNION_TYPER = ['vielse', 'partnerskab', 'ugift union'] as const;

export function UnionTypeSheet({ partner, onClose, onGem }: {
  partner: { personId: string; navn: string };
  onClose: () => void;
  onGem: (type: string, ordinal: number | null) => void;
}) {
  const [valgtType, setValgtType] = useState<string>('vielse');
  const [ordinalTekst, setOrdinalTekst] = useState('');
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Ny union</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>Partner: {partner.navn}</Body>
        <View style={{ flexDirection: 'row', gap: 6, marginBottom: 12 }}>
          {UNION_TYPER.map((t) => (
            <Pressable key={t}
              style={[editorStyles.koenPille, valgtType === t && editorStyles.koenPilleAktiv]}
              onPress={() => setValgtType(t)}>
              <BtnLabel size={11} color={valgtType === t ? '#fff' : Colors.textSecondary2}>{t}</BtnLabel>
            </Pressable>
          ))}
        </View>
        <TextInput
          style={editorStyles.addInput}
          placeholder="Ordinal (valgfri, fx 1)"
          placeholderTextColor={Colors.textMuted2}
          value={ordinalTekst}
          onChangeText={setOrdinalTekst}
          keyboardType="numeric"
        />
        <SheetButtons onGem={() => {
            const ordinal = ordinalTekst.trim() ? Number(ordinalTekst.trim()) : null;
            onGem(valgtType, ordinal);
          }} onClose={onClose} />
      </View>
    </Modal>
  );
}
