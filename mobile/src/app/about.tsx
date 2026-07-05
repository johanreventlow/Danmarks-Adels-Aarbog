// Om slægten (README §5.6). Bygget fra bunden (billeder-i-narrativer 2026-07-05, Slice C4) —
// tidligere en hårdkodet pladsholder uden datahentning; nu en port af web/src/data/public.ts's
// fetchAbout-mønster. Hver linje/"Generelt" kan have flere udgaver (Slice C3's edition-faner) —
// pickPreferredBio vælger én pr. subjekt. NarrativRenderer (Slice C1) giver ##-overskrifter/
// linjeskift/indlejrede billeder i selve prosaen, ikke kun rå tekst.
import { useEffect, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { LoadGate } from '../components/LoadGate';
import { TopBar } from '../components/TopBar';
import { NarrativRenderer } from '../components/NarrativRenderer';
import { Body, Mono, Serif } from '../components/Typography';
import { fetchAbout, type AboutSection } from '../data/about';
import { Border, Colors, Radius } from '../theme/tokens';

const SLAEGT = 'Reventlow';

export default function AboutScreen() {
  const [sections, setSections] = useState<AboutSection[] | null>(null);
  useEffect(() => { fetchAbout().then(setSections).catch(() => setSections([])); }, []);

  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Om slægten" />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          <Serif size={34} style={{ lineHeight: 35 }}>Slægten {SLAEGT}</Serif>
          <Mono size={10} color={Colors.textMuted} style={{ marginTop: 8, letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
            Indledning til stamtavlen · Danmarks Adels Aarbog
          </Mono>
          <View style={styles.rule} />

          {sections == null ? (
            <Body size={13} color={Colors.textSecondary2}>Henter…</Body>
          ) : sections.length === 0 ? (
            <View style={styles.placeholder}>
              <Body size={13} color={Colors.textSecondary2} style={{ lineHeight: 13 * 1.5 }}>
                Ingen slægts-narrativ registreret endnu. Indledningen indlæses fra stamtavlen.
              </Body>
              <Mono size={9} color={Colors.gold} style={{ marginTop: 9, letterSpacing: 9 * 0.1, textTransform: 'uppercase' }}>
                Indlæses fra stamtavlen
              </Mono>
            </View>
          ) : (
            sections.map((s, i) => (
              <View key={i} style={{ marginBottom: 22 }}>
                {s.lineageNavn && <Serif size={22} color={Colors.bordeaux} style={{ marginBottom: 8 }}>{s.lineageNavn}</Serif>}
                <NarrativRenderer tekst={s.tekst} size={14} color={Colors.ink} />
              </View>
            ))
          )}
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
