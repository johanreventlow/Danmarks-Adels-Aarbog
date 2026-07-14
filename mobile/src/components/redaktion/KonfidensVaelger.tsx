import { Pressable, View } from 'react-native';
import { BtnLabel } from '../Typography';
import { Colors } from '../../theme/tokens';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

const KONFIDENS_VAERDIER = ['sikker', 'sandsynlig', 'formodet', 'omstridt'] as const;

export function KonfidensVaelger({ vaerdi, onVael }: { vaerdi: string | null; onVael: (k: string | null) => void }) {
  return (
    <View style={{ flexDirection: 'row', gap: 4, flexWrap: 'wrap' }}>
      {KONFIDENS_VAERDIER.map((k) => (
        <Pressable key={k}
          style={[editorStyles.koenPille, vaerdi === k && editorStyles.koenPilleAktiv]}
          onPress={() => onVael(k)}>
          <BtnLabel size={10} color={vaerdi === k ? '#fff' : Colors.textSecondary2}>{k}</BtnLabel>
        </Pressable>
      ))}
      <Pressable style={editorStyles.koenPille} onPress={() => onVael(null)}>
        <BtnLabel size={10} color={Colors.textMuted}>ryd</BtnLabel>
      </Pressable>
    </View>
  );
}
