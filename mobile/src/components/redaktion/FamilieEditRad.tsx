import { Pressable, View } from 'react-native';
import { Body, Mono } from '../Typography';
import { Colors } from '../../theme/tokens';
import { KonfidensVaelger } from './KonfidensVaelger';
import { personEditorSheetStyles as editorStyles } from './personEditorSheetStyles';

export function FamilieEditRad({ label, aar, konfidens, onKonfidens, onSlet, onOp, onNed, onFlyt, onOpen }: {
  label: string; aar?: string; konfidens: string | null; onKonfidens: (k: string | null) => void; onSlet: () => void;
  // Kun relevant for børn (søskende-rækkefølge + flyt mellem forhold, brugerfund 2026-07-02) —
  // udeladt for partner-rækker.
  onOp?: () => void; onNed?: () => void; onFlyt?: () => void;
  // onOpen (valgfri): gør navnet klikbart → naviger til den person (router.push, ny editor-skærm).
  onOpen?: () => void;
}) {
  return (
    <View style={editorStyles.relEditRad}>
      <View style={{ flex: 1 }}>
        {onOpen
          ? <Pressable onPress={onOpen}><Body size={13} color={Colors.bordeaux}>{label} ↗</Body></Pressable>
          : <Body size={13}>{label}</Body>}
        {aar ? <Mono size={9} color={Colors.textMuted2}>{aar}</Mono> : null}
      </View>
      {onOp || onNed ? (
        <View style={{ flexDirection: 'row' }}>
          <Pressable disabled={!onOp} onPress={onOp}><Mono size={11} color={onOp ? Colors.textSecondary2 : Colors.textMuted3}>↑</Mono></Pressable>
          <Pressable disabled={!onNed} onPress={onNed} style={{ marginLeft: 4 }}><Mono size={11} color={onNed ? Colors.textSecondary2 : Colors.textMuted3}>↓</Mono></Pressable>
        </View>
      ) : null}
      <KonfidensVaelger vaerdi={konfidens} onVael={onKonfidens} />
      {onFlyt ? (
        <Pressable onPress={onFlyt} style={{ marginLeft: 4 }}><Mono size={9} color={Colors.bordeaux}>flyt→</Mono></Pressable>
      ) : null}
      <Pressable onPress={onSlet}><Mono size={9} color={Colors.danger}>🗑</Mono></Pressable>
    </View>
  );
}
