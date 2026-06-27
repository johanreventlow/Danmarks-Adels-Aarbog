import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { LoginSheet } from '../../../components/redaktion/LoginSheet';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Konto() {
  const session = useStore((s) => s.session);
  const rolle = useStore((s) => s.rolle);
  const dryRun = useStore((s) => s.dryRun);
  const showAnn = useStore((s) => s.showAnnotations);
  const setDryRun = useStore((s) => s.setDryRun);
  const setShowAnn = useStore((s) => s.setShowAnnotations);
  const doSignOut = useStore((s) => s.doSignOut);
  const [loginOpen, setLoginOpen] = useState(false);
  const email = session?.user?.email ?? '';

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Konto" showBack={false} />
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        {session ? (
          <View style={styles.card}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <InitialBadge name={email || '?'} size={52} bg={Colors.bordeaux} color="#fff" />
              <View>
                <Body>{email}</Body>
                <Mono size={9} color={Colors.textMuted}>{rolle.toUpperCase()}</Mono>
              </View>
            </View>
          </View>
        ) : (
          <View style={[styles.card, { backgroundColor: Colors.ink }]}>
            <Serif size={20} color={Colors.paperBg}>Log ind for at redigere</Serif>
            <Pressable style={styles.loginBtn} onPress={() => setLoginOpen(true)}>
              <BtnLabel color={Colors.ink}>Log ind</BtnLabel>
            </Pressable>
          </View>
        )}

        <View style={styles.card}>
          <Row label="Dry-run · skriver ikke" value={dryRun} onChange={setDryRun} />
          <Row label="Vis forklaringer" value={showAnn} onChange={setShowAnn} />
        </View>

        {session ? (
          <Pressable style={styles.logout} onPress={doSignOut}>
            <BtnLabel color={Colors.danger}>Log ud</BtnLabel>
          </Pressable>
        ) : null}
      </ScrollView>
      <LoginSheet visible={loginOpen} onClose={() => setLoginOpen(false)} />
    </View>
  );
}

function Row({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <View style={styles.row}>
      <Body>{label}</Body>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 16, marginBottom: 12 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 6 },
  loginBtn: { backgroundColor: Colors.goldLight, borderRadius: Radius.field, padding: 12,
    alignItems: 'center', marginTop: 12 },
  logout: { borderWidth: 1, borderColor: 'rgba(138,43,43,0.3)', borderRadius: Radius.field,
    padding: 12, alignItems: 'center' },
});
