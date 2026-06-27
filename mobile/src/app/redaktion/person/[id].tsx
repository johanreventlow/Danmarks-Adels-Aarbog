import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { Body, Mono, Serif } from '../../../components/Typography';
import { fetchPersonEvidence, type PersonEvidence } from '../../../data/redaktionRead';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel']; // koen håndteres separat (ikke et fact)

export default function PersonEditor() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const model = useStore((s) => s.model);
  const showAnn = useStore((s) => s.showAnnotations);
  const [ev, setEv] = useState<PersonEvidence | null>(null);
  const person = id && model ? model.byId[id] : null;

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch(() => {}); }, [id]);

  function onAction(a: FaktaAction) { console.log('action', a); } // wires i Task 9

  if (!person) return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Person" />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>Personen blev ikke fundet.</Body>
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={person.name} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <View style={{ alignItems: 'center', marginBottom: 16 }}>
          <InitialBadge name={person.name} size={56} bg="#f8ecef" />
          <Serif size={25} style={{ marginTop: 8 }}>{person.name}</Serif>
          <Mono size={9} color={Colors.textMuted}>id {String(person.id)} · {ev?.koen ?? '—'}</Mono>
        </View>
        {showAnn ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 12 }}>
            Konklusion ← oplysninger. Hver oplysning er én kildes udsagn.
          </Mono>
        ) : null}
        {FELTER.map((felt) => (
          <FaktaKort key={felt} felt={felt} evidens={ev?.felter[felt]} onAction={onAction} />
        ))}
      </ScrollView>
    </View>
  );
}
