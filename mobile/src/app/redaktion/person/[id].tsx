import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { SletBekraeftSheet } from '../../../components/redaktion/SletBekraeftSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { EntitetPicker } from '../../../components/redaktion/EntitetPicker';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { parentsOf, spousesOf, childrenByMarriage } from '../../../data/selectors';
import { fetchPersonEvidence, fetchPersonNarrativ, fetchPersonRelationer, type PersonEvidence, type PersonRelation } from '../../../data/redaktionRead';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel']; // koen håndteres separat (ikke et fact)
const FELT_LABEL: Record<string, string> = { navn: 'navn', foedt: 'født', doed: 'død', titel: 'titel' };

function CenterMsg({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={title} />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>{children}</Body>
    </View>
  );
}

function RelTilfoejSheet({ scratch, onClose, onGem }: {
  scratch: { objektType: string; objektId: string; navn: string; rolle: string; periode: string };
  onClose: () => void;
  onGem: (rolle: string, periode: string) => void;
}) {
  const [rolle, setRolle] = useState(scratch.rolle);
  const [periode, setPeriode] = useState(scratch.periode);
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Tilføj relation</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>{scratch.navn}</Body>
        <TextInput
          style={editorStyles.addInput}
          placeholder="Rolle (valgfri)"
          placeholderTextColor={Colors.textMuted2}
          value={rolle}
          onChangeText={setRolle}
        />
        <TextInput
          style={[editorStyles.addInput, { marginTop: 8 }]}
          placeholder="Periode (valgfri)"
          placeholderTextColor={Colors.textMuted2}
          value={periode}
          onChangeText={setPeriode}
        />
        <View style={{ flexDirection: 'row', gap: 8, marginTop: 12 }}>
          <Pressable style={editorStyles.addOpret} onPress={() => onGem(rolle, periode)}>
            <BtnLabel color="#fff">Gem</BtnLabel>
          </Pressable>
          <Pressable style={editorStyles.addAnnuller} onPress={onClose}>
            <BtnLabel color={Colors.textMuted}>Annullér</BtnLabel>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

export default function PersonEditor() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const redaktionModel = useStore((s) => s.redaktionModel);
  const redaktionAux = useStore((s) => s.redaktionAux);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const showAnn = useStore((s) => s.showAnnotations);
  const dryRun = useStore((s) => s.dryRun);
  const setDryRun = useStore((s) => s.setDryRun);
  const [ev, setEv] = useState<PersonEvidence | null>(null);
  const [pending, setPending] = useState<Change | null>(null);
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  const person = id && redaktionModel ? redaktionModel.byId[id] : null;

  // privat: initialiseres fra redaktionModel.byId[id].privat
  const [privat, setPrivat] = useState(false);
  useEffect(() => { if (person) setPrivat(Boolean(person.privat)); }, [person?.privat]);

  // narrativ-tekst + narrativ-privat: prefill fra fetchPersonNarrativ (skrive-mål + privat bevares).
  // narrativStatus BLOKERER Gem indtil prefill er lykkedes — ellers ville en slugt fetch-fejl
  // (tom tekst vist) lade Gem OVERSKRIVE den eksisterende narrativ destruktivt (cycle 04 NEW1).
  const [narrativTekst, setNarrativTekst] = useState('');
  const [narrativPrivat, setNarrativPrivat] = useState(false);
  const [narrativStatus, setNarrativStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  useEffect(() => {
    if (!id) return;
    setNarrativStatus('loading');
    fetchPersonNarrativ(id).then((n) => {
      setNarrativTekst(n?.tekst ?? '');
      setNarrativPrivat(n?.privat ?? false);
      setNarrativStatus('ready');
    }).catch(() => setNarrativStatus('error'));
  }, [id]);

  // Sektion-niveau "opret nyt fact"-form (operation B): hvilket felt + scratch-værdier.
  const [addFelt, setAddFelt] = useState<string | null>(null);
  const [addScratch, setAddScratch] = useState({ vaerdi: '', kilde: '' });

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch(() => {}); }, [id]);

  const [relationer, setRelationer] = useState<PersonRelation[]>([]);
  const [pickerType, setPickerType] = useState<'organisation' | 'estate' | null>(null);
  const [relScratch, setRelScratch] = useState<{ objektType: string; objektId: string; navn: string; rolle: string; periode: string } | null>(null);
  useEffect(() => {
    if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
  }, [id, redaktionAux]);

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
      // Operation A: ny oplysning til DETTE fact (fact-målrettet).
      setPending({
        art: 'tilfoejOplysning',
        subjektType: 'person',
        subjektId: id!,
        factId: String(a.factId),
        felt: a.felt,
        vaerdi: a.vaerdi,
        kildeFritekst: a.kilde,
      });
    }
  }

  // Operation B: opret nyt distinkt fact (fx ny titel) fra sektion-knappen.
  function opretFakta(felt: string, vaerdi: string, kilde: string) {
    setPending({
      art: 'opretFakta',
      subjektType: 'person',
      subjektId: id!,
      felt,
      vaerdi,
      kildeFritekst: kilde || undefined,
    });
  }

  if (redaktionStatus === 'idle' || redaktionStatus === 'loading') return <CenterMsg title="Person">Henter…</CenterMsg>;
  if (redaktionStatus === 'error') return <CenterMsg title="Person">Kunne ikke hente redaktion-data.</CenterMsg>;
  if (!person) return <CenterMsg title="Person">Personen blev ikke fundet.</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={person.name} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <View style={{ alignItems: 'center', marginBottom: 16 }}>
          <InitialBadge name={person.name} size={56} bg="#f8ecef" />
          <Serif size={25} style={{ marginTop: 8 }}>{person.name}</Serif>
          <Mono size={9} color={Colors.textMuted}>id {String(person.id)} · {ev?.koen ?? '—'}</Mono>
        </View>

        {/* Skrivemode (global, samme state som dashboard/konto) — placeret her så man kan
            slå LIVE til lige hvor man skriver (in-app-nav til personer = plan 2). */}
        <View style={[editorStyles.skrivemode, dryRun ? editorStyles.skrivemodeDry : editorStyles.skrivemodeLive]}>
          <View style={{ flex: 1 }}>
            <Mono size={8} color={Colors.textMuted}>SKRIVEMODE (HELE SESSIONEN)</Mono>
            <Mono size={11} color={dryRun ? Colors.textSecondary2 : Colors.liveRoed}>
              {dryRun ? 'Dry-run · skriver ikke' : 'LIVE · skriver til basen'}
            </Mono>
          </View>
          <Switch
            value={!dryRun}
            onValueChange={(live) => setDryRun(!live)}
            thumbColor={dryRun ? Colors.textMuted2 : Colors.liveRoed}
            trackColor={{ false: Colors.beige3, true: Colors.konfliktFlade }}
          />
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
        {FELTER.map((felt) => {
          const facts = ev?.felter[felt] ?? [];
          return (
            <View key={felt} style={{ marginBottom: 6 }}>
              <Mono size={9} color={Colors.gold} style={{ marginTop: 6, marginBottom: 4 }}>
                {(FELT_LABEL[felt] ?? felt).toUpperCase()}
              </Mono>
              {facts.length === 0 ? (
                <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 8 }}>— ingen oplysninger</Mono>
              ) : (
                facts.map((fe) => (
                  <FaktaKort key={fe.factId} felt={felt} evidens={fe} hideFeltLabel onAction={onAction} />
                ))
              )}
              {/* Operation B: opret nyt distinkt fact under feltet (fx ny titel). */}
              {addFelt === felt ? (
                <View style={editorStyles.addForm}>
                  <TextInput
                    style={editorStyles.addInput}
                    placeholder={`Ny ${FELT_LABEL[felt] ?? felt}…`}
                    placeholderTextColor={Colors.textMuted2}
                    value={addScratch.vaerdi}
                    onChangeText={(v) => setAddScratch((s) => ({ ...s, vaerdi: v }))}
                    autoFocus
                  />
                  <TextInput
                    style={editorStyles.addInput}
                    placeholder="Kilde (valgfri)"
                    placeholderTextColor={Colors.textMuted2}
                    value={addScratch.kilde}
                    onChangeText={(v) => setAddScratch((s) => ({ ...s, kilde: v }))}
                  />
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <Pressable
                      style={editorStyles.addOpret}
                      onPress={() => {
                        if (!addScratch.vaerdi.trim()) return;
                        opretFakta(felt, addScratch.vaerdi.trim(), addScratch.kilde.trim());
                        setAddFelt(null);
                        setAddScratch({ vaerdi: '', kilde: '' });
                      }}
                    >
                      <BtnLabel color="#fff">Opret</BtnLabel>
                    </Pressable>
                    <Pressable style={editorStyles.addAnnuller} onPress={() => setAddFelt(null)}>
                      <BtnLabel color={Colors.textMuted}>Annullér</BtnLabel>
                    </Pressable>
                  </View>
                </View>
              ) : (
                <Pressable
                  onPress={() => { setAddFelt(felt); setAddScratch({ vaerdi: '', kilde: '' }); }}
                  style={{ paddingVertical: 6 }}
                >
                  <Mono size={9} color={Colors.bordeaux}>+ Ny {FELT_LABEL[felt] ?? felt}</Mono>
                </Pressable>
              )}
            </View>
          );
        })}

        {/* Køn (redigerbart — arbejdsværdi, ikke et fact) */}
        <View style={{ marginBottom: 6 }}>
          <Mono size={9} color={Colors.gold} style={{ marginTop: 6, marginBottom: 4 }}>KØN</Mono>
          <View style={{ flexDirection: 'row', gap: 8 }}>
            {(['mand', 'kvinde', 'ukendt'] as const).map((k) => {
              const aktiv = (ev?.koen ?? 'ukendt') === k;
              return (
                <Pressable key={k}
                  style={[editorStyles.koenPille, aktiv && editorStyles.koenPilleAktiv]}
                  onPress={() => setPending({ art: 'fakta', subjektType: 'person', subjektId: id!, felt: 'koen', vaerdi: k })}>
                  <BtnLabel size={12} color={aktiv ? '#fff' : Colors.textSecondary2}>{k}</BtnLabel>
                </Pressable>
              );
            })}
          </View>
        </View>

        {/* Narrativ-sektion */}
        <View style={editorStyles.narrativSektion}>
          <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Narrativ / biografi</Mono>
          {narrativStatus === 'error' ? (
            // Blokér editoren ved fetch-fejl — vis IKKE et tomt felt man kan komme til at gemme
            // (det ville overskrive den eksisterende narrativ destruktivt, cycle 04 NEW1).
            <Mono size={11} color={Colors.liveRoed}>
              Kunne ikke hente narrativ. Gem er deaktiveret (undgår at overskrive eksisterende tekst). Genindlæs.
            </Mono>
          ) : (
            <>
              <TextInput
                multiline
                editable={narrativStatus === 'ready'}
                value={narrativTekst}
                onChangeText={setNarrativTekst}
                style={editorStyles.narrativInput}
                placeholder={narrativStatus === 'loading' ? 'Henter…' : 'Skriv biografi her…'}
                placeholderTextColor={Colors.textMuted2}
                textAlignVertical="top"
              />
              <Pressable
                style={[editorStyles.gemKnap, narrativStatus !== 'ready' && { opacity: 0.5 }]}
                disabled={narrativStatus !== 'ready'}
                onPress={() => setPending({ art: 'narrativ', subjektType: 'person', subjektId: id!,
                  vaerdi: narrativTekst, payload: { privat: narrativPrivat } })}
              >
                <BtnLabel color="#fff">Gem narrativ</BtnLabel>
              </Pressable>
            </>
          )}
        </View>

        {/* Familie & relationer (read-only) */}
        {redaktionModel ? (() => {
          const foraeldre = parentsOf(redaktionModel, id!);
          const aegtefaeller = spousesOf(redaktionModel, id!);
          const aegteskaber = childrenByMarriage(redaktionModel, id!).filter((m) => m.children.length);
          const kld = redaktionAux?.sourcesBy[id!] ?? [];
          const PersonRad = ({ pid, navn }: { pid: string | null; navn: string }) => (
            <Pressable style={editorStyles.relRad} disabled={!pid}
              onPress={() => pid && router.push(`/redaktion/person/${pid}` as never)}>
              <InitialBadge name={navn} size={28} />
              <Body size={14} style={{ marginLeft: 8 }}>{navn}</Body>
            </Pressable>
          );
          return (
            <View style={editorStyles.relSektion}>
              {foraeldre.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>FORÆLDRE</Mono>
                {foraeldre.map((p) => <PersonRad key={p.id} pid={p.id} navn={p.name} />)}</>) : null}
              {aegtefaeller.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>ÆGTEFÆLLER</Mono>
                {aegtefaeller.map((s, i) => <PersonRad key={s.id ?? i} pid={s.id} navn={s.name} />)}</>) : null}
              {aegteskaber.map((m, i) => (
                <View key={m.unionId ?? i}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>BØRN{m.spouseName ? ` · m. ${m.spouseName}` : ''}</Mono>
                  {m.children.map((c) => <PersonRad key={c.id} pid={c.id} navn={c.name} />)}
                </View>
              ))}
              {/* HVERV (redigerbart) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>HVERV</Mono>
              {relationer.filter((r) => r.art === 'hverv' || r.art === 'event').map((r) => (
                <View key={r.relationId} style={editorStyles.relEditRad}>
                  <View style={{ flex: 1 }}>
                    <Body size={13}>{r.navn}{r.rolle ? ` · ${r.rolle}` : ''}</Body>
                    {r.periode ? <Mono size={9} color={Colors.textMuted}>{r.periode}</Mono> : null}
                  </View>
                  {/* Kun hverv (organisation) er redigerbart; historical_event vises read-only
                      (cycle 06 NEW1 — undgå utilsigtet sletning af event-evidens uden for scope). */}
                  {r.art === 'hverv' ? (
                    <Pressable onPress={() => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: String(r.relationId) })}>
                      <Mono size={9} color={Colors.danger}>🗑</Mono>
                    </Pressable>
                  ) : null}
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => { setPickerType('organisation'); setRelScratch(null); }}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj hverv</Mono>
              </Pressable>

              {/* GODSER (redigerbart) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>GODSER</Mono>
              {relationer.filter((r) => r.art === 'gods').map((r) => (
                <View key={r.relationId} style={editorStyles.relEditRad}>
                  <View style={{ flex: 1 }}>
                    <Body size={13}>{r.navn}{r.rolle ? ` · ${r.rolle}` : ''}</Body>
                    {r.periode ? <Mono size={9} color={Colors.textMuted}>{r.periode}</Mono> : null}
                  </View>
                  <Pressable onPress={() => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: String(r.relationId) })}>
                    <Mono size={9} color={Colors.danger}>🗑</Mono>
                  </Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => { setPickerType('estate'); setRelScratch(null); }}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj gods</Mono>
              </Pressable>

              {kld.length ? (<><Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>KILDER</Mono>
                {kld.map((s, i) => <View key={i} style={editorStyles.sekRad}><Body size={13}>{s.work}</Body><Mono size={9} color={Colors.textMuted}>{s.ref}</Mono></View>)}</>) : null}
            </View>
          );
        })() : null}
      </ScrollView>

      {pickerType ? (
        <EntitetPicker type={pickerType}
          onClose={() => setPickerType(null)}
          onValg={(v) => setRelScratch({ ...v, rolle: '', periode: '' })} />
      ) : null}
      {relScratch ? (
        <RelTilfoejSheet scratch={relScratch} onClose={() => setRelScratch(null)}
          onGem={(rolle, periode) => {
            setPending({ art: 'tilfoejRelation', subjektType: 'person', subjektId: id!,
              payload: { objektType: relScratch.objektType, objektId: relScratch.objektId, rolle, periodeRaw: periode || null } });
            setRelScratch(null);
          }} />
      ) : null}
      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={() => {
          setPending(null);
          if (id) fetchPersonEvidence(id).then(setEv).catch(() => {});
          if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
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
  addForm: {
    backgroundColor: Colors.paperCard,
    borderWidth: 1,
    borderColor: Border.light,
    borderRadius: Radius.field,
    padding: 10,
    marginBottom: 8,
    gap: 8,
  },
  addInput: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontFamily: 'HankenGrotesk_400Regular',
    fontSize: 13,
    color: Colors.ink,
  },
  addOpret: {
    backgroundColor: Colors.konklusionGroen,
    borderRadius: Radius.field,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  addAnnuller: {
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  skrivemode: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: Radius.field,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 10,
    marginBottom: 14,
  },
  skrivemodeDry: {
    backgroundColor: Colors.paperCard,
    borderColor: Border.light,
  },
  skrivemodeLive: {
    backgroundColor: Colors.konfliktFlade,
    borderColor: Colors.liveRoed,
  },
  koenPille: {
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.chip,
    paddingHorizontal: 16,
    paddingVertical: 6,
  },
  koenPilleAktiv: {
    backgroundColor: Colors.bordeaux,
    borderColor: Colors.bordeaux,
  },
  relSektion: {
    marginTop: 16,
    paddingTop: 14,
    borderTopWidth: 1,
    borderTopColor: Border.light,
  },
  relLabel: {
    marginTop: 10,
    marginBottom: 4,
  },
  relEditRad: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 5,
  },
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(34,31,26,0.4)',
  },
  modalSheet: {
    backgroundColor: Colors.paperBg,
    borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet,
    padding: 20,
    paddingBottom: 36,
    borderTopWidth: 1,
    borderColor: Border.light,
  },
  relRad: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 5,
  },
  sekRad: {
    paddingVertical: 4,
  },
});
