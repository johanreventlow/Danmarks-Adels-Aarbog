// Slægtens våben (README §5.9). Port af v2-designet (linje 216-240): autoriseret våben
// (150×185 stribet pladsholder) + blasonering, og grid 2×N af varianter/segl + note.
// Medier (coat_of_arms/media) er endnu ikke linket → pladsholdere (fabrikér ikke heraldik).
import { ScrollView, StyleSheet, View } from 'react-native';
import { LoadGate } from '../components/LoadGate';
import { StripedPlaceholder } from '../components/StripedPlaceholder';
import { TopBar } from '../components/TopBar';
import { Body, Kicker, Mono, Serif } from '../components/Typography';
import { Border, Colors, Fonts, Radius, Shadow } from '../theme/tokens';

// Blasonering indlæses fra coat_of_arms når data linkes; indtil da neutral pladsholder-tekst.
const BLASONERING = 'Blasoneringen indlæses fra Aarbogens våbenbeskrivelse, når coat_of_arms knyttes.';

const VARIANTS = [
  { titel: 'DAA-gengivelse', meta: 'autoriseret · 2018-20' },
  { titel: 'Ældre stik', meta: 'variant · 1800-tal' },
  { titel: 'Segl', meta: 'segl · dateret' },
  { titel: 'Linje-brisering', meta: 'variant · linje V' },
];

export default function ArmsScreen() {
  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Slægtens våben" />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          <Mono size={10} color={Colors.textMuted} style={{ letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
            Autoriseret våben
          </Mono>
          <Body size={12} color={Colors.textMuted} style={{ marginBottom: 14 }}>
            Dansk Adelsforenings gældende gengivelse
          </Body>

          <View style={styles.armCard}>
            <StripedPlaceholder width={150} height={185} radius={10} label="våbenskjold" />
            <Mono size={8.5} color={Colors.gold} style={{ marginTop: 14, letterSpacing: 8.5 * 0.1, textTransform: 'uppercase' }}>
              Blasonering
            </Mono>
            <Serif size={16} italic color={Colors.textSecondary} style={{ textAlign: 'center', marginTop: 5, lineHeight: 16 * 1.45, fontFamily: Fonts.serifItalic }}>
              {BLASONERING}
            </Serif>
          </View>

          <Mono size={10} color={Colors.textMuted} style={{ marginTop: 26, letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
            Øvrige gengivelser & segl
          </Mono>
          <Body size={12} color={Colors.textMuted} style={{ marginBottom: 14 }}>
            Varianter over tid, brisering mellem linjer, daterede segl
          </Body>

          <View style={styles.grid}>
            {VARIANTS.map((v) => (
              <View key={v.titel} style={styles.variant}>
                <StripedPlaceholder radius={8} style={{ width: '100%', aspectRatio: 0.82 }} />
                <Serif size={15} style={{ marginTop: 7, lineHeight: 16 }}>{v.titel}</Serif>
                <Mono size={9} color={Colors.textMuted} style={{ marginTop: 2 }}>{v.meta}</Mono>
              </View>
            ))}
          </View>

          <View style={styles.note}>
            <Body size={12} color={Colors.textSecondary2} style={{ lineHeight: 12 * 1.5 }}>
              Varianter, briseringer og daterede segl tilføjes efterhånden som de digitaliseres.
            </Body>
          </View>
        </ScrollView>
      </LoadGate>
    </View>
  );
}

const styles = StyleSheet.create({
  armCard: {
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: 16,
    padding: 22,
    alignItems: 'center',
    ...Shadow.card,
  },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 11 },
  variant: {
    width: '47%',
    flexGrow: 1,
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 12,
    padding: 11,
  },
  note: {
    marginTop: 14,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: 'rgba(34,31,26,0.2)',
    borderRadius: Radius.field,
    padding: 13,
    backgroundColor: Colors.paperCard,
  },
});
