import { useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';
import type { FeltEvidens, Oplysning } from '../../data/redaktionRead';
import { Border, Colors, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export type FaktaAction =
  | { type: 'gørKonklusion'; assertionId: number }
  | { type: 'redigér'; assertionId: number; felt: string; vaerdi: string; kilde?: string }
  | { type: 'slet'; assertionId: number }
  | { type: 'tilføj'; felt: string; vaerdi: string; kilde?: string };

// Inline-editor tilstand: hvilken oplysning redigeres (assertionId) eller 'ny'
type EditState = { mode: 'redigér'; assertionId: number } | { mode: 'tilføj' } | null;

export function FaktaKort({ felt, evidens, onAction }: {
  felt: string; evidens?: FeltEvidens; onAction: (a: FaktaAction) => void;
}) {
  const [open, setOpen] = useState(false);
  const [editState, setEditState] = useState<EditState>(null);
  const [scratch, setScratch] = useState({ vaerdi: '', kilde: '' });
  const konkl = evidens?.oplysninger.find((o) => o.erKonklusion);

  function startRedigér(o: Oplysning) {
    setEditState({ mode: 'redigér', assertionId: o.assertionId });
    setScratch({ vaerdi: o.vaerdi, kilde: '' });
  }

  function startTilføj() {
    setEditState({ mode: 'tilføj' });
    setScratch({ vaerdi: '', kilde: '' });
  }

  function annuller() { setEditState(null); }

  function gem() {
    if (!editState) return;
    if (editState.mode === 'redigér') {
      onAction({
        type: 'redigér',
        assertionId: editState.assertionId,
        felt,
        vaerdi: scratch.vaerdi,
        kilde: scratch.kilde || undefined,
      });
    } else {
      onAction({
        type: 'tilføj',
        felt,
        vaerdi: scratch.vaerdi,
        kilde: scratch.kilde || undefined,
      });
    }
    setEditState(null);
  }

  const isTilføjEdit = editState?.mode === 'tilføj';

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
          {(evidens?.oplysninger ?? []).map((o) => {
            const isEditing = editState?.mode === 'redigér' && editState.assertionId === o.assertionId;
            return (
              <View key={o.assertionId}>
                <OplysningRad
                  o={o}
                  onGørKonklusion={() => onAction({ type: 'gørKonklusion', assertionId: o.assertionId })}
                  onRedigér={() => startRedigér(o)}
                  onSlet={() => onAction({ type: 'slet', assertionId: o.assertionId })}
                />
                {isEditing ? (
                  <InlineEditor
                    vaerdi={scratch.vaerdi}
                    kilde={scratch.kilde}
                    label="Redigér oplysning"
                    onVaerdi={(v) => setScratch((s) => ({ ...s, vaerdi: v }))}
                    onKilde={(v) => setScratch((s) => ({ ...s, kilde: v }))}
                    onGem={gem}
                    onAnnuller={annuller}
                  />
                ) : null}
              </View>
            );
          })}
          {isTilføjEdit ? (
            <InlineEditor
              vaerdi={scratch.vaerdi}
              kilde={scratch.kilde}
              label="Ny oplysning"
              onVaerdi={(v) => setScratch((s) => ({ ...s, vaerdi: v }))}
              onKilde={(v) => setScratch((s) => ({ ...s, kilde: v }))}
              onGem={gem}
              onAnnuller={annuller}
            />
          ) : (
            <Pressable style={styles.addBtn} onPress={startTilføj}>
              <BtnLabel color={Colors.bordeaux}>+ Tilføj oplysning</BtnLabel>
            </Pressable>
          )}
        </View>
      ) : null}
    </View>
  );
}

function OplysningRad({ o, onGørKonklusion, onRedigér, onSlet }: {
  o: Oplysning;
  onGørKonklusion: () => void;
  onRedigér: () => void;
  onSlet: () => void;
}) {
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
          <Pressable onPress={onGørKonklusion}>
            <Mono size={9} color={Colors.konklusionGroen}>Gør til konkl.</Mono>
          </Pressable>
        ) : null}
        <Pressable onPress={onRedigér}>
          <Mono size={9} color={Colors.textMuted}>✎</Mono>
        </Pressable>
        <Pressable onPress={onSlet}>
          <Mono size={9} color={Colors.danger}>🗑</Mono>
        </Pressable>
      </View>
    </View>
  );
}

function InlineEditor({ vaerdi, kilde, label, onVaerdi, onKilde, onGem, onAnnuller }: {
  vaerdi: string; kilde: string; label: string;
  onVaerdi: (v: string) => void; onKilde: (v: string) => void;
  onGem: () => void; onAnnuller: () => void;
}) {
  return (
    <View style={styles.inlineEditor}>
      <Mono size={9} color={Colors.textMuted} style={{ marginBottom: 6 }}>{label.toUpperCase()}</Mono>
      <TextInput
        style={styles.field}
        value={vaerdi}
        onChangeText={onVaerdi}
        placeholder="Værdi"
        placeholderTextColor={Colors.textMuted2}
        autoFocus
      />
      <TextInput
        style={[styles.field, { marginTop: 6 }]}
        value={kilde}
        onChangeText={onKilde}
        placeholder="Kilde (valgfri)"
        placeholderTextColor={Colors.textMuted2}
      />
      <View style={{ flexDirection: 'row', gap: 8, marginTop: 10 }}>
        <Pressable style={[styles.gemBtn, { flex: 1 }]} onPress={onGem}>
          <BtnLabel color="#fff">Registrér</BtnLabel>
        </Pressable>
        <Pressable style={[styles.annullerBtn, { flex: 1 }]} onPress={onAnnuller}>
          <BtnLabel color={Colors.ink}>Annullér</BtnLabel>
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
  oplKonkl: { backgroundColor: Colors.konklusionFlade, borderColor: 'rgba(31,91,58,0.32)' },
  addBtn: { paddingVertical: 10, marginTop: 4 },
  inlineEditor: {
    backgroundColor: Colors.paperBg,
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.card,
    padding: 12,
    marginTop: 8,
  },
  field: {
    backgroundColor: Colors.paperCard,
    borderWidth: 1,
    borderColor: Border.light,
    borderRadius: Radius.field,
    padding: 10,
    fontSize: 14,
    color: Colors.ink,
    fontFamily: undefined, // sans default
  },
  gemBtn: {
    backgroundColor: Colors.konklusionGroen,
    borderRadius: Radius.field,
    padding: 12,
    alignItems: 'center',
  },
  annullerBtn: {
    backgroundColor: Colors.beige,
    borderRadius: Radius.field,
    padding: 12,
    alignItems: 'center',
  },
});
