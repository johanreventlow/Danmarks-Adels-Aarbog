import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { LoginSheet } from '../../../components/redaktion/LoginSheet';
import { Body, Kicker, Mono, Serif } from '../../../components/Typography';
import { fetchKonflikter, type Konflikt } from '../../../data/redaktionRead';
import { counts } from '../../../data/selectors';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function Dashboard() {
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const session = useStore((s) => s.session);
  const rolle = useStore((s) => s.rolle);
  const dryRun = useStore((s) => s.dryRun);
  const setDryRun = useStore((s) => s.setDryRun);
  const [konflikter, setKonflikter] = useState<Konflikt[]>([]);
  const [konfliktFejl, setKonfliktFejl] = useState(false);
  const [loginOpen, setLoginOpen] = useState(false);
  const c = counts(model, aux);

  useEffect(() => {
    if (session) {
      setKonfliktFejl(false);
      // Fejl vises som eksplicit fejl-tilstand, ALDRIG som tom kø (cycle 03 NEW1).
      fetchKonflikter().then(setKonflikter).catch(() => setKonfliktFejl(true));
    }
  }, [session]);

  return (
    <View style={{ flex: 1, backgroundColor: Colors.surfaceGround }}>
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        <Kicker color={Colors.goldInk}>DANMARKS ADELS AARBOG</Kicker>
        <Serif size={34} style={{ marginBottom: 16 }}>Redaktion</Serif>

        <View style={[styles.card, { backgroundColor: Colors.surfaceInverse }]}>
          {session ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <InitialBadge name={session.user?.email ?? '?'} size={40} bg={Colors.bordeaux} color="#fff" />
              <View style={{ flex: 1 }}>
                <Body color={Colors.inkOnInverse}>{session.user?.email}</Body>
                <Mono size={9} color={Colors.inkMutedOnInverse}>{rolle.toUpperCase()}</Mono>
              </View>
            </View>
          ) : (
            <Pressable onPress={() => setLoginOpen(true)}>
              <Serif size={18} color={Colors.inkOnInverse}>Log ind for at redigere</Serif>
            </Pressable>
          )}
          <View style={styles.divider} />
          <View style={styles.rowBetween}>
            <Mono size={11} color={dryRun ? Colors.inkMutedOnInverse : Colors.live}>
              {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}
            </Mono>
            <Switch value={dryRun} onValueChange={setDryRun} />
          </View>
        </View>

        {session && konflikter.length ? (
          <>
            <Mono size={9.5} color={Colors.inkMuted} style={{ marginTop: 8, marginBottom: 6 }}>
              TIL GENNEMSYN · {konflikter.length} UENIGE FELTER
            </Mono>
            {konflikter.map((k) => {
              const navn = model?.byId[k.personId]?.name ?? `#${k.personId}`;
              return (
                <Pressable key={`${k.personId}-${k.factId}`} style={styles.konfliktRow}
                  onPress={() => router.push(`/redaktion/person/${k.personId}` as never)}>
                  <InitialBadge name={navn} size={32} />
                  <View style={{ flex: 1, marginLeft: 10 }}>
                    <Serif size={16}>{navn}</Serif>
                    <Mono size={9} color={Colors.inkMuted}>uenige kilder · {k.felt}</Mono>
                  </View>
                </Pressable>
              );
            })}
          </>
        ) : null}

        {session && konfliktFejl ? (
          <View style={styles.konfliktFejl}>
            <Mono size={9.5} color={Colors.live} style={{ marginBottom: 4 }}>TIL GENNEMSYN · FEJL</Mono>
            <Mono size={11} color={Colors.danger}>
              Kunne ikke hente konflikt-køen. Tom kø her betyder IKKE “ingen konflikter” — prøv igen.
            </Mono>
          </View>
        ) : null}

        <Mono size={9.5} color={Colors.inkMuted} style={{ marginTop: 12, marginBottom: 6 }}>
          ENTITETER I BASEN
        </Mono>
        <View style={styles.grid}>
          <GridCell n={c.personer} label="Personer" onPress={() => router.navigate('/redaktion/entiteter')} />
          {/* flere celler additivt fra counts(): familier, godser, kilder … */}
        </View>
      </ScrollView>
      <LoginSheet visible={loginOpen} onClose={() => setLoginOpen(false)} />
    </View>
  );
}

function GridCell({ n, label, onPress }: { n: number; label: string; onPress?: () => void }) {
  return (
    <Pressable style={styles.cell} onPress={onPress} disabled={!onPress}>
      <Serif size={21} color={Colors.bordeaux}>{n}</Serif>
      <Body size={13}>{label}</Body>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: Radius.card, padding: 16, marginBottom: 12 },
  divider: { height: 1, backgroundColor: 'rgba(244,239,230,0.14)', marginVertical: 12 },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  konfliktRow: { flexDirection: 'row', alignItems: 'center', backgroundColor: Colors.bordeauxTint,
    borderWidth: 1, borderColor: 'rgba(136,26,51,0.2)', borderRadius: 13, padding: 12, marginBottom: 7 },
  konfliktFejl: { backgroundColor: Colors.dangerTint, borderWidth: 1, borderColor: Colors.live,
    borderRadius: 13, padding: 12, marginTop: 8, marginBottom: 7 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.surfaceRaised, borderWidth: 1, borderColor: Border.light,
    borderRadius: 13, padding: 14, minWidth: '47%' },
});
