// Er vi i familie? (README §5.4) — UDSKUDT i denne leverance. Viser de to valgte personer
// og en "kommer snart"-tilstand; den fulde LCA-algoritme + person-vælger (M1) bygges senere.
import { ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LoadGate } from '../../components/LoadGate';
import { Body, Kicker, Serif } from '../../components/Typography';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

export default function RelateScreen() {
  const insets = useSafeAreaInsets();
  const model = useStore((s) => s.model);
  const relA = useStore((s) => s.relA);
  const relB = useStore((s) => s.relB);
  const a = relA && model ? model.byId[relA] : null;
  const b = relB && model ? model.byId[relB] : null;

  return (
    <LoadGate>
      <ScrollView contentContainerStyle={{ padding: 20, paddingTop: insets.top + 16 }}>
        <Serif size={26} style={{ marginBottom: 16 }}>Er vi i familie?</Serif>
        <View style={styles.field}>
          <Kicker size={8}>Person A</Kicker>
          <Serif size={18}>{a?.name ?? 'Vælg person'}</Serif>
        </View>
        <Serif size={20} italic color={Colors.textMuted} style={{ textAlign: 'center', marginVertical: 6 }}>&</Serif>
        <View style={styles.field}>
          <Kicker size={8}>Person B</Kicker>
          <Serif size={18}>{b?.name ?? 'Vælg person'}</Serif>
        </View>
        <View style={styles.soon}>
          <Kicker color={Colors.gold}>Slægtskab</Kicker>
          <Body size={13} color={Colors.beige2} style={{ marginTop: 6 }}>
            Slægtskabs-beregning (fælles ane, fætter/kusine-grad, trin-for-trin) bygges i næste runde.
          </Body>
        </View>
      </ScrollView>
    </LoadGate>
  );
}

const styles = StyleSheet.create({
  field: {
    backgroundColor: Colors.paperCard,
    borderRadius: Radius.card,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    padding: 14,
  },
  soon: {
    marginTop: 24,
    backgroundColor: Colors.ink,
    borderRadius: Radius.card,
    padding: 18,
  },
});
