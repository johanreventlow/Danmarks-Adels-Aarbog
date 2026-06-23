// Om slægten (README §5.6). Port af v2-designet (linje 148-167): titel + kilde-label +
// sektioner med overskrift + brødtekst eller stiplet pladsholder ("Indlæses fra stamtavlen")
// indtil narrative subjekt_type='slaegt' har data.
import { ScrollView, StyleSheet, View } from 'react-native';
import { LoadGate } from '../components/LoadGate';
import { TopBar } from '../components/TopBar';
import { Body, Mono, Serif } from '../components/Typography';
import { Border, Colors, Fonts, Radius } from '../theme/tokens';

const SLAEGT = 'Reventlow';
const SOURCE_LABEL = 'DAA 2018-20';

// Indtil slaegt-narrativ loades vises pladsholdere (tom-tilstand, jf. design).
const SECTIONS = [
  {
    heading: 'Slægtens oprindelse',
    note: 'Den indledende slægtshistorie fra Aarbogens stamtavle indlæses her — den fulde prosatekst, fuldtekstsøgbar.',
  },
  {
    heading: 'Heraldisk indledning',
    note: 'Det heraldiske forsatsstof (våben, brisering mellem linjer) som selvstændig artikel.',
  },
];

export default function AboutScreen() {
  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Om slægten" />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          <Serif size={34} style={{ lineHeight: 35 }}>Slægten {SLAEGT}</Serif>
          <Mono size={10} color={Colors.textMuted} style={{ marginTop: 8, letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
            Indledning til stamtavlen · {SOURCE_LABEL}
          </Mono>
          <View style={styles.rule} />

          {SECTIONS.map((s) => (
            <View key={s.heading} style={{ marginBottom: 22 }}>
              <Serif size={22} style={{ marginBottom: 8 }}>{s.heading}</Serif>
              <View style={styles.placeholder}>
                <Body size={13} color={Colors.textSecondary2} style={{ lineHeight: 13 * 1.5 }}>{s.note}</Body>
                <Mono size={9} color={Colors.gold} style={{ marginTop: 9, letterSpacing: 9 * 0.1, textTransform: 'uppercase' }}>
                  Indlæses fra stamtavlen
                </Mono>
              </View>
            </View>
          ))}
        </ScrollView>
      </LoadGate>
    </View>
  );
}

const styles = StyleSheet.create({
  rule: { height: 1, backgroundColor: Border.medium, marginVertical: 18 },
  placeholder: {
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: 'rgba(34,31,26,0.2)',
    borderRadius: Radius.field,
    padding: 16,
    backgroundColor: Colors.paperCard,
  },
});
