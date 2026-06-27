import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { fetchSletPreview, type SletPreview } from '../../data/redaktionRead';
import { oversaetFejl, submitChange } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, BtnLabel, Mono, Serif } from '../Typography';

export function SletBekraeftSheet({ personId, onClose, onDeleted }: {
  personId: string;
  onClose: () => void;
  onDeleted: () => void;
}) {
  const dryRun = useStore((s) => s.dryRun);
  const model = useStore((s) => s.model);
  const [preview, setPreview] = useState<SletPreview | null>(null);
  const [bekraeftet, setBekraeftet] = useState(false);
  const [status, setStatus] = useState<'idle' | 'busy' | 'ok' | 'err'>('idle');
  const [fejl, setFejl] = useState<string | null>(null);

  useEffect(() => {
    setBekraeftet(false);
    setStatus('idle');
    setFejl(null);
    fetchSletPreview(personId).then(setPreview).catch(() => setPreview({ antalRelationer: 0, antalFacts: 0, relationer: [] }));
  }, [personId]);

  async function slet() {
    setStatus('busy');
    setFejl(null);
    try {
      await submitChange({ art: 'sletPerson', subjektType: 'person', subjektId: personId }, { dryRun });
      setStatus('ok');
      if (!dryRun) onDeleted();
    } catch (e) {
      setFejl(oversaetFejl(e instanceof Error ? e.message : String(e)));
      setStatus('err');
    }
  }

  const kanSlette = bekraeftet && status !== 'busy';

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 6 }}>Slet person?</Serif>
        <Mono size={10} color={dryRun ? Colors.textMuted : Colors.liveRoed} style={{ marginBottom: 12 }}>
          {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · sletter permanent'}
        </Mono>

        {preview && (preview.antalRelationer > 0 || preview.antalFacts > 0) ? (
          <View style={styles.advarsel}>
            <Mono size={11} color={Colors.danger}>
              {'⚠ '}{preview.antalRelationer} relationer · {preview.antalFacts} fakta brydes
            </Mono>
            {preview.relationer.length > 0 ? (
              <ScrollView style={{ maxHeight: 100, marginTop: 6 }}>
                {preview.relationer.map((r, i) => {
                  const modpartNavn = model?.byId[String(r.modpartId)]?.name ?? `#${r.modpartId}`;
                  return (
                    <Mono key={i} size={10} color={Colors.textSecondary} style={{ marginBottom: 2 }}>
                      {r.rolle} ({r.retning}) → {modpartNavn}
                    </Mono>
                  );
                })}
              </ScrollView>
            ) : null}
          </View>
        ) : null}

        <Pressable
          style={styles.checkRow}
          onPress={() => setBekraeftet((v) => !v)}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: bekraeftet }}
        >
          <View style={[styles.checkbox, bekraeftet && styles.checkboxChecked]}>
            {bekraeftet ? <Mono size={10} color="#fff">✓</Mono> : null}
          </View>
          <Body size={13} style={{ marginLeft: 8 }}>Jeg bekræfter at personen skal slettes</Body>
        </Pressable>

        {fejl ? (
          <Mono size={11} color={Colors.danger} style={{ marginTop: 8 }}>{fejl}</Mono>
        ) : null}
        {status === 'ok' ? (
          <Mono size={11} color={Colors.konklusionGroen} style={{ marginTop: 8 }}>
            {'✓ '}{dryRun ? 'Forhåndsvist' : 'Slettet'}
          </Mono>
        ) : null}

        <Pressable
          style={[styles.sletBtn, !kanSlette && styles.btnDisabled]}
          disabled={!kanSlette}
          onPress={slet}
        >
          <BtnLabel color="#fff">{'🗑 '}Slet endeligt</BtnLabel>
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
  advarsel: {
    backgroundColor: Colors.konfliktFlade,
    borderRadius: Radius.card,
    padding: 12,
    marginBottom: 12,
  },
  checkRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    marginTop: 4,
  },
  checkbox: {
    width: 20,
    height: 20,
    borderRadius: 4,
    borderWidth: 1.5,
    borderColor: Colors.textSecondary2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.paperCard,
  },
  checkboxChecked: {
    backgroundColor: Colors.danger,
    borderColor: Colors.danger,
  },
  sletBtn: {
    backgroundColor: Colors.danger,
    borderRadius: Radius.field,
    padding: 14,
    alignItems: 'center',
    marginTop: 12,
  },
  btnDisabled: {
    opacity: 0.4,
  },
  cancelBtn: {
    padding: 12,
    alignItems: 'center',
    marginTop: 4,
  },
});
