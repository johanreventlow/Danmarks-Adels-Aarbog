import { useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { SkrivePreviewSheet } from './SkrivePreviewSheet';
import { pickerSheetStyles } from './pickerSheetStyles';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import type { Change } from '../../data/redaktionWrite';

type EntType = 'person' | 'estate' | 'kilde' | 'organisation';
const TYPER: { key: EntType; label: string }[] = [
  { key: 'person', label: 'Person' }, { key: 'estate', label: 'Gods' },
  { key: 'kilde', label: 'Kilde' }, { key: 'organisation', label: 'Organisation' },
];
const KOEN = ['mand', 'kvinde', 'ukendt'];
const ESTATE_SLAGS = ['gods', 'len', 'stamhus', 'lensgrevskab', 'baroni'];
const KILDE_SLAGS = ['kirkebog', 'DAA-udgave', 'bog', 'artikel', 'diplomsamling'];
const ORG_SLAGS = ['amt', 'regiment', 'hof', 'institution', 'ridderorden'];

function Pille({ valgt, label, onPress }: { valgt: boolean; label: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress}
      style={[styles.pille, valgt && styles.pilleAktiv]}>
      <Mono size={11} color={valgt ? Colors.paperBg : Colors.textSecondary}>{label}</Mono>
    </Pressable>
  );
}

