import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { InitialBadge } from '../../../components/InitialBadge';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { FaktaKort, type FaktaAction } from '../../../components/redaktion/FaktaKort';
import { SletBekraeftSheet } from '../../../components/redaktion/SletBekraeftSheet';
import { SkrivePreviewSheet } from '../../../components/redaktion/SkrivePreviewSheet';
import { EntitetPicker } from '../../../components/redaktion/EntitetPicker';
import { PersonPicker } from '../../../components/redaktion/PersonPicker';
import { MentionPicker } from '../../../components/redaktion/MentionPicker';
import { MediaUploadSheet } from '../../../components/redaktion/MediaUploadSheet';
import { MediaGallery } from '../../../components/redaktion/MediaGallery';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { insertAt } from '../../../lib/mentions';
import { useMediaUris } from '../../../lib/media';
import { fetchPersonEvidence, fetchPersonNarrativ, fetchPersonRelationer, fetchPersonFamilie, fetchPersonMedia, fetchSammeSomLinks, fetchForaeldreUkendtMarkering, nudgeOrdinal, BARN_ROLLER, type PersonEvidence, type PersonRelation, type PersonFamilie, type PersonMedia, type FamilieUnion, type SammeSomLink, type ForaeldreUkendtMarkering } from '../../../data/redaktionRead';
import { GRADE_FORAELDER_UKENDT, GRADE_INGEN_FORBINDELSE } from '../../../data/generations';
import { previewSammeSom } from '../../../data/sammeSomPreflight';
import { eraAdvarsel } from '../../../data/eraAdvarsel';
import { type Change } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

const FELTER = ['navn', 'foedt', 'doed', 'titel']; // koen håndteres separat (ikke et fact)
const FELT_LABEL: Record<string, string> = { navn: 'navn', foedt: 'født', doed: 'død', titel: 'titel' };

const KONFIDENS_VAERDIER = ['sikker', 'sandsynlig', 'formodet', 'omstridt'] as const;
const UNION_TYPER = ['vielse', 'partnerskab', 'ugift union'] as const;

function KonfidensVaelger({ vaerdi, onVael }: { vaerdi: string | null; onVael: (k: string | null) => void }) {
  return (
    <View style={{ flexDirection: 'row', gap: 4, flexWrap: 'wrap' }}>
      {KONFIDENS_VAERDIER.map((k) => (
        <Pressable key={k}
          style={[editorStyles.koenPille, vaerdi === k && editorStyles.koenPilleAktiv]}
          onPress={() => onVael(k)}>
          <BtnLabel size={10} color={vaerdi === k ? '#fff' : Colors.textSecondary2}>{k}</BtnLabel>
        </Pressable>
      ))}
      <Pressable style={editorStyles.koenPille} onPress={() => onVael(null)}>
        <BtnLabel size={10} color={Colors.textMuted}>ryd</BtnLabel>
      </Pressable>
    </View>
  );
}

function FamilieEditRad({ label, aar, konfidens, onKonfidens, onSlet, onOp, onNed, onFlyt, onOpen }: {
  label: string; aar?: string; konfidens: string | null; onKonfidens: (k: string | null) => void; onSlet: () => void;
  // Kun relevant for børn (søskende-rækkefølge + flyt mellem forhold, brugerfund 2026-07-02) —
  // udeladt for partner-rækker.
  onOp?: () => void; onNed?: () => void; onFlyt?: () => void;
  // onOpen (valgfri): gør navnet klikbart → naviger til den person (router.push, ny editor-skærm).
  onOpen?: () => void;
}) {
  return (
    <View style={editorStyles.relEditRad}>
      <View style={{ flex: 1 }}>
        {onOpen
          ? <Pressable onPress={onOpen}><Body size={13} color={Colors.bordeaux}>{label} ↗</Body></Pressable>
          : <Body size={13}>{label}</Body>}
        {aar ? <Mono size={9} color={Colors.textMuted2}>{aar}</Mono> : null}
      </View>
      {onOp || onNed ? (
        <View style={{ flexDirection: 'row' }}>
          <Pressable disabled={!onOp} onPress={onOp}><Mono size={11} color={onOp ? Colors.textSecondary2 : Colors.textMuted3}>↑</Mono></Pressable>
          <Pressable disabled={!onNed} onPress={onNed} style={{ marginLeft: 4 }}><Mono size={11} color={onNed ? Colors.textSecondary2 : Colors.textMuted3}>↓</Mono></Pressable>
        </View>
      ) : null}
      <KonfidensVaelger vaerdi={konfidens} onVael={onKonfidens} />
      {onFlyt ? (
        <Pressable onPress={onFlyt} style={{ marginLeft: 4 }}><Mono size={9} color={Colors.bordeaux}>flyt→</Mono></Pressable>
      ) : null}
      <Pressable onPress={onSlet}><Mono size={9} color={Colors.danger}>🗑</Mono></Pressable>
    </View>
  );
}

