import { StyleSheet } from 'react-native';
import { Border, Colors, Radius } from '../../theme/tokens';

export const pickerSheetStyles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field,
    paddingHorizontal: 12, paddingVertical: 9, marginBottom: 8, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { paddingVertical: 9, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light },
});
