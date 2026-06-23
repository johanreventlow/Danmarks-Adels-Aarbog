// Gods-detalje (README §5.8). Port af v2-designet (linje 188-213): gods-navn + slags-badge,
// "Kommer snart"-boks til godshistorik, og ægte ejer-tidslinje (prik-og-streg, periode + navn,
// klikbar → person). Data fra aux.estateById + aux.ownersByEstate.
import { useLocalSearchParams, useRouter } from 'expo-router';
import { ScrollView, StyleSheet, View } from 'react-native';
import { LoadGate } from '../../components/LoadGate';
import { TopBar } from '../../components/TopBar';
import { Body, BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';

export default function EstateScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);

  const estate = id && aux ? aux.estateById[id] : null;
  const owners = id && aux ? aux.ownersByEstate[id] ?? [] : [];

  return (
    <View style={{ flex: 1 }}>
      <TopBar title={estate?.navn ?? 'Gods'} />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          {!estate ? (
            <Body color={Colors.textMuted}>Godset blev ikke fundet.</Body>
          ) : (
            <>
              <Serif size={32} style={{ lineHeight: 33 }}>{estate.navn}</Serif>
              {estate.slags ? (
                <View style={styles.slagsBadge}>
                  <BtnLabel size={11.5} color={Colors.bordeaux}>{estate.slags}</BtnLabel>
                </View>
              ) : null}

              <View style={styles.soonBox}>
                <Body size={13} color={Colors.textSecondary2} style={{ lineHeight: 13 * 1.5 }}>
                  Beskrivelse af godsets historie indlæses fra Aarbogen.
                </Body>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 9, letterSpacing: 9 * 0.1, textTransform: 'uppercase' }}>
                  Kommer snart
                </Mono>
              </View>

              <Kicker size={9.5} style={{ marginTop: 24, marginBottom: 12, letterSpacing: 9.5 * 0.14 }}>
                Ejere gennem tiden
              </Kicker>
              {owners.map((o, i) => {
                const person = model?.byId[o.personId];
                const name = person?.name ?? 'Ukendt ejer';
                const last = i === owners.length - 1;
                return (
                  <View key={`${o.personId}-${i}`} style={{ flexDirection: 'row', gap: 13, alignItems: 'flex-start' }}>
                    <View style={styles.dotCol}>
                      <View style={styles.dot} />
                      {!last ? <View style={styles.line} /> : null}
                    </View>
                    <View
                      style={{ flex: 1, paddingBottom: 16 }}
                      onStartShouldSetResponder={() => true}
                      onResponderRelease={() => person && router.push(`/person/${o.personId}`)}>
                      {o.period ? <Mono size={10.5} color={Colors.textMuted}>{o.period}</Mono> : null}
                      <Serif size={19} color={person ? Colors.ink : Colors.textMuted} style={{ marginTop: 1, lineHeight: 20, fontFamily: Fonts.serifSemi }}>
                        {name}{person ? ' ›' : ''}
                      </Serif>
                    </View>
                  </View>
                );
              })}
            </>
          )}
        </ScrollView>
      </LoadGate>
    </View>
  );
}

const styles = StyleSheet.create({
  slagsBadge: {
    alignSelf: 'flex-start',
    marginTop: 9,
    backgroundColor: Colors.bordeauxFillLight2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(136,26,51,0.16)',
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  soonBox: {
    marginTop: 18,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: 'rgba(34,31,26,0.2)',
    borderRadius: Radius.field,
    padding: 15,
    backgroundColor: Colors.paperCard,
  },
  dotCol: { width: 13, alignItems: 'center', paddingTop: 6 },
  dot: { width: 11, height: 11, borderRadius: Radius.round, backgroundColor: Colors.bordeaux },
  line: { width: 2, flex: 1, minHeight: 26, backgroundColor: 'rgba(136,26,51,0.22)', marginTop: 2 },
});
