import { useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, TextInput, View } from 'react-native';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { searchPool } from '../../data/selectors';
import { Colors } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';
import { pickerSheetStyles } from './pickerSheetStyles';

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
      <Pressable style={pickerSheetStyles.backdrop} onPress={onClose} />
      <View style={pickerSheetStyles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Vælg person</Serif>
        <TextInput style={pickerSheetStyles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus autoCorrect={false} />
        <ScrollView style={{ maxHeight: 360 }} keyboardShouldPersistTaps="handled">
          {matches.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {matches.map((p) => (
            <Pressable key={p.id} style={pickerSheetStyles.row}
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
