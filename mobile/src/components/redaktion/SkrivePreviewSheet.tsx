import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { buildRpcCall, describeCall, oversaetFejl, submitChange, type Change } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export function SkrivePreviewSheet({ change, onClose, onApplied }: {
  change: Change | null;
  onClose: () => void;
  onApplied: () => void;
}) {
  const dryRun = useStore((s) => s.dryRun);
  const [status, setStatus] = useState<'idle' | 'busy' | 'ok' | 'err'>('idle');
  const [fejl, setFejl] = useState<string | null>(null);

  useEffect(() => {
    setStatus('idle');
    setFejl(null);
  }, [change]);

  if (!change) return null;

  const call = buildRpcCall(change);

  async function run() {
    setStatus('busy');
    setFejl(null);
    try {
      await submitChange(change as Change, { dryRun });
      setStatus('ok');
      if (!dryRun) onApplied();
    } catch (e) {
      setFejl(oversaetFejl(e instanceof Error ? e.message : String(e)));
      setStatus('err');
    }
  }

  const btnLabel = dryRun
    ? 'Forhåndsvis'
    : status === 'ok'
      ? 'Luk'
      : 'Skriv til basen';

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>
          {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}
        </Serif>
        <ScrollView style={{ maxHeight: 220 }}>
          <View style={styles.code}>
            <Mono size={11} color={Colors.paperBg}>
              {call ? describeCall(call) : '(intet kald)'}
            </Mono>
          </View>
        </ScrollView>
        {fejl ? (
          <Mono size={11} color={Colors.bordeaux} style={{ marginTop: 8 }}>{fejl}</Mono>
        ) : null}
        {status === 'ok' ? (
          <Mono size={11} color={Colors.konklusionGroen} style={{ marginTop: 8 }}>
            {'✓ '}{dryRun ? 'Forhåndsvist' : 'Udført'}
          </Mono>
        ) : null}
        <Pressable
          style={[styles.btn, status === 'busy' && styles.btnDisabled]}
          disabled={status === 'busy'}
          onPress={status === 'ok' && !dryRun ? onClose : run}
        >
          <BtnLabel color="#fff">{btnLabel}</BtnLabel>
        </Pressable>
        {status !== 'busy' ? (
          <Pressable style={styles.cancelBtn} onPress={onClose}>
            <BtnLabel color={Colors.textSecondary}>Annullér</BtnLabel>
          </Pressable>
        ) : null}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(34,31,26,0.4)',
  },
  sheet: {
    backgroundColor: Colors.paperBg,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    padding: 20,
    paddingBottom: 36,
    borderTopWidth: 1,
    borderColor: Border.light,
  },
  code: {
    backgroundColor: Colors.ink,
    borderRadius: 8,
    padding: 12,
    marginBottom: 6,
  },
  btn: {
    backgroundColor: Colors.bordeaux,
    borderRadius: Radius.field,
    padding: 14,
    alignItems: 'center',
    marginTop: 12,
  },
  btnDisabled: {
    opacity: 0.5,
  },
  cancelBtn: {
    padding: 12,
    alignItems: 'center',
    marginTop: 4,
  },
});
