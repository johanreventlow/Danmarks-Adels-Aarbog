// Review 37 P11 (projektejeren 2026-11-22): systemet vælger vejen ud fra red_slet_person_preview. Kun en offentlig
// person kan slettes her, så det kan fortrydes. Mobil har ingen fuld sletning (»Slet helt«): for en ikke-offentlig
// person forklarer arket hvorfor og henviser til web-redaktionen, og den simple sletning er slået fra.
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { sletAarsagTekst, sletKraeverSletHelt } from '@daa/core';
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
  const [previewFejl, setPreviewFejl] = useState<string | null>(null);
  // SLET_KRAEVER_SLET_HELT: status ændret mellem forhåndsvisning og tryk — kun den fulde sletning (web) er tilbage.
  const [kraeverHelt, setKraeverHelt] = useState(false);

  useEffect(() => {
    setBekraeftet(false);
    setStatus('idle');
    setFejl(null);
    setPreview(null);
    setPreviewFejl(null);
    setKraeverHelt(false);
    let aktiv = true;
    fetchSletPreview(personId).then((p) => { if (aktiv) setPreview(p); })
      .catch((e) => { if (aktiv) setPreviewFejl(oversaetFejl(e instanceof Error ? e.message : String(e))); });
    return () => { aktiv = false; };
  }, [personId]);

  async function slet() {
    setStatus('busy');
    setFejl(null);
    try {
      await submitChange({ art: 'sletPerson', subjektType: 'person', subjektId: personId }, { dryRun });
      setStatus('ok');
      if (!dryRun) onDeleted();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setKraeverHelt(sletKraeverSletHelt(msg) !== null);
      setFejl(oversaetFejl(msg));
      setStatus('err');
    }
  }

  const fortrydelig = !!preview && preview.kanFortrydes && !preview.sletningBlokeret && !kraeverHelt;
  const kanSlette = fortrydelig && bekraeftet && status !== 'busy';
  const helt = preview && !preview.kanFortrydes ? sletAarsagTekst(preview.aarsag ?? 'ukendt') : null;

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 6 }}>{helt ? 'Slet helt — kan ikke fortrydes' : 'Slet person — kan fortrydes'}</Serif>
        <Mono size={10} color={dryRun ? Colors.inkMuted : Colors.live} style={{ marginBottom: 12 }}>
          {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · sletter permanent'}
        </Mono>

        {!preview && !previewFejl ? (
          <Body size={13} style={{ marginBottom: 8 }}>Henter forhåndsvisning…</Body>
        ) : null}
        {previewFejl ? (
          <Mono size={11} color={Colors.danger} style={{ marginBottom: 8 }}>
            Forhåndsvisningen kunne ikke hentes: {previewFejl}
          </Mono>
        ) : null}
        {helt ? (
          <View style={styles.advarsel}>
            <Body size={13} style={{ fontWeight: '600' }}>Personen kan ikke slettes, så det kan fortrydes.</Body>
            <Body size={13} style={{ marginTop: 6 }}>{helt.hvorfor}</Body>
            <Body size={13} style={{ marginTop: 6 }}>Vil du hellere kunne fortryde? {helt.hvordan}</Body>
            <Body size={13} style={{ marginTop: 6 }}>Den fulde sletning (»Slet helt«, kan ikke fortrydes) findes kun i web-redaktionen: brug »Slet person…« dér.</Body>
          </View>
        ) : null}
        {fortrydelig ? (
          <Body size={13} style={{ marginBottom: 8 }}>Personen og dens oplysninger fjernes. Historikken gemmes, så sletningen kan fortrydes under »Slettede personer« i web-redaktionen. Skal oplysningerne også ud af historikken (GDPR), så brug »Slet person…« i web-redaktionen.</Body>
        ) : null}
        {preview?.kanFortrydes && preview.sletningBlokeret ? (
          <Mono size={11} color={Colors.danger} style={{ marginBottom: 8 }}>
            Personen har narrativ-publiceringshistorik og kan ikke slettes her. Brug »Slet person…« i web-redaktionen.
          </Mono>
        ) : null}
        {fortrydelig && preview && (preview.antalRelationer > 0 || preview.antalFacts > 0
          || preview.antalNarrativer > 0 || preview.antalMedlemskaber > 0) ? (
          <View style={styles.advarsel}>
            <Mono size={11} color={Colors.danger}>
              {'⚠ '}{preview.antalRelationer} relationer · {preview.antalFacts} fakta · {preview.antalNarrativer} biografier · {preview.antalMedlemskaber} medlemskaber
            </Mono>
            {preview.antalBindinger > 0 ? (
              <Mono size={10} color={Colors.inkSecondary} style={{ marginTop: 4 }}>
                {preview.antalBindinger} biografi(er) er bundet til en kildepost — bindingen følger med, kilderegistreringen bevares.
              </Mono>
            ) : null}
            {preview.relationer.length > 0 ? (
              <ScrollView style={{ maxHeight: 100, marginTop: 6 }}>
                {preview.relationer.map((r, i) => {
                  const modpartNavn = model?.byId[String(r.modpartId)]?.name ?? `#${r.modpartId}`;
                  return (
                    <Mono key={i} size={10} color={Colors.inkSecondary} style={{ marginBottom: 2 }}>
                      {r.rolle} ({r.retning}) → {modpartNavn}
                    </Mono>
                  );
                })}
              </ScrollView>
            ) : null}
          </View>
        ) : null}

        {fortrydelig ? (
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
        ) : null}

        {fejl ? (
          <Mono size={11} color={Colors.danger} style={{ marginTop: 8 }}>{fejl}</Mono>
        ) : null}
        {kraeverHelt ? (
          <Mono size={11} color={Colors.danger} style={{ marginTop: 4 }}>Den fulde sletning findes kun i web-redaktionen: brug »Slet person…« dér.</Mono>
        ) : null}
        {status === 'ok' ? (
          <Mono size={11} color={Colors.success} style={{ marginTop: 8 }}>
            {'✓ '}{dryRun ? 'Forhåndsvist' : 'Slettet'}
          </Mono>
        ) : null}

        {fortrydelig || status === 'ok' ? (
          <Pressable
            style={[styles.sletBtn, !kanSlette && styles.btnDisabled]}
            disabled={!kanSlette}
            onPress={slet}
            accessibilityRole="button"
            accessibilityState={{ disabled: !kanSlette }}
          >
            <BtnLabel color="#fff">{'🗑 '}Slet (kan fortrydes)</BtnLabel>
          </Pressable>
        ) : null}
        {status !== 'busy' ? (
          <Pressable style={styles.cancelBtn} onPress={onClose}>
            <BtnLabel color={Colors.inkSecondary}>Annullér</BtnLabel>
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
    backgroundColor: Colors.surfaceGround,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    padding: 20,
    paddingBottom: 36,
    borderTopWidth: 1,
    borderColor: Border.light,
  },
  advarsel: {
    backgroundColor: Colors.dangerTint,
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
    borderColor: Colors.inkMuted,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceRaised,
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
