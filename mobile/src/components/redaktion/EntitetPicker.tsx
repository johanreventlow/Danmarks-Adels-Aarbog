import { useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';

export function EntitetPicker({ type, onValg, onClose }: {
  type: 'organisation' | 'estate';
  onValg: (v: { objektType: string; objektId: string; navn: string }) => void;
  onClose: () => void;
}) {
  const aux = useStore((s) => s.redaktionAux);
  const [query, setQuery] = useState('');
  const liste = useMemo(() => {
    const base = type === 'organisation'
      ? (aux?.orgListe ?? []).map((o) => ({ id: o.id, navn: o.navn }))
      : (aux?.godsListe ?? []).map((g) => ({ id: g.id, navn: g.navn }));
    const q = query.trim().toLowerCase();
    return q ? base.filter((x) => x.navn.toLowerCase().includes(q)) : base;
  }, [aux, type, query]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>{type === 'organisation' ? 'Vælg organisation' : 'Vælg gods'}</Serif>
        <TextInput style={styles.input} placeholder="Søg…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus />
        <ScrollView style={{ maxHeight: 320 }}>
          {liste.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {liste.map((x) => (
            <Pressable key={x.id} style={styles.row}
              onPress={() => { onValg({ objektType: type, objektId: x.id, navn: x.navn }); onClose(); }}>
              <Body size={14}>{x.navn}</Body>
              <Mono size={8} color={Colors.textMuted}>#{x.id}</Mono>
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
