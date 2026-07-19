import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { HaendelseTidslinje } from '../../../components/redaktion/HaendelseTidslinje';
import { SletBekraeftSheet } from '../../../components/redaktion/SletBekraeftSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { EntitetPicker } from '../../../components/redaktion/EntitetPicker';
import { PersonPicker } from '../../../components/redaktion/PersonPicker';
import { NarrativEditor } from '../../../components/redaktion/NarrativEditor';
import { MediaUploadSheet } from '../../../components/redaktion/MediaUploadSheet';
import { MediaGallery } from '../../../components/redaktion/MediaGallery';
import { MediaDetaljeSheet } from '../../../components/redaktion/MediaDetaljeSheet';
import { KonfidensVaelger } from '../../../components/redaktion/KonfidensVaelger';
import { FamilieEditRad } from '../../../components/redaktion/FamilieEditRad';
import { ForaeldrePaastandePanel } from '../../../components/redaktion/ForaeldrePaastandePanel';
import { FlytBarnSheet } from '../../../components/redaktion/FlytBarnSheet';
import { UnionTypeSheet } from '../../../components/redaktion/UnionTypeSheet';
import { BarnSheet } from '../../../components/redaktion/BarnSheet';
import { SammeSomSheet } from '../../../components/redaktion/SammeSomSheet';
import { RelTilfoejSheet } from '../../../components/redaktion/RelTilfoejSheet';
import { personEditorSheetStyles } from '../../../components/redaktion/personEditorSheetStyles';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { useMediaAndThumbUris } from '../../../lib/media';
import {
  buildTidslinje,
  fetchHaendelserForPerson,
  fetchStoriesForPerson,
  storyPrefillFraPost,
  fetchPersonEvidence,
  fetchPersonRelationer,
  fetchPersonFamilie,
  fetchPersonMedia,
  fetchSammeSomLinks,
  fetchForaeldreUkendtMarkering,
  fetchMediaAnvendelse,
  nudgeOrdinal,
  type HaendelsePost,
  type StoryPost,
  type TidslinjePost,
  type PersonEvidence,
  type PersonRelation,
  type PersonFamilie,
  type PersonMedia,
  type MediaAnvendelse,
  type SammeSomLink,
  type ForaeldreUkendtMarkering,
} from '../../../data/redaktionRead';
import { GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE, previewSammeSom } from '@daa/core';
import { eraAdvarsel } from '../../../data/eraAdvarsel';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel', 'daab', 'begravelse', 'floruit', 'naturalisering']; // koen håndteres separat (ikke et fact)
const FELT_LABEL: Record<string, string> = {
  navn: 'navn', foedt: 'født', doed: 'død', titel: 'titel',
  daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisation',
};

