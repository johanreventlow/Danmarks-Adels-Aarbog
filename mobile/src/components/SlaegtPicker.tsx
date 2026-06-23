// Slægts-vælger (M2) — bottom-sheet modal (README §5 modaler). Reventlow er aktiv (bordeaux);
// Bardenfleth / Ahlefeldt-Laurvig / Scheel = "ikke tilføjet" (dæmpet, ikke-klikbar).
// Port af v2-markup (linje 642-665) + slaegtList (1198-1208).
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Border, Colors, Radius } from '../theme/tokens';
import { Body, BtnLabel, Mono, Serif } from './Typography';

type Slaegt = { name: string; crest: string; sub: string; active?: boolean; coming?: boolean };

export function SlaegtPicker({
  visible,
  personCount,
  onClose,
}: {
  visible: boolean;
  personCount: number;
  onClose: () => void;
}) {
  const slaegter: Slaegt[] = [
    { name: 'Reventlow', crest: 'R', sub: `${personCount} personer · DAA 2018-20`, active: true },
    { name: 'Bardenfleth', crest: 'B', sub: 'Tilføjes i kommende udtræk', coming: true },
    { name: 'Ahlefeldt-Laurvig', crest: 'A', sub: 'Tilføjes i kommende udtræk', coming: true },
    { name: 'Scheel', crest: 'S', sub: 'Tilføjes i kommende udtræk', coming: true },
  ];

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <Pressable style={{ flex: 1 }} onPress={onClose} />
        <View style={styles.sheet}>
          <View style={styles.header}>
            <Serif size={21}>Vælg slægt</Serif>
            <Pressable onPress={onClose} hitSlop={10}>
              <BtnLabel size={13} color={Colors.bordeaux}>Luk</BtnLabel>
            </Pressable>
          </View>
          <Body size={12} color={Colors.textMuted} style={{ marginBottom: 12 }}>
            Hver ny slægt lægges til som sit eget datasæt. Slægtskab kan findes på tværs.
          </Body>
          <ScrollView contentContainerStyle={{ gap: 8 }}>
            {slaegter.map((sl) => (
              <Pressable
                key={sl.name}
                disabled={!sl.active}
                onPress={onClose}
                style={[styles.row, sl.active ? styles.rowActive : styles.rowComing]}>
                <View style={[styles.crest, { backgroundColor: sl.active ? Colors.bordeaux : Colors.beige2 }]}>
                  <Serif size={17} color={sl.active ? Colors.paperBg : '#bcae93'}>{sl.crest}</Serif>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={20} style={{ lineHeight: 21 }}>{sl.name}</Serif>
                  <Body size={11.5} color={Colors.textSecondary2} style={{ marginTop: 1 }}>{sl.sub}</Body>
                </View>
                {sl.active ? (
                  <Mono size={9} color={Colors.bordeaux} style={{ letterSpacing: 0.7, textTransform: 'uppercase' }}>aktiv</Mono>
                ) : (
                  <Mono size={9} color="#bcae93" style={{ letterSpacing: 0.7, textTransform: 'uppercase' }}>ikke tilføjet</Mono>
                )}
              </Pressable>
            ))}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(20,17,13,0.4)', justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: Colors.paperBg,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    maxHeight: '74%',
    paddingHorizontal: 18,
    paddingTop: 16,
    paddingBottom: 26,
  },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 13, borderRadius: 13, paddingVertical: 13, paddingHorizontal: 15, borderWidth: 1.5 },
  rowActive: { backgroundColor: Colors.bordeauxFillLight, borderColor: Colors.bordeaux },
  rowComing: { backgroundColor: Colors.paperCard, borderColor: Border.light, opacity: 0.7 },
  crest: { width: 38, height: 38, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
});