function FlytBarnSheet({ barnNavn, andreUnioner, onClose, onVael }: {
  barnNavn: string;
  andreUnioner: FamilieUnion[];
  onClose: () => void;
  onVael: (tilFamilyId: string) => void;
}) {
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Flyt {barnNavn} til…</Serif>
        {andreUnioner.length === 0 ? (
          <Body size={13} color={Colors.textMuted}>Personen har ingen andre registrerede forhold at flytte til.</Body>
        ) : andreUnioner.map((u) => (
          <Pressable key={u.familyId} style={editorStyles.relRad} onPress={() => onVael(u.familyId)}>
            <Body size={14}>{u.partnere.map((p) => p.navn).join(' & ') || '(ukendt partner)'} · {u.type}</Body>
          </Pressable>
        ))}
      </View>
    </Modal>
  );
}

function SheetButtons({ marginTop, onGem, onClose, gemLabel }: { marginTop?: number; onGem: () => void; onClose: () => void; gemLabel?: string }) {
  return (
    <View style={{ flexDirection: 'row', gap: 8, marginTop: marginTop ?? 12 }}>
      <Pressable style={editorStyles.addOpret} onPress={onGem}><BtnLabel color="#fff">{gemLabel ?? 'Gem'}</BtnLabel></Pressable>
      <Pressable style={editorStyles.addAnnuller} onPress={onClose}><BtnLabel color={Colors.textMuted}>Annullér</BtnLabel></Pressable>
    </View>
  );
}

function UnionTypeSheet({ partner, onClose, onGem }: {
  partner: { personId: string; navn: string };
  onClose: () => void;
  onGem: (type: string, ordinal: number | null) => void;
}) {
  const [valgtType, setValgtType] = useState<string>('vielse');
  const [ordinalTekst, setOrdinalTekst] = useState('');
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Ny union</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>Partner: {partner.navn}</Body>
        <View style={{ flexDirection: 'row', gap: 6, marginBottom: 12 }}>
          {UNION_TYPER.map((t) => (
            <Pressable key={t}
              style={[editorStyles.koenPille, valgtType === t && editorStyles.koenPilleAktiv]}
              onPress={() => setValgtType(t)}>
              <BtnLabel size={11} color={valgtType === t ? '#fff' : Colors.textSecondary2}>{t}</BtnLabel>
            </Pressable>
          ))}
        </View>
        <TextInput
          style={editorStyles.addInput}
          placeholder="Ordinal (valgfri, fx 1)"
          placeholderTextColor={Colors.textMuted2}
          value={ordinalTekst}
          onChangeText={setOrdinalTekst}
          keyboardType="numeric"
        />
        <SheetButtons onGem={() => {
            const ordinal = ordinalTekst.trim() ? Number(ordinalTekst.trim()) : null;
            onGem(valgtType, ordinal);
          }} onClose={onClose} />
      </View>
    </Modal>
  );
}

function BarnSheet({ scratch, advarsel, onClose, onGem }: {
  scratch: { familyId: string; personId: string; navn: string };
  advarsel: string | null;
  onClose: () => void;
  onGem: (rolle: string, konfidens: string | null) => void;
}) {
  const [rolle, setRolle] = useState<string>('barn');
  const [konfidens, setKonfidens] = useState<string | null>(null);
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 10 }}>Tilføj barn</Serif>
        <Body size={14} style={{ marginBottom: 12 }}>{scratch.navn}</Body>
        {advarsel ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 10 }}>{advarsel}</Mono>
        ) : null}
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 6 }}>ROLLE</Mono>
        <View style={{ flexDirection: 'row', gap: 6, flexWrap: 'wrap', marginBottom: 12 }}>
          {BARN_ROLLER.map((r) => (
            <Pressable key={r}
              style={[editorStyles.koenPille, rolle === r && editorStyles.koenPilleAktiv]}
              onPress={() => setRolle(r)}>
              <BtnLabel size={11} color={rolle === r ? '#fff' : Colors.textSecondary2}>{r}</BtnLabel>
            </Pressable>
          ))}
        </View>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 6 }}>KONFIDENS</Mono>
        <KonfidensVaelger vaerdi={konfidens} onVael={setKonfidens} />
        <SheetButtons marginTop={14} onGem={() => onGem(rolle, konfidens)} onClose={onClose} />
      </View>
    </Modal>
  );
}

