// @-vælger til hyperlinks i narrativ-tekst (spec §5.4). PoC kun person-mål (D2).
// Mirror'er PersonPicker.tsx (samme datakilde/søgning/sheet-stil) — returnerer et færdigt
// token via makeToken i stedet for {personId, navn}.
import { useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, TextInput, View } from 'react-native';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { searchPool } from '../../data/selectors';
import { makeToken } from '../../lib/mentions';
import { Colors } from '../../theme/tokens';
import { Body, Mono, Serif } from '../Typography';
import { pickerSheetStyles } from './pickerSheetStyles';

export function MentionPicker({ onVælg, onClose }: {
  onVælg: (token: string) => void;
  onClose: () => void;
}) {
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [query, setQuery] = useState('');
  useEffect(() => { fetchRedaktionPersoner().then(setPersoner).catch(() => {}); }, []);
  const pool = useMemo(() => personer
    .map((p) => ({ id: p.id, name: p.navn, years: p.aar, born: p.born })), [personer]);
  const { matches } = useMemo(() => searchPool(pool, { query, sort: 'alpha', activeLetter: null }), [pool, query]);

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={pickerSheetStyles.backdrop} onPress={onClose} />
      <View style={pickerSheetStyles.sheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Indsæt link til person</Serif>
        <TextInput style={pickerSheetStyles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoFocus autoCorrect={false} />
        <ScrollView style={{ maxHeight: 360 }} keyboardShouldPersistTaps="handled">
          {matches.length === 0 ? <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body> : null}
          {matches.map((p) => (
            <Pressable key={p.id} style={pickerSheetStyles.row}
              onPress={() => { onVælg(makeToken('person', Number(p.id), p.name)); onClose(); }}>
              <Body size={14}>{p.name}</Body>
              {p.years ? <Mono size={9} color={Colors.textMuted}>{p.years}</Mono> : null}
            </Pressable>
          ))}
        </ScrollView>
      </View>
    </Modal>
  );
}
