import { useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { searchPool } from '../../data/selectors';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';

export function PersonPicker({ excludeId, onValg, onClose }: {
  excludeId?: string;
  onValg: (v: { personId: string; navn: string }) => void;
  onClose: () => void;
}) {
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [query, setQuery] = useState('');
  useEffect(() => { fetchRedaktionPersoner().then(setPersoner).catch(() => {}); }, []);
  const pool = useMemo(() => personer.filter((p) => p.id !== excludeId)
    .map((p) => ({ id: p.id, name: p.navn, years: p.aar, born: p.born })), [personer, excludeId]);
  const { matches } = useMemo(() => searchPool(pool, { query, sort: 'alpha', activeLetter: null }), [pool, query]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Vælg person</Serif>
        <TextInput style={styles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus autoCorrect={false} />
        <ScrollView style={{ maxHeight: 360 }} keyboardShouldPersistTaps="handled">
          {matches.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {matches.map((p) => (
            <Pressable key={p.id} style={styles.row}
              onPress={() => { onValg({ personId: p.id, navn: p.name }); onClose(); }}>
              <Body size={14}>{p.name}</Body>
              {p.years ? <Mono size={9} color={Colors.textMuted}>{p.years}</Mono> : null}
            </Pressable>
          ))}
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet, padding: 20, paddingBottom: 36 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field,
    paddingHorizontal: 12, paddingVertical: 9, marginBottom: 8, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  row: { paddingVertical: 9, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: Border.light },
});
