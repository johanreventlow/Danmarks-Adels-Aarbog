import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { SletBekraeftSheet } from '../../../components/redaktion/SletBekraeftSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { fetchPersonEvidence, type PersonEvidence } from '../../../data/redaktionRead';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel']; // koen håndteres separat (ikke et fact)

export default function PersonEditor() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const showAnn = useStore((s) => s.showAnnotations);
  const [ev, setEv] = useState<PersonEvidence | null>(null);
  const [pending, setPending] = useState<Change | null>(null);
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  // privat: model har ikke feltet; bruger lokal optimistisk state (false som default)
  const [privat, setPrivat] = useState(false);
  // narrativ-tekst: prefill fra person.bio (første ikke-private narrativ fra load)
  const [narrativTekst, setNarrativTekst] = useState('');
  const person = id && model ? model.byId[id] : null;

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch(() => {}); }, [id]);

  // Seed narrativ-tekst fra model.bio (den første ikke-private narrativ, ordret fra basen).
  useEffect(() => { if (person?.bio) setNarrativTekst(person.bio); }, [person?.bio]);

  function onAction(a: FaktaAction) {
    if (a.type === 'gørKonklusion') {
      setPending({
        art: 'setKonklusion',
        subjektType: 'person',
        subjektId: id!,
        assertionId: String(a.assertionId),
      });
    } else if (a.type === 'slet') {
      setPending({
        art: 'sletOplysning',
        subjektType: 'person',
        subjektId: id!,
        assertionId: String(a.assertionId),
      });
    } else if (a.type === 'redigér') {
      setPending({
        art: 'redigerOplysning',
        subjektType: 'person',
        subjektId: id!,
        assertionId: String(a.assertionId),
        felt: a.felt,
        vaerdi: a.vaerdi,
        kildeFritekst: a.kilde,
      });
    } else if (a.type === 'tilføj') {
      setPending({
        art: 'fakta',
        subjektType: 'person',
        subjektId: id!,
        felt: a.felt,
        vaerdi: a.vaerdi,
        kildeFritekst: a.kilde,
      });
    }
  }

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

        {/* Handlingsrække: Privat-toggle + Slet-knap */}
        <View style={editorStyles.handlingsraekke}>
          <View style={editorStyles.privatRow}>
            <Body size={13} style={{ marginRight: 8 }}>Privat</Body>
            <Switch
              value={privat}
              onValueChange={(nyVaerdi) => {
                setPrivat(nyVaerdi);
                setPending({
                  art: 'setPrivat',
                  subjektType: 'person',
                  subjektId: id!,
                  payload: { privat: nyVaerdi },
                });
              }}
              thumbColor={privat ? Colors.bordeaux : Colors.textMuted2}
              trackColor={{ false: Colors.beige3, true: Colors.bordeauxFillLight2 }}
            />
          </View>
          <Pressable
            style={editorStyles.sletKnap}
            onPress={() => setConfirmDeleteOpen(true)}
          >
            <BtnLabel color={Colors.danger}>{'🗑 '}Slet person</BtnLabel>
          </Pressable>
        </View>

        {showAnn ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 12 }}>
            Konklusion ← oplysninger. Hver oplysning er én kildes udsagn.
          </Mono>
        ) : null}
        {FELTER.map((felt) => (
          <FaktaKort key={felt} felt={felt} evidens={ev?.felter[felt]} onAction={onAction} />
        ))}

        {/* Narrativ-sektion */}
        <View style={editorStyles.narrativSektion}>
          <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Narrativ / biografi</Mono>
          {person.bio && narrativTekst === person.bio ? (
            <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 4 }}>
              (prefill fra model — kun første ikke-private narrativ)
            </Mono>
          ) : null}
          <TextInput
            multiline
            value={narrativTekst}
            onChangeText={setNarrativTekst}
            style={editorStyles.narrativInput}
            placeholder="Skriv biografi her…"
            placeholderTextColor={Colors.textMuted2}
            textAlignVertical="top"
          />
          <Pressable
            style={editorStyles.gemKnap}
            onPress={() => {
              setPending({
                art: 'narrativ',
                subjektType: 'person',
                subjektId: id!,
                vaerdi: narrativTekst,
              });
            }}
          >
            <BtnLabel color="#fff">Gem narrativ</BtnLabel>
          </Pressable>
        </View>
      </ScrollView>

      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={() => {
          setPending(null);
          if (id) fetchPersonEvidence(id).then(setEv).catch(() => {});
        }}
      />
      {confirmDeleteOpen ? (
        <SletBekraeftSheet
          personId={id!}
          onClose={() => setConfirmDeleteOpen(false)}
          onDeleted={() => {
            setConfirmDeleteOpen(false);
            router.back();
          }}
        />
      ) : null}
    </View>
  );
}

const editorStyles = StyleSheet.create({
  handlingsraekke: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 16,
    paddingHorizontal: 4,
  },
  privatRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sletKnap: {
    borderWidth: 1,
    borderColor: Colors.danger,
    borderRadius: Radius.field,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  narrativSektion: {
    marginTop: 20,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: Border.light,
  },
  narrativInput: {
    backgroundColor: Colors.paperCard,
    borderRadius: Radius.field,
    borderWidth: 1,
    borderColor: Border.medium,
    padding: 12,
    minHeight: 120,
    fontFamily: 'HankenGrotesk_400Regular',
    fontSize: 13,
    color: Colors.ink,
  },
  gemKnap: {
    backgroundColor: Colors.bordeaux,
    borderRadius: Radius.field,
    padding: 14,
    alignItems: 'center',
    marginTop: 10,
  },
});
