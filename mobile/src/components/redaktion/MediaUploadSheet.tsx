import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { BtnLabel, Body, Mono, Serif } from '../Typography';
import { pickImage, buildVariants, type BuiltVariants, type PickedImage } from '../../lib/mediaUpload';
import {
  decideMediaDedup, deriveMediaDedupTarget, ensureExistingMediaLinked,
  executeMediaDedupResume, fetchExistingMediaBySha, fetchMediaLinked,
  type MediaDedupHit, type MediaDedupTarget,
} from '../../data/mediaDedup';
import { oversaetFejl, submitChange } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;
export type MediaUploadTarget = { afbildetPersonId: string } | { objektType: string; objektId: string };
type MediaDedupState = {
  existing: MediaDedupHit;
  built: BuiltVariants;
  target: MediaDedupTarget;
  alreadyLinked: boolean;
};

export function MediaUploadSheet({ target, onClose, onGem, onApplied }: {
  target: MediaUploadTarget;
  onClose: () => void;
  onGem: (payload: Record<string, unknown>) => void;
  onApplied?: () => void | Promise<void>;
}) {
  const dryRun = useStore((s) => s.dryRun);
  const router = useRouter();
  const [picked, setPicked] = useState<PickedImage | null>(null);
  const [busy, setBusy] = useState(false);
  const [slags, setSlags] = useState<string>('foto');
  const [titel, setTitel] = useState('');
  const [kunstner, setKunstner] = useState('');
  const [datering, setDatering] = useState('');
  const [rettighederStatus, setRettighederStatus] = useState('ukendt');
  const [maaPubliceres, setMaaPubliceres] = useState(false);
  const [fejl, setFejl] = useState<string | null>(null);
  const [besked, setBesked] = useState<string | null>(null);
  const [dedup, setDedup] = useState<MediaDedupState | null>(null);

  async function vaelg() {
    setFejl(null); setBesked(null); setDedup(null); setBusy(true);
    try {
      const img = await pickImage();
      if (!img) { setFejl('Intet billede valgt (afvist tilladelse eller annulleret).'); return; }
      setPicked(img);
      if (!titel && img.fileName) setTitel(img.fileName.replace(/\.[^.]+$/, ''));
    } finally { setBusy(false); }
  }

  const refresh = async () => { await onApplied?.(); };
  const link = async (mediaId: string, maal: MediaDedupTarget) => {
    await submitChange({
      art: 'tilknytMedia', subjektType: 'media', subjektId: mediaId, mediaId,
      payload: { maalType: maal.maalType, maalId: maal.maalId },
    }, { dryRun: false });
  };

  async function tilknytEksisterende() {
    if (!dedup) return;
    setFejl(null); setBesked(null);
    if (dryRun) {
      setBesked(`Dry-run · medie ${dedup.existing.id} ville blive tilknyttet ${dedup.target.maalType} ${dedup.target.maalId}.`);
      return;
    }
    setBusy(true);
    try {
      await ensureExistingMediaLinked({
        mediaId: dedup.existing.id, target: dedup.target, alreadyLinked: dedup.alreadyLinked,
      }, { link, refresh });
      setBesked(`Eksisterende medie ${dedup.existing.id} er tilknyttet.`);
    } catch (error) {
      setFejl(oversaetFejl(String((error as Error)?.message ?? error)));
    } finally { setBusy(false); }
  }

  async function genoptagKladde() {
    if (!dedup) return;
    setFejl(null); setBesked(null); setBusy(true);
    try {
      const result = await executeMediaDedupResume({
        dryRun, mediaId: dedup.existing.id, alreadyLinked: dedup.alreadyLinked,
        target: dedup.target, large: dedup.built.large,
        variants: [dedup.built.thumb, dedup.built.medium],
      }, { link, refresh });
      setBesked(result.kind === 'dry-run'
        ? `Dry-run · medie ${dedup.existing.id} ville få large + 2 varianter, blive bekræftet og tilknyttet.`
        : `Afbrudt upload ${dedup.existing.id} er færdiggjort og tilknyttet.`);
    } catch (error) {
      setFejl(oversaetFejl(String((error as Error)?.message ?? error)));
    } finally { setBusy(false); }
  }

  return (
    <Modal visible transparent animationType="slide" onRequestClose={busy ? () => {} : onClose}>
      <Pressable style={styles.modalBackdrop} onPress={busy ? undefined : onClose} disabled={busy} />
      <View style={styles.modalSheet}>
        <ScrollView contentContainerStyle={{ padding: 20, paddingBottom: 36 }} keyboardShouldPersistTaps="handled">
          <Serif size={20} style={{ marginBottom: 10 }}>Tilføj billede</Serif>
          {dedup?.existing.thumbUrl
            ? <Image source={{ uri: dedup.existing.thumbUrl }} style={styles.preview} contentFit="cover" />
            : picked ? <Image source={{ uri: picked.uri }} style={styles.preview} contentFit="cover" /> : null}
          <Pressable style={styles.addAnnuller} onPress={vaelg} disabled={busy}>
            <BtnLabel color={Colors.textSecondary2}>{picked ? 'Vælg andet billede' : 'Vælg billede fra bibliotek'}</BtnLabel>
          </Pressable>
          {fejl ? <Mono size={10} color={Colors.bordeaux} style={{ marginTop: 8 }}>{fejl}</Mono> : null}
          {besked ? <Mono size={10} color={Colors.konklusionGroen} style={{ marginTop: 8 }}>{besked}</Mono> : null}
          {dedup ? (() => {
            const decision = decideMediaDedup(dedup.existing, dedup.alreadyLinked);
            return <View style={styles.dedupBox}>
              <Serif size={18}>{decision.kind === 'klar-link' ? 'Billedet findes allerede'
                : decision.kind === 'fjernet' ? 'Billedet ligger i papirkurven'
                  : decision.kind === 'kladde' ? 'Afbrudt upload fundet' : 'Eksisterende billede fundet'}</Serif>
              <Body size={12} color={Colors.textSecondary2} style={{ marginTop: 4 }}>
                {dedup.existing.titel || '(uden titel)'} · #{dedup.existing.id}
              </Body>
              {decision.kind === 'klar-link' ? <>
                {decision.alreadyLinked ? <Body size={12} style={{ marginTop: 10 }}>
                  Tilknytningen blev fundet ved preflight og kontrolleres igen ved handlingen.
                </Body> : null}
                <Pressable style={styles.addOpret} disabled={busy} onPress={tilknytEksisterende}>
                  <BtnLabel color="#fff">{busy ? 'Behandler…' : decision.alreadyLinked ? 'Sikr tilknytning' : 'Tilknyt eksisterende'}</BtnLabel>
                </Pressable>
              </> : decision.kind === 'fjernet' ? <>
                <Body size={12} style={{ marginTop: 10 }}>
                  Mediet skal genoprettes fra filsiden. Upload-arket genopretter det ikke automatisk.
                </Body>
                <Pressable style={styles.addOpret} disabled={busy} onPress={() => { onClose(); router.push(decision.route as never); }}>
                  <BtnLabel color="#fff">Åbn filsiden</BtnLabel>
                </Pressable>
              </> : decision.kind === 'kladde' ? <>
                <Body size={12} style={{ marginTop: 10 }}>
                  De indholdsadresserede filer genbruges, og den eksisterende mediepost færdiggøres.
                </Body>
                <Pressable style={styles.addOpret} disabled={busy} onPress={genoptagKladde}>
                  <BtnLabel color="#fff">{busy ? 'Behandler…' : 'Færdiggør afbrudt upload'}</BtnLabel>
                </Pressable>
              </> : <Body size={12} color={Colors.bordeaux} style={{ marginTop: 10 }}>
                Mediets status “{dedup.existing.uploadStatus}” kan ikke håndteres fra upload-arket.
              </Body>}
              <Pressable style={[styles.addAnnuller, busy && styles.disabled]} disabled={busy}
                onPress={() => { setDedup(null); setBesked(null); }}>
                <BtnLabel color={Colors.textMuted}>Tilbage</BtnLabel>
              </Pressable>
            </View>;
          })() : picked ? <>
            <Mono size={9} color={Colors.gold} style={{ marginTop: 14, marginBottom: 6 }}>SLAGS</Mono>
            <View style={styles.chips}>{MEDIA_SLAGS.map((s) => (
              <Pressable key={s} style={[styles.chip, slags === s && styles.chipAktiv]} onPress={() => setSlags(s)}>
                <BtnLabel size={11} color={slags === s ? '#fff' : Colors.textSecondary2}>{s}</BtnLabel>
              </Pressable>
            ))}</View>
            <TextInput style={styles.input} placeholder="Titel" placeholderTextColor={Colors.textMuted2} value={titel} onChangeText={setTitel} />
            <TextInput style={styles.input} placeholder="Kunstner" placeholderTextColor={Colors.textMuted2} value={kunstner} onChangeText={setKunstner} />
            <TextInput style={styles.input} placeholder="Datering" placeholderTextColor={Colors.textMuted2} value={datering} onChangeText={setDatering} />
            <Mono size={9} color={Colors.gold} style={{ marginTop: 14, marginBottom: 6 }}>RETTIGHEDSSTATUS</Mono>
            <View style={styles.chips}>{RETTIGHED_STATUS.map((s) => (
              <Pressable key={s} style={[styles.chip, rettighederStatus === s && styles.chipAktiv]} onPress={() => setRettighederStatus(s)}>
                <BtnLabel size={9.5} color={rettighederStatus === s ? '#fff' : Colors.textSecondary2}>{s}</BtnLabel>
              </Pressable>
            ))}</View>
            <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}>
              <Body size={13} style={{ marginRight: 8, flex: 1 }}>Må publiceres (rettigheder afklaret)</Body>
              <Switch value={maaPubliceres} onValueChange={setMaaPubliceres}
                thumbColor={maaPubliceres ? Colors.bordeaux : Colors.textMuted2}
                trackColor={{ false: Colors.beige3, true: Colors.bordeauxFillLight2 }} />
            </View>
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 14 }}>
              <Pressable style={styles.addOpret} onPress={async () => {
                if (!titel.trim()) { setFejl('Titel er påkrævet.'); return; }
                setFejl(null); setBusy(true);
                try {
                  const built = await buildVariants(picked);
                  const { thumb, medium, large, sha256 } = built;
                  const existing = await fetchExistingMediaBySha(sha256);
                  if (existing) {
                    const dedupTarget = deriveMediaDedupTarget(target);
                    if (!dedupTarget) throw new Error('Uploadmålet kan ikke tilknyttes.');
                    const alreadyLinked = await fetchMediaLinked(existing.id, dedupTarget);
                    setDedup({ existing, built, target: dedupTarget, alreadyLinked });
                    return;
                  }
                  onGem({
                    ...('afbildetPersonId' in target ? { afbildetPersonId: target.afbildetPersonId } : { objektType: target.objektType, objektId: target.objektId }),
                    slags, titel: titel.trim(), kunstner: kunstner.trim() || null, datering: datering.trim() || null,
                    rettighederStatus, maaPubliceres, localUri: large.uri, mimeType: large.mimeType,
                    byteSize: large.byteSize, bredde: large.bredde, hoejde: large.hoejde,
                    originalFilnavn: picked.fileName, storagePath: large.storagePath, sha256,
                    varianter: [thumb, medium],
                  });
                } catch (error) { setFejl(oversaetFejl(String((error as Error)?.message ?? error))); }
                finally { setBusy(false); }
              }} disabled={busy}><BtnLabel color="#fff">{busy ? 'Behandler…' : 'Gem'}</BtnLabel></Pressable>
              <Pressable style={[styles.addAnnuller, busy && styles.disabled]} disabled={busy} onPress={onClose}>
                <BtnLabel color={Colors.textMuted}>Annullér</BtnLabel>
              </Pressable>
            </View>
          </> : null}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  modalSheet: { maxHeight: '92%', backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet, borderTopWidth: 1, borderColor: Border.light },
  preview: { width: 120, height: 120, borderRadius: 10, marginBottom: 12, alignSelf: 'center' },
  chips: { flexDirection: 'row', gap: 6, flexWrap: 'wrap' },
  chip: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 12, paddingVertical: 6 },
  chipAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  input: { backgroundColor: '#fff', borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.field, paddingHorizontal: 10, paddingVertical: 8, marginTop: 10, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14, color: Colors.ink },
  addOpret: { backgroundColor: Colors.konklusionGroen, borderRadius: Radius.field, paddingHorizontal: 16, paddingVertical: 8 },
  addAnnuller: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.field, paddingHorizontal: 16, paddingVertical: 8, alignSelf: 'flex-start' },
  dedupBox: { borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field, padding: 14, gap: 10 },
  disabled: { opacity: 0.5 },
});
