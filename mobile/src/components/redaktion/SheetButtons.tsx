import { Pressable, View } from 'react-native';
import { BtnLabel } from '../Typography';
import { Colors } from '../../theme/tokens';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

export function SheetButtons({ marginTop, onGem, onClose, gemLabel }: { marginTop?: number; onGem: () => void; onClose: () => void; gemLabel?: string }) {
  return (
    <View style={{ flexDirection: 'row', gap: 8, marginTop: marginTop ?? 12 }}>
      <Pressable style={editorStyles.addOpret} onPress={onGem}><BtnLabel color="#fff">{gemLabel ?? 'Gem'}</BtnLabel></Pressable>
      <Pressable style={editorStyles.addAnnuller} onPress={onClose}><BtnLabel color={Colors.textMuted}>Annullér</BtnLabel></Pressable>
    </View>
  );
}
