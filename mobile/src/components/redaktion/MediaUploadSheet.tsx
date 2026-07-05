import { Image } from 'expo-image';
import { useState } from 'react';
import { Modal, Pressable, StyleSheet, Switch, TextInput, View } from 'react-native';
import { BtnLabel, Body, Mono, Serif } from '../Typography';
import { pickImage, buildVariants, type PickedImage } from '../../lib/mediaUpload';
import { Border, Colors, Radius } from '../../theme/tokens';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;

// Portræt (afbildetPersonId) ELLER objekt-foto (objektType/objektId) — aldrig begge. Delt mellem
// person-editoren og objekt-materiale-skærmen (samme sheet, kun payload-formen afgør hvilken
// red_upload_media-gren buildRpcCall rammer).
export type MediaUploadTarget = { afbildetPersonId: string } | { objektType: string; objektId: string };

// Billede-upload (mediehåndtering Slice 0g). Billedvalg sker uafhængigt af dry-run (kun lokal
// enhedsadgang); selve upload af bytes til Storage sker først i submitChange's LIVE-gren, aldrig
// her — sheeten bygger blot payload'en til den delte Change→SkrivePreviewSheet-flow.
export function MediaUploadSheet({ target, onClose, onGem }: {
  target: MediaUploadTarget;
  onClose: () => void;
  onGem: (payload: Record<string, unknown>) => void;
}) {
  const [picked, setPicked] = useState<PickedImage | null>(null);
  const [busy, setBusy] = useState(false);
  const [slags, setSlags] = useState<string>('foto');
  const [titel, setTitel] = useState('');
  const [maaPubliceres, setMaaPubliceres] = useState(false);
  const [fejl, setFejl] = useState<string | null>(null);

  async function vaelg() {
    setFejl(null);
    setBusy(true);
    try {
      const img = await pickImage();
      if (!img) { setFejl('Intet billede valgt (afvist tilladelse eller annulleret).'); return; }
      setPicked(img);
      if (!titel && img.fileName) setTitel(img.fileName.replace(/\.[^.]+$/, ''));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.modalBackdrop} onPress={onClose} />
      <View style={styles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Tilføj billede</Serif>
        {picked ? (
          <Image source={{ uri: picked.uri }} style={{ width: 120, height: 120, borderRadius: 10, marginBottom: 12, alignSelf: 'center' }} contentFit="cover" />
        ) : null}
        <Pressable style={styles.addAnnuller} onPress={vaelg} disabled={busy}>
          <BtnLabel color={Colors.textSecondary2}>{picked ? 'Vælg andet billede' : 'Vælg billede fra bibliotek'}</BtnLabel>
        </Pressable>
        {fejl ? <Mono size={10} color={Colors.bordeaux} style={{ marginTop: 8 }}>{fejl}</Mono> : null}
        {picked ? (
          <>
            <Mono size={9} color={Colors.gold} style={{ marginTop: 14, marginBottom: 6 }}>SLAGS</Mono>
            <View style={{ flexDirection: 'row', gap: 6, flexWrap: 'wrap' }}>
              {MEDIA_SLAGS.map((s) => (
                <Pressable key={s}
                  style={[styles.koenPille, slags === s && styles.koenPilleAktiv]}
                  onPress={() => setSlags(s)}>
                  <BtnLabel size={11} color={slags === s ? '#fff' : Colors.textSecondary2}>{s}</BtnLabel>
                </Pressable>
              ))}
            </View>
            <TextInput
              style={[styles.addInput, { marginTop: 12 }]}
              placeholder="Titel"
              placeholderTextColor={Colors.textMuted2}
              value={titel}
              onChangeText={setTitel}
            />
            <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}>
              <Body size={13} style={{ marginRight: 8, flex: 1 }}>Må publiceres (rettigheder afklaret)</Body>
              <Switch
                value={maaPubliceres}
                onValueChange={setMaaPubliceres}
                thumbColor={maaPubliceres ? Colors.bordeaux : Colors.textMuted2}
                trackColor={{ false: Colors.beige3, true: Colors.bordeauxFillLight2 }}
              />
            </View>
            <View style={{ flexDirection: 'row', gap: 8, marginTop: 14 }}>
              <Pressable style={styles.addOpret} onPress={async () => {
                if (!titel.trim()) { setFejl('Titel er påkrævet.'); return; }
                setFejl(null);
                setBusy(true);
                try {
                  const { thumb, medium, large } = await buildVariants(picked);
                  onGem({
                    ...('afbildetPersonId' in target
                      ? { afbildetPersonId: target.afbildetPersonId }
                      : { objektType: target.objektType, objektId: target.objektId }),
                    slags, titel: titel.trim(), maaPubliceres,
                    localUri: large.uri, mimeType: large.mimeType, byteSize: large.byteSize,
                    bredde: large.bredde, hoejde: large.hoejde, originalFilnavn: picked.fileName,
                    storagePath: large.storagePath,
                    varianter: [thumb, medium],
                  });
                } catch {
                  setFejl('Kunne ikke behandle billedet. Prøv et andet billede.');
                } finally {
                  setBusy(false);
                }
              }} disabled={busy}>
                <BtnLabel color="#fff">{busy ? 'Behandler…' : 'Gem'}</BtnLabel>
              </Pressable>
              <Pressable style={styles.addAnnuller} onPress={onClose}>
                <BtnLabel color={Colors.textMuted}>Annullér</BtnLabel>
              </Pressable>
            </View>
          </>
        ) : null}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  modalSheet: {
    backgroundColor: Colors.paperBg,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    padding: 20,
    paddingBottom: 36,
    borderTopWidth: 1,
    borderColor: Border.light,
  },
  koenPille: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 16, paddingVertical: 6 },
  koenPilleAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
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
  addOpret: { backgroundColor: Colors.konklusionGroen, borderRadius: Radius.field, paddingHorizontal: 16, paddingVertical: 8 },
  addAnnuller: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.field, paddingHorizontal: 16, paddingVertical: 8 },
});
