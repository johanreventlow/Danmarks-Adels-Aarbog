import { useState } from 'react';
import { Modal, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { oversaetFejl } from '../../data/redaktionWrite';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';

export function LoginSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const doSignIn = useStore((s) => s.doSignIn);
  const [email, setEmail] = useState('');
  const [pw, setPw] = useState('');
  const [fejl, setFejl] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit() {
    setBusy(true); setFejl(null);
    try { await doSignIn(email.trim(), pw); onClose(); }
    catch (e) { setFejl(oversaetFejl(e instanceof Error ? e.message : String(e))); }
    finally { setBusy(false); }
  }

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <View style={styles.handle} />
        <Serif size={22} style={{ marginBottom: 14 }}>Log ind</Serif>
        <TextInput style={styles.input} placeholder="E-mail" autoCapitalize="none"
          keyboardType="email-address" value={email} onChangeText={setEmail} />
        <TextInput style={styles.input} placeholder="Adgangskode" secureTextEntry
          value={pw} onChangeText={setPw} />
        {fejl ? <Mono size={11} color={Colors.bordeaux} style={{ marginBottom: 8 }}>{fejl}</Mono> : null}
        <Pressable style={[styles.btn, busy && { opacity: 0.6 }]} disabled={busy} onPress={submit}>
          <BtnLabel color="#fff">{busy ? 'Logger ind…' : 'Log ind'}</BtnLabel>
        </Pressable>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 38, height: 4, borderRadius: 2,
    backgroundColor: Border.medium, marginBottom: 14 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, padding: 12, marginBottom: 10, fontFamily: Fonts.sans, fontSize: 14 },
  btn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14, alignItems: 'center' },
});