export function OpretSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const router = useRouter();
  const [type, setType] = useState<EntType | null>(null);
  // person
  const [navn, setNavn] = useState('');
  const [koen, setKoen] = useState<string | null>(null);
  const [levende, setLevende] = useState(false);
  const [foedt, setFoedt] = useState('');
  const [doed, setDoed] = useState('');
  const [titel, setTitel] = useState('');
  // fælles tekst
  const [slags, setSlags] = useState<string | null>(null);
  const [udgave, setUdgave] = useState('');
  const [ekstern, setEkstern] = useState(false);
  const [pending, setPending] = useState<Change | null>(null);

  function nulstil() {
    setType(null); setNavn(''); setKoen(null); setLevende(false); setFoedt('');
    setDoed(''); setTitel(''); setSlags(null); setUdgave(''); setEkstern(false); setPending(null);
  }
  function luk() { nulstil(); onClose(); }

  function byg(): Change | null {
    if (type === 'person') {
      if (!navn.trim()) return null;
      return { art: 'opretPerson', subjektType: 'person', subjektId: '',
        payload: { navn: navn.trim(), koen: koen ?? undefined, levende, privat: true,
          foedtRaw: foedt.trim(), doedRaw: doed.trim(), titelRaw: titel.trim() } };
    }
    if (type === 'estate') {
      if (!navn.trim()) return null;
      return { art: 'opretEstate', subjektType: 'estate', subjektId: '',
        payload: { navn: navn.trim(), slags: slags ?? undefined } };
    }
    if (type === 'kilde') {
      if (!navn.trim()) return null;
      return { art: 'opretKilde', subjektType: 'source', subjektId: '',
        payload: { titel: navn.trim(), slags: slags ?? undefined, udgave: udgave.trim(), ekstern } };
    }
    if (type === 'organisation') {
      if (!navn.trim()) return null;
      return { art: 'opretOrganisation', subjektType: 'organisation', subjektId: '',
        payload: { navn: navn.trim(), slags: slags ?? undefined } };
    }
    return null;
  }

  async function efterOpret(result?: unknown) {
    const t = type; // bevares før nulstil
    await useStore.getState().loadRedaktionModel(true);
    if (useStore.getState().redaktionStatus !== 'ready') {
      Alert.alert('Oprettet', 'Posten blev oprettet, men listen kunne ikke opdateres. Genindlæs appen for at se den.');
      luk();
      return;
    }
    luk();
    if (t === 'person' && result != null) router.push(`/redaktion/person/${result}` as never);
  }

  const navnLabel = type === 'kilde' ? 'Titel' : 'Navn';
  const slagsListe = type === 'estate' ? ESTATE_SLAGS : type === 'kilde' ? KILDE_SLAGS : ORG_SLAGS;
  const kanGemme = navn.trim().length > 0;

  // KUN én native Modal synlig ad gangen (Codex: nested native Modal upålidelig på iOS).
  // Opret-Modal skjules mens preview er åben; SkrivePreviewSheet rendres som SØSKENDE, ikke inde i.
  return (
    <>
    <Modal visible={visible && !pending} transparent animationType="slide" onRequestClose={luk}>
      <Pressable style={styles.backdrop} onPress={luk} />
      <View style={styles.sheet}>
        {!type ? (
          <>
            <Serif size={20} style={{ marginBottom: 14 }}>Opret ny post</Serif>
            <View style={styles.grid}>
              {TYPER.map((t) => (
                <Pressable key={t.key} style={styles.cell} onPress={() => setType(t.key)}>
                  <Serif size={17} color={Colors.bordeaux}>{t.label}</Serif>
                </Pressable>
              ))}
            </View>
          </>
        ) : (
          <ScrollView style={{ maxHeight: 460 }}>
            <Serif size={20} style={{ marginBottom: 12 }}>Ny {TYPER.find((t) => t.key === type)!.label.toLowerCase()}</Serif>
            <Mono size={9} color={Colors.gold}>{navnLabel.toUpperCase()} *</Mono>
            <TextInput style={pickerSheetStyles.input} value={navn} onChangeText={setNavn}
              placeholder={navnLabel} placeholderTextColor={Colors.textMuted} autoFocus />

            {type === 'person' ? (
              <>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 10 }}>KØN</Mono>
                <View style={styles.pilleRad}>
                  {KOEN.map((k) => <Pille key={k} label={k} valgt={koen === k} onPress={() => setKoen(koen === k ? null : k)} />)}
                </View>
                <View style={styles.switchRad}>
                  <Body size={13}>Nulevende</Body>
                  <Switch value={levende} onValueChange={setLevende} />
                </View>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>FØDT</Mono>
                <TextInput style={pickerSheetStyles.input} value={foedt} onChangeText={setFoedt}
                  placeholder="fx 1700" placeholderTextColor={Colors.textMuted} />
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>DØD</Mono>
                <TextInput style={pickerSheetStyles.input} value={doed} onChangeText={setDoed}
                  placeholder="fx 1755" placeholderTextColor={Colors.textMuted} />
                <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>TITEL</Mono>
                <TextInput style={pickerSheetStyles.input} value={titel} onChangeText={setTitel}
                  placeholder="fx greve" placeholderTextColor={Colors.textMuted} />
              </>
            ) : (
              <>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 10 }}>SLAGS</Mono>
                <View style={styles.pilleRad}>
                  {slagsListe.map((s) => <Pille key={s} label={s} valgt={slags === s} onPress={() => setSlags(slags === s ? null : s)} />)}
                </View>
                {type === 'kilde' ? (
                  <>
                    <Mono size={9} color={Colors.gold} style={{ marginTop: 6 }}>UDGAVE</Mono>
                    <TextInput style={pickerSheetStyles.input} value={udgave} onChangeText={setUdgave}
                      placeholder="fx DAA 2018-20" placeholderTextColor={Colors.textMuted} />
                    <View style={styles.switchRad}>
                      <Body size={13}>Eksternt værk</Body>
                      <Switch value={ekstern} onValueChange={setEkstern} />
                    </View>
                  </>
                ) : null}
              </>
            )}

            <Pressable style={[styles.btn, !kanGemme && styles.btnDisabled]} disabled={!kanGemme}
              onPress={() => { const c = byg(); if (c) setPending(c); }}>
              <BtnLabel color="#fff">Gennemse & opret</BtnLabel>
            </Pressable>
            <Pressable style={styles.cancel} onPress={nulstil}>
              <BtnLabel color={Colors.textSecondary}>Tilbage</BtnLabel>
            </Pressable>
          </ScrollView>
        )}
      </View>
    </Modal>
    <SkrivePreviewSheet change={pending} onClose={() => setPending(null)} onApplied={efterOpret} />
    </>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet,
    padding: 20, paddingBottom: 36, borderTopWidth: 1, borderColor: Border.light },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: 13,
    padding: 18, minWidth: '47%', alignItems: 'center' },
  pilleRad: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 4 },
  pille: { borderWidth: 1, borderColor: Border.medium, borderRadius: 14, paddingVertical: 5, paddingHorizontal: 11 },
  pilleAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  switchRad: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  btn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14, alignItems: 'center', marginTop: 16 },
  btnDisabled: { opacity: 0.5 },
  cancel: { padding: 12, alignItems: 'center', marginTop: 4 },
});
