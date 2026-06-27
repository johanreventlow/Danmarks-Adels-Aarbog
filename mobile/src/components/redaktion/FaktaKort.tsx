import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import type { FeltEvidens, Oplysning } from '../../data/redaktionRead';
import { Border, Colors, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export type FaktaAction =
  | { type: 'gørKonklusion'; assertionId: number }
  | { type: 'redigér'; assertionId: number; nuvaerende: string }
  | { type: 'slet'; assertionId: number }
  | { type: 'tilføj'; felt: string };

export function FaktaKort({ felt, evidens, onAction }: {
  felt: string; evidens?: FeltEvidens; onAction: (a: FaktaAction) => void;
}) {
  const [open, setOpen] = useState(false);
  const konkl = evidens?.oplysninger.find((o) => o.erKonklusion);
  return (
    <View style={styles.card}>
      <Pressable style={styles.head} onPress={() => setOpen((v) => !v)}>
        <View style={{ flex: 1 }}>
          <Mono size={9} color={Colors.textMuted}>{felt.toUpperCase()}</Mono>
          <Serif size={19}>{konkl?.vaerdi ?? '—'}</Serif>
        </View>
        {evidens?.uenig ? <Mono size={8} color={Colors.bordeaux}>UENIGE</Mono> : null}
        <Mono size={9} color={Colors.textMuted}>{evidens?.oplysninger.length ?? 0} oplysn.</Mono>
      </Pressable>
      {open ? (
        <View>
          {(evidens?.oplysninger ?? []).map((o) => (
            <OplysningRad key={o.assertionId} o={o} felt={felt} onAction={onAction} />
          ))}
          <Pressable style={styles.addBtn} onPress={() => onAction({ type: 'tilføj', felt })}>
            <BtnLabel color={Colors.bordeaux}>+ Tilføj oplysning</BtnLabel>
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

function OplysningRad({ o, felt: _felt, onAction }: { o: Oplysning; felt: string; onAction: (a: FaktaAction) => void }) {
  return (
    <View style={[styles.opl, o.erKonklusion && styles.oplKonkl]}>
      <View style={{ flex: 1 }}>
        <Serif size={17}>{o.vaerdi}</Serif>
        <Mono size={8} color={Colors.textMuted}>
          {o.erKonklusion ? 'konklusion' : 'oplysning'} · {o.kilder[0]?.sourceTitel ?? '(kilde mangler)'}
        </Mono>
      </View>
      <View style={{ flexDirection: 'row', gap: 8 }}>
        {!o.erKonklusion ? (
          <Pressable onPress={() => onAction({ type: 'gørKonklusion', assertionId: o.assertionId })}>
            <Mono size={9} color="#1f5b3a">Gør til konkl.</Mono>
          </Pressable>
        ) : null}
        <Pressable onPress={() => onAction({ type: 'redigér', assertionId: o.assertionId, nuvaerende: o.vaerdi })}>
          <Mono size={9} color={Colors.textMuted}>✎</Mono>
        </Pressable>
        <Pressable onPress={() => onAction({ type: 'slet', assertionId: o.assertionId })}>
          <Mono size={9} color="#8a2b2b">🗑</Mono>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 12, marginBottom: 8 },
  head: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  opl: { flexDirection: 'row', alignItems: 'center', backgroundColor: Colors.paperBg,
    borderWidth: 1, borderColor: Border.light, borderRadius: Radius.badge + 1, padding: 10, marginTop: 8 },
  oplKonkl: { backgroundColor: '#eaf3ec', borderColor: 'rgba(31,91,58,0.32)' },
  addBtn: { paddingVertical: 10, marginTop: 4 },
});
