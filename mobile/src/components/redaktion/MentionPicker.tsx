// @-vælger til hyperlinks i narrativ-tekst (spec §5.4). PoC kun person-mål (D2).
// Mirror'er PersonPicker.tsx (samme datakilde/søgning/sheet-stil) — returnerer et færdigt
// token via makeToken i stedet for {personId, navn}.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Modal, Pressable, ScrollView, TextInput, View } from 'react-native';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { oversaetFejl } from '../../data/redaktionWrite';
import { searchPool } from '../../data/selectors';
import { makeToken } from '../../lib/mentions';
import { Colors } from '../../theme/tokens';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import { pickerSheetStyles } from './pickerSheetStyles';

export function MentionPicker({ onVælg, onClose }: {
  onVælg: (token: string) => void;
  onClose: () => void;
}) {
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [query, setQuery] = useState('');
  // review10 M3: fejl skal kunne skelnes fra "ingen personer" — ellers er en netværks-/
  // auth-fejl umulig at se eller genforsøge for redaktøren.
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState<string | null>(null);

  const indlæs = useCallback(() => {
    setStatus('loading');
    fetchRedaktionPersoner()
      .then((p) => { setPersoner(p); setStatus('ready'); })
      .catch((e: any) => { setFejl(oversaetFejl(e.message)); setStatus('error'); });
  }, []);
  useEffect(() => { indlæs(); }, [indlæs]);

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
        {status === 'error' ? (
          <View style={{ padding: 12 }}>
            <Body color={Colors.danger}>{fejl}</Body>
            <Pressable onPress={indlæs} style={{ marginTop: 8 }}>
              <BtnLabel color={Colors.bordeaux}>Prøv igen</BtnLabel>
            </Pressable>
          </View>
        ) : null}
        <ScrollView style={{ maxHeight: 360 }} keyboardShouldPersistTaps="handled">
          {status === 'ready' && matches.length === 0 ? (
            <Body color={Colors.textMuted} style={{ padding: 12 }}>Ingen.</Body>
          ) : null}
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