// Retningsvælger + rådgivende pre-flight for et samme_som-identitets-link.
function SammeSomSheet({ redigeret, valgt, kanoniskId, onByt, preview, onClose, onGem }: {
  redigeret: { id: string; navn: string };
  valgt: { id: string; navn: string };
  kanoniskId: string;
  onByt: () => void;
  preview: { folder: boolean; grund: string | null };
  onClose: () => void;
  onGem: () => void;
}) {
  const kanonisk = kanoniskId === redigeret.id ? redigeret : valgt;
  const alias = kanoniskId === redigeret.id ? valgt : redigeret;
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={editorStyles.modalBackdrop} onPress={onClose} />
      <View style={editorStyles.modalSheet}>
        <Serif size={20} style={{ marginBottom: 12 }}>Samme person</Serif>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 4 }}>KANONISK (beholdes)</Mono>
        <Body size={15} style={{ marginBottom: 10 }}>{kanonisk.navn}</Body>
        <Mono size={9} color={Colors.gold} style={{ marginBottom: 4 }}>FOLDES IND I OVENSTÅENDE</Mono>
        <Body size={15} style={{ marginBottom: 12 }}>{alias.navn}</Body>
        <Pressable style={{ paddingVertical: 6, marginBottom: 8 }} onPress={onByt}>
          <Mono size={10} color={Colors.bordeaux}>⇅ Byt retning</Mono>
        </Pressable>
        {!preview.folder ? (
          <Mono size={10} color={Colors.bordeaux} style={{ marginBottom: 10, lineHeight: 14 }}>
            ⚠ Foldes ikke endnu — {preview.grund}. Linket oprettes, men personerne vises separat til
            konflikten er løst. (redaktionel projektion — offentlig visning kan afvige)
          </Mono>
        ) : null}
        <SheetButtons marginTop={6} onGem={onGem} onClose={onClose} />
      </View>
    </Modal>
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
        <SheetButtons onGem={() => onGem(rolle, periode)} onClose={onClose} />
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
  const [markering, setMarkering] = useState<ForaeldreUkendtMarkering | null>(null);
  const [markGrade, setMarkGrade] = useState<string>(GRADE_FORAELDER_UKENDT);
  const [markKilde, setMarkKilde] = useState('');
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
  // source_id fra prefill = den udgave-række Gem skal ramme (default 1 = primær DAA-udgave).
  const [narrativSourceId, setNarrativSourceId] = useState<number | null>(null);
  const [narrativStatus, setNarrativStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  // ref, ikke state: cursor-position påvirker aldrig render-output (kun læst ved
  // mention-indsættelse) — useState her ville trigge et unødigt re-render pr. tastetryk.
  const narrativSelPos = useRef(0);
  const [mentionPickerÅben, setMentionPickerÅben] = useState(false);
  useEffect(() => {
    if (!id) return;
    setNarrativStatus('loading');
    fetchPersonNarrativ(id).then((n) => {
      setNarrativTekst(n?.tekst ?? '');
      setNarrativPrivat(n?.privat ?? false);
      setNarrativSourceId(n?.sourceId ?? null);
      setNarrativStatus('ready');
    }).catch(() => setNarrativStatus('error'));
  }, [id]);

  // Sektion-niveau "opret nyt fact"-form (operation B): hvilket felt + scratch-værdier.
  const [addFelt, setAddFelt] = useState<string | null>(null);
  const [addScratch, setAddScratch] = useState({ vaerdi: '', kilde: '' });

  useEffect(() => { if (id) fetchPersonEvidence(id).then(setEv).catch(() => {}); }, [id]);
  useEffect(() => {
    if (!id) return;
    fetchForaeldreUkendtMarkering(id)
      .then((m) => { setMarkering(m); if (m) { setMarkGrade(m.grade || GRADE_FORAELDER_UKENDT); setMarkKilde(m.kilde ?? ''); } })
      .catch(() => {});
  }, [id]);

  const [relationer, setRelationer] = useState<PersonRelation[]>([]);
  const [pickerType, setPickerType] = useState<'organisation' | 'estate' | null>(null);
  const [relScratch, setRelScratch] = useState<{ objektType: string; objektId: string; navn: string; rolle: string; periode: string } | null>(null);
  useEffect(() => {
    if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
  }, [id, redaktionAux]);

  // Samme person (identitets-links, samme_som).
  const [sammeSom, setSammeSom] = useState<SammeSomLink[]>([]);
  const [ssPicker, setSsPicker] = useState(false);
  // scratch: den valgte person + retning (kanoniskId = den der beholdes/foldes ind i).
  const [ssScratch, setSsScratch] = useState<{ personId: string; navn: string; kanoniskId: string } | null>(null);
  const refreshSammeSom = () => { if (id) fetchSammeSomLinks(id).then(setSammeSom).catch(() => {}); };
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
  useEffect(() => { if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch(() => {}); }, [id, redaktionModel]);

  // Add-flow state for familie:
  const [partnerPicker, setPartnerPicker] = useState(false);
  const [barnPickerFam, setBarnPickerFam] = useState<string | null>(null);
  const [unionScratch, setUnionScratch] = useState<{ personId: string; navn: string } | null>(null);
  const [barnScratch, setBarnScratch] = useState<{ familyId: string; personId: string; navn: string } | null>(null);
  const [flytBarnScratch, setFlytBarnScratch] = useState<{ fraFamilyId: string; personId: string; rolle: string; navn: string } | null>(null);

  // Materiale (mediehåndtering Slice 0g).
  const [media, setMedia] = useState<PersonMedia[]>([]);
  const [uploadSheetOpen, setUploadSheetOpen] = useState(false);
  const refreshMedia = () => { if (id) fetchPersonMedia(id).then(setMedia).catch(() => {}); };
  useEffect(refreshMedia, [id]);
  const mediaUris = useMediaUris(media.map((m) => ({ id: m.id, storage_path: m.storagePath })));

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
              <Pressable disabled={narrativStatus !== 'ready'} onPress={() => setMentionPickerÅben(true)}
                style={{ alignSelf: 'flex-start', marginBottom: 6 }}>
                <BtnLabel size={12.5} color={Colors.bordeaux}>🔗 Indsæt link</BtnLabel>
              </Pressable>
              <TextInput
                multiline
                editable={narrativStatus === 'ready'}
                value={narrativTekst}
                onChangeText={setNarrativTekst}
                onSelectionChange={(e) => { narrativSelPos.current = e.nativeEvent.selection.start; }}
                style={editorStyles.narrativInput}
                placeholder={narrativStatus === 'loading' ? 'Henter…' : 'Skriv biografi her…'}
                placeholderTextColor={Colors.textMuted2}
                textAlignVertical="top"
              />
              <Pressable
                style={[editorStyles.gemKnap, narrativStatus !== 'ready' && { opacity: 0.5 }]}
                disabled={narrativStatus !== 'ready'}
                onPress={() => setPending({ art: 'narrativ', subjektType: 'person', subjektId: id!,
                  vaerdi: narrativTekst, payload: { privat: narrativPrivat, sourceId: narrativSourceId } })}
              >
                <BtnLabel color="#fff">Gem narrativ</BtnLabel>
              </Pressable>
              {mentionPickerÅben ? (
                <MentionPicker
                  onClose={() => setMentionPickerÅben(false)}
                  onVælg={(token) => {
                    const r = insertAt(narrativTekst, narrativSelPos.current, token);
                    setNarrativTekst(r.text);
                    narrativSelPos.current = r.cursor;
                  }}
                />
              ) : null}
            </>
          )}
        </View>

        {/* Materiale (mediehåndtering Slice 0g+0h) */}
        <View style={editorStyles.narrativSektion}>
          <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Materiale</Mono>
          <MediaGallery
            media={media}
            mediaUris={mediaUris}
            onFjern={(m) => setPending({ art: 'sletRelation', subjektType: 'person', subjektId: id!, relationId: m.relationId })}
            onSlet={(m) => setPending({ art: 'fjernMedia', subjektType: 'person', subjektId: id!, mediaId: m.id })}
          />
          <Pressable style={{ paddingVertical: 6 }} onPress={() => setUploadSheetOpen(true)}>
            <Mono size={9} color={Colors.bordeaux}>+ Tilføj billede</Mono>
          </Pressable>
        </View>

        {/* Familie & relationer */}
        {redaktionModel ? (() => {
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
                  <View style={editorStyles.relEditRad}>
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

              {/* SAMME PERSON (identitets-links) */}
              <Mono size={9} color={Colors.gold} style={editorStyles.relLabel}>SAMME PERSON</Mono>
              {sammeSom.map((l) => (
                <View key={l.relationId} style={editorStyles.relEditRad}>
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
        onApplied={() => {
          setPending(null);
          if (id) fetchPersonEvidence(id).then(setEv).catch(() => {});
          if (id) fetchForaeldreUkendtMarkering(id).then(setMarkering).catch(() => {});
          if (id) fetchPersonRelationer(id, redaktionAux).then(setRelationer).catch(() => {});
          if (id) fetchPersonFamilie(id, redaktionModel).then(setFamilie).catch(() => {});
          refreshSammeSom();
          if (pending?.art === 'uploadMedia' || pending?.art === 'fjernMedia' || pending?.art === 'sletRelation') refreshMedia();
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
