// Person-vælger (M1) — bottom-sheet modal (README §5 modaler). Søgefelt + scroll-liste;
// vælg en person til slægtskabs-felt A eller B. Port af v2-markup (linje 618-639).
import { useMemo, useState } from 'react';
import { FlatList, Modal, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { compareDanish } from '../lib/collation';
import { useStore } from '../store/useStore';
import { Border, Colors, Fonts, Radius } from '../theme/tokens';
import { BtnLabel, Mono, Serif } from './Typography';

export function PersonPicker({
  visible,
  title,
  onClose,
  onPick,
}: {
  visible: boolean;
  title: string;
  onClose: () => void;
  onPick: (id: string) => void;
}) {
  const model = useStore((s) => s.model);
  const [query, setQuery] = useState('');

  const results = useMemo(() => {
    const pool = model?.persons ?? [];
    const q = query.trim().toLowerCase();
    return pool
      .filter((p) => !q || p.name.toLowerCase().includes(q))
      .sort((a, b) => compareDanish(a.name, b.name));
  }, [model, query]);

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <Pressable style={{ flex: 1 }} onPress={onClose} />
        <View style={styles.sheet}>
          <View style={styles.header}>
            <Serif size={21}>{title}</Serif>
            <Pressable onPress={onClose} hitSlop={10}>
              <BtnLabel size={13} color={Colors.bordeaux}>Luk</BtnLabel>
            </Pressable>
          </View>
          <TextInput
            style={styles.input}
            placeholder="Søg navn…"
            placeholderTextColor={Colors.textMuted}
            value={query}
            onChangeText={setQuery}
            autoCorrect={false}
            autoFocus
          />
          <FlatList
            style={{ marginTop: 12 }}
            data={results}
            keyExtractor={(p) => p.id}
            keyboardShouldPersistTaps="handled"
            renderItem={({ item }) => (
              <Pressable
                style={styles.row}
                onPress={() => {
                  onPick(item.id);
                  setQuery('');
                }}>
                <View style={styles.avatar}>
                  <Serif size={15} color={Colors.bordeaux}>{item.name[0]?.toUpperCase() ?? '?'}</Serif>
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={17} style={{ lineHeight: 18 }}>{item.name}</Serif>
                  {item.years ? <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 1 }}>{item.years}</Mono> : null}
                </View>
              </Pressable>
            )}
          />
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
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 },
  input: {
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 15,
    paddingVertical: 12,
    fontFamily: Fonts.sans,
    fontSize: 15,
    color: Colors.ink,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 10,
    paddingHorizontal: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.faint,
  },
  avatar: {
    width: 36, height: 36, borderRadius: Radius.round, backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
});
