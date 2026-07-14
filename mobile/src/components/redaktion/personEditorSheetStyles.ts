import { StyleSheet } from 'react-native';
import { Border, Colors, Radius } from '../../theme/tokens';

// Delte stil-nøgler for person-editorens inline sheets/forms (KonfidensVaelger, FamilieEditRad,
// SheetButtons, FlytBarnSheet, UnionTypeSheet, BarnSheet, SammeSomSheet, RelTilfoejSheet).
// Udtrukket fra mobile/src/app/redaktion/person/[id].tsx (review 27 M-K2) — værdier uændrede.
export const personEditorSheetStyles = StyleSheet.create({
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(34,31,26,0.4)',
  },
  modalSheet: {
    backgroundColor: Colors.paperBg,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    padding: 20,
    paddingBottom: 36,
    borderTopWidth: 1,
    borderColor: Border.light,
  },
  koenPille: {
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.chip,
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  koenPilleAktiv: {
    backgroundColor: Colors.bordeaux,
    borderColor: Colors.bordeaux,
  },
  addInput: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontFamily: 'HankenGrotesk_400Regular',
    fontSize: 13,
    color: Colors.ink,
  },
  addOpret: {
    backgroundColor: Colors.konklusionGroen,
    borderRadius: Radius.field,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  addAnnuller: {
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  relEditRad: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 5,
  },
  relRad: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 5,
  },
});