type StoryDraft = {
  storyId: number | null; titel: string; tekst: string; privat: boolean;
  haendelseId: number | null; dateMin: string; dateMax: string;
  dateQualifier: string; dateRaw: string;
  kilder: { sourceId: number; side: string }[];
};

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
  const [haendelser, setHaendelser] = useState<HaendelsePost[]>([]);
  const [stories, setStories] = useState<StoryPost[]>([]);
  const [storyEditor, setStoryEditor] = useState<StoryDraft | null>(null);
  const [storyKilderEfterGem, setStoryKilderEfterGem] = useState<StoryDraft['kilder'] | null>(null);
  const [pending, setPending] = useState<Change | null>(null);
  const [markering, setMarkering] = useState<ForaeldreUkendtMarkering | null>(null);
  const [foraeldreReload, setForaeldreReload] = useState(0); // refetch forældre-slot efter vaelgForaeldre
  const [markGrade, setMarkGrade] = useState<string>(GRADE_FORAELDER_UKENDT);
  const [markKilde, setMarkKilde] = useState('');
  const [confirmDeleteOpen, setConfirmDeleteOpen] = useState(false);
  const person = id && redaktionModel ? redaktionModel.byId[id] : null;

  // privat: initialiseres fra redaktionModel.byId[id].privat
  const [privat, setPrivat] = useState(false);
  useEffect(() => { if (person) setPrivat(Boolean(person.privat)); }, [person?.privat]);

  // Sektion-niveau "opret nyt fact"-form (operation B): hvilket felt + scratch-værdier.
  const [addFelt, setAddFelt] = useState<string | null>(null);
  const [addScratch, setAddScratch] = useState({ vaerdi: '', kilde: '' });

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch((e) => console.warn('[redaktion/person] evidens fejlede:', e)); }, [id]);
  const refreshHaendelser = () => { if (id) fetchHaendelserForPerson(id).then(setHaendelser).catch((e) => console.warn('[redaktion/person] hændelser fejlede:', e)); };
  useEffect(refreshHaendelser, [id]);
  const refreshStories = () => { if (id) fetchStoriesForPerson(id).then(setStories).catch((e) => console.warn('[redaktion/person] stories fejlede:', e)); };
  useEffect(refreshStories, [id]);
  const tidslinje = useMemo(() => buildTidslinje(haendelser, ev ?? { felter: {}, koen: null }), [haendelser, ev]);
  useEffect(() => {
    if (!id) return;
    fetchForaeldreUkendtMarkering(id)
      .then((m) => { setMarkering(m); if (m) { setMarkGrade(m.grade || GRADE_FORAELDER_UKENDT); setMarkKilde(m.kilde ?? ''); } })
      .catch((e) => console.warn('[redaktion/person] forældre-ukendt-markering fejlede:', e));
  }, [id]);

  const [relationer, setRelationer] = useState<PersonRelation[]>([]);
  const [pickerType, setPickerType] = useState<'organisation' | 'estate' | null>(null);
  const [relScratch, setRelScratch] = useState<{ objektType: string; objektId: string; navn: string; rolle: string; periode: string } | null>(null);
  useEffect(() => {
    if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch((e) => console.warn('[redaktion/person] relationer fejlede:', e));
  }, [id, redaktionAux]);

  // Samme person (identitets-links, samme_som).
  const [sammeSom, setSammeSom] = useState<SammeSomLink[]>([]);
  const [ssPicker, setSsPicker] = useState(false);
  // scratch: den valgte person + retning (kanoniskId = den der beholdes/foldes ind i).
  const [ssScratch, setSsScratch] = useState<{ personId: string; navn: string; kanoniskId: string } | null>(null);
  const refreshSammeSom = () => { if (id) fetchSammeSomLinks(id).then(setSammeSom).catch((e) => console.warn('[redaktion/person] samme-som fejlede:', e)); };
  useEffect(refreshSammeSom, [id]);
  // Rå-db til rådgivende pre-flight (rekonstrueret fra redaktionsmodellen; unions ej nødvendig for
  // karantæne-tjekket — kun personer + forældre-kanter bruges).
  const ssRawDb = useMemo(() => ({
    persons: redaktionModel?.persons ?? [],
    unions: [],
    parentChild: Object.entries(redaktionModel?.indexes.parentsByChild ?? {}).flatMap(
      ([child, parents]) => parents.map((parent) => ({ child, parent, union: '' })),
    ),
  }), [redaktionModel]);

  // Familie (2C-2b): redigerbar partner+barn-sektion.
  const [familie, setFamilie] = useState<PersonFamilie>({ somPartner: [], somBarn: [] });
  useEffect(() => { if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch((e) => console.warn('[redaktion/person] familie fejlede:', e)); }, [id, redaktionModel]);

  // Add-flow state for familie:
  const [partnerPicker, setPartnerPicker] = useState(false);
  const [barnPickerFam, setBarnPickerFam] = useState<string | null>(null);
  const [unionScratch, setUnionScratch] = useState<{ personId: string; navn: string } | null>(null);
  const [barnScratch, setBarnScratch] = useState<{ familyId: string; personId: string; navn: string } | null>(null);
  const [flytBarnScratch, setFlytBarnScratch] = useState<{ fraFamilyId: string; personId: string; rolle: string; navn: string } | null>(null);

  // Materiale (mediehåndtering Slice 0g).
  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [mediaDetalje, setMediaDetalje] = useState<PersonMedia | null>(null);
  const [mediaAnvendelse, setMediaAnvendelse] = useState<MediaAnvendelse | undefined>();
  const [mediaAnvendelseFejl, setMediaAnvendelseFejl] = useState('');
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const refreshMedia = () => { if (id) fetchPersonMedia(id).then(setMedia).catch(() => {}); };
  useEffect(refreshMedia, [id]);
  const { uris: mediaUris, thumbUris: mediaThumbUris } = useMediaAndThumbUris(
    media.map((m) => ({ id: m.id, storage_path: m.storagePath, thumb_storage_path: m.thumbStoragePath })),
    (m) => m.thumb_storage_path,
  );
  useEffect(() => {
    if (!mediaDetalje) { setMediaAnvendelse(undefined); setMediaAnvendelseFejl(''); return; }
    let aktiv = true; setMediaAnvendelse(undefined); setMediaAnvendelseFejl('');
    fetchMediaAnvendelse(mediaDetalje.id).then((a) => { if (aktiv) setMediaAnvendelse(a); })
      .catch(() => { if (aktiv) setMediaAnvendelseFejl('Kunne ikke kontrollere anvendelser. Sletning er blokeret.'); });
    return () => { aktiv = false; };
  }, [mediaDetalje?.id]);

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

  const datoeFor = (pid: string) => ({ foedsel: redaktionModel?.byId?.[pid]?.born ?? null, doed: redaktionModel?.byId?.[pid]?.died ?? null });

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={person.name} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <View style={{ alignItems: 'center', marginBottom: 16 }}>
          <InitialBadge name={person.name} size={56} bg="#f8ecef" />
          <Serif size={25} style={{ marginTop: 8 }}>{person.name}</Serif>
          <Mono size={9} color={Colors.textMuted}>id {String(person.id)} · {ev?.koen ?? '—'}</Mono>
          <Pressable onPress={() => router.push(`/redaktion/historik/${id}` as never)} style={{ marginTop: 6 }}>
            <BtnLabel size={12.5} color={Colors.bordeaux}>📜 Historik</BtnLabel>
          </Pressable>
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
            value={dryRun}
            onValueChange={setDryRun}
            thumbColor={dryRun ? Colors.textMuted2 : Colors.liveRoed}
            trackColor={{ false: Colors.konfliktFlade, true: Colors.beige3 }}
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

        {/* "Forældre ukendt"-markering (docs/reviews/25): kilden forbinder ikke opad → kandidat-kolonne. */}
        <View style={{ marginBottom: 12, borderWidth: 1, borderColor: markering ? Colors.bordeauxFillLight2 : Border.light, borderRadius: Radius.card, padding: 12, backgroundColor: markering ? '#faf1dc' : Colors.paperCard }}>
          <Mono size={9} color={Colors.gold} style={{ marginBottom: 8, letterSpacing: 9 * 0.12, textTransform: 'uppercase' }}>Forældre ukendt — kilden forbinder ikke opad</Mono>
          {markering ? (
            <Body size={12.5} style={{ marginBottom: 8, lineHeight: 17 }}>
              Markeret: {markering.grade === GRADE_FORAELDER_UKENDT ? 'forælder findes, men ukendt' : 'ingen forbindelse angivet'}{markering.kilde ? ` · kilde: ${markering.kilde}` : ''}.
            </Body>
          ) : null}
          <View style={{ flexDirection: 'row', gap: 6, marginBottom: 8 }}>
            {[GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE].map((g) => (
              <Pressable key={g} onPress={() => setMarkGrade(g)} style={{ flex: 1, paddingVertical: 7, borderRadius: Radius.field, borderWidth: 1.5, borderColor: markGrade === g ? Colors.bordeaux : Border.light, backgroundColor: markGrade === g ? Colors.bordeauxFillLight2 : Colors.paperCard, alignItems: 'center' }}>
                <Mono size={9} color={markGrade === g ? Colors.bordeaux : Colors.textMuted}>{g === GRADE_FORAELDER_UKENDT ? 'FORÆLDER UKENDT' : 'INGEN FORBINDELSE'}</Mono>
              </Pressable>
            ))}
          </View>
          <TextInput value={markKilde} onChangeText={setMarkKilde} placeholder="Kilde (fx DAA 1939 s.97)" placeholderTextColor={Colors.textMuted2}
            style={{ fontSize: 13, paddingHorizontal: 10, paddingVertical: 8, borderRadius: Radius.field, borderWidth: 1, borderColor: Border.light, backgroundColor: Colors.paperCard, color: Colors.ink, marginBottom: 8 }} />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <Pressable onPress={() => setPending({ art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: id!, vaerdi: markGrade, kildeFritekst: markKilde.trim() || undefined })}
              style={{ flex: 1, paddingVertical: 9, borderRadius: Radius.field, backgroundColor: Colors.bordeaux, alignItems: 'center' }}>
              <BtnLabel color={Colors.paperCard}>{markering ? 'Opdatér markering' : 'Markér'}</BtnLabel>
            </Pressable>
            {markering ? (
              <Pressable onPress={() => setPending({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: id!, factId: String(markering.factId) })}
                style={{ paddingVertical: 9, paddingHorizontal: 14, borderRadius: Radius.field, borderWidth: 1, borderColor: Colors.danger, alignItems: 'center' }}>
                <BtnLabel color={Colors.danger}>Fjern</BtnLabel>
              </Pressable>
            ) : null}
          </View>
        </View>

        {id ? <ForaeldrePaastandePanel personId={id} onChange={setPending} sammeSom={sammeSom} reloadKey={foraeldreReload} /> : null}

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
                    style={personEditorSheetStyles.addInput}
                    placeholder={`Ny ${FELT_LABEL[felt] ?? felt}…`}
                    placeholderTextColor={Colors.textMuted2}
                    value={addScratch.vaerdi}
                    onChangeText={(v) => setAddScratch((s) => ({ ...s, vaerdi: v }))}
                    autoFocus
                  />
                  <TextInput
                    style={personEditorSheetStyles.addInput}
                    placeholder="Kilde (valgfri)"
                    placeholderTextColor={Colors.textMuted2}
                    value={addScratch.kilde}
                    onChangeText={(v) => setAddScratch((s) => ({ ...s, kilde: v }))}
                  />
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <Pressable
                      style={personEditorSheetStyles.addOpret}
                      onPress={() => {
                        if (!addScratch.vaerdi.trim()) return;
                        opretFakta(felt, addScratch.vaerdi.trim(), addScratch.kilde.trim());
                        setAddFelt(null);
                        setAddScratch({ vaerdi: '', kilde: '' });
                      }}
                    >
                      <BtnLabel color="#fff">Opret</BtnLabel>
                    </Pressable>
                    <Pressable style={personEditorSheetStyles.addAnnuller} onPress={() => setAddFelt(null)}>
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
                  style={[personEditorSheetStyles.koenPille, aktiv && personEditorSheetStyles.koenPilleAktiv]}
                  onPress={() => setPending({ art: 'fakta', subjektType: 'person', subjektId: id!, felt: 'koen', vaerdi: k })}>
                  <BtnLabel size={12} color={aktiv ? '#fff' : Colors.textSecondary2}>{k}</BtnLabel>
                </Pressable>
              );
            })}
          </View>
        </View>

        <HaendelseTidslinje poster={tidslinje}
          onSetStatus={(haendelseId, status) => setPending({
            art: 'haendelseStatus', subjektType: 'person', subjektId: id!, haendelseId, status,
          })}
          onNyHistorie={(post) => {
            const prefill = storyPrefillFraPost(post);
            setStoryEditor({ storyId: null, titel: '', tekst: prefill.tekst, privat: false,
              haendelseId: prefill.haendelseId, dateMin: prefill.dateMin ?? '',
              dateMax: prefill.dateMax ?? '', dateQualifier: prefill.dateQualifier ?? '',
              dateRaw: prefill.dateRaw ?? '',
              kilder: prefill.kilder.map((k) => ({ sourceId: k.sourceId, side: k.side ?? '' })) });
          }} />

        <View style={editorStyles.narrativSektion}>
          <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 7 }}>MINIHISTORIER · ALLE STATUSSER</Mono>
          {stories.map((story) => (
            <View key={story.id} style={editorStyles.storyCard}>
              <Serif size={17}>{story.titel || 'Historie uden titel'}</Serif>
              <Body size={13} color={Colors.textSecondary} style={{ marginTop: 3 }}>{story.tekst}</Body>
              <View style={editorStyles.storyStatusRow}>
                {(['kladde', 'klar', 'publiceret', 'arkiveret'] as const).map((status) => {
                  const aktiv = story.status === status;
                  return <Pressable key={status}
                    style={[personEditorSheetStyles.koenPille, aktiv && personEditorSheetStyles.koenPilleAktiv]}
                    onPress={() => setPending({ art: 'setStoryStatus', subjektType: 'person', subjektId: id!,
                      storyId: story.id, storyStatus: status })}>
                    <BtnLabel size={9} color={aktiv ? '#fff' : Colors.textSecondary2}>{status}</BtnLabel>
                  </Pressable>;
                })}
                <Pressable style={editorStyles.storyEditButton} onPress={() => setStoryEditor({
                  storyId: story.id, titel: story.titel ?? '', tekst: story.tekst, privat: story.privat,
                  haendelseId: story.haendelseId, dateMin: story.dato.min ?? '', dateMax: story.dato.max ?? '',
                  dateQualifier: story.dato.qualifier ?? '', dateRaw: story.dato.raw ?? '',
                  kilder: story.kilder.map((k) => ({ sourceId: k.sourceId, side: k.side ?? '' })),
                })}>
                  <BtnLabel size={10} color={Colors.bordeaux}>Redigér</BtnLabel>
                </Pressable>
              </View>
            </View>
          ))}
          {!stories.length ? <Mono size={9} color={Colors.textMuted}>Ingen historier endnu.</Mono> : null}
        </View>

        <NarrativEditor subjektType="person" subjektId={id!} media={media} mediaThumbUris={mediaThumbUris} />

        {/* Materiale (mediehåndtering Slice 0g+0h) */}
        <View style={editorStyles.narrativSektion}>
          <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Materiale</Mono>
          <MediaGallery
            media={media}
            mediaUris={mediaUris}
            mediaThumbUris={mediaThumbUris}
            onVaelg={setMediaDetalje}
            onFjern={(m) => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: m.relationId })}
            onGenopret={(m) => setPending({ art: 'genopretMedia', subjektType: 'person', subjektId: id!, mediaId: m.id })}
          />
          <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
            <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
          </Pressable>
        </View>

        {/* Familie & relationer */}
        {redaktionModel ? (() => {
          const kld = redaktionAux?.sourcesBy[id!] ?? [];
          const PersonRad = ({ pid, navn }: { pid: string | null; navn: string }) => (
            <Pressable style={personEditorSheetStyles.relRad} disabled={!pid}
              onPress={() => pid && router.push(`/redaktion/person/${pid}` as never)}>
              <InitialBadge name={navn} size={28} />
              <Body size={14} style={{ marginLeft: 8 }}>{navn}</Body>
            </Pressable>
          );
          return (
            <View style={editorStyles.relSektion}>
              {/* ÆGTEFÆLLER + BØRN (redigerbart, pr. union) */}
              {familie.somPartner.map((u) => (
                <View key={u.familyId}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>ÆGTEFÆLLE ({u.type})</Mono>
                  {u.partnere.map((pt) => (
                    <FamilieEditRad key={pt.personId} label={pt.navn} aar={pt.aar} konfidens={pt.konfidens}
                      onOpen={() => router.push(`/redaktion/person/${pt.personId}` as never)}
                      onKonfidens={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: pt.personId, rolle: 'partner', konfidens: k })}
                      onSlet={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: pt.personId, rolle: 'partner' })} />
                  ))}
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>BØRN</Mono>
                  {u.boern.map((b, i) => {
                    const opOrdinal = nudgeOrdinal(u.boern, i, 'op');
                    const nedOrdinal = nudgeOrdinal(u.boern, i, 'ned');
                    return (
                      <FamilieEditRad key={`${b.personId}-${b.rolle}`} label={b.navn + (b.rolle !== 'barn' ? ' · ' + b.rolle : '')} aar={b.aar} konfidens={b.konfidens}
                        onOpen={() => router.push(`/redaktion/person/${b.personId}` as never)}
                        onKonfidens={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle, konfidens: k })}
                        onSlet={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle })}
                        onOp={opOrdinal == null ? undefined : () => setPending({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle, ordinal: opOrdinal })}
                        onNed={nedOrdinal == null ? undefined : () => setPending({ art: 'setFamilieOrdinal', subjektType: 'person', subjektId: id!, familyId: u.familyId, personId: b.personId, rolle: b.rolle, ordinal: nedOrdinal })}
                        onFlyt={() => setFlytBarnScratch({ fraFamilyId: u.familyId, personId: b.personId, rolle: b.rolle, navn: b.navn })} />
                    );
                  })}
                  <Pressable style={{ paddingVertical: 6 }} onPress={() => setBarnPickerFam(u.familyId)}>
                    <Mono size={9} color={Colors.bordeaux}>+ Tilføj barn</Mono>
                  </Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => setPartnerPicker(true)}>
                <Mono size={9} color={Colors.bordeaux}>+ Tilføj partner (ny union)</Mono>
              </Pressable>

              {/* FORÆLDRE (somBarn) — forældre read-only; konfidens+slet redigerbart */}
              {familie.somBarn.map((sb) => (
                <View key={sb.familyId}>
                  <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>FORÆLDRE{sb.rolle !== 'barn' ? ` · ${sb.rolle}` : ''}</Mono>
                  {sb.foraeldre.map((f) => <PersonRad key={f.personId} pid={f.personId} navn={f.navn} />)}
                  <View style={personEditorSheetStyles.relEditRad}>
                    <KonfidensVaelger vaerdi={sb.konfidens}
                      onVael={(k) => setPending({ art: 'setFamilieKonfidens', subjektType: 'person', subjektId: id!, familyId: sb.familyId, personId: id!, rolle: sb.rolle, konfidens: k })} />
                    {/* Fjerner barnets membership i HELE forældre-familien (begge forældre afkobles —
                        modellen kan ikke afkoble én forælder uden at flytte barnet). Dry-run-preview =
                        bekræftelses-gate (cycle 07 Codex H3: tidligere label "afkobl forælder" var misvisende). */}
                    <Pressable onPress={() => setPending({ art: 'sletFamilieLink', subjektType: 'person', subjektId: id!, familyId: sb.familyId, personId: id!, rolle: sb.rolle })}>
                      <Mono size={9} color={Colors.danger}>🗑 fjern fra denne forældre-familie</Mono>
                    </Pressable>
                  </View>
                </View>
              ))}

              {/* HVERV (redigerbart) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>HVERV</Mono>
              {relationer.filter((r) => r.art === 'hverv' || r.art === 'event').map((r) => (
                <View key={r.relationId} style={personEditorSheetStyles.relEditRad}>
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
                <View key={r.relationId} style={personEditorSheetStyles.relEditRad}>
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

              {/* SAMME PERSON (identitets-links) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>SAMME PERSON</Mono>
              {sammeSom.map((l) => (
                <View key={l.relationId} style={personEditorSheetStyles.relEditRad}>
                  <View style={{ flex: 1 }}>
                    <Body size={13}>{redaktionModel?.byId?.[l.modpartId]?.name ?? `#${l.modpartId}`}</Body>
                    <Mono size={9} color={Colors.textMuted}>{l.retning === 'alias' ? 'denne foldes ind i' : 'foldes ind i denne'}</Mono>
                  </View>
                  <Pressable onPress={() => setPending({ art: 'fjernSammeSom', subjektType: 'person', subjektId: id!, relationId: l.relationId })}>
                    <Mono size={9} color={Colors.danger}>🗑</Mono>
                  </Pressable>
                </View>
              ))}
              <Pressable style={{ paddingVertical: 6 }} onPress={() => setSsPicker(true)}>
                <Mono size={9} color={Colors.bordeaux}>+ Marker som samme person</Mono>
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
      {partnerPicker ? (
        <PersonPicker excludeId={id} onClose={() => setPartnerPicker(false)}
          onValg={(v) => setUnionScratch(v)} />
      ) : null}
      {unionScratch ? (
        <UnionTypeSheet partner={unionScratch} onClose={() => setUnionScratch(null)}
          onGem={(type, ordinal) => {
            setPending({ art: 'opretUnion', subjektType: 'person', subjektId: id!,
              payload: { partnerA: id, partnerB: unionScratch.personId, type, ordinal } });
            setUnionScratch(null);
          }} />
      ) : null}
      {barnPickerFam ? (
        <PersonPicker excludeId={id} onClose={() => setBarnPickerFam(null)}
          onValg={(v) => { setBarnScratch({ familyId: barnPickerFam, personId: v.personId, navn: v.navn }); setBarnPickerFam(null); }} />
      ) : null}
      {barnScratch ? (
        <BarnSheet scratch={barnScratch}
          advarsel={eraAdvarsel(
            redaktionModel?.byId?.[barnScratch.personId]?.born ?? null,
            // Fokus-personen er selv en forælder i denne union, men mapFamilieRows filtrerer
            // den ud af `partnere` — medtag dens datoer eksplicit, ellers er era-tjekket dødt
            // for unioner med kun én registreret forælder (almindeligt i DAA).
            [datoeFor(id!), ...(familie.somPartner.find((u) => u.familyId === barnScratch.familyId)?.partnere ?? []).map((pt) => datoeFor(pt.personId))]
          )}
          onClose={() => setBarnScratch(null)}
          onGem={(rolle, konfidens) => {
            setPending({ art: 'tilfoejBarn', subjektType: 'person', subjektId: id!,
              payload: { familyId: barnScratch.familyId, barnId: barnScratch.personId, rolle, konfidens } });
            setBarnScratch(null);
          }} />
      ) : null}
      {flytBarnScratch ? (
        <FlytBarnSheet barnNavn={flytBarnScratch.navn}
          andreUnioner={familie.somPartner.filter((u) => u.familyId !== flytBarnScratch.fraFamilyId)}
          onClose={() => setFlytBarnScratch(null)}
          onVael={(tilFamilyId) => {
            setPending({ art: 'flytBarn', subjektType: 'person', subjektId: id!,
              familyId: flytBarnScratch.fraFamilyId, tilFamilyId, personId: flytBarnScratch.personId, rolle: flytBarnScratch.rolle });
            setFlytBarnScratch(null);
          }} />
      ) : null}
      {ssPicker ? (
        <PersonPicker excludeId={id} onClose={() => setSsPicker(false)}
          onValg={(v) => { setSsScratch({ personId: v.personId, navn: v.navn, kanoniskId: id! }); setSsPicker(false); }} />
      ) : null}
      {mediaDetalje ? (
        <MediaDetaljeSheet
          media={mediaDetalje}
          uri={mediaUris[mediaDetalje.id]}
          thumbUri={mediaThumbUris[mediaDetalje.id]}
          anvendelse={mediaAnvendelse}
          anvendelseFejl={mediaAnvendelseFejl}
          onClose={() => setMediaDetalje(null)}
          onGemMetadata={(payload) => { setPending({ art: 'opdaterMedia', subjektType: 'person', subjektId: id!, mediaId: mediaDetalje.id, payload }); setMediaDetalje(null); }}
          onGemRettigheder={(payload) => { setPending({ art: 'mediaRettigheder', subjektType: 'person', subjektId: id!, mediaId: mediaDetalje.id, payload }); setMediaDetalje(null); }}
          onFjern={() => { setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: mediaDetalje.relationId }); setMediaDetalje(null); }}
          onFjernTilknytning={(relationId) => { setPending({ art: 'sletRelation', subjektType: 'media', subjektId: mediaDetalje.id, relationId }); setMediaDetalje(null); }}
          onTilknyt={() => { const mediaId = mediaDetalje.id; setMediaDetalje(null); router.push({ pathname: '/redaktion/entitet/medie/[id]', params: { id: mediaId } }); }}
          onSlet={() => { setPending({ art: 'fjernMedia', subjektType: 'person', subjektId: id!, mediaId: mediaDetalje.id }); setMediaDetalje(null); }}
          onGenopret={() => { setPending({ art: 'genopretMedia', subjektType: 'person', subjektId: id!, mediaId: mediaDetalje.id }); setMediaDetalje(null); }}
        />
      ) : null}
      {uploadSheetOpen ? (
        <MediaUploadSheet
          target={{ afbildetPersonId: id! }}
          onClose={() => setUploadSheetOpen(false)}
          onGem={(payload) => {
            setPending({ art: 'uploadMedia', subjektType: 'person', subjektId: id!, payload });
            setUploadSheetOpen(false);
          }}
        />
      ) : null}
      {storyEditor ? (
        <StoryEditorSheet
          draft={storyEditor}
          sources={redaktionAux?.kildeListe ?? []}
          onChange={setStoryEditor}
          onClose={() => setStoryEditor(null)}
          onGem={() => {
            const payload = {
              titel: storyEditor.titel.trim() || null, tekst: storyEditor.tekst.trim(),
              haendelseId: storyEditor.haendelseId, dateMin: storyEditor.dateMin || null,
              dateMax: storyEditor.dateMax || null, dateQualifier: storyEditor.dateQualifier || null,
              dateRaw: storyEditor.dateRaw || null, privat: storyEditor.privat,
            };
            setStoryKilderEfterGem(storyEditor.kilder);
            setPending(storyEditor.storyId == null
              ? { art: 'opretStory', subjektType: 'person', subjektId: id!, payload }
              : { art: 'redigerStory', subjektType: 'person', subjektId: id!, storyId: storyEditor.storyId, payload });
            setStoryEditor(null);
          }}
        />
      ) : null}
      {ssScratch ? (
        <SammeSomSheet
          redigeret={{ id: id!, navn: redaktionModel?.byId?.[id!]?.name ?? id! }}
          valgt={{ id: ssScratch.personId, navn: ssScratch.navn }}
          kanoniskId={ssScratch.kanoniskId}
          onByt={() => setSsScratch({ ...ssScratch, kanoniskId: ssScratch.kanoniskId === id! ? ssScratch.personId : id! })}
          preview={previewSammeSom(
            ssRawDb,
            [],
            { alias: ssScratch.kanoniskId === id! ? ssScratch.personId : id!, canonical: ssScratch.kanoniskId },
          )}
          onClose={() => setSsScratch(null)}
          onGem={() => {
            const aliasId = ssScratch.kanoniskId === id! ? ssScratch.personId : id!;
            setPending({ art: 'sammeSom', subjektType: 'person', subjektId: id!,
              payload: { aliasId, objektId: ssScratch.kanoniskId } });
            setSsScratch(null);
          }} />
      ) : null}
      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={(result) => {
          const applied = pending;
          if (id) fetchPersonEvidence(id).then(setEv).catch(() => {});
          refreshHaendelser();
          refreshStories();
          if (id) fetchForaeldreUkendtMarkering(id).then(setMarkering).catch(() => {});
          setForaeldreReload((k) => k + 1);
          if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
          if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch(() => {});
          refreshSammeSom();
          if (['uploadMedia','opdaterMedia','genopretMedia','mediaRettigheder','fjernMedia','sletRelation','tilknytMedia'].includes(applied?.art ?? '')) refreshMedia();
          if ((applied?.art === 'opretStory' || applied?.art === 'redigerStory') && storyKilderEfterGem) {
            const storyId = applied.storyId ?? Number(result);
            setStoryKilderEfterGem(null);
            if (Number.isFinite(storyId)) {
              setPending({ art: 'setStoryKilder', subjektType: 'person', subjektId: id!, storyId,
                kilder: storyKilderEfterGem.map((k) => ({ sourceId: k.sourceId,
                  ...(k.side.trim() ? { side: k.side.trim() } : {}) })) });
              return;
            }
          }
          setPending(null);
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

function StoryEditorSheet({ draft, sources, onChange, onClose, onGem }: {
  draft: StoryDraft;
  sources: { id: string; titel: string; slags: string; udgave: string }[];
  onChange: (draft: StoryDraft) => void;
  onClose: () => void;
  onGem: () => void;
}) {
  const ord = draft.tekst.trim() ? draft.tekst.trim().split(/\s+/).length : 0;
  const setKilde = (index: number, value: Partial<StoryDraft['kilder'][number]>) =>
    onChange({ ...draft, kilder: draft.kilder.map((k, i) => i === index ? { ...k, ...value } : k) });
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <View style={storySheetStyles.backdrop}>
        <View style={storySheetStyles.sheet}>
          <View style={storySheetStyles.header}>
            <Serif size={21}>{draft.storyId == null ? 'Ny minihistorie' : `Redigér historie #${draft.storyId}`}</Serif>
            <Pressable onPress={onClose}><BtnLabel color={Colors.textMuted}>Luk</BtnLabel></Pressable>
          </View>
          <ScrollView keyboardShouldPersistTaps="handled">
            <TextInput style={storySheetStyles.input} value={draft.titel} placeholder="Titel (valgfri)"
              placeholderTextColor={Colors.textMuted2} onChangeText={(titel) => onChange({ ...draft, titel })} />
            <TextInput style={[storySheetStyles.input, storySheetStyles.textarea]} value={draft.tekst}
              placeholder="Omskriv til cirka 40–90 ord" placeholderTextColor={Colors.textMuted2}
              multiline textAlignVertical="top" onChangeText={(tekst) => onChange({ ...draft, tekst })} />
            <Mono size={8.5} color={Colors.textMuted}>{ord} ord · vejledende norm 40–90</Mono>
            <View style={storySheetStyles.datoGrid}>
              {([['dateMin', 'Dato min'], ['dateMax', 'Dato max'], ['dateQualifier', 'Kvalifikator'], ['dateRaw', 'Dato som skrevet']] as const).map(([key, label]) => (
                <TextInput key={key} style={[storySheetStyles.input, storySheetStyles.datoInput]}
                  value={draft[key]} placeholder={label} placeholderTextColor={Colors.textMuted2}
                  onChangeText={(value) => onChange({ ...draft, [key]: value })} />
              ))}
            </View>
            <View style={storySheetStyles.privatRow}>
              <Body size={12}>Privat</Body>
              <Switch value={draft.privat} onValueChange={(privat) => onChange({ ...draft, privat })}
                trackColor={{ false: Border.light, true: Colors.bordeaux }} />
            </View>
            <Mono size={9} color={Colors.gold} style={{ marginTop: 10 }}>KILDER</Mono>
            {draft.kilder.map((k, index) => (
              <View key={`${k.sourceId}-${index}`} style={storySheetStyles.kildeCard}>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 5 }}>
                  {sources.map((source) => {
                    const aktiv = Number(source.id) === k.sourceId;
                    return <Pressable key={source.id} onPress={() => setKilde(index, { sourceId: Number(source.id) })}
                      style={[storySheetStyles.sourcePill, aktiv && storySheetStyles.sourcePillActive]}>
                      <BtnLabel size={9} color={aktiv ? '#fff' : Colors.textSecondary2}>{source.titel || source.udgave || `#${source.id}`}</BtnLabel>
                    </Pressable>;
                  })}
                </ScrollView>
                <TextInput style={storySheetStyles.input} value={k.side} placeholder="Side"
                  placeholderTextColor={Colors.textMuted2} onChangeText={(side) => setKilde(index, { side })} />
                <Pressable onPress={() => onChange({ ...draft, kilder: draft.kilder.filter((_, i) => i !== index) })}>
                  <BtnLabel size={10} color={Colors.bordeaux}>Fjern kilde</BtnLabel>
                </Pressable>
              </View>
            ))}
            <Pressable disabled={!sources.length} style={storySheetStyles.secondaryButton}
              onPress={() => onChange({ ...draft, kilder: [...draft.kilder, { sourceId: Number(sources[0].id), side: '' }] })}>
              <BtnLabel color={Colors.bordeaux}>+ Kilde</BtnLabel>
            </Pressable>
            <Pressable disabled={!draft.tekst.trim()} style={[storySheetStyles.saveButton, !draft.tekst.trim() && { opacity: 0.45 }]} onPress={onGem}>
              <BtnLabel color="#fff">Gem historie</BtnLabel>
            </Pressable>
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const storySheetStyles = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(34,31,26,0.4)' },
  sheet: { maxHeight: '88%', backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet,
    borderTopRightRadius: Radius.sheet, borderWidth: 1, borderColor: Border.light, padding: 18, paddingBottom: 34 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  input: { borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field,
    backgroundColor: Colors.paperCard, color: Colors.ink, paddingHorizontal: 10, paddingVertical: 9, marginBottom: 7 },
  textarea: { minHeight: 116 },
  datoGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 9 },
  datoInput: { width: '48%', marginBottom: 0 },
  privatRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 8 },
  kildeCard: { borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field, padding: 8, marginTop: 7 },
  sourcePill: { borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field,
    paddingHorizontal: 8, paddingVertical: 5, marginBottom: 7 },
  sourcePillActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  secondaryButton: { borderWidth: 1, borderColor: Colors.bordeaux, borderRadius: Radius.field,
    padding: 10, alignItems: 'center', marginTop: 8 },
  saveButton: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field,
    padding: 13, alignItems: 'center', marginTop: 10 },
});

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
  storyStatusRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 8, alignItems: 'center' },
  storyCard: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 11, marginBottom: 8 },
  storyEditButton: { borderWidth: 1, borderColor: Colors.bordeaux, borderRadius: Radius.field,
    paddingHorizontal: 9, paddingVertical: 5 },
  addForm: {
    backgroundColor: Colors.paperCard,
    borderWidth: 1,
    borderColor: Border.light,
    borderRadius: Radius.field,
    padding: 10,
    marginBottom: 8,
    gap: 8,
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
  sekRad: {
    paddingVertical: 4,
  },
});
