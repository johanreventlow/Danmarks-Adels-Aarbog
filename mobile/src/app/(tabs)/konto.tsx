// Offentlig Konto-fane — login er ikke forbeholdt redaktører. Alle kan logge ind som
// medlem (ser levende slægtninge via RLS); redaktør-rollen får derudover en genvej ind.
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { InitialBadge } from '../../components/InitialBadge';
import { TopBar } from '../../components/TopBar';
import { LoginSheet } from '../../components/redaktion/LoginSheet';
import { Body, BtnLabel, Mono, Serif } from '../../components/Typography';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

export default function Konto() {
  const router = useRouter();
  const session = useStore((s) => s.session);
  const rolle = useStore((s) => s.rolle);
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
            <Serif size={20} color={Colors.paperBg}>Log ind</Serif>
            <Body size={13} color="#cabfa9" style={{ marginTop: 4 }}>
              Som medlem ser du også levende slægtninge. Redaktører kan derudover bidrage
              med rettelser.
            </Body>
            <Pressable style={styles.loginBtn} onPress={() => setLoginOpen(true)}>
              <BtnLabel color={Colors.ink}>Log ind</BtnLabel>
            </Pressable>
          </View>
        )}

        {session && rolle === 'redaktion' ? (
          <Pressable style={styles.redaktionBtn} onPress={() => router.push('/redaktion')}>
            <BtnLabel color="#fff">Gå til redaktion</BtnLabel>
          </Pressable>
        ) : null}

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

const styles = StyleSheet.create({
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 16, marginBottom: 12 },
  loginBtn: { backgroundColor: Colors.goldLight, borderRadius: Radius.field, padding: 12,
    alignItems: 'center', marginTop: 12 },
  redaktionBtn: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14,
    alignItems: 'center', marginBottom: 12 },
  logout: { borderWidth: 1, borderColor: 'rgba(138,43,43,0.3)', borderRadius: Radius.field,
    padding: 12, alignItems: 'center' },
});
